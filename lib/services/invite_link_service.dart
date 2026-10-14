import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/invite_link.dart';
import 'notification_service.dart';

/// Nhận link mời iping://join?code=… khi app được mở từ link.
/// Mã được giữ trong [pendingCode] cho tới khi người dùng đã đăng nhập và xử lý xong.
class InviteLinkService {
  InviteLinkService._();
  static final instance = InviteLinkService._();

  final pendingCode = ValueNotifier<String?>(null);
  StreamSubscription<Uri>? _sub;

  void init() {
    if (_sub != null || kIsWeb) return;
    try {
      // uriLinkStream phát cả link mở app lần đầu lẫn các link sau đó.
      _sub = AppLinks().uriLinkStream.listen(_onLink, onError: (_) {});
    } catch (e) {
      debugPrint('Không nghe được link mời: $e');
    }
  }

  void _onLink(Uri uri) {
    final code = parseInviteCode(uri.toString());
    if (code == null) return;
    pendingCode.value = code;
    if (FirebaseAuth.instance.currentUser == null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Đăng nhập để tham gia nhóm bằng mã $code')),
      );
    }
  }

  /// Lấy mã đang chờ (và xoá khỏi hàng chờ).
  String? take() {
    final code = pendingCode.value;
    pendingCode.value = null;
    return code;
  }
}
