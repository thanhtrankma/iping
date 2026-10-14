import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'common.dart';
import 'glass.dart';

/// Bản đồ dùng chung, tự đổi giữa vệ tinh và bản đồ thường theo cài đặt.
///
/// Ảnh vệ tinh của Esri World Imagery chỉ phù hợp để phát triển; khi phát hành
/// cần tài khoản ArcGIS hoặc chuyển sang nhà cung cấp có giấy phép.
class IPingMap extends StatelessWidget {
  const IPingMap({
    super.key,
    required this.controller,
    required this.center,
    this.zoom = 15,
    this.layers = const [],
    this.interactive = true,
    this.onTap,
    this.fit,
    this.style,
  });

  final MapController controller;
  final LatLng center;
  final double zoom;
  final List<Widget> layers;
  final bool interactive;
  final void Function(TapPosition, LatLng)? onTap;
  final CameraFit? fit;

  /// Ép kiểu bản đồ, bỏ qua cài đặt của người dùng.
  final MapStyle? style;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapStyle>(
      valueListenable: SettingsService.instance.mapStyle,
      builder: (context, setting, _) {
        final satellite = (style ?? setting) == MapStyle.satellite;
        return FlutterMap(
          mapController: controller,
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            initialCameraFit: fit,
            onTap: onTap,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
            ),
          ),
          children: [
            if (satellite) ...[
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.iping.app',
                maxNativeZoom: 19,
              ),
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.iping.app',
                maxNativeZoom: 19,
              ),
            ] else
              osmTileLayer(),
            ...layers,
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  satellite ? '© Esri, Maxar' : '© OpenStreetMap',
                  style: TextStyle(
                    fontSize: 9,
                    color: satellite ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Ghim thành viên kiểu Find My (iOS 26): avatar trong vòng kính sáng,
/// quầng mờ bao ngoài, đuôi nhọn chỉ đúng toạ độ và chip pin nhỏ.
class MemberPin extends StatelessWidget {
  const MemberPin({
    super.key,
    required this.uid,
    required this.name,
    this.size = 54,
    this.dimmed = false,
    this.label,
    this.battery,
  });
  final String uid;
  final String name;
  final double size;
  final bool dimmed;
  final String? label;

  /// Mức pin (0–100); null thì không hiện chip pin.
  final int? battery;

  static double heightFor(double size, {bool withLabel = false}) => size + 14 + (withLabel ? 34 : 0);

  @override
  Widget build(BuildContext context) {
    const ring = 3.0; // vòng kính ngoài
    const gap = 2.0; // viền trắng sát avatar
    final r = size / 2 - ring - gap;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _PinChip(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 13, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(label!,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
                ],
              ),
            ),
          ),
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Vòng kính: trắng trong mờ, viền phản quang, bóng tản rộng.
              Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(ring),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: dimmed ? 0.75 : 0.95),
                      Colors.white.withValues(alpha: dimmed ? 0.55 : 0.7),
                    ],
                  ),
                  border: Border.all(color: Colors.white, width: 0.8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5)),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(gap),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: ValueListenableBuilder<Map<String, String>>(
                    valueListenable: AvatarRegistry.instance,
                    builder: (context, photos, _) =>
                        AvatarCircle(uid: uid, name: name, radius: r, dimmed: dimmed, photoUrl: photos[uid]),
                  ),
                ),
              ),
              if (battery != null)
                Positioned(
                  right: -size * 0.12,
                  bottom: -2,
                  child: _PinChip(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: _BatteryGlyph(level: battery!),
                  ),
                ),
            ],
          ),
        ),
        CustomPaint(size: const Size(16, 10), painter: _TailPainter()),
        // Bóng tiếp đất nhỏ ngay dưới đầu nhọn.
        Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

