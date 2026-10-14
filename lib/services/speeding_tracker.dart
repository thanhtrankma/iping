/// Phát hiện chạy quá tốc độ để báo nhóm ngay (hàm thuần, có test).
///
/// Chỉ báo khi [needConsecutive] lần đo liên tiếp vượt [limitKmh] (bỏ qua GPS nhảy số),
/// và mỗi lần báo cách nhau ít nhất [cooldown] để không spam.
class SpeedingTracker {
  SpeedingTracker({this.limitKmh = 80, this.cooldown = const Duration(minutes: 10), this.needConsecutive = 2});

  final double limitKmh;
  final Duration cooldown;
  final int needConsecutive;

  int _over = 0;
  DateTime? _lastAlert;

  /// Trả về `true` nếu nên gửi cảnh báo cho lần đo này.
  bool update(double kmh, DateTime now) {
    if (kmh <= limitKmh) {
      _over = 0;
      return false;
    }
    _over++;
    if (_over < needConsecutive) return false;
    final last = _lastAlert;
    if (last != null && now.difference(last) < cooldown) return false;
    _lastAlert = now;
    return true;
  }
}
