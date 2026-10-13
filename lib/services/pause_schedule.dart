// Logic thuần cho "tạm dừng chia sẻ theo nhóm" (không phụ thuộc Firebase, dễ test).

/// Các mốc tạm dừng có sẵn.
enum PausePreset { oneHour, eightHours, tomorrowMorning, forever }

/// Giờ "sáng mai" khi chọn "Đến sáng mai".
const morningHour = 7;

extension PausePresetLabel on PausePreset {
  String get label => switch (this) {
        PausePreset.oneHour => 'Trong 1 giờ',
        PausePreset.eightHours => 'Trong 8 giờ',
        PausePreset.tomorrowMorning => 'Đến sáng mai ($morningHour:00)',
        PausePreset.forever => 'Cho đến khi bật lại',
      };
}

/// Thời điểm hết tạm dừng; `null` nghĩa là tạm dừng vô thời hạn.
DateTime? pauseUntil(PausePreset preset, DateTime now) => switch (preset) {
      PausePreset.oneHour => now.add(const Duration(hours: 1)),
      PausePreset.eightHours => now.add(const Duration(hours: 8)),
      PausePreset.tomorrowMorning => nextMorning(now),
      PausePreset.forever => null,
    };

/// 7 giờ sáng kế tiếp. Nếu đang là rạng sáng (trước 7 giờ) thì lấy 7 giờ hôm nay.
DateTime nextMorning(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, morningHour);
  return now.isBefore(today) ? today : DateTime(now.year, now.month, now.day + 1, morningHour);
}

/// Bảng nhóm đang tạm dừng: gid → hạn (null = vô thời hạn).
class PauseSchedule {
  const PauseSchedule([this.entries = const {}]);

  final Map<String, DateTime?> entries;

  /// Nhóm có đang tạm dừng ở thời điểm [now] không.
  bool isPaused(String gid, DateTime now) {
    if (!entries.containsKey(gid)) return false;
    final until = entries[gid];
    return until == null || now.isBefore(until);
  }

  DateTime? untilOf(String gid) => entries[gid];

  PauseSchedule pause(String gid, DateTime? until) => PauseSchedule({...entries, gid: until});

  PauseSchedule resume(String gid) => PauseSchedule({...entries}..remove(gid));

  /// Bỏ các mục đã hết hạn.
  PauseSchedule prune(DateTime now) =>
      PauseSchedule({for (final e in entries.entries) if (isPaused(e.key, now)) e.key: e.value});

  /// Các nhóm vừa hết hạn tính đến [now].
  List<String> expired(DateTime now) => [for (final gid in entries.keys) if (!isPaused(gid, now)) gid];

  /// Hạn gần nhất trong tương lai (để hẹn giờ tự bật lại).
  DateTime? nextExpiry(DateTime now) {
    DateTime? next;
    for (final until in entries.values) {
      if (until == null || !until.isAfter(now)) continue;
      if (next == null || until.isBefore(next)) next = until;
    }
    return next;
  }

  /// Lưu dạng gid → mili giây epoch (0 = vô thời hạn).
  Map<String, int> toJson() => {for (final e in entries.entries) e.key: e.value?.millisecondsSinceEpoch ?? 0};

  factory PauseSchedule.fromJson(Map<String, dynamic> json) => PauseSchedule({
        for (final e in json.entries)
          if (e.value is int)
            e.key: e.value == 0 ? null : DateTime.fromMillisecondsSinceEpoch(e.value as int),
      });
}

/// Mô tả ngắn trạng thái tạm dừng, ví dụ "Tạm dừng đến 14:30" hoặc "Tạm dừng đến 07:00 ngày mai".
String pauseLabel(DateTime? until, DateTime now) {
  if (until == null) return 'Đang tạm dừng';
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(until.hour)}:${two(until.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(until.year, until.month, until.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Tạm dừng đến $hm';
  if (diff == 1) return 'Tạm dừng đến $hm ngày mai';
  return 'Tạm dừng đến $hm ${two(until.day)}/${two(until.month)}';
}
