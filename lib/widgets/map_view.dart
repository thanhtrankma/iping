import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'common.dart';

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
  });

  final MapController controller;
  final LatLng center;
  final double zoom;
  final List<Widget> layers;
  final bool interactive;
  final void Function(TapPosition, LatLng)? onTap;
  final CameraFit? fit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapStyle>(
      valueListenable: SettingsService.instance.mapStyle,
      builder: (context, style, _) {
        final satellite = style == MapStyle.satellite;
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

/// Ghim hình giọt nước với avatar, giống iSharing.
class MemberPin extends StatelessWidget {
  const MemberPin({super.key, required this.uid, required this.name, this.size = 54, this.dimmed = false, this.label});
  final String uid;
  final String name;
  final double size;
  final bool dimmed;
  final String? label;

  static double heightFor(double size, {bool withLabel = false}) => size + 14 + (withLabel ? 34 : 0);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_rounded, size: 13, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(label!, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3.5),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black38, offset: Offset(0, 3))],
          ),
          child: ValueListenableBuilder<Map<String, String>>(
            valueListenable: AvatarRegistry.instance,
            builder: (context, photos, _) =>
                AvatarCircle(uid: uid, name: name, radius: size / 2, dimmed: dimmed, photoUrl: photos[uid]),
          ),
        ),
        CustomPaint(size: const Size(16, 10), painter: _TailPainter()),
        Container(
          width: 8,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Marker cho một thành viên, đầu nhọn của ghim nằm đúng toạ độ.
Marker memberMarker(MemberLocation l, {double size = 54, String? label}) => Marker(
      point: l.point,
      width: 140,
      height: MemberPin.heightFor(size, withLabel: label != null),
      alignment: Alignment.topCenter,
      child: MemberPin(uid: l.uid, name: l.name, size: size, dimmed: !l.sharing, label: label),
    );

/// Lớp vùng địa điểm + nhãn.
List<Widget> placeLayers(List<Place> places) => [
      CircleLayer(circles: [
        for (final p in places)
          CircleMarker(
            point: p.point,
            radius: p.radius,
            useRadiusInMeter: true,
            color: AppColors.brand.withValues(alpha: 0.18),
            borderColor: Colors.white,
            borderStrokeWidth: 2,
          ),
      ]),
      MarkerLayer(markers: [
        for (final p in places)
          Marker(
            point: p.point,
            width: 140,
            height: 30,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_rounded, size: 14, color: AppColors.brand),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandDeep)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    ];
