import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/invite_link_service.dart';
import '../theme.dart';
import '../utils/invite_link.dart';
import '../widgets/common.dart';
import 'group_actions.dart';

/// Mã QR chứa link mời của nhóm.
class InviteQr extends StatelessWidget {
  const InviteQr({super.key, required this.code, this.size = 180});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: QrImageView(
        data: inviteLink(code),
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.brand),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111827)),
        embeddedImage: const AssetImage('assets/branding/logo_rounded_512.png'),
        embeddedImageStyle: QrEmbeddedImageStyle(size: Size.square(size * 0.2)),
        semanticsLabel: 'Mã QR mời vào nhóm',
      ),
    );
  }
}

/// Nút "Chia sẻ" link + mã mời qua bảng chia sẻ của hệ thống.
class ShareInviteButton extends StatelessWidget {
  const ShareInviteButton({super.key, required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.ios_share_rounded),
      label: const Text('Chia sẻ'),
      onPressed: () {
        // iPad cần vị trí gốc để hiện bảng chia sẻ.
        final box = context.findRenderObject() as RenderBox?;
        SharePlus.instance.share(ShareParams(
          text: inviteMessage(group.name, group.inviteCode),
          subject: 'Lời mời vào nhóm "${group.name}" trên IPing',
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ));
      },
    );
  }
}

/// Hộp thoại nhập mã mời, có lối tắt quét mã QR. Trả về mã 6 ký tự đã chuẩn hoá.
Future<String?> promptJoinCode(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _JoinCodeDialog());

class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return Navigator.pop(context);
    final code = findInviteCode(text);
    if (code == null) return setState(() => _error = 'Mã mời gồm 6 chữ hoặc số.');
    Navigator.pop(context, code);
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (code != null && mounted) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tham gia nhóm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: 'Nhập mã mời 6 ký tự', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Quét mã QR'),
              onPressed: _scan,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _submit,
          child: const Text('Xong'),
        ),
      ],
    );
  }
}

/// Màn quét mã QR mời. Trả về mã 6 ký tự khi đọc được mã hợp lệ.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _lastInvalid;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      final code = parseInviteCode(raw);
      if (code != null) {
        _done = true;
        Navigator.pop(context, code);
        return;
      }
      // Báo một lần cho mỗi mã lạ, tránh spam thông báo.
      if (raw != null && raw != _lastInvalid) {
        _lastInvalid = raw;
        showMessage(context, 'Đây không phải mã mời IPing');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Quét mã QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'IPing cần quyền camera để quét mã. Hãy bật quyền camera trong Cài đặt.'
                        : 'Không mở được camera.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: SafeArea(
              child: Text(
                'Đưa mã QR mời vào khung để tham gia nhóm',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Xử lý link mời iping://join?code=… sau khi đã đăng nhập: hỏi xác nhận, tham gia, chọn nhóm.
class InviteLinkListener extends StatefulWidget {
  const InviteLinkListener({super.key, required this.child});
  final Widget child;

  @override
  State<InviteLinkListener> createState() => _InviteLinkListenerState();
}

class _InviteLinkListenerState extends State<InviteLinkListener> {
  final _links = InviteLinkService.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _links.pendingCode.addListener(_handle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handle());
  }

  @override
  void dispose() {
    _links.pendingCode.removeListener(_handle);
    super.dispose();
  }

  Future<void> _handle() async {
    if (_busy || !mounted || _links.pendingCode.value == null) return;
    _busy = true;
    try {
      final code = _links.take()!;
      // Hỏi lại trước khi tham gia: vào nhóm nghĩa là chia sẻ vị trí với người lạ.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.group_add_rounded, color: AppColors.brand, size: 40),
          title: const Text('Tham gia nhóm?'),
          content: Text(
            'Bạn được mời vào một nhóm với mã $code. Các thành viên trong nhóm sẽ thấy vị trí của bạn.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tham gia'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final gid = await GroupActions.joinCode(context, code);
      if (gid == null || !mounted) return;
      final group = await GroupService.instance.group(gid).first.timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (mounted) showMessage(context, group == null ? 'Đã tham gia nhóm' : 'Đã tham gia nhóm "${group.name}"');
    } catch (_) {
      // Lỗi tham gia đã được GroupActions báo cho người dùng.
    } finally {
      _busy = false;
      // Có thể có link mới đến trong lúc đang xử lý.
      if (mounted && _links.pendingCode.value != null) _handle();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
