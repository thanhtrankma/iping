import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import 'location_service.dart';

/// "Về an toàn": người dùng báo cho nhóm mình đang đi tới đâu và dự kiến tới lúc nào.
///
/// - Máy người đi tự phát hiện khi tới nơi (trong [SafeTrip.radius]) → báo "đã về an toàn".
/// - Cloud Function `checkSafeTrips` chạy mỗi phút: chuyến quá giờ mà chưa tới → đánh dấu
///   `overdue` và gửi cảnh báo khẩn cho cả nhóm (kèm vị trí cuối, % pin), nhắc lại sau 15 phút.
/// - Người đi có thể gia hạn, tự xác nhận đã tới, hoặc báo "Tôi ổn" để kết thúc.
///
/// Dữ liệu: `groups/{gid}/safeTrips/{uid}` (mỗi người một chuyến mỗi nhóm, ghi đè chuyến cũ).
class SafeTripService {
  SafeTripService._();
  static final instance = SafeTripService._();

  /// Bán kính mặc định quanh điểm đến (m). Lớn hơn geofence vì GPS trong nhà kém chính xác.
  static const defaultRadius = 150.0;

  /// Gia hạn nhanh.
  static const extendStep = Duration(minutes: 15);

  final _db = FirebaseFirestore.instance;

  /// Chuyến đang mở của chính mình theo nhóm (để kiểm tra tới nơi).
  final Map<String, SafeTrip> _mine = {};
  final Map<String, StreamSubscription<SafeTrip?>> _subs = {};
  final Set<String> _arriving = {};

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _name => FirebaseAuth.instance.currentUser?.displayName ?? 'Thành viên';

  CollectionReference<Map<String, dynamic>> _col(String gid) =>
      _db.collection('groups').doc(gid).collection('safeTrips');

  // ---- Đọc ----

