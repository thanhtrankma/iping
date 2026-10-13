import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'group_service.dart';
import 'hex_grid.dart';

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

  /// Ghi nhận một vị trí mới (gọi từ LocationService).
  void record(double lat, double lng, {double accuracy = 0, DateTime? time}) {
    if (_uid == null || accuracy > 100) return;
    final p = (LatLng(lat, lng), time ?? DateTime.now());
    final last = _last;
    _last = p;
    _add(HexGrid.trackCells([if (last != null) last, p], radius: revealRadius));
  }

  void _add(Iterable<HexCell> list) {
    var changed = false;
    for (final c in list) {
      if (cells.add(c)) {
        changed = true;
        _pending.putIfAbsent(HexGrid.bucketOf(c), () => {}).add(c.id);
      }
    }
    if (!changed) return;
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
    }
  }

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