/// Chip trắng trong mờ dạng viên thuốc trên bản đồ (nhãn giờ, chip pin...).
/// Không dùng BackdropFilter để bản đồ nhiều ghim vẫn mượt.
class _PinChip extends StatelessWidget {
  const _PinChip({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 0.8)),
        color: Colors.white.withValues(alpha: 0.9),
        shadows: [BoxShadow(blurRadius: 8, color: Colors.black.withValues(alpha: 0.2), offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = level <= 20 ? AppColors.sos : AppColors.online;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$level%',
            style: TextStyle(
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: level <= 20 ? AppColors.sos : Colors.black87)),
        const SizedBox(width: 3),
        Container(
          width: 16,
          height: 8,
          padding: const EdgeInsets.all(1.2),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black.withValues(alpha: 0.35), width: 0.8),
            borderRadius: BorderRadius.circular(2.5),
          ),
          child: FractionallySizedBox(
            widthFactor: (level / 100).clamp(0.1, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.2)),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: 3.5,
          margin: const EdgeInsets.only(left: 0.8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(1)),
          ),
        ),
      ],
    );
  }
}

/// Đuôi ghim: tam giác bo mềm, cùng màu vòng kính.
class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..quadraticBezierTo(w * 0.62, h * 0.55, w / 2 + 1, h - 0.6)
      ..quadraticBezierTo(w / 2, h, w / 2 - 1, h - 0.6)
      ..quadraticBezierTo(w * 0.38, h * 0.55, 0, 0)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Marker cho một thành viên, đầu nhọn của ghim nằm đúng toạ độ.
/// Ghim thành viên; [onTap] (nếu có) mở thông tin người đó. Vùng chạm chỉ gồm chính cái ghim.
Marker memberMarker(MemberLocation l, {double size = 54, String? label, VoidCallback? onTap}) {
  final pin = MemberPin(uid: l.uid, name: l.name, size: size, dimmed: !l.sharing, label: label, battery: l.battery);
  return Marker(
    point: l.point,
    width: 140,
    height: MemberPin.heightFor(size, withLabel: label != null),
    alignment: Alignment.topCenter,
    child: onTap == null
        ? pin
        : Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: pin),
          ),
  );
}

/// Một nút trong [MapControlStack].
class MapControl {
  const MapControl({this.icon, this.child, required this.tooltip, required this.onTap, this.color});
  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
}

/// Cụm nút bản đồ xếp dọc trong một viên kính, như Apple Maps:
/// một khối kính, các nút ngăn bằng đường kẻ mảnh, mỗi nút có phản hồi chạm riêng.
class MapControlStack extends StatelessWidget {
  const MapControlStack({super.key, required this.controls, this.width = 50});
  final List<MapControl> controls;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      capsule: true,
      opacity: 0.6,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < controls.length; i++) ...[
              if (i > 0)
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(horizontal: 11),
                  color: scheme.onSurface.withValues(alpha: 0.15),
                ),
              Tooltip(
                message: controls[i].tooltip,
                child: GlassPressable(
                  onTap: controls[i].onTap,
                  shape: const CircleBorder(),
                  scale: 0.86,
                  child: SizedBox(
                    width: width,
                    height: width,
                    child: Center(
                      child: controls[i].child ??
                          Icon(controls[i].icon, size: width * 0.44, color: controls[i].color ?? scheme.onSurface),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lớp vùng địa điểm + nhãn.
List<Widget> placeLayers(List<Place> places) => [
      CircleLayer(circles: [
        for (final p in places)
          CircleMarker(
            point: p.point,
            radius: p.radius,
            useRadiusInMeter: true,
            color: AppColors.brand.withValues(alpha: 0.16),
            borderColor: Colors.white.withValues(alpha: 0.9),
            borderStrokeWidth: 1.5,
          ),
      ]),
      MarkerLayer(markers: [
        for (final p in places)
          Marker(
            point: p.point,
            width: 140,
            height: 30,
            child: Center(
              child: _PinChip(
                padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                      child: const Icon(Icons.place_rounded, size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: AppColors.brandDeep)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    ];
