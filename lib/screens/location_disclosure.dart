import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/push_router.dart' show navigatorKey;
import '../theme.dart';
import '../widgets/glass.dart';

/// Màn giải thích quyền vị trí, hiện TRƯỚC hộp thoại xin quyền của hệ thống.
///
/// Google Play yêu cầu "prominent disclosure" cho app dùng vị trí nền: nói rõ dữ liệu gì được thu thập,
/// kể cả khi app đóng, dùng để làm gì và người dùng phải bấm đồng ý.
class LocationDisclosure {
  static const _acceptedKey = 'location_disclosure_v1';
  static const _backgroundAskedKey = 'location_background_asked_v1';

  /// Đã đồng ý thì trả về true ngay; chưa thì hiện màn giải thích.
  static Future<bool> ensureAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_acceptedKey) ?? false) return true;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    final ok = await showGlassSheet<bool>(context, builder: (ctx) => const _DisclosureSheet()) ?? false;
    if (ok) await prefs.setBool(_acceptedKey, true);
    return ok;
  }

  /// Sau khi đã có quyền "khi dùng app": giải thích vì sao cần "Luôn cho phép" (hỏi một lần).
  static Future<bool> askBackground() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_backgroundAskedKey) ?? false) return false;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    await prefs.setBool(_backgroundAskedKey, true);
    if (!context.mounted) return false;
    return await showGlassSheet<bool>(context, builder: (ctx) => const _BackgroundSheet()) ?? false;
  }
}

class _DisclosureSheet extends StatelessWidget {
  const _DisclosureSheet();

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    Widget point(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassIconBadge(icon: icon, color: color, size: 34),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, height: 1.35, color: secondary))),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: GlassIconBadge(icon: Icons.location_on_rounded, color: AppColors.brand, size: 56)),
          const SizedBox(height: 14),
          const Text('IPing sử dụng vị trí của bạn',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 12),
          Text(
            'IPing thu thập dữ liệu vị trí chính xác của bạn, kể cả khi ứng dụng đã đóng hoặc không được sử dụng, '
            'để chia sẻ vị trí với các nhóm bạn tham gia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: secondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          point(Icons.groups_rounded, AppColors.brand,
              'Thành viên trong nhóm của bạn thấy vị trí, pin và lịch sử di chuyển của bạn.'),
          point(Icons.notifications_active_rounded, AppColors.orange,
              'Báo cho nhóm khi bạn đến hoặc rời địa điểm, về tới nơi an toàn, hoặc khi bạn gửi SOS.'),
          point(Icons.toggle_off_rounded, AppColors.online,
              'Bạn có thể tắt chia sẻ hoặc tạm ẩn với từng nhóm bất cứ lúc nào trong Menu.'),
          const SizedBox(height: 6),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đồng ý và tiếp tục')),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không, cảm ơn')),
        ],
      ),
    );
  }
}

class _BackgroundSheet extends StatelessWidget {
  const _BackgroundSheet();

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: GlassIconBadge(icon: Icons.my_location_rounded, color: AppColors.brand, size: 56)),
          const SizedBox(height: 14),
          const Text('Cho phép vị trí "Luôn luôn"?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 12),
          Text(
            'Để nhóm vẫn nhận được thông báo khi bạn đến, rời địa điểm hoặc về tới nơi lúc ứng dụng đã đóng, '
            'hãy chọn "Luôn cho phép" ở màn tiếp theo. Bạn vẫn dùng IPing được nếu chỉ cho phép khi đang mở app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: secondary),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tiếp tục')),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Để sau')),
        ],
      ),
    );
  }
}
