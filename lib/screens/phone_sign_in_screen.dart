import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/auth_errors.dart';
import '../utils/phone.dart';
import '../widgets/glass.dart';

/// Sau khi đăng nhập bằng số điện thoại: hỏi tên nếu là người mới, rồi về màn chính.
void _finishPhoneSignIn(NavigatorState nav) {
  if (AuthService.instance.needsName) {
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneNameScreen()),
      (r) => r.isFirst,
    );
  } else {
    nav.popUntil((r) => r.isFirst);
  }
}

/// Khung chung cho các bước đăng nhập bằng số điện thoại.
class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = true,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, automaticallyImplyLeading: showBack),
      body: GlassBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 20, 40),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            Glass(
              radius: 26,
              opacity: 0.6,
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(text!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

Widget _busyOr(bool busy, String label) => busy
    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
    : Text(label);

// ---------- Bước 1: nhập số điện thoại ----------

class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
  final _code = TextEditingController(text: '+84');
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _send() {
    final phone = normalizePhone(_phone.text, countryCode: _code.text);
    if (phone == null) {
      setState(() => _error = 'Số điện thoại không hợp lệ.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    AuthService.instance
        .sendPhoneCode(
      phone,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _busy = false);
        nav.push(MaterialPageRoute(
          builder: (_) => OtpScreen(phone: phone, verificationId: verificationId, resendToken: resendToken),
        ));
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = authErrorMessage(e.code);
          });
        }
      },
      onAutoVerified: () => _finishPhoneSignIn(nav),
    )
        .catchError((Object e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is FirebaseAuthException ? authErrorMessage(e.code) : 'Có lỗi xảy ra.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PhoneStep(
      icon: Icons.phone_iphone_rounded,
      title: 'Đăng nhập bằng số điện thoại',
      subtitle: 'Chúng tôi sẽ gửi mã xác minh 6 số qua SMS',
      children: [
        Row(
          children: [
            SizedBox(
              width: 84,
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[+\d]')),
                  LengthLimitingTextInputFormatter(5)
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s.\-+()]'))],
                decoration: const InputDecoration(hintText: '09xx xxx xxx', prefixIcon: Icon(Icons.phone_outlined)),
                onSubmitted: (_) => _busy ? null : _send(),
              ),
            ),
          ],
        ),
        _ErrorText(_error),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _send, child: _busyOr(_busy, 'Gửi mã')),
      ],
    );
  }
}

// ---------- Bước 2: nhập mã 6 số ----------

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, required this.verificationId, this.resendToken});
  final String phone;
  final String verificationId;
  final int? resendToken;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _resendAfter = 60;
  final _code = TextEditingController();
  late String _verificationId = widget.verificationId;
  late int? _resendToken = widget.resendToken;
  bool _busy = false;
  String? _error;
  int _wait = _resendAfter;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = _resendAfter);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_wait <= 1) t.cancel();
      setState(() => _wait--);
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Mã gồm 6 chữ số.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      if (await AuthService.instance.verifyPhoneCode(_verificationId, code)) _finishPhoneSignIn(nav);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resend() {
    setState(() {
      _error = null;
      _code.clear();
    });
    _startTimer();
    final nav = Navigator.of(context);
    AuthService.instance.sendPhoneCode(
      widget.phone,
      resendToken: _resendToken,
      onCodeSent: (id, token) {
        _verificationId = id;
        _resendToken = token;
      },
      onError: (e) {
        if (mounted) setState(() => _error = authErrorMessage(e.code));
      },
      onAutoVerified: () => _finishPhoneSignIn(nav),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PhoneStep(
      icon: Icons.sms_outlined,
      title: 'Nhập mã xác minh',
      subtitle: 'Mã 6 số đã được gửi tới ${widget.phone}',
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 12),
          decoration: const InputDecoration(hintText: '••••••'),
          onChanged: (v) {
            if (v.length == 6 && !_busy) _verify();
          },
        ),
        _ErrorText(_error),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _verify, child: _busyOr(_busy, 'Xác minh')),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _wait > 0 || _busy ? null : _resend,
          child: Text(_wait > 0 ? 'Gửi lại mã sau ${_wait}s' : 'Gửi lại mã',
              style: TextStyle(color: _wait > 0 ? scheme.onSurfaceVariant : null)),
        ),
      ],
    );
  }
}

// ---------- Bước 3: đặt tên cho người mới ----------

class PhoneNameScreen extends StatefulWidget {
  const PhoneNameScreen({super.key});

  @override
  State<PhoneNameScreen> createState() => _PhoneNameScreenState();
}

class _PhoneNameScreenState extends State<PhoneNameScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nhập tên của bạn');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await AuthService.instance.setInitialName(name.length > 50 ? name.substring(0, 50) : name);
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không lưu được tên, hãy thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bắt buộc có tên để người thân nhận ra bạn.
    return PopScope(
      canPop: false,
      child: _PhoneStep(
        icon: Icons.person_outline_rounded,
        title: 'Bạn tên là gì?',
        subtitle: 'Tên này sẽ hiển thị với người thân trong nhóm',
        showBack: false,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Tên hiển thị', prefixIcon: Icon(Icons.person_outline_rounded)),
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          _ErrorText(_error),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: _busyOr(_busy, 'Hoàn tất')),
        ],
      ),
    );
  }
}
