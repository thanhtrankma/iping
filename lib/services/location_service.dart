import 'dart:async';
import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../screens/location_disclosure.dart';
import 'battery_alert_service.dart';
import 'explore_service.dart';
import 'geofence_service.dart';
import 'group_consent.dart';
import 'location_gates.dart';
import 'notification_service.dart' show scaffoldMessengerKey;
import 'sharing_notification.dart';
import 'safe_trip_service.dart';
import 'group_service.dart';
import 'privacy_service.dart';
import 'speeding_tracker.dart';
import 'profile_service.dart';

/// Theo dõi vị trí của chính người dùng và ghi vào các nhóm họ đã đồng ý chia sẻ ([GroupConsent]).
/// Chỉ chạy khi người dùng tự bật "Chia sẻ vị trí".
///
/// Thứ tự xin quyền (chính sách Google Play), chỉ khi người dùng bấm "Bật chia sẻ" hoặc một thao tác cần vị trí:
/// màn giải thích → quyền "khi dùng app" → (nếu cần) "Luôn cho phép" → mới bắt đầu lấy vị trí
/// (hộp thoại "Độ chính xác vị trí" của Android chỉ có thể hiện ở bước cuối này).
/// Mở app / màn chào / đổi nhóm KHÔNG bao giờ hỏi quyền ([devicePosition]).
class LocationService {
  LocationService._();
  static final instance = LocationService._();

  static const _prefKey = 'sharing_enabled';
  // Dùng chung với trình xử lý push nền (yêu cầu vị trí).
  static const sharingPrefKey = _prefKey;

  final sharing = ValueNotifier<bool>(false);
  final lastPosition = ValueNotifier<Position?>(null);

  final _db = FirebaseFirestore.instance;
  final _battery = Battery();
  StreamSubscription<Position>? _posSub;
  StreamSubscription<List<Group>>? _groupSub;
  List<Group> _groups = [];

  /// Các nhóm người dùng đang tham gia.
  List<Group> get groups => _groups;

  /// Nhóm được nhận vị trí lúc này: đã đồng ý chia sẻ và không đang tạm ẩn.
  List<Group> get _writable => writableGroups(
        _groups,
        id: (g) => g.id,
        allowed: GroupConsent.instance.allows,
        paused: PrivacyService.instance.isPaused,
      );

  Set<String> _consentSeen = const {};

