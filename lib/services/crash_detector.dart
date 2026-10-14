import 'dart:math' as math;

/// Phát hiện va chạm (beta, hàm thuần có test).
///
/// Coi là va chạm khi gia tốc (đã trừ trọng lực) vượt [thresholdG] trong lúc vừa di chuyển nhanh hơn
/// [minSpeedKmh] (trong [speedWindow] gần nhất). Sau khi báo, chờ [cooldown] mới báo lại.
class CrashDetector {
  CrashDetector({
    this.thresholdG = 4.0,
    this.minSpeedKmh = 25,
    this.speedWindow = const Duration(seconds: 30),
    this.cooldown = const Duration(minutes: 2),
  });

  static const g = 9.80665;

  final double thresholdG;
  final double minSpeedKmh;
  final Duration speedWindow;
  final Duration cooldown;

  DateTime? _lastFastAt;
  DateTime? _lastCrashAt;

  /// Ghi nhận tốc độ GPS (km/h).
  void onSpeed(double kmh, DateTime now) {
    if (kmh >= minSpeedKmh) _lastFastAt = now;
  }

  /// Mẫu gia tốc (m/s², đã trừ trọng lực). Trả về `true` nếu nghi va chạm.
  bool onAcceleration(double x, double y, double z, DateTime now) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (magnitude < thresholdG * g) return false;
    final fast = _lastFastAt;
    if (fast == null || now.difference(fast) > speedWindow) return false;
    final last = _lastCrashAt;
    if (last != null && now.difference(last) < cooldown) return false;
    _lastCrashAt = now;
    return true;
  }
}
