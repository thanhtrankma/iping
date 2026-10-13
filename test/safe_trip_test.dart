import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/services/safe_trip_service.dart';
import 'package:latlong2/latlong.dart';

SafeTrip _trip({
  SafeTripStatus status = SafeTripStatus.active,
  DateTime? dueAt,
  double? startLat = 21.0,
  double? startLng = 105.80,
}) =>
    SafeTrip(
      uid: 'a',
      name: 'An',
      destName: 'Nhà',
      destLat: 21.0,
      destLng: 105.85,
      radius: 150,
      startedAt: DateTime(2026, 1, 1, 17),
      dueAt: dueAt ?? DateTime(2026, 1, 1, 18),
      status: status,
      startLat: startLat,
      startLng: startLng,
    );

void main() {
  group('suggestSafeTripDuration', () {
    test('quãng ngắn: tối thiểu 10 phút dự phòng, làm tròn 5 phút', () {
      // 1 km * 1.3 / (25 km/h) ≈ 3,1 phút + 10 phút dự phòng → 15 phút.
      expect(suggestSafeTripDuration(1000), const Duration(minutes: 15));
    });

    test('quãng dài: dự phòng 25%', () {
      // 20 km * 1.3 / (25 km/h) = 62,4 phút + 15,6 phút = 78 → 80 phút.
      expect(suggestSafeTripDuration(20000), const Duration(minutes: 80));
    });

    test('dùng tốc độ hiện tại khi đang di chuyển nhanh', () {
      // 20 km ở 72 km/h (20 m/s): 21,7 phút + 10 → 35 phút.
      expect(suggestSafeTripDuration(20000, speed: 20), const Duration(minutes: 35));
      // Đứng yên / tốc độ nhiễu → bỏ qua, dùng mặc định.
      expect(suggestSafeTripDuration(20000, speed: 1), suggestSafeTripDuration(20000));
    });

    test('luôn là bội số 5 phút trong khoảng 10 phút – 24 giờ', () {
      for (final m in <double>[0, 10, 500, 3000, 15000, 80000, 2e6]) {
        final d = suggestSafeTripDuration(m);
        expect(d.inMinutes % 5, 0, reason: '$m m');
        expect(d.inMinutes, inInclusiveRange(10, 24 * 60), reason: '$m m');
      }
    });
  });

  group('SafeTrip', () {
    test('isOpen theo trạng thái', () {
      expect(_trip().isOpen, isTrue);
      expect(_trip(status: SafeTripStatus.overdue).isOpen, isTrue);
      expect(_trip(status: SafeTripStatus.arrived).isOpen, isFalse);
      expect(_trip(status: SafeTripStatus.ended).isOpen, isFalse);
    });

    test('isLate: qua giờ dù server chưa đánh dấu, hoặc server đã đánh dấu', () {
      final due = DateTime(2026, 1, 1, 18);
      expect(_trip(dueAt: due).isLate(due.subtract(const Duration(minutes: 1))), isFalse);
      expect(_trip(dueAt: due).isLate(due.add(const Duration(minutes: 1))), isTrue);
      expect(_trip(dueAt: due, status: SafeTripStatus.overdue).isLate(due.subtract(const Duration(hours: 1))), isTrue);
      expect(_trip(dueAt: due, status: SafeTripStatus.arrived).isLate(due.add(const Duration(hours: 1))), isFalse);
    });

    test('remaining âm khi quá giờ', () {
      final due = DateTime(2026, 1, 1, 18);
      expect(_trip(dueAt: due).remaining(DateTime(2026, 1, 1, 17, 48)), const Duration(minutes: 12));
      expect(_trip(dueAt: due).remaining(DateTime(2026, 1, 1, 18, 5)), const Duration(minutes: -5));
    });

    test('progress: 0 ở điểm xuất phát, 1 khi vào bán kính đích, kẹp trong 0–1', () {
      final t = _trip();
      expect(t.progress(const LatLng(21.0, 105.80)), closeTo(0, 0.01));
      expect(t.progress(const LatLng(21.0, 105.825)), closeTo(0.5, 0.05));
      expect(t.progress(const LatLng(21.0, 105.8495)), 1);
      // Đi ngược hướng: không âm.
      expect(t.progress(const LatLng(21.0, 105.75)), 0);
    });

    test('progress = 0 khi không biết điểm xuất phát', () {
      expect(_trip(startLat: null, startLng: null).progress(const LatLng(21.0, 105.84)), 0);
    });
  });
}
