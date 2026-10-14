import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/speeding_tracker.dart';

void main() {
  final t0 = DateTime(2026, 10, 14, 8);

  test('một lần đo vượt ngưỡng (GPS nhảy số) thì không báo', () {
    final t = SpeedingTracker();
    expect(t.update(95, t0), isFalse);
    expect(t.update(60, t0.add(const Duration(seconds: 5))), isFalse);
    expect(t.update(95, t0.add(const Duration(seconds: 10))), isFalse);
  });

  test('2 lần liên tiếp vượt ngưỡng thì báo, sau đó chờ cooldown', () {
    final t = SpeedingTracker();
    expect(t.update(90, t0), isFalse);
    expect(t.update(92, t0.add(const Duration(seconds: 5))), isTrue);
    expect(t.update(93, t0.add(const Duration(minutes: 5))), isFalse);
    expect(t.update(94, t0.add(const Duration(minutes: 11))), isTrue);
  });
}
