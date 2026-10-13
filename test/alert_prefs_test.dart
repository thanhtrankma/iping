import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/alert_prefs.dart';
import 'package:gan_nhau/services/battery_alert_service.dart';

void main() {
  group('alertPrefKeyFor', () {
    test('ánh xạ mọi data.type đang dùng', () {
      const expected = {
        'arrive': 'place',
        'leave': 'place',
        'sos': 'sos',
        'join': 'join',
        'meetup_arrive': 'meetup',
        'message': 'message',
        'moment': 'moment',
        'meetup': 'meetup',
        'ping': 'ping',
        'low_battery': 'battery',
      };
      expected.forEach((type, key) => expect(alertPrefKeyFor(type), key, reason: type));
      expect(alertPrefKeyFor('leave_group'), isNull);
    });

    test('mọi khoá đều có trên màn cài đặt', () {
      final keys = alertTypes.map((t) => t.key).toSet();
      for (final type in ['arrive', 'sos', 'join', 'meetup', 'message', 'moment', 'ping', 'low_battery']) {
        expect(keys, contains(alertPrefKeyFor(type)));
      }
    });
  });

  group('AlertPrefs', () {
    test('mặc định nhận tất cả', () {
      final p = AlertPrefs.fromMap(null);
      expect(p.wants('message', 'a'), isTrue);
      expect(p.wants('unknown', 'a'), isTrue);
    });

    test('tắt theo loại', () {
      final p = AlertPrefs.fromMap({
        'types': {'place': false, 'ping': true},
      });
      expect(p.wants('arrive', 'a'), isFalse);
      expect(p.wants('leave', 'a'), isFalse);
      expect(p.wants('ping', 'a'), isTrue);
      expect(p.wants('message', 'a'), isTrue);
    });

    test('tắt theo người gửi, trừ SOS', () {
      final p = AlertPrefs.fromMap({
        'mutedUids': ['a', 3],
      });
      expect(p.mutedUids, ['a']);
      expect(p.wants('message', 'a'), isFalse);
      expect(p.wants('message', 'b'), isTrue);
      expect(p.wants('sos', 'a'), isTrue);
      expect(
          AlertPrefs.fromMap({
            'types': {'sos': false},
          }).wants('sos', 'a'),
          isFalse);
    });

    test('bỏ qua dữ liệu hỏng', () {
      final p = AlertPrefs.fromMap({'types': 'x', 'mutedUids': 1});
      expect(p.types, isEmpty);
      expect(p.mutedUids, isEmpty);
    });
  });

  group('LowBatteryTracker', () {
    test('báo một lần khi xuống 15%', () {
      final t = LowBatteryTracker();
      expect(t.update(40, charging: false), isFalse);
      expect(t.update(16, charging: false), isFalse);
      expect(t.update(15, charging: false), isTrue);
      expect(t.update(12, charging: false), isFalse);
      expect(t.update(5, charging: false), isFalse);
    });

    test('không báo khi đang sạc', () {
      final t = LowBatteryTracker();
      expect(t.update(10, charging: true), isFalse);
      expect(t.update(10, charging: false), isTrue);
    });

    test('đặt lại khi cắm sạc', () {
      final t = LowBatteryTracker();
      expect(t.update(14, charging: false), isTrue);
      expect(t.update(14, charging: true), isFalse);
      expect(t.update(13, charging: false), isTrue);
    });

    test('chỉ đặt lại khi pin > 25%', () {
      final t = LowBatteryTracker();
      expect(t.update(15, charging: false), isTrue);
      expect(t.update(20, charging: false), isFalse);
      expect(t.update(25, charging: false), isFalse);
      expect(t.update(15, charging: false), isFalse);
      expect(t.update(26, charging: false), isFalse);
      expect(t.update(15, charging: false), isTrue);
    });

    test('khôi phục trạng thái đã báo', () {
      final t = LowBatteryTracker(alerted: true);
      expect(t.update(10, charging: false), isFalse);
    });
  });
}
