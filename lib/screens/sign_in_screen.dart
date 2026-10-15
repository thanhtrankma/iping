import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/auth_errors.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/legal_links.dart';
import 'account_dialogs.dart';
import 'phone_sign_in_screen.dart';

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

  /// Đăng ký bằng email: bắt buộc đánh dấu đủ 13 tuổi và đồng ý điều khoản.
  bool _accepted = false;
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
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apple() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await AuthService.instance.signInWithApple();
      if (ok && mounted) finishSignIn(Navigator.of(context));
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (e) {
      debugPrint('Apple sign-in: $e');
      if (mounted) setState(() => _error = 'Không đăng nhập được bằng Apple. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (e) {
      debugPrint('Google sign-in: $e');
      if (mounted) setState(() => _error = 'Không đăng nhập được bằng Google. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ô nhập dạng viên thuốc, nền mờ nhẹ bên trong thẻ kính (không lồng kính trong kính).
  InputDecoration _field(BuildContext context, String hint, IconData icon, {Widget? suffix}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(icon, color: scheme.onSurface.withValues(alpha: 0.55)),
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.7), width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.8), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.sos.withValues(alpha: 0.6), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.sos, width: 1.5),
      ),
      errorStyle: const TextStyle(fontWeight: FontWeight.w500),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Scaffold(
      backgroundColor: AppColors.brandDeep,
      body: _BrandBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        const _Hero(),
                        const SizedBox(height: 32),
                        Glass(
                          radius: 36,
                          opacity: 0.8,
                          blur: 22,
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 14),
                          child: Material(
                            type: MaterialType.transparency,
                            child: Form(
                              key: _form,
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 220),
                                      child: Column(
                                        key: ValueKey(_register),
                                        children: [
                                          Text(
                                            _register ? 'Tạo tài khoản' : 'Chào mừng trở lại',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.headlineSmall?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.6,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _register
                                                ? 'Chỉ mất 30 giây để bắt đầu'
                                                : 'Đăng nhập để xem người thân của bạn',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: secondary, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    if (_register) ...[
                                      TextFormField(
                                        controller: _name,
                                        textCapitalization: TextCapitalization.words,
                                        textInputAction: TextInputAction.next,
                                        decoration: _field(context, 'Tên hiển thị', Icons.person_outline_rounded),
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty) ? 'Nhập tên của bạn' : null,
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.email],
                                      decoration: _field(context, 'Email', Icons.mail_outline_rounded),
                                      validator: (v) =>
                                          (v == null || !v.contains('@')) ? 'Email không hợp lệ' : null,
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: !_showPassword,
                                      autofillHints: const [AutofillHints.password],
                                      decoration: _field(
                                        context,
                                        'Mật khẩu',
                                        Icons.lock_outline_rounded,
                                        suffix: Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: IconButton(
                                            color: scheme.onSurface.withValues(alpha: 0.55),
                                            icon: Icon(_showPassword
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined),
                                            onPressed: () => setState(() => _showPassword = !_showPassword),
                                          ),
                                        ),
                                      ),
                                      validator: (v) => (v == null || v.length < 6) ? 'Ít nhất 6 ký tự' : null,
                                      onFieldSubmitted: (_) => _submit(),
                                    ),
                                    if (!_register)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => showForgotPasswordDialog(context, initialEmail: _email.text.trim()),
                                          child: const Text('Quên mật khẩu?'),
                                        ),
                                      ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 12),
                                      DecoratedBox(
                                        decoration: ShapeDecoration(
                                          shape: glassShape(radius: 20),
                                          color: AppColors.sos.withValues(alpha: 0.12),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.error_rounded, color: AppColors.sos, size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: const TextStyle(
                                                    color: AppColors.sos,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_register)
                                      FormField<bool>(
                                        key: const ValueKey('terms'),
                                        initialValue: _accepted,
                                        validator: (_) => _accepted ? null : 'Bạn cần đồng ý để tạo tài khoản',
                                        builder: (field) => Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Checkbox(
                                                    value: _accepted,
                                                    visualDensity: VisualDensity.compact,
                                                    onChanged: (v) {
                                                      setState(() => _accepted = v ?? false);
                                                      field.didChange(v);
                                                    },
                                                  ),
                                                  const Expanded(
                                                    child: Padding(
                                                      padding: EdgeInsets.only(top: 10),
                                                      child: LegalConsentText(
                                                        prefix: 'Tôi đủ 13 tuổi và đồng ý ',
                                                        textAlign: TextAlign.start,
                                                        fontSize: 13.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (field.hasError)
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 14, top: 2),
                                                  child: Text(field.errorText!,
                                                      style: const TextStyle(
                                                          color: AppColors.sos,
                                                          fontSize: 12.5,
                                                          fontWeight: FontWeight.w500)),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 20),
                                    _PrimaryButton(
                                      busy: _busy,
                                      label: _register ? 'Tạo tài khoản' : 'Đăng nhập',
                                      onPressed: _submit,
                                    ),
                                    const SizedBox(height: 14),
                                    _OrDivider(color: secondary),
                                    const SizedBox(height: 14),
                                    // Sign in with Apple: bắt buộc trên iOS khi có đăng nhập Google (App Store 4.8).
                                    if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size.fromHeight(50),
                                        ),
                                        onPressed: _busy ? null : _apple,
                                        icon: const Icon(Icons.apple, size: 24),
                                        label: const Text('Tiếp tục với Apple'),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    OutlinedButton.icon(
                                      onPressed: _busy ? null : _google,
                                      icon: const _GoogleMark(),
                                      label: const Text('Tiếp tục với Google'),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => Navigator.of(context)
                                              .push(MaterialPageRoute(builder: (_) => const PhoneSignInScreen())),
                                      icon: const Icon(Icons.phone_iphone_rounded),
                                      label: const Text('Tiếp tục với số điện thoại'),
                                    ),
                                    const SizedBox(height: 12),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 6),
                                      child: LegalConsentText(),
                                    ),
                                    const SizedBox(height: 6),
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
                                          style: TextStyle(color: secondary, fontWeight: FontWeight.w500),
                                        ),
                                        TextSpan(
                                          text: _register ? 'Đăng nhập' : 'Đăng ký ngay',
                                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                                        ),
                                      ])),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
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

