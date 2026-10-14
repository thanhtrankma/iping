import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/privacy_service.dart';
import '../theme.dart';

/// Nghi va chạm (BETA): đếm ngược để người dùng huỷ; hết giờ thì gửi SOS tới các nhóm.
class CrashCountdownScreen extends StatefulWidget {
  const CrashCountdownScreen({super.key});

  static const seconds = 30;

  @override
  State<CrashCountdownScreen> createState() => _CrashCountdownScreenState();
}

class _CrashCountdownScreenState extends State<CrashCountdownScreen> {
  int _left = CrashCountdownScreen.seconds;
  Timer? _timer;
  bool _sending = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      HapticFeedback.mediumImpact();
      if (_left <= 0) _sendSos();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendSos() async {
    _timer?.cancel();
    if (_sending) return;
    setState(() => _sending = true);
    final pos = await LocationService.instance.currentPosition();
    var sent = 0;
    for (final g in LocationService.instance.groups) {
      if (PrivacyService.instance.isPaused(g.id)) continue;
      try {
        await GroupService.instance
            .sendSos(g.id, lat: pos?.latitude, lng: pos?.longitude)
            .timeout(const Duration(seconds: 10));
        sent++;
      } on TimeoutException {
        sent++; // Đã vào hàng đợi, sẽ gửi khi có mạng.
      } catch (e) {
        debugPrint('Crash SOS ${g.id}: $e');
      }
    }
    if (!mounted) return;
    setState(() => _result = sent > 0 ? 'Đã gửi SOS tới $sent nhóm.' : 'Không gửi được SOS. Hãy gọi 113 / 115.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.sos,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.car_crash_rounded, color: Colors.white, size: 72),
              const SizedBox(height: 16),
              const Text('Có vẻ bạn vừa gặp va chạm',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Phát hiện va chạm (beta) có thể nhầm khi điện thoại bị rơi hoặc va đập.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
              const Spacer(),
              if (_result != null)
                Text(_result!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))
              else if (_sending)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                Text('$_left', style: const TextStyle(color: Colors.white, fontSize: 96, fontWeight: FontWeight.w900)),
                const Text('giây nữa sẽ gửi SOS kèm vị trí tới các nhóm',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
              const Spacer(),
              if (_result == null && !_sending) ...[
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.sos),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tôi ổn, huỷ', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  onPressed: _sendSos,
                  child: const Text('Gửi SOS ngay'),
                ),
              ] else
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.sos),
                  onPressed: _sending ? null : () => Navigator.pop(context),
                  child: const Text('Đóng'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
