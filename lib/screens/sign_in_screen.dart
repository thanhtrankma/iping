import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await AuthService.instance
            .register(_name.text.trim(), _email.text.trim(), _password.text);
      } else {
        await AuthService.instance.signIn(_email.text.trim(), _password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(String code) => switch (code) {
        'invalid-email' => 'Email không hợp lệ.',
        'email-already-in-use' => 'Email này đã được đăng ký.',
        'weak-password' => 'Mật khẩu cần ít nhất 6 ký tự.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Email hoặc mật khẩu không đúng.',
        'network-request-failed' => 'Không có kết nối mạng.',
        _ => 'Có lỗi xảy ra ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: AppColors.brandDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      const _Hero(),
                      const SizedBox(height: 36),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Form(
                                key: _form,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(_register ? 'Tạo tài khoản' : 'Chào mừng trở lại',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _register
                                          ? 'Chỉ mất 30 giây để bắt đầu'
                                          : 'Đăng nhập để xem người thân của bạn',
                                      style: TextStyle(color: scheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 24),
                                    if (_register) ...[
                                      TextFormField(
                                        controller: _name,
                                        textCapitalization: TextCapitalization.words,
                                        decoration: const InputDecoration(
                                          hintText: 'Tên hiển thị',
                                          prefixIcon: Icon(Icons.person_outline_rounded),
                                        ),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'Nhập tên của bạn' : null,
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [AutofillHints.email],
                                      decoration: const InputDecoration(
                                        hintText: 'Email',
                                        prefixIcon: Icon(Icons.mail_outline_rounded),
                                      ),
                                      validator: (v) =>
                                          (v == null || !v.contains('@')) ? 'Email không hợp lệ' : null,
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: !_showPassword,
                                      autofillHints: const [AutofillHints.password],
                                      decoration: InputDecoration(
                                        hintText: 'Mật khẩu',
                                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                                        suffixIcon: IconButton(
                                          icon: Icon(_showPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined),
                                          onPressed: () =>
                                              setState(() => _showPassword = !_showPassword),
                                        ),
                                      ),
                                      validator: (v) =>
                                          (v == null || v.length < 6) ? 'Ít nhất 6 ký tự' : null,
                                      onFieldSubmitted: (_) => _submit(),
                                    ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: scheme.errorContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(_error!,
                                                  style: TextStyle(color: scheme.onErrorContainer)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                    FilledButton(
                                      onPressed: _busy ? null : _submit,
                                      child: _busy
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2.5, color: Colors.white))
                                          : Text(_register ? 'Tạo tài khoản' : 'Đăng nhập'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(() {
                                                _register = !_register;
                                                _error = null;
                                              }),
                                      child: Text.rich(TextSpan(children: [
                                        TextSpan(
                                          text: _register ? 'Đã có tài khoản? ' : 'Chưa có tài khoản? ',
                                          style: TextStyle(color: scheme.onSurfaceVariant),
                                        ),
                                        TextSpan(
                                          text: _register ? 'Đăng nhập' : 'Đăng ký ngay',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ])),
                                    ),
                                    const Spacer(),
                                    SizedBox(height: MediaQuery.paddingOf(context).bottom),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            for (final size in [150.0, 115.0])
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                ),
              ),
            const AppLogo(size: 76, onDark: true),
          ],
        ),
        const SizedBox(height: 16),
        const Text('IPing',
            style: TextStyle(
                color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text('Luôn biết người thân đang ở đâu',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15)),
      ],
    );
  }
}
