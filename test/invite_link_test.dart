import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/utils/invite_link.dart';

void main() {
  group('parseInviteCode', () {
    test('đọc mã từ link iping://join', () {
      expect(parseInviteCode('iping://join?code=ABC234'), 'ABC234');
      expect(parseInviteCode('  iping://join?code=abc234  '), 'ABC234');
      expect(parseInviteCode('IPING://JOIN?code=ABC234'), 'ABC234');
      expect(parseInviteCode('iping://join?foo=1&code=XYZ789'), 'XYZ789');
    });

    test('đọc mã 6 ký tự trần', () {
      expect(parseInviteCode('ABC234'), 'ABC234');
      expect(parseInviteCode('abc234'), 'ABC234');
      expect(parseInviteCode('ABC 234'), 'ABC234');
      expect(parseInviteCode('ABC-234'), 'ABC234');
    });

    test('từ chối dữ liệu không hợp lệ', () {
      expect(parseInviteCode(null), isNull);
      expect(parseInviteCode(''), isNull);
      expect(parseInviteCode('ABC23'), isNull);
      expect(parseInviteCode('ABC2345'), isNull);
      expect(parseInviteCode('ABC!23'), isNull);
      expect(parseInviteCode('iping://join'), isNull);
      expect(parseInviteCode('iping://join?code=ABC'), isNull);
      expect(parseInviteCode('iping://other?code=ABC234'), isNull);
      expect(parseInviteCode('https://example.com/join?code=ABC234'), isNull);
    });
  });

  test('link và tin nhắn mời chứa mã', () {
    expect(inviteLink('abc234'), 'iping://join?code=ABC234');
    expect(parseInviteCode(inviteLink('ABC234')), 'ABC234');
    final msg = inviteMessage('Gia đình', 'ABC234');
    expect(msg, contains('iping://join?code=ABC234'));
    expect(msg, contains('mã: ABC234'));
  });

  test('findInviteCode nhận link nằm trong tin nhắn dán vào', () {
    expect(findInviteCode(inviteMessage('Gia đình', 'ABC234')), 'ABC234');
    expect(findInviteCode('xyz789'), 'XYZ789');
    expect(findInviteCode('không có mã'), isNull);
  });
}
