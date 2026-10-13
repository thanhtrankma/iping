import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'group_service.dart';

/// Phát hiện đến/rời địa điểm bằng cách so vị trí mới với các vùng của nhóm.
/// Sự kiện được ghi vào Firestore; Cloud Function gửi push cho các thành viên khác.
class GeofenceService {
  GeofenceService._();
  static final instance = GeofenceService._();

  /// Vùng đệm để tránh báo đến/rời liên tục khi đứng sát mép vùng.
  static const _exitMargin = 30.0;
  /// Bỏ qua vị trí kém chính xác.
  static const _maxAccuracy = 100.0;

  /// Coi là đã tới điểm hẹn khi cách dưới 100 m.
  static const _meetupRadius = 100.0;

  final Map<String, List<Place>> _places = {};
  final Map<String, StreamSubscription<List<Place>>> _subs = {};
  final Map<String, List<Meetup>> _meetups = {};
  final Map<String, StreamSubscription<List<Meetup>>> _meetupSubs = {};
  /// Meetup đã báo "tới nơi" trong phiên này, tránh báo trùng khi Firestore chưa kịp cập nhật.
  final Set<String> _arrivedSent = {};

  void watch(List<Group> groups) {
    final ids = groups.map((g) => g.id).toSet();
    for (final gid in _subs.keys.toList()) {
      if (!ids.contains(gid)) {
        _subs.remove(gid)?.cancel();
        _places.remove(gid);
        _meetupSubs.remove(gid)?.cancel();
        _meetups.remove(gid);
      }
    }
    for (final gid in ids) {
      _subs[gid] ??= GroupService.instance.places(gid).listen((p) => _places[gid] = p);
      _meetupSubs[gid] ??= GroupService.instance.activeMeetups(gid).listen((m) => _meetups[gid] = m);
    }
  }

  Future<void> check(Position p, List<Group> groups) async {
    if (p.accuracy > _maxAccuracy) return;
    await _checkMeetups(p);
    final prefs = await SharedPreferences.getInstance();

    for (final g in groups) {
      for (final place in _places[g.id] ?? const <Place>[]) {
        final dist = Geolocator.distanceBetween(p.latitude, p.longitude, place.lat, place.lng);
        final bool nowInside;
        if (dist <= place.radius) {
          nowInside = true;
        } else if (dist > place.radius + _exitMargin) {
          nowInside = false;
        } else {
          continue;
        }

        final key = 'gf_${g.id}_${place.id}';
        final wasInside = prefs.getBool(key);
        if (wasInside == nowInside) continue;
        await prefs.setBool(key, nowInside);
        // Lần đầu thấy vùng này: chỉ ghi nhận trạng thái, không báo.
        if (wasInside == null) continue;

        await GroupService.instance.addEvent(
          g.id,
          type: nowInside ? 'arrive' : 'leave',
          placeName: place.name,
          lat: p.latitude,
          lng: p.longitude,
        );
      }
    }
  }
}

extension on GeofenceService {
  /// Tự đánh dấu "đã tới" khi người tham gia meetup đến gần điểm hẹn.
  Future<void> _checkMeetups(Position p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    for (final entry in _meetups.entries) {
      for (final m in entry.value) {
        if (m.statusOf(uid) != MeetupStatus.going) continue;
        final dist = Geolocator.distanceBetween(p.latitude, p.longitude, m.lat, m.lng);
        if (dist > GeofenceService._meetupRadius) continue;
        if (!_arrivedSent.add('${entry.key}/${m.id}')) continue;
        await GroupService.instance.setMeetupStatus(entry.key, m.id, MeetupStatus.arrived);
        await GroupService.instance.addEvent(entry.key,
            type: 'meetup_arrive', placeName: m.title, lat: p.latitude, lng: p.longitude);
      }
    }
  }
}
