import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/push_router.dart' show navigatorKey;
import '../theme.dart';
import '../widgets/glass.dart';

/// iOS / iPadOS: Apple (5.1.1(iv)) không cho màn giải thích có nút "không" trước hộp thoại hệ thống:
/// chỉ một nút "Tiếp tục" dẫn tới hộp thoại xin quyền (người dùng chọn ở đó).
/// Android: Google Play yêu cầu người dùng được chọn đồng ý / không đồng ý ngay trên màn giải thích.
bool get _isApple => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

/// Màn giải thích quyền vị trí, hiện TRƯỚC hộp thoại xin quyền của hệ thống.
///
/// Google Play yêu cầu "prominent disclosure" cho app dùng vị trí nền: nói rõ dữ liệu gì được thu thập,
/// kể cả khi app đóng, dùng cho tính năng nào, ai thấy, cách dừng, và người dùng phải bấm đồng ý.
/// Danh sách tính năng phải khớp mục "Quyền vị trí ở chế độ nền" trong docs/PLAY_STORE.md.
class LocationDisclosure {
  static const _acceptedKey = 'location_disclosure_v1';
  static const _backgroundAskedKey = 'location_background_asked_v1';

  /// Đã đồng ý thì trả về true ngay; chưa thì hiện màn giải thích.
  static Future<bool> ensureAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_acceptedKey) ?? false) return true;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    final result = await showGlassSheet<bool>(context, builder: (ctx) => const LocationDisclosureSheet());
    // iOS: màn này chỉ dẫn tới hộp thoại của hệ thống, kể cả khi người dùng vuốt đóng.
    final ok = result ?? _isApple;
    if (ok) await prefs.setBool(_acceptedKey, true);
    return ok;
  }

  /// Sau khi đã có quyền "khi dùng app": giải thích vì sao cần "Luôn cho phép" (hỏi một lần).
  ///
  /// Trả về `true` nếu người dùng muốn tiếp tục: Android → xin quyền nền (Android 11+ mở trang Cài đặt
  /// của app để chọn "Luôn cho phép"); iOS → mở Cài đặt của IPing (Vị trí → "Luôn luôn"), vì
  /// geolocator không thể hỏi lại "Luôn luôn" sau khi đã có "Khi dùng ứng dụng".
  static Future<bool> askBackground() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_backgroundAskedKey) ?? false) return false;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    await prefs.setBool(_backgroundAskedKey, true);
    if (!context.mounted) return false;
    return await showGlassSheet<bool>(context, builder: (ctx) => const BackgroundLocationSheet()) ?? false;
  }
}

/// Các tính năng dùng vị trí khi IPing chạy nền / đã đóng (khớp docs/PLAY_STORE.md).
@visibleForTesting
const backgroundLocationFeatures = [
  'Chia sẻ vị trí liên tục (kèm tốc độ, % pin, lịch sử di chuyển 30 ngày) với các nhóm bạn chọn.',
  'Báo cho nhóm khi bạn đến hoặc rời địa điểm đã lưu, hoặc khi bạn tới điểm hẹn Meetup.',
  '"Về an toàn": tự báo khi bạn về tới nơi; quá giờ chưa tới thì nhóm nhận cảnh báo kèm vị trí cuối.',
  'Cảnh báo chạy quá tốc độ và báo cáo lái xe.',
  'Trả lời khi thành viên trong nhóm hỏi "Bạn đang ở đâu?", kể cả khi IPing đã đóng.',
  'Khám phá: đánh dấu các khu vực bạn đã đi qua (chỉ mình bạn thấy).',
];

@visibleForTesting
class LocationDisclosureSheet extends StatelessWidget {
  const LocationDisclosureSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    Widget point(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassIconBadge(icon: icon, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.35, color: secondary))),
            ],
          ),
        );
    const icons = [
      (Icons.groups_rounded, AppColors.brand),
      (Icons.place_rounded, AppColors.teal),
      (Icons.home_rounded, AppColors.online),
      (Icons.speed_rounded, AppColors.orange),
      (Icons.person_pin_circle_rounded, AppColors.purple),
      (Icons.explore_rounded, AppColors.indigo),
    ];

    return SingleChildScrollView(
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
            'khi bạn bật "Chia sẻ vị trí", để:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: secondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < backgroundLocationFeatures.length; i++)
            point(icons[i].$1, icons[i].$2, backgroundLocationFeatures[i]),
          const SizedBox(height: 4),
          point(Icons.visibility_rounded, AppColors.gray,
              'Chỉ thành viên của những nhóm bạn đã chọn chia sẻ mới thấy vị trí của bạn. '
              'IPing không bán dữ liệu vị trí và không dùng cho quảng cáo.'),
          point(
            Icons.toggle_off_rounded,
            AppColors.sos,
            _isApple
                ? 'Dừng bất cứ lúc nào: tắt "Chia sẻ vị trí" hoặc tạm ẩn với từng nhóm trong Menu, '
                    'hoặc đổi quyền Vị trí của IPing trong Cài đặt.'
                : 'Dừng bất cứ lúc nào: bấm "Dừng chia sẻ" trên thông báo, tắt "Chia sẻ vị trí" '
                    'hoặc tạm ẩn với từng nhóm trong Menu.',
          ),
          const SizedBox(height: 6),
          if (_isApple)
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tiếp tục'))
          else ...[
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đồng ý và tiếp tục')),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không, cảm ơn')),
          ],
        ],
      ),
    );
  }
}

@visibleForTesting
class BackgroundLocationSheet extends StatelessWidget {
  const BackgroundLocationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    final apple = _isApple;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: GlassIconBadge(icon: Icons.my_location_rounded, color: AppColors.brand, size: 56)),
          const SizedBox(height: 14),
          Text(apple ? 'Cho phép vị trí "Luôn luôn"?' : 'Cho phép vị trí "Luôn cho phép"?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 12),
          Text(
            apple
                ? 'Khi IPing đang chạy nền, việc chia sẻ vẫn tiếp tục (iPhone hiện chỉ báo vị trí màu xanh). '
                    'Để nhóm vẫn nhận được vị trí khi IPing đã bị đóng hẳn — báo đến / rời địa điểm, "Về an toàn", '
                    'trả lời khi thành viên hỏi "Bạn đang ở đâu?" — hãy mở Cài đặt → Vị trí → chọn "Luôn luôn". '
                    'Bạn vẫn dùng IPing được nếu chỉ cho phép "Khi dùng ứng dụng".'
                : 'Để nhóm vẫn nhận được vị trí và thông báo khi bạn đến, rời địa điểm, về tới nơi, hoặc khi '
                    'thành viên hỏi "Bạn đang ở đâu?" lúc IPing đã đóng, hãy chọn "Luôn cho phép" ở màn tiếp theo. '
                    'Bạn vẫn dùng IPing được nếu chỉ cho phép khi đang dùng ứng dụng.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: secondary),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(apple ? 'Mở Cài đặt' : 'Tiếp tục'),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Để sau')),
        ],
      ),
    );
  }
}
