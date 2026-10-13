import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/screens/account_dialogs.dart';
import 'package:gan_nhau/utils/auth_errors.dart';

void main() {
  test('isDeleteConfirmation chỉ nhận đúng chữ XOÁ', () {
    expect(isDeleteConfirmation('XOÁ'), isTrue);
    expect(isDeleteConfirmation(' xoá '), isTrue);
    expect(isDeleteConfirmation('XÓA'), isTrue);
    expect(isDeleteConfirmation('XÓA'), isTrue);
    expect(isDeleteConfirmation(''), isFalse);
    expect(isDeleteConfirmation('XO'), isFalse);
    expect(isDeleteConfirmation('XOÁ TÀI KHOẢN'), isFalse);
  });

  test('authErrorMessage trả về câu tiếng Việt', () {
    expect(authErrorMessage('invalid-email'), 'Email không hợp lệ.');
    expect(authErrorMessage('invalid-verification-code'), 'Mã xác minh không đúng.');
    expect(authErrorMessage('something-else'), contains('something-else'));
  });
}
