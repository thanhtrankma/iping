import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/auth_errors.dart';
import '../widgets/common.dart';

/// Hộp thoại "Quên mật khẩu?": nhập email rồi gửi link đặt lại mật khẩu.
Future<void> showForgotPasswordDialog(BuildContext context, {String initialEmail = ''}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ForgotPasswordDialog(initialEmail: initialEmail),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});
  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Email không hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      // Không tiết lộ email có tồn tại hay không.
      if (e.code == 'user-not-found') {
        if (mounted) setState(() => _sent = true);
      } else {
        if (mounted) setState(() => _error = authErrorMessage(e.code));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AlertDialog(
        icon: const Icon(Icons.mark_email_read_outlined, color: AppColors.online, size: 40),
        title: const Text('Đã gửi email'),
        content: Text('Nếu ${_email.text.trim()} đã đăng ký, bạn sẽ nhận được link đặt lại mật khẩu. '
            'Hãy kiểm tra cả thư mục Spam.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Quên mật khẩu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nhập email bạn đã đăng ký, chúng tôi sẽ gửi link để đặt lại mật khẩu.'),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              hintText: 'Email',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _busy ? null : _send(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Gửi link'),
        ),
      ],
    );
  }
}

/// Xác nhận mạnh (gõ XOÁ) rồi xoá vĩnh viễn tài khoản.
Future<void> confirmDeleteAccount(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (ok != true || !context.mounted) return;

  // Chặn thao tác trong lúc xoá.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Đang xoá tài khoản…')),
          ],
        ),
      ),
    ),
  );
  final nav = Navigator.of(context, rootNavigator: true);
  try {
    await AuthService.instance.deleteAccount();
    // Về màn đăng nhập (AuthGate tự đổi khi đã đăng xuất).
    nav.popUntil((r) => r.isFirst);
  } catch (e) {
    nav.pop();
    if (!context.mounted) return;
    if (e is AppleReauthCanceled) {
      showMessage(context, 'Bạn đã huỷ xác nhận với Apple nên tài khoản chưa bị xoá. Hãy thử lại khi sẵn sàng.');
      return;
    }
    final msg = switch (e) {
      FirebaseFunctionsException(:final code) => authErrorMessage(code),
      FirebaseAuthException(code: 'user-mismatch') => 'Hãy xác nhận bằng đúng Apple ID đã dùng để đăng nhập IPing.',
      FirebaseAuthException(code: 'missing-apple-code') => 'Apple chưa xác nhận được. Hãy thử lại.',
      FirebaseAuthException(:final code) => authErrorMessage(code),
      _ => 'Có lỗi xảy ra.',
    };
    showMessage(context, 'Không xoá được tài khoản. $msg');
  }
}

/// Chữ xác nhận xoá: "XOÁ" (chấp nhận cả kiểu bỏ dấu "XÓA", dấu tổ hợp hoặc chữ thường).
bool isDeleteConfirmation(String text) {
  final t = text.trim().toUpperCase().replaceAll(RegExp('[̀-ͯ]'), '');
  return t == 'XOÁ' || t == 'XÓA' || t == 'XOA';
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = isDeleteConfirmation(_text.text);
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: AppColors.sos, size: 40),
      title: const Text('Xoá tài khoản?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Thao tác này không thể hoàn tác. Chúng tôi sẽ xoá vĩnh viễn:'),
            const SizedBox(height: 8),
            const Text('• Hồ sơ, ảnh đại diện và khoảnh khắc của bạn\n'
                '• Vị trí và lịch sử di chuyển\n'
                '• Bạn sẽ rời khỏi mọi nhóm đang tham gia'),
            const SizedBox(height: 16),
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'Gõ '),
              TextSpan(text: 'XOÁ', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: ' để xác nhận.'),
            ])),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'XOÁ'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 44),
            backgroundColor: AppColors.sos,
            foregroundColor: Colors.white,
          ),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: const Text('Xoá vĩnh viễn'),
        ),
      ],
    );
  }
}
