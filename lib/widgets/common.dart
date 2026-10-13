import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../utils/format.dart';

const defaultCenter = LatLng(21.0285, 105.8542); // Hà Nội

/// Lớp bản đồ OpenStreetMap. Khi phát hành thật, nên dùng nhà cung cấp tile
/// riêng (MapTiler, Mapbox...) theo chính sách sử dụng của OSM.
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.iping.app',
    );

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<String?> promptText(BuildContext context,
    {required String title, required String label, bool upperCase = false}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: upperCase ? TextCapitalization.characters : TextCapitalization.sentences,
        decoration: InputDecoration(hintText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Xong'),
        ),
      ],
    ),
  );
}

/// Logo IPing (ảnh trong assets/branding, sinh bằng scripts/make_branding.py).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.onDark = false});
  final double size;
  /// Giữ để tương thích; logo mới đã có viền kính nên dùng được trên mọi nền.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/logo_rounded_512.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.text});
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(text!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.radius = 20,
    this.dimmed = false,
    this.online = false,
    this.ring = false,
  });
  final String uid;
  final String name;
  final double radius;
  final bool dimmed;
  final bool online;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: AvatarRegistry.instance,
      builder: (context, photos, _) => _build(context, photos[uid]),
    );
  }

  Widget _build(BuildContext context, String? photo) {
    final avatar = AvatarCircle(uid: uid, name: name, radius: radius, dimmed: dimmed, photoUrl: photo);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (ring)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26, offset: Offset(0, 2))],
            ),
            child: avatar,
          )
        else
          avatar,
        if (online)
          Positioned(
            right: ring ? 2 : 0,
            bottom: ring ? 2 : 0,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Các avatar xếp chồng lên nhau, dùng trên thẻ nhóm.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.members, this.radius = 14, this.max = 4});
  final List<(String uid, String name)> members;
  final double radius;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final step = radius * 1.4;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: count == 0 ? 0 : step * (count - 1) + radius * 2 + 4,
      height: radius * 2 + 4,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: MemberAvatar(uid: shown[i].$1, name: shown[i].$2, radius: radius),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: radius,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Text('+$extra', style: TextStyle(fontSize: radius * 0.75, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Công tắc bật/tắt chia sẻ vị trí. Người dùng luôn chủ động quyết định.
class SharingSwitchCard extends StatelessWidget {
  const SharingSwitchCard({super.key});

  Future<void> _toggle(BuildContext context, bool on) async {
    if (on) {
      final err = await LocationService.instance.start();
      if (err != null && context.mounted) showMessage(context, err);
    } else {
      await LocationService.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: LocationService.instance.sharing,
      builder: (context, on, _) {
        final fg = on ? Colors.white : scheme.onSurface;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            gradient: on ? AppColors.brandGradient : null,
            color: on ? null : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: on
                ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: on ? Colors.white.withValues(alpha: 0.2) : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(on ? Icons.location_on_rounded : Icons.location_off_rounded,
                    color: on ? Colors.white : scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(on ? 'Đang chia sẻ vị trí' : 'Chia sẻ vị trí đang tắt',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      on ? 'Các nhóm của bạn đang thấy bạn trên bản đồ' : 'Không ai thấy vị trí của bạn',
                      style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                onChanged: (v) => _toggle(context, v),
                activeThumbColor: AppColors.brand,
                activeTrackColor: Colors.white,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Hình tròn avatar: ảnh nếu có, nếu không thì chữ cái đầu trên nền màu.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    required this.uid,
    required this.name,
    required this.radius,
    this.dimmed = false,
    this.photoUrl,
  });
  final String uid;
  final String name;
  final double radius;
  final bool dimmed;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = Text(initial(name),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.85));
    final url = photoUrl;
    final circle = CircleAvatar(
      radius: radius,
      backgroundColor: dimmed ? Colors.grey.shade400 : avatarColor(uid),
      foregroundImage: url == null ? null : CachedNetworkImageProvider(url),
      child: fallback,
    );
    if (!dimmed || url == null) return circle;
    // Làm xám ảnh khi thành viên tắt chia sẻ.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.33, 0.33, 0.33, 0, 0, //
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: circle,
    );
  }
}