  /// Các chuyến đang mở (đang đi hoặc quá giờ) trong nhóm.
  Stream<List<SafeTrip>> open(String gid) => _col(gid)
      .where('status', whereIn: [SafeTripStatus.active.name, SafeTripStatus.overdue.name])
      .snapshots()
      .map((s) => s.docs.map(SafeTrip.fromDoc).toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt)));

  /// Chuyến của một thành viên (kể cả đã kết thúc), `null` nếu chưa từng có.
  Stream<SafeTrip?> of(String gid, String uid) =>
      _col(gid).doc(uid).snapshots().map((d) => d.exists ? SafeTrip.fromDoc(d) : null);

  /// Chuyến đang mở của chính mình trong nhóm.
  Stream<SafeTrip?> mine(String gid) => of(gid, _uid).map((t) => t != null && t.isOpen ? t : null);

  // ---- Ghi ----

  /// Bắt đầu chuyến. Tự bật chia sẻ vị trí nếu đang tắt (cần để phát hiện tới nơi).
  /// Trả về thông báo lỗi, hoặc `null` nếu thành công.
  Future<String?> start(
    String gid, {
    required String destName,
    required double destLat,
    required double destLng,
    required DateTime dueAt,
    double radius = defaultRadius,
  }) async {
    final loc = LocationService.instance;
    if (!loc.sharing.value) {
      final err = await loc.start();
      if (err != null) return err;
    }
    final p = loc.lastPosition.value ?? await loc.currentPosition();

    final batch = _db.batch();
    batch.set(_col(gid).doc(_uid), {
      'name': _name,
      'destName': destName,
      'destLat': destLat,
      'destLng': destLng,
      'radius': radius,
      'dueAt': Timestamp.fromDate(dueAt),
      'startedAt': FieldValue.serverTimestamp(),
      'status': SafeTripStatus.active.name,
      'alerts': 0,
      if (p != null) 'startLat': p.latitude,
      if (p != null) 'startLng': p.longitude,
    });
    batch.set(_event(gid), _eventData('safe_start', destName, dueAt: dueAt));
    await batch.commit();
    return null;
  }

  /// Gia hạn thêm [by] tính từ giờ dự kiến (hoặc từ bây giờ nếu đã quá giờ).
  Future<void> extend(String gid, SafeTrip trip, {Duration by = extendStep}) {
    final now = DateTime.now();
    final base = trip.dueAt.isAfter(now) ? trip.dueAt : now;
    final due = base.add(by);
    final batch = _db.batch();
    batch.update(_col(gid).doc(_uid), {
      'dueAt': Timestamp.fromDate(due),
      'status': SafeTripStatus.active.name,
      'alerts': 0,
    });
    // Đang quá giờ (nhóm đã bị báo động) → báo cho nhóm biết đã gia hạn.
    if (trip.isLate(now)) batch.set(_event(gid), _eventData('safe_extend', trip.destName, dueAt: due));
    return batch.commit();
  }

  /// Đánh dấu đã tới nơi (tự phát hiện hoặc người đi tự bấm).
  Future<void> arrive(String gid, {double? lat, double? lng}) async {
    final ref = _col(gid).doc(_uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final trip = SafeTrip.fromDoc(snap);
      if (!trip.isOpen) return;
      tx.update(ref, {'status': SafeTripStatus.arrived.name, 'endedAt': FieldValue.serverTimestamp()});
      tx.set(_event(gid), _eventData('safe_arrive', trip.destName, lat: lat, lng: lng));
    });
  }

  /// Kết thúc chuyến khi chưa tới. Nếu đang quá giờ, nhóm nhận "đã báo an toàn".
  Future<void> end(String gid, SafeTrip trip) {
    final late = trip.isLate(DateTime.now());
    final batch = _db.batch();
    batch.update(_col(gid).doc(_uid), {'status': SafeTripStatus.ended.name, 'endedAt': FieldValue.serverTimestamp()});
    batch.set(_event(gid), _eventData(late ? 'safe_ok' : 'safe_end', trip.destName));
    return batch.commit();
  }

  DocumentReference<Map<String, dynamic>> _event(String gid) =>
      _db.collection('groups').doc(gid).collection('events').doc();

  Map<String, dynamic> _eventData(String type, String destName, {DateTime? dueAt, double? lat, double? lng}) => {
        'type': type,
        'uid': _uid,
        'name': _name,
        'placeName': destName,
        if (dueAt != null) 'dueAt': Timestamp.fromDate(dueAt),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'createdAt': FieldValue.serverTimestamp(),
      };

  // ---- Tự phát hiện tới nơi ----

  /// Theo dõi chuyến của chính mình trong các nhóm (gọi khi danh sách nhóm đổi).
  void watch(List<Group> groups) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ids = uid == null ? <String>{} : groups.map((g) => g.id).toSet();
    for (final gid in _subs.keys.toList()) {
      if (!ids.contains(gid)) {
        _subs.remove(gid)?.cancel();
        _mine.remove(gid);
      }
    }
    for (final gid in ids) {
      _subs[gid] ??= of(gid, uid!).listen((t) {
        if (t != null && t.isOpen) {
          _mine[gid] = t;
        } else {
          _mine.remove(gid);
          _arriving.remove(gid);
        }
      }, onError: (Object e) {
        // Vd. vừa bị xoá khỏi nhóm (permission-denied): bỏ theo dõi nhóm này.
        debugPrint('Safe trip $gid: $e');
        _subs.remove(gid)?.cancel();
        _mine.remove(gid);
        _arriving.remove(gid);
      });
    }
  }

  /// Gọi với mỗi vị trí mới (kể cả nhóm đang tạm dừng chia sẻ: chỉ báo "đã tới", không lộ toạ độ).
  Future<void> check(Position p) async {
    if (_mine.isEmpty || p.accuracy > 100) return;
    for (final entry in _mine.entries.toList()) {
      final t = entry.value;
      final dist = Geolocator.distanceBetween(p.latitude, p.longitude, t.destLat, t.destLng);
      // Cho phép sai số GPS nhưng không quá 100 m.
      if (dist > t.radius + math.min(p.accuracy, 100) / 2) continue;
      if (!_arriving.add(entry.key)) continue;
      try {
        await arrive(entry.key, lat: p.latitude, lng: p.longitude);
      } catch (_) {
        _arriving.remove(entry.key);
      }
    }
  }
}

/// Gợi ý thời gian cần cho quãng đường [meters] (theo đường chim bay) với tốc độ hiện tại [speed] (m/s):
/// ước tính đường thực tế dài hơn ~30%, tốc độ mặc định 25 km/h khi chưa di chuyển,
/// cộng thêm khoảng dự phòng 25% (tối thiểu 10 phút), làm tròn lên bội số 5 phút.
Duration suggestSafeTripDuration(double meters, {double? speed}) {
  final v = (speed != null && speed > 2) ? speed : 25 / 3.6;
  final travel = meters * 1.3 / v;
  final buffer = math.max(600.0, travel * 0.25);
  final minutes = ((travel + buffer) / 60 / 5).ceil() * 5;
  return Duration(minutes: minutes.clamp(10, 24 * 60));
}
