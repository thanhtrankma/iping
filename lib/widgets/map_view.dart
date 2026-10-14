import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/map_tiles.dart';
import '../models/models.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'common.dart';
import 'glass.dart';

/// Bản đồ dùng chung, tự đổi giữa vệ tinh và bản đồ thường theo cài đặt.
///
/// Nguồn tile lấy từ `config/map_tiles.dart` (MapTiler khi có key).
class IPingMap extends StatelessWidget {
  const IPingMap({
    super.key,
    required this.controller,
    required this.center,
    this.zoom = 15,
    this.layers = const [],
    this.interactive = true,
    this.onTap,
    this.onPositionChanged,
    this.onMapReady,
    this.fit,
    this.style,
    this.showAttribution = true,
    this.attributionPadding = const EdgeInsets.all(8),
  });

  final MapController controller;
  final LatLng center;
  final double zoom;
  final List<Widget> layers;
  final bool interactive;
  final void Function(TapPosition, LatLng)? onTap;
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;
  final VoidCallback? onMapReady;
  final CameraFit? fit;

  /// Ép kiểu bản đồ, bỏ qua cài đặt của người dùng.
  final MapStyle? style;

  /// Tự vẽ [MapAttribution] ở góc dưới trái bản đồ. Màn nào có bảng nổi che đáy bản đồ thì tắt
  /// và tự đặt [MapAttribution] / [SheetMapAttribution] ở chỗ không bị che.
  final bool showAttribution;
  final EdgeInsets attributionPadding;

  @override
  Widget build(BuildContext context) {
    // Đổi lại lớp bản đồ khi đổi kiểu bản đồ hoặc khi key bản đồ thay đổi / Esri bị lỗi.
    return ListenableBuilder(
      listenable: Listenable.merge([SettingsService.instance.mapStyle, MapKeys.instance]),
      builder: (context, _) {
        final satellite = (style ?? SettingsService.instance.mapStyle.value) == MapStyle.satellite;
        return FlutterMap(
          mapController: controller,
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            initialCameraFit: fit,
            onTap: onTap,
            onPositionChanged: onPositionChanged,
            onMapReady: onMapReady,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
            ),
          ),
          children: [
            if (satellite) ...satelliteTileLayers(context) else streetTileLayer(context),
            ...layers,
            if (showAttribution)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(padding: attributionPadding, child: MapAttribution(style: style)),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: AppColors.brandDeep)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    ];

// ---- Ghi nguồn bản đồ ----

/// Kiểu bản đồ đang hiện: [style] ép kiểu, không thì theo cài đặt.
bool _isSatellite(MapStyle? style) => (style ?? SettingsService.instance.mapStyle.value) == MapStyle.satellite;

/// Một bên cung cấp dữ liệu / ảnh bản đồ cần ghi nguồn.
typedef MapAttributionSource = ({String title, String detail, String url});

/// Các nguồn của lớp bản đồ đang dùng (khớp với `config/map_tiles.dart`).
List<MapAttributionSource> mapAttributionSources({required bool satellite}) {
  final keys = MapKeys.instance;
  final esri = satellite && (keys.usingArcgis || !keys.usingMapTiler);
  final mapTiler = !esri && keys.usingMapTiler;
  return [
    if (esri)
      (
        title: 'Powered by Esri',
        detail: 'Ảnh vệ tinh: Esri, Vantor, Earthstar Geographics và cộng đồng người dùng GIS',
        url: 'https://www.esri.com/en-us/legal/copyright-trademarks',
      ),
    if (mapTiler)
      (
        title: '© MapTiler',
        detail: satellite ? 'Ảnh vệ tinh và ô bản đồ' : 'Ô bản đồ',
        url: 'https://www.maptiler.com/copyright/',
      ),
    (
      title: '© OpenStreetMap contributors',
      detail: 'Dữ liệu bản đồ, giấy phép ODbL',
      url: 'https://www.openstreetmap.org/copyright',
    ),
  ];
}

/// Mở bảng liệt kê đầy đủ nguồn bản đồ kèm liên kết.
Future<void> showMapAttributions(BuildContext context, {MapStyle? style}) {
  final sources = mapAttributionSources(satellite: _isSatellite(style));
  return showGlassSheet<void>(
    context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle('Nguồn bản đồ', subtitle: 'Dữ liệu và hình ảnh bản đồ do các bên sau cung cấp.'),
            InsetGroup(
              dividerIndent: 16,
              children: [
                for (final s in sources)
                  ListTile(
                    title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(s.detail),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                    onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Viên ghi nguồn bản đồ ("© OpenStreetMap contributors"...) kèm nút ⓘ mở danh sách nguồn đầy đủ.
///
/// Bắt buộc hiển thị theo điều khoản của nhà cung cấp tile: mỗi màn có bản đồ phải đặt nó ở chỗ
/// không bị bảng nổi che (xem [SheetMapAttribution] cho màn có bảng kéo).
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key, this.style});

  /// Ép kiểu bản đồ (giống [IPingMap.style]); null thì theo cài đặt.
  final MapStyle? style;

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.min(340.0, MediaQuery.sizeOf(context).width * 0.75);
    return ListenableBuilder(
      listenable: Listenable.merge([SettingsService.instance.mapStyle, MapKeys.instance]),
      builder: (context, _) {
        final text = mapAttribution(satellite: _isSatellite(style));
        return Semantics(
          button: true,
          label: 'Nguồn bản đồ: $text. Xem chi tiết',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showMapAttributions(context, style: style),
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
              decoration: ShapeDecoration(
                shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 0.6)),
                color: Colors.white.withValues(alpha: 0.88),
                shadows: [BoxShadow(blurRadius: 6, color: Colors.black.withValues(alpha: 0.15), offset: const Offset(0, 1))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, height: 1.2, color: Colors.black87, letterSpacing: -0.1),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.info_outline_rounded, size: 14, color: Colors.black54),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [MapAttribution] luôn nằm ngay trên mép trên của một [DraggableScrollableSheet] và di chuyển theo nó,
/// để bảng kéo không bao giờ che dòng ghi nguồn.
///
/// Đặt làm con trực tiếp của cùng [Stack] chứa bảng kéo, SAU bảng kéo.
class SheetMapAttribution extends StatelessWidget {
  const SheetMapAttribution({
    super.key,
    required this.controller,
    required this.initialSize,
    this.style,
    this.left = 14,
    this.gap = 8,
  });

  /// Controller của bảng kéo (phải là controller truyền cho [DraggableScrollableSheet]).
  final DraggableScrollableController controller;

  /// `initialChildSize` của bảng, dùng khi bảng chưa gắn controller (khung hình đầu).
  final double initialSize;
  final MapStyle? style;
  final double left;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) => ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            final size = controller.isAttached ? controller.size : initialSize;
            // Bảng kéo gần hết màn hình thì vẫn giữ viên ghi nguồn trong màn hình.
            final bottom = math.min(box.maxHeight * size + gap, box.maxHeight - top - 30);
            return Stack(children: [Positioned(left: left, bottom: bottom, child: child!)]);
          },
          child: MapAttribution(style: style),
        ),
      ),
    );
  }
}
