import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'group_consent.dart';
import 'group_service.dart';
import 'hex_grid.dart';
import 'location_gates.dart';
import 'location_service.dart';
import 'privacy_service.dart';

/// Điểm khám phá của một thành viên trong nhóm (`groups/{gid}/explore/{uid}`).
class ExploreScore {
  ExploreScore({
    required this.uid,
    required this.name,
    required this.count,
    required this.areaKm2,
    this.areaName,
    this.percent,
    this.updatedAt,
  });

  final String uid;
  final String name;
  final int count;
  final double areaKm2;
  final String? areaName;
  final double? percent;
  final DateTime? updatedAt;

  factory ExploreScore.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ExploreScore(
      uid: doc.id,
      name: d['name'] as String? ?? 'Thành viên',
      count: (d['count'] as num?)?.toInt() ?? 0,
      areaKm2: (d['areaKm2'] as num?)?.toDouble() ?? 0,
      areaName: d['areaName'] as String?,
      percent: (d['percent'] as num?)?.toDouble(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Lưu các ô lục giác người dùng đã đi qua ("Khám phá").
///
/// Lưu cục bộ để bản đồ dùng được khi offline, và đồng bộ lên Firestore tại
/// `users/{uid}/explore/{bucket}` (mỗi bucket 64 x 64 ô, mảng `cells`).
class ExploreService {
  ExploreService._();
  static final instance = ExploreService._();

  /// Bán kính mở sương quanh vị trí hiện tại (số vòng ô).
  static const revealRadius = 1;

  final _db = FirebaseFirestore.instance;

  /// Tất cả ô đã khám phá.
  final Set<HexCell> cells = {};

  /// Tăng mỗi khi [cells] thay đổi để giao diện vẽ lại.
  final revision = ValueNotifier<int>(0);

  final _revealed = StreamController<List<HexCell>>.broadcast(sync: true);

  /// Các ô vừa được mở khi đi (không gồm dữ liệu tải lại / đồng bộ), để màn Khám phá
  /// chạy hiệu ứng "nổ" ô lục giác.
  Stream<List<HexCell>> get revealed => _revealed.stream;

  String? _uid;
  final Map<String, Set<String>> _pending = {};
  Timer? _flushTimer;
  Timer? _saveTimer;
  (LatLng, DateTime)? _last;

  String get _localKey => 'explore_cells_$_uid';

  Future<void> init(String uid) async {
    if (_uid == uid) return;
    _uid = uid;
    cells.clear();
    _pending.clear();
    _last = null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey) ?? '';
    for (final id in raw.split(',')) {
      final c = HexCell.tryParse(id);
      if (c != null) cells.add(c);
    }
    revision.value++;
    unawaited(_syncRemote(uid));
  }

  Future<void> dispose() async {
    await flush();
    _flushTimer?.cancel();
    _saveTimer?.cancel();
    _uid = null;
    cells.clear();
    _pending.clear();
    revision.value++;
  }

  /// Màn Khám phá đang mở (do [ExploreScreen] bật / tắt).
  bool screenVisible = false;

  /// Khám phá không phải mục đích dùng vị trí nền riêng: chỉ nhận vị trí khi đang bật chia sẻ
  /// (cùng phiên dịch vụ nền) hoặc khi màn Khám phá đang mở ở tiền cảnh. Không bao giờ tự xin quyền.
  bool get mayRecord => exploreMayRecord(
        sharing: LocationService.instance.sharing.value,
        screenVisible: screenVisible,
        appInForeground: WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );

  /// Ghi nhận một vị trí mới (từ luồng chia sẻ, hoặc từ màn Khám phá khi đang mở).
  void record(double lat, double lng, {double accuracy = 0, DateTime? time}) {
    if (_uid == null || accuracy > 100 || !mayRecord) return;
    final p = (LatLng(lat, lng), time ?? DateTime.now());
    final last = _last;
    _last = p;
    _add(HexGrid.trackCells([if (last != null) last, p], radius: revealRadius), live: true);
  }

  void _add(Iterable<HexCell> list, {bool live = false}) {
    final added = <HexCell>[];
    for (final c in list) {
      if (cells.add(c)) {
        added.add(c);
        _pending.putIfAbsent(HexGrid.bucketOf(c), () => {}).add(c.id);
      }
    }
    if (added.isEmpty) return;
    if (live) _revealed.add(added);
    revision.value++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _saveLocal);
    // Gom ghi Firestore: tối đa 1 lần mỗi 30 giây.
    _flushTimer ??= Timer(const Duration(seconds: 30), flush);
  }

  Future<void> _saveLocal() async {
    if (_uid == null) return;
    (await SharedPreferences.getInstance()).setString(_localKey, cells.map((c) => c.id).join(','));
  }

  /// Đẩy các ô mới lên Firestore.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final uid = _uid;
    if (uid == null || _pending.isEmpty) return;
    final pending = Map.of(_pending);
    _pending.clear();
    final batch = _db.batch();
    pending.forEach((bucket, ids) {
      batch.set(_db.doc('users/$uid/explore/$bucket'), {
        'cells': FieldValue.arrayUnion(ids.toList()),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    try {
      await batch.commit();
    } catch (e) {
      debugPrint('Explore flush: $e');
      // Ghi lại lần sau.
      pending.forEach((b, ids) => _pending.putIfAbsent(b, () => {}).addAll(ids));
      return;
    }
    await publishScore();
  }

  // ---- Bảng xếp hạng ----

  String? _areaName;
  double? _percent;

  /// Tổng diện tích thật (km²) của các ô đã khám phá.
  double get exploredKm2 => cells.fold<double>(0, (s, c) => s + HexGrid.areaM2(c)) / 1e6;

  /// Ghi điểm vào mọi nhóm đang tham gia để thành viên khác thấy trên bảng xếp hạng.
  Future<void> publishScore() async {
    final uid = _uid;
    // Không gửi điểm (kèm tên khu vực) cho nhóm đang tạm dừng hoặc chưa đồng ý chia sẻ.
    final groups = writableGroups(
      LocationService.instance.groups,
      id: (g) => g.id,
      allowed: GroupConsent.instance.allows,
      paused: PrivacyService.instance.isPaused,
    );
    if (uid == null || groups.isEmpty) return;
    final data = {
      'name': FirebaseAuth.instance.currentUser?.displayName ?? 'Thành viên',
      'count': cells.length,
      'areaKm2': double.parse(exploredKm2.toStringAsFixed(4)),
      if (_areaName != null) 'areaName': _areaName,
      if (_percent != null) 'percent': double.parse(_percent!.toStringAsFixed(2)),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await Future.wait(groups.map((g) async {
      try {
        await _db.doc('groups/${g.id}/explore/$uid').set(data, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Explore score ${g.id}: $e');
      }
    }));
  }

  /// Ghi khu vực hiện tại và % đã khám phá (chỉ khi thay đổi đáng kể).
  /// Tên khu vực tiết lộ nơi đang đứng: chỉ gửi khi đang bật chia sẻ vị trí.
  Future<void> publishArea(String name, double percent) async {
    if (!LocationService.instance.sharing.value) return;
    if (name == _areaName && _percent != null && (percent - _percent!).abs() < 0.05) return;
    _areaName = name;
    _percent = percent;
    await publishScore();
  }

  Stream<List<ExploreScore>> scores(String gid) =>
      _db.collection('groups/$gid/explore').snapshots().map((s) => s.docs.map(ExploreScore.fromDoc).toList());

  /// Gộp dữ liệu trên Firestore với dữ liệu cục bộ, rồi lấp dữ liệu cũ một lần.
  Future<void> _syncRemote(String uid) async {
    try {
      final snap = await _db.collection('users/$uid/explore').get();
      if (_uid != uid) return;
      final remote = <HexCell>{};
      for (final d in snap.docs) {
        for (final id in (d.data()['cells'] as List? ?? const [])) {
          final c = HexCell.tryParse(id as String);
          if (c != null) remote.add(c);
        }
      }
      // Ô chỉ có ở máy (ghi khi offline / app bị tắt trước khi đẩy lên).
      _add(cells.difference(remote));
      final added = remote.difference(cells);
      if (added.isNotEmpty) {
        cells.addAll(added);
        revision.value++;
        unawaited(_saveLocal());
      }
      await _backfill(uid);
      await publishScore();
    } catch (e) {
      debugPrint('Explore sync: $e');
    }
  }

  /// Lấp ô từ lịch sử vị trí đã có (`groups/{gid}/locations/{uid}/points`), chạy một lần.
  Future<void> _backfill(String uid) async {
    final key = 'explore_backfilled_$uid';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return;
    final groups = await GroupService.instance.myGroups(uid).first;
    final now = DateTime.now();
    final points = <(LatLng, DateTime)>[];
    for (final g in groups) {
      final list = await GroupService.instance.history(g.id, uid, now.subtract(const Duration(days: 31)), now);
      points.addAll(list.map((p) => (LatLng(p.lat, p.lng), p.time)));
    }
    if (_uid != uid) return;
    points.sort((a, b) => a.$2.compareTo(b.$2));
    _add(HexGrid.trackCells(points, radius: revealRadius));
    await prefs.setBool(key, true);
    await flush();
  }
}
