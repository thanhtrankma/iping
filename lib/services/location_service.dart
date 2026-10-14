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
import 'safe_trip_service.dart';
import 'group_service.dart';
import 'privacy_service.dart';
import 'speeding_tracker.dart';
import 'profile_service.dart';

/// Theo dõi vị trí của chính người dùng và ghi vào mọi nhóm họ tham gia.
/// Chỉ chạy khi người dùng tự bật "Chia sẻ vị trí".
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

  Future<void> init(String uid) async {
    await _groupSub?.cancel();
    _groupSub = GroupService.instance.myGroups(uid).listen((groups) {
      _groups = groups;
      GeofenceService.instance.watch(groups);
      SafeTripService.instance.watch(groups);
      AvatarRegistry.instance.addGroups(groups);
    });
    BatteryAlertService.instance.start();
    await PrivacyService.instance.load();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) ?? false) await start();
  }

  Future<void> dispose() async {
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
  Future<String?> start() async {
    final err = await _ensurePermission(background: true);
    if (err != null) return err;

    await _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: _onStreamError);
    sharing.value = true;
    (await SharedPreferences.getInstance()).setBool(_prefKey, true);
    _startHeartbeat();

    try {
      _onPosition(await Geolocator.getCurrentPosition());
    } catch (e) {
      debugPrint('getCurrentPosition: $e');
    }
    return null;
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
    for (final g in _groups) {
      if (PrivacyService.instance.isPaused(g.id)) continue;
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
    for (final g in _groups) {
      if (PrivacyService.instance.isPaused(g.id)) continue;
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
    if (uid == null || _groups.isEmpty) return;
    final batch = _db.batch();
    for (final g in _groups) {
      batch.set(_db.doc('groups/${g.id}/locations/$uid'), {
        'sharing': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

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
    for (final g in _groups) {
      if (PrivacyService.instance.isPaused(g.id)) continue;
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
    final privacy = PrivacyService.instance;
    final active = _groups.where((g) => !privacy.isPaused(g.id)).toList();
    for (final g in _groups) {
      if (privacy.isPaused(g.id)) unawaited(privacy.markPaused(g.id));
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
          notificationText: 'Nhóm của bạn có thể thấy vị trí của bạn. Tắt trong ứng dụng bất cứ lúc nào.',
          enableWakeLock: true,
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
        // Android 11+ mở trang Cài đặt để chọn "Luôn cho phép"; từ chối thì vẫn chạy khi mở app.
        await Geolocator.requestPermission();
      }
    }
    return null;
  }

}