/// Nút chính dạng viên thuốc, gradient thương hiệu, có phát sáng và phản hồi khi chạm.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.busy, required this.label, required this.onPressed});
  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassPressable(
      onTap: busy ? null : onPressed,
      shape: const StadiumBorder(),
      scale: 0.97,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: busy ? 0.75 : 1,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            gradient: AppColors.brandGradient,
            shadows: [
              BoxShadow(color: AppColors.brand.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8)),
            ],
          ),
          child: busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Nền rực rỡ màu thương hiệu với các đốm màu đã làm mờ, để thẻ kính có thứ để khúc xạ.
class _BrandBackdrop extends StatelessWidget {
  const _BrandBackdrop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF1A2272), Color(0xFF0B0D12)]
                  : const [Color(0xFF5B7CFF), Color(0xFF2E3FD1)],
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.decal),
              child: CustomPaint(painter: _BrandBlobPainter(dark)),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _BrandBlobPainter extends CustomPainter {
  _BrandBlobPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = dark ? 0.55 : 0.8;
    void blob(Color c, double x, double y, double r) => canvas.drawCircle(
          Offset(size.width * x, size.height * y),
          size.shortestSide * r,
          Paint()..color = c.withValues(alpha: a),
        );
    blob(AppColors.purple, 0.95, 0.1, 0.55);
    blob(AppColors.teal, 0.0, 0.45, 0.5);
    blob(AppColors.pink, 1.0, 0.75, 0.45);
    blob(AppColors.indigo, 0.2, 1.0, 0.6);
  }

  @override
  bool shouldRepaint(_BrandBlobPainter old) => old.dark != dark;
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.white.withValues(alpha: 0.35), blurRadius: 50, spreadRadius: 6),
              BoxShadow(color: AppColors.brandDeep.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 12)),
            ],
          ),
          child: const AppLogo(size: 92, onDark: true),
        ),
        const SizedBox(height: 20),
        const Text(
          'IPing',
          style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.2),
        ),
        const SizedBox(height: 4),
        Text(
          'Cùng chia sẻ vị trí, mỗi người tự quyết định',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: color.withValues(alpha: 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('hoặc', style: TextStyle(color: color)),
        ),
        Expanded(child: Divider(color: color.withValues(alpha: 0.3))),
      ],
    );
  }
}

/// Chữ "G" nhiều màu đơn giản (không dùng logo ảnh).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(
        colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
      ).createShader(r),
      child: const Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
