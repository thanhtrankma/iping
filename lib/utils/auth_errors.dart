/// Đổi mã lỗi FirebaseAuth / Cloud Functions thành câu tiếng Việt dễ hiểu.
String authErrorMessage(String code) => switch (code) {
      'invalid-email' => 'Email không hợp lệ.',
      'missing-email' => 'Hãy nhập email.',
      'email-already-in-use' => 'Email này đã được đăng ký.',
      'weak-password' => 'Mật khẩu cần ít nhất 6 ký tự.',
      'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Email hoặc mật khẩu không đúng.',
      'user-disabled' => 'Tài khoản này đã bị khoá.',
      'too-many-requests' => 'Bạn thử quá nhiều lần. Hãy đợi một lát rồi thử lại.',
      'network-request-failed' || 'unavailable' => 'Không có kết nối mạng.',
      'operation-not-allowed' => 'Cách đăng nhập này chưa được bật.',
      'account-exists-with-different-credential' =>
        'Email này đã đăng ký bằng cách khác. Hãy đăng nhập bằng email và mật khẩu.',
      'invalid-phone-number' || 'missing-phone-number' => 'Số điện thoại không hợp lệ.',
      'invalid-verification-code' || 'missing-verification-code' => 'Mã xác minh không đúng.',
      'session-expired' || 'code-expired' => 'Mã đã hết hạn. Hãy gửi lại mã mới.',
      'quota-exceeded' => 'Hệ thống đang quá tải gửi SMS. Hãy thử lại sau.',
      'captcha-check-failed' ||
      'app-not-authorized' ||
      'missing-client-identifier' =>
        'Không xác minh được ứng dụng. Hãy thử lại.',
      'unauthenticated' || 'requires-recent-login' => 'Phiên đăng nhập đã hết. Hãy đăng nhập lại.',
      _ => 'Có lỗi xảy ra ($code).',
    };