  Future<void> init(String uid) async {
    // Phải nạp trước mọi lệnh ghi: chưa nạp thì [GroupConsent.allows] luôn false (không gửi gì).
    await GroupConsent.instance.load(uid);
    _consentSeen = GroupConsent.instance.consented.value;
    GroupConsent.instance.consented.removeListener(_onConsentChanged);
    GroupConsent.instance.consented.addListener(_onConsentChanged);
    await _groupSub?.cancel();
    // Chuyển đổi người dùng cũ / dọn nhóm đã rời TRƯỚC khi dùng danh sách để ghi vị trí
    // (asyncMap giữ đúng thứ tự các lần cập nhật).
    _groupSub = GroupService.instance.myGroups(uid).asyncMap((groups) async {
      await GroupConsent.instance.onGroups(groups);
      return groups;
    }).listen((groups) {
      _groups = groups;
      GeofenceService.instance.watch(groups);
      SafeTripService.instance.watch(groups);
      AvatarRegistry.instance.addGroups(groups);
    });
    BatteryAlertService.instance.start();
    await PrivacyService.instance.load();
    // Bấm "Dừng chia sẻ" trên thông báo khi app chưa chạy: dừng hẳn, không tự bật lại.
    final stopRequested = await SharingNotification.instance.init(_stopFromNotification);
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefKey) ?? false)) return;
    if (stopRequested) {
      await _stopFromNotification();
    } else {
      await _resume();
    }
  }

  /// Bật lại chia sẻ khi mở app (người dùng đã bật từ trước). Không hỏi quyền, không hiện màn nào:
  /// quyền đã bị thu hồi thì coi như tắt chia sẻ, người dùng tự bật lại khi muốn.
  Future<void> _resume() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
        await stop();
        return;
      }
      // GPS đang tắt: chờ lần mở app sau (không mở hộp thoại bật GPS khi vừa mở app).
      if (!await Geolocator.isLocationServiceEnabled()) return;
    } catch (e) {
      debugPrint('Resume sharing: $e');
      return;
    }
    await _startStream();
  }

  Future<void> _stopFromNotification() async {
    await stop();
    showGlobalMessage(scaffoldMessengerKey, 'Đã dừng chia sẻ vị trí.');
  }

  /// Các trường ghi vào `groups/{gid}/locations/{uid}` khi thôi / dừng / tạm dừng chia sẻ: nhóm không còn
  /// thấy mình "đang chia sẻ" và không đọc được toạ độ, tốc độ, pin cuối cùng nữa.
  static Map<String, Object> get hiddenLocationFields => {
        'sharing': false,
        'lat': FieldValue.delete(),
        'lng': FieldValue.delete(),
        'accuracy': FieldValue.delete(),
        'speed': FieldValue.delete(),
        'battery': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Ẩn vị trí của mình trong nhóm [gid] ([hiddenLocationFields]). Dùng `update` để không tạo doc
  /// khi chưa từng chia sẻ với nhóm này (lỗi not-found được bỏ qua).
  Future<void> hideFrom(String gid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.doc('groups/$gid/locations/$uid').update(hiddenLocationFields);
    } catch (e) {
      debugPrint('Hide location $gid: $e');
    }
  }

  /// Đồng ý theo nhóm thay đổi: nhóm vừa rút đồng ý → ẩn vị trí đã ghi; nhóm vừa đồng ý → ghi ngay.
  void _onConsentChanged() {
    final now = GroupConsent.instance.consented.value;
    final removed = _consentSeen.difference(now);
    final added = now.difference(_consentSeen);
    _consentSeen = now;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    for (final gid in removed) {
      if (!_groups.any((g) => g.id == gid)) continue;
      unawaited(hideFrom(gid));
    }
    if (added.isNotEmpty) unawaited(refresh());
  }

  Future<void> dispose() async {
    GroupConsent.instance.consented.removeListener(_onConsentChanged);
    GroupConsent.instance.reset();
    _consentSeen = const {};
    _heartbeat?.cancel();
    _heartbeat = null;
    await _posSub?.cancel();
    await _groupSub?.cancel();
    _posSub = null;
    _groupSub = null;
    _groups = [];
    GeofenceService.instance.watch(const []);
    SafeTripService.instance.watch(const []);
    await BatteryAlertService.instance.stop();
  }

  /// Trả về thông báo lỗi nếu không bắt đầu được, `null` nếu thành công.
  ///
  /// Chỉ gọi khi người dùng bấm "Bật chia sẻ" (hoặc thao tác cần chia sẻ như "Về an toàn").
  /// Thứ tự: màn giải thích → quyền khi dùng app → "Luôn cho phép" → luồng vị trí.
  Future<String?> start() async {
    final err = await _ensurePermission(background: true);
    if (err != null) return err;
    await _startStream();
    return null;
  }

  /// Bắt đầu luồng vị trí (đã có quyền). Trên Android, đây là lúc duy nhất hộp thoại
  /// "Độ chính xác vị trí" của Google có thể hiện.
  Future<void> _startStream() async {
    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: _onStreamError);
    sharing.value = true;
    (await SharedPreferences.getInstance()).setBool(_prefKey, true);
    _startHeartbeat();
    // Thông báo dịch vụ nền đã hiện: gắn nút "Dừng chia sẻ".
    unawaited(SharingNotification.instance.attachStopAction());

    try {
      _onPosition(await Geolocator.getCurrentPosition());
    } catch (e) {
      debugPrint('getCurrentPosition: $e');
    }
  }

  /// Ghi `lastSeenAt` định kỳ khi đang chia sẻ, kể cả khi đứng yên (distanceFilter không phát vị trí mới).
  /// Server dựa vào đây để phân biệt "ngồi yên" với "mất kết nối" (checkStaleLocations).
  static const heartbeatInterval = Duration(minutes: 15);
  Timer? _heartbeat;

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _beat());
  }

  Future<void> _beat() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !sharing.value) return;
    for (final g in _writable) {
      _db
          .doc('groups/${g.id}/locations/$uid')
          .set({'lastSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('heartbeat ${g.id}: $e'));
    }
  }

  bool _reportedOff = false;

  /// GPS bị tắt hoặc quyền vị trí bị thu hồi khi đang chia sẻ: báo nhóm một lần mỗi phiên.
  Future<void> _onStreamError(Object e) async {
    debugPrint('Location error: $e');
    if (_reportedOff || !sharing.value) return;
    if (e is! LocationServiceDisabledException && e is! PermissionDeniedException) return;
    _reportedOff = true;
    for (final g in _writable) {
      try {
        await GroupService.instance.addEvent(g.id, type: 'location_off').timeout(const Duration(seconds: 10));
      } catch (err) {
        debugPrint('location_off ${g.id}: $err');
      }
    }
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    _posSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    sharing.value = false;
    (await SharedPreferences.getInstance()).setBool(_prefKey, false);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Chỉ nhóm đã đồng ý mới từng nhận vị trí; nhóm khác không cần (và không nên tạo doc vị trí).
    final targets = _groups.where((g) => GroupConsent.instance.allows(g.id)).toList();
    if (uid == null || targets.isEmpty) return;
    // Ghi riêng từng nhóm: doc chưa tồn tại (chưa từng gửi vị trí) không làm hỏng các nhóm khác.
    await Future.wait(targets.map((g) => hideFrom(g.id)));
  }

  /// Vị trí hiện tại cho thao tác do người dùng tự bấm (SOS, check-in, "Vị trí của tôi", "Về an toàn",
  /// đăng khoảnh khắc kèm vị trí). Chưa có quyền thì hỏi theo đúng thứ tự (màn giải thích trước).
  /// KHÔNG gọi từ luồng mở app / màn chào / đổi nhóm: dùng [devicePosition].
  Future<Position?> currentPosition() async {
    if (lastPosition.value != null) return lastPosition.value;
    if (await _ensurePermission() != null) return null;
    try {
      return await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  /// Quyền vị trí đã được cấp chưa (chỉ kiểm tra, không bao giờ hỏi).
  Future<bool> hasPermission() async {
    try {
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Vị trí của máy để căn bản đồ khi mở app / đổi nhóm, không cần bật chia sẻ.
  ///
  /// KHÔNG BAO GIỜ hỏi quyền hay mở hộp thoại hệ thống (kể cả "Độ chính xác vị trí"):
  /// - chưa có quyền → `null` (bản đồ dùng vị trí mặc định);
  /// - đã có quyền → vị trí hệ thống còn nhớ (không bật GPS);
  /// - đang chia sẻ → vị trí mới từ luồng chia sẻ được báo qua [onFresh].
  Future<Position?> devicePosition({void Function(Position)? onFresh}) async {
    if (lastPosition.value != null) return lastPosition.value;
    if (!await hasPermission()) return null;
    if (sharing.value && onFresh != null) {
      void once() {
        final p = lastPosition.value;
        if (p == null) return;
        lastPosition.removeListener(once);
        onFresh(p);
      }

      lastPosition.addListener(once);
    }
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Ghi lại vị trí gần nhất (ví dụ khi một nhóm vừa hết tạm dừng).
  Future<void> refresh() async {
    final p = lastPosition.value;
    if (p != null && sharing.value) await _onPosition(p);
  }

  /// Lấy vị trí mới ngay và ghi một lần vào các nhóm (yêu cầu vị trí).
  /// Không gửi gì nếu đang tắt chia sẻ; trả về `true` nếu đã ghi.
  Future<bool> pushNow() async {
    if (!sharing.value) return false;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return false;
    try {
      await _onPosition(await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 15)));
      return true;
    } catch (e) {
      debugPrint('pushNow: $e');
      return false;
    }
  }

  final _speeding = SpeedingTracker();

  /// Chạy quá 80 km/h: báo ngay cho các nhóm (không gửi cho nhóm đang tạm ẩn).
  void _checkSpeeding(Position p) {
    if (p.speed < 0 || p.accuracy > 50) return;
    final kmh = p.speed * 3.6;
    if (!_speeding.update(kmh, p.timestamp)) return;
    for (final g in _writable) {
      GroupService.instance
          .addEvent(g.id, type: 'speeding', speed: kmh.round())
          .catchError((Object e) => debugPrint('speeding ${g.id}: $e'));
    }
  }

  Future<void> _onPosition(Position p) async {
    _reportedOff = false;
    if (sharing.value) _checkSpeeding(p);
    lastPosition.value = p;
    // Mở sương ở màn Khám phá (chỉ lưu cho chính người dùng).
    ExploreService.instance.record(p.latitude, p.longitude, accuracy: p.accuracy, time: p.timestamp);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !sharing.value) return;

    int? battery;
    try {
      battery = await _battery.batteryLevel;
    } catch (_) {}

    final data = {
      'name': user.displayName ?? 'Thành viên',
      'photoUrl': user.photoURL,
      'lat': p.latitude,
      'lng': p.longitude,
      'accuracy': p.accuracy,
      if (p.speed >= 0) 'speed': p.speed,
      if (battery != null) 'battery': battery,
      'sharing': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      // Giờ thiết bị, dùng tạm khi giờ server chưa về (ghi offline / độ trễ).
      'clientAt': Timestamp.fromDate(p.timestamp),
    };
    final saveHistory = _shouldSaveHistory(p);
    final point = {
      'lat': p.latitude,
      'lng': p.longitude,
      if (p.speed >= 0) 'speed': p.speed,
      't': Timestamp.fromDate(p.timestamp),
      // Firestore TTL tự xoá điểm cũ hơn 30 ngày.
      'expireAt': Timestamp.fromDate(p.timestamp.add(const Duration(days: 30))),
    };
    // Nhóm đang tạm dừng: chỉ đánh dấu "đã tắt chia sẻ" một lần, không ghi vị trí.
    // Nhóm chưa đồng ý chia sẻ (vd. vừa vào bằng mã mời): không ghi gì.
    final privacy = PrivacyService.instance;
    final active = _writable;
    for (final g in _groups) {
      if (privacy.isPaused(g.id) && GroupConsent.instance.allows(g.id)) unawaited(privacy.markPaused(g.id));
    }
    // Ghi riêng từng nhóm: một nhóm vừa rời (bị rules từ chối) không chặn các nhóm khác.
    await Future.wait(active.map((g) async {
      final ref = _db.doc('groups/${g.id}/locations/${user.uid}');
      try {
        await ref.set(data);
        if (saveHistory) await ref.collection('points').add(point);
      } catch (e) {
        debugPrint('Write location ${g.id}: $e');
      }
    }));

    await GeofenceService.instance.check(p, active);
    await SafeTripService.instance.check(p);
    if (battery != null) await BatteryAlertService.instance.check(level: battery);
  }

  Position? _lastSaved;

  /// Lưu lịch sử khi đã đi ≥ 40 m (cách ≥ 8 giây), hoặc đứng yên quá 5 phút.
  bool _shouldSaveHistory(Position p) {
    final last = _lastSaved;
    if (p.accuracy > 100) return false;
    final ok = last == null ||
        p.timestamp.difference(last.timestamp) >= const Duration(minutes: 5) ||
        (Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude) >= 40 &&
            p.timestamp.difference(last.timestamp) >= const Duration(seconds: 8));
    if (ok) _lastSaved = p;
    return ok;
  }

  LocationSettings _settings() {
    const distanceFilter = 25; // mét
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'IPing đang chia sẻ vị trí',
          notificationText: 'Nhóm của bạn đang thấy vị trí của bạn. Bấm "Dừng chia sẻ" để tắt.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.other,
        distanceFilter: distanceFilter,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilter);
  }

  /// [background]: đang bật chia sẻ → sau khi có quyền "khi dùng app" thì xin thêm "Luôn cho phép" (hỏi một lần).
  Future<String?> _ensurePermission({bool background = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Hãy bật dịch vụ định vị (GPS) trên thiết bị.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      // Google Play: phải giải thích và người dùng đồng ý TRƯỚC hộp thoại xin quyền của hệ thống.
      if (!await LocationDisclosure.ensureAccepted()) {
        return 'Bạn cần đồng ý cho IPing dùng vị trí để chia sẻ với nhóm.';
      }
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) return 'Bạn chưa cấp quyền vị trí.';
    if (perm == LocationPermission.deniedForever) {
      return 'Quyền vị trí đang bị chặn. Hãy bật lại trong Cài đặt của thiết bị.';
    }
    if (background && perm == LocationPermission.whileInUse) {
      if (await LocationDisclosure.askBackground()) {
        if (Platform.isIOS) {
          // geolocator chỉ hỏi "Khi dùng ứng dụng"; đã có quyền đó thì không hỏi lại được "Luôn luôn"
          // → mở trang Cài đặt của IPing để người dùng tự chọn. Không chọn thì vẫn chia sẻ khi app chạy.
          await Geolocator.openAppSettings();
        } else {
          // Android 11+ mở trang Cài đặt để chọn "Luôn cho phép"; từ chối thì vẫn chạy khi mở app.
          await Geolocator.requestPermission();
        }
      }
    }
    return null;
  }

}
