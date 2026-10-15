import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const termsUrl = 'https://iping-share.web.app/terms';
const privacyUrl = 'https://iping-share.web.app/privacy';

Future<void> openLegalUrl(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// "Bằng việc tiếp tục, bạn xác nhận đủ 13 tuổi và đồng ý Điều khoản sử dụng và Chính sách quyền riêng tư"
/// với hai liên kết bấm được. [prefix] thay cho phần mở đầu (vd. dùng trong ô đánh dấu đăng ký).
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({
    super.key,
    this.prefix = 'Bằng việc tiếp tục, bạn xác nhận đủ 13 tuổi và đồng ý ',
    this.color,
    this.linkColor,
    this.textAlign = TextAlign.center,
    this.fontSize = 12.5,
  });

  final String prefix;
  final Color? color;
  final Color? linkColor;
  final TextAlign textAlign;
  final double fontSize;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final _terms = TapGestureRecognizer()..onTap = () => openLegalUrl(termsUrl);
  late final _privacy = TapGestureRecognizer()..onTap = () => openLegalUrl(privacyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(
      fontSize: widget.fontSize,
      height: 1.4,
      color: widget.color ?? scheme.onSurface.withValues(alpha: 0.6),
    );
    final link = TextStyle(
      color: widget.linkColor ?? scheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: (widget.linkColor ?? scheme.primary).withValues(alpha: 0.5),
    );
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: widget.prefix),
        TextSpan(text: 'Điều khoản sử dụng', style: link, recognizer: _terms),
        const TextSpan(text: ' và '),
        TextSpan(text: 'Chính sách quyền riêng tư', style: link, recognizer: _privacy),
        const TextSpan(text: '.'),
      ]),
      textAlign: widget.textAlign,
    );
  }
}
