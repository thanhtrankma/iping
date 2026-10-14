import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/utils/phone.dart';

void main() {
  group('normalizePhone', () {
    test('số nội địa 0xx → +84', () {
      expect(normalizePhone('0912345678'), '+84912345678');
      expect(normalizePhone('0912 345 678'), '+84912345678');
      expect(normalizePhone('091-234.5678'), '+84912345678');
      expect(normalizePhone('(091) 2345678'), '+84912345678');
    });

    test('thiếu số 0 đầu', () {
      expect(normalizePhone('912345678'), '+84912345678');
      expect(normalizePhone('812345678'), '+84812345678');
    });

    test('đã có mã quốc gia', () {
      expect(normalizePhone('+84912345678'), '+84912345678');
      expect(normalizePhone('+84 912 345 678'), '+84912345678');
      expect(normalizePhone('84912345678'), '+84912345678');
      expect(normalizePhone('0084912345678'), '+84912345678');
    });

    test('mã quốc gia khác', () {
      expect(normalizePhone('0412345678', countryCode: '+61'), '+61412345678');
      expect(normalizePhone('2025550123', countryCode: '1'), '+12025550123');
      expect(normalizePhone('+12025550123'), '+12025550123');
    });

    test('số không hợp lệ', () {
      expect(normalizePhone(''), isNull);
      expect(normalizePhone('   '), isNull);
      expect(normalizePhone('09abc12345'), isNull);
      expect(normalizePhone('0123'), isNull);
      expect(normalizePhone('+0912345678'), isNull);
      expect(normalizePhone('0912345678', countryCode: ''), isNull);
      expect(normalizePhone('+8491234567891234'), isNull);
    });
  });
}
