import 'dart:math' as math;

/// Một điểm trong lịch sử vị trí.
class TrackPoint {
  const TrackPoint({required this.lat, required this.lng, required this.time, this.speed});
  final double lat;
  final double lng;
  final DateTime time;
  /// m/s do GPS báo, `null` nếu không có.
  final double? speed;
}

sealed class Segment {
  DateTime get start;
  DateTime get end;
  Duration get duration => end.difference(start);
}

/// Đứng yên một chỗ đủ lâu.
class Stay extends Segment {
  Stay({required this.lat, required this.lng, required this.start, required this.end});
  final double lat;
  final double lng;
  @override
  final DateTime start;
  @override
  final DateTime end;
}

/// Một chuyến di chuyển giữa hai lần dừng.
class Trip extends Segment {
  Trip(this.points)
      : distance = _pathLength(points),
        maxSpeed = _maxSpeed(points),
        hardBrakes = _hardBrakes(points),
        speedingEvents = _speedingEvents(points);

  final List<TrackPoint> points;
  /// mét
  final double distance;
  /// m/s
  final double maxSpeed;
  final int hardBrakes;
  final int speedingEvents;

  @override
  DateTime get start => points.first.time;
  @override
  DateTime get end => points.last.time;
  TrackPoint get from => points.first;
  TrackPoint get to => points.last;

  /// m/s
  double get avgSpeed => duration.inSeconds == 0 ? 0 : distance / duration.inSeconds;

  /// Coi là lái xe khi tốc độ trung bình > 20 km/h hoặc tối đa > 40 km/h.
  bool get isDrive => avgSpeed > 20 / 3.6 || maxSpeed > 40 / 3.6;

  /// Điểm an toàn 0–100: trừ điểm cho mỗi lần phanh gấp / chạy quá tốc độ.
  int get safetyScore => (100 - hardBrakes * 8 - speedingEvents * 10).clamp(0, 100);
}

const speedLimit = 80 / 3.6; // m/s
const _hardBrakeDecel = 3.5; // m/s²

double distanceBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double d) => d * math.pi / 180;

double _d(TrackPoint a, TrackPoint b) => distanceBetween(a.lat, a.lng, b.lat, b.lng);

double _pathLength(List<TrackPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += _d(pts[i - 1], pts[i]);
  }
  return sum;
}

/// Tốc độ tại mỗi điểm: ưu tiên GPS, nếu không có thì tính từ điểm trước.
List<double> _speeds(List<TrackPoint> pts) => [
      for (var i = 0; i < pts.length; i++)
        if (pts[i].speed != null && pts[i].speed! > 0)
          pts[i].speed!
        else if (i == 0)
          0
        else
          () {
            final dt = pts[i].time.difference(pts[i - 1].time).inMilliseconds / 1000;
            return dt <= 0 ? 0.0 : _d(pts[i - 1], pts[i]) / dt;
          }(),
    ];

double _maxSpeed(List<TrackPoint> pts) => _speeds(pts).fold(0.0, math.max);

int _hardBrakes(List<TrackPoint> pts) {
  final s = _speeds(pts);
  var count = 0;
  for (var i = 1; i < pts.length; i++) {
    final dt = pts[i].time.difference(pts[i - 1].time).inMilliseconds / 1000;
    if (dt <= 0 || dt > 10) continue;
    if ((s[i - 1] - s[i]) / dt >= _hardBrakeDecel) count++;
  }
  return count;
}

int _speedingEvents(List<TrackPoint> pts) {
  final s = _speeds(pts);
  var count = 0;
  var over = false;
  for (final v in s) {
    if (v > speedLimit && !over) count++;
    over = v > speedLimit;
  }
  return count;
}

/// Chia lịch sử thành các đoạn "ở một chỗ" và "di chuyển".
///
/// Một cụm điểm nằm trong [stayRadius] quanh điểm đầu cụm, kéo dài ít nhất
/// [minStay], được coi là một lần dừng. Các điểm giữa hai lần dừng là một
/// chuyến đi; chuyến ngắn hơn [minTripDistance] bị bỏ qua.
List<Segment> buildTimeline(
  List<TrackPoint> input, {
  double stayRadius = 150,
  Duration minStay = const Duration(minutes: 5),
  double minTripDistance = 300,
}) {
  final pts = [...input]..sort((a, b) => a.time.compareTo(b.time));
  if (pts.isEmpty) return [];

  // 1. Gom cụm.
  final clusters = <List<TrackPoint>>[];
  var current = <TrackPoint>[pts.first];
  for (final p in pts.skip(1)) {
    if (_d(current.first, p) <= stayRadius) {
      current.add(p);
    } else {
      clusters.add(current);
      current = [p];
    }
  }
  clusters.add(current);

  // 2. Cụm đủ lâu là Stay, còn lại là điểm di chuyển.
  final result = <Segment>[];
  var moving = <TrackPoint>[];

  void flushTrip(TrackPoint? endAt) {
    if (endAt != null) moving.add(endAt);
    if (moving.length >= 2) {
      final trip = Trip(List.unmodifiable(moving));
      if (trip.distance >= minTripDistance) result.add(trip);
    }
    moving = [];
  }

  for (final c in clusters) {
    final isStay = c.last.time.difference(c.first.time) >= minStay;
    if (isStay) {
      flushTrip(c.first);
      final lat = c.map((p) => p.lat).reduce((a, b) => a + b) / c.length;
      final lng = c.map((p) => p.lng).reduce((a, b) => a + b) / c.length;
      result.add(Stay(lat: lat, lng: lng, start: c.first.time, end: c.last.time));
      moving = [c.last];
    } else {
      moving.addAll(c);
    }
  }
  flushTrip(null);
  return result;
}
