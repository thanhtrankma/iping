import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/trip_analyzer.dart';

void main() {
  final t0 = DateTime(2026, 10, 13, 7);

  // Đi thẳng về hướng bắc ~ 111 m mỗi 0.001 độ vĩ.
  List<TrackPoint> line(DateTime start, int n, {double lat0 = 20.8, int stepSec = 10, double? speed}) => [
        for (var i = 0; i < n; i++)
          TrackPoint(
            lat: lat0 + i * 0.001,
            lng: 106.6,
            time: start.add(Duration(seconds: i * stepSec)),
            speed: speed,
          ),
      ];

  List<TrackPoint> stay(DateTime start, double lat, int minutes) => [
        for (var m = 0; m <= minutes; m++)
          TrackPoint(lat: lat, lng: 106.6, time: start.add(Duration(minutes: m))),
      ];

  test('dừng – đi – dừng thành Stay, Trip, Stay', () {
    final a = stay(t0, 20.8, 20);
    final moveStart = a.last.time.add(const Duration(seconds: 10));
    final move = line(moveStart, 30, lat0: 20.801);
    final b = stay(move.last.time.add(const Duration(seconds: 10)), move.last.lat + 0.0005, 30);

    final timeline = buildTimeline([...a, ...move, ...b]);
    expect(timeline.map((s) => s.runtimeType).toList(), [Stay, Trip, Stay]);

    final trip = timeline[1] as Trip;
    expect(trip.distance, greaterThan(3000));
    // ~111 m / 10 s ≈ 40 km/h
    expect(trip.isDrive, isTrue);
  });

  test('bỏ qua dịch chuyển ngắn do sai số GPS', () {
    final pts = [
      ...stay(t0, 20.8, 10),
      TrackPoint(lat: 20.8012, lng: 106.6, time: t0.add(const Duration(minutes: 11))),
      ...stay(t0.add(const Duration(minutes: 12)), 20.8, 10),
    ];
    expect(buildTimeline(pts).whereType<Trip>(), isEmpty);
  });

  test('đếm chạy quá tốc độ và phanh gấp', () {
    final pts = [
      TrackPoint(lat: 20.80, lng: 106.6, time: t0, speed: 15),
      TrackPoint(lat: 20.81, lng: 106.6, time: t0.add(const Duration(seconds: 5)), speed: 25),
      TrackPoint(lat: 20.82, lng: 106.6, time: t0.add(const Duration(seconds: 10)), speed: 26),
      TrackPoint(lat: 20.83, lng: 106.6, time: t0.add(const Duration(seconds: 13)), speed: 10),
    ];
    final trip = Trip(pts);
    expect(trip.speedingEvents, 1);
    expect(trip.hardBrakes, 1);
    expect(trip.safetyScore, 100 - 8 - 10);
  });
}
