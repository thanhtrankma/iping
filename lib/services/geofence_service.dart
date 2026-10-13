import 'dart:async';

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

  final Map<String, List<Place>> _places = {};
  final Map<String, StreamSubscription<List<Place>>> _subs = {};

  void watch(List<Group> groups) {
    final ids = groups.map((g) => g.id).toSet();
    for (final gid in _subs.keys.toList()) {
      if (!ids.contains(gid)) {
        _subs.remove(gid)?.cancel();
        _places.remove(gid);
      }
    }
    for (final gid in ids) {
      _subs[gid] ??= GroupService.instance.places(gid).listen((p) => _places[gid] = p);
    }
  }

  Future<void> check(Position p, List<Group> groups) async {
    if (p.accuracy > _maxAccuracy) return;
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
