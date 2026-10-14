import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/crash_detector.dart';

void main() {
  final t0 = DateTime(2026, 10, 14, 9);

  test('đứng yên mà rơi điện thoại (gia tốc lớn) thì không báo', () {
    final d = CrashDetector();
    expect(d.onAcceleration(50, 0, 0, t0), isFalse);
  });

  test('đang chạy nhanh rồi va đập mạnh thì báo, sau đó chờ cooldown', () {
    final d = CrashDetector()..onSpeed(50, t0);
    expect(d.onAcceleration(10, 5, 0, t0.add(const Duration(seconds: 5))), isFalse); // xóc nhẹ
    expect(d.onAcceleration(45, 10, 5, t0.add(const Duration(seconds: 6))), isTrue);
    expect(d.onAcceleration(45, 10, 5, t0.add(const Duration(seconds: 20))), isFalse);
  });

  test('đã chậm lại quá lâu thì không tính', () {
    final d = CrashDetector()..onSpeed(50, t0);
    expect(d.onAcceleration(45, 0, 0, t0.add(const Duration(minutes: 1))), isFalse);
  });
}
