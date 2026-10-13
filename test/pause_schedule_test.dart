import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/pause_schedule.dart';

void main() {
  final now = DateTime(2026, 10, 13, 14, 30);

  group('pauseUntil', () {
    test('1 giờ và 8 giờ', () {
      expect(pauseUntil(PausePreset.oneHour, now), DateTime(2026, 10, 13, 15, 30));
      expect(pauseUntil(PausePreset.eightHours, now), DateTime(2026, 10, 13, 22, 30));
    });

    test('đến sáng mai là 7 giờ hôm sau', () {
      expect(pauseUntil(PausePreset.tomorrowMorning, now), DateTime(2026, 10, 14, 7));
    });

    test('rạng sáng thì "sáng mai" là 7 giờ hôm nay', () {
      expect(nextMorning(DateTime(2026, 10, 13, 2)), DateTime(2026, 10, 13, 7));
      expect(nextMorning(DateTime(2026, 10, 13, 7)), DateTime(2026, 10, 14, 7));
    });

    test('qua cuối tháng', () {
      expect(nextMorning(DateTime(2026, 10, 31, 23)), DateTime(2026, 11, 1, 7));
    });

    test('vô thời hạn', () => expect(pauseUntil(PausePreset.forever, now), isNull));
  });

  group('PauseSchedule', () {
    final s = const PauseSchedule().pause('a', DateTime(2026, 10, 13, 15)).pause('b', null);

    test('isPaused theo thời gian', () {
      expect(s.isPaused('a', now), isTrue);
      expect(s.isPaused('a', DateTime(2026, 10, 13, 15)), isFalse);
      expect(s.isPaused('b', DateTime(2030)), isTrue);
      expect(s.isPaused('c', now), isFalse);
    });

    test('resume, prune và expired', () {
      expect(s.resume('b').isPaused('b', now), isFalse);
      final later = DateTime(2026, 10, 13, 16);
      expect(s.expired(later), ['a']);
      expect(s.prune(later).entries.keys, ['b']);
    });

    test('nextExpiry bỏ qua vô thời hạn và mốc đã qua', () {
      final t = s.pause('c', DateTime(2026, 10, 13, 14, 45)).pause('d', DateTime(2026, 10, 13, 10));
      expect(t.nextExpiry(now), DateTime(2026, 10, 13, 14, 45));
      expect(const PauseSchedule().pause('x', null).nextExpiry(now), isNull);
    });

    test('lưu và đọc lại JSON', () {
      final back = PauseSchedule.fromJson(s.toJson());
      expect(back.untilOf('a'), DateTime(2026, 10, 13, 15));
      expect(back.entries.containsKey('b'), isTrue);
      expect(back.untilOf('b'), isNull);
    });
  });

  test('pauseLabel', () {
    expect(pauseLabel(null, now), 'Đang tạm dừng');
    expect(pauseLabel(DateTime(2026, 10, 13, 15, 5), now), 'Tạm dừng đến 15:05');
    expect(pauseLabel(DateTime(2026, 10, 14, 7), now), 'Tạm dừng đến 07:00 ngày mai');
  });
}
