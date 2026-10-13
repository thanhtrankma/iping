import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/area_service.dart';
import '../services/hex_grid.dart';
import '../theme.dart';

/// Lớp "sương mù" của màn Khám phá: phủ kín bản đồ, khoét các ô lục giác đã đi qua,
/// tô đậm và viền khu vực hiện tại.
class ExploreFogLayer extends StatelessWidget {
  const ExploreFogLayer({super.key, required this.cells, required this.revision, this.area});
  final Set<HexCell> cells;

  /// Đổi giá trị để buộc vẽ lại khi [cells] thay đổi tại chỗ.
  final int revision;
  final ExploreArea? area;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FogPainter(camera: camera, cells: cells, revision: revision, area: area),
        ),
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  _FogPainter({required this.camera, required this.cells, required this.revision, required this.area});

  final MapCamera camera;
  final Set<HexCell> cells;
  final int revision;
  final ExploreArea? area;

  static const _fog = Color(0xD2DCE6FA);
  static const _areaShade = Color(0x263B5BFD);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Mét Mercator -> điểm ảnh màn hình (bản đồ không xoay nên chỉ là phép tịnh tiến + co giãn).
    final ppm = 256 * math.pow(2, camera.zoom) / (2 * math.pi * HexGrid.earthRadius);
    final c = camera.center;
    final (cx, cy) = HexGrid.project(c.latitude, c.longitude);
    final o = camera.latLngToScreenPoint(c);
    Offset px(double x, double y) => Offset(o.x + (x - cx) * ppm, o.y - (y - cy) * ppm);

    // Các ô nằm trong màn hình (thêm lề 1 ô).
    final mx = (size.width / 2 + HexGrid.size * ppm * 2) / ppm;
    final my = (size.height / 2 + HexGrid.size * ppm * 2) / ppm;
    final hex = Path();
    final tiles = Path();
    final drawTiles = HexGrid.size * ppm >= 4;
    for (final cell in cells) {
      final (x, y) = HexGrid.centerXY(cell);
      if ((x - cx).abs() > mx || (y - cy).abs() > my) continue;
      final center = px(x, y);
      final pts = [for (final (dx, dy) in HexGrid.cornerOffsets) center + Offset(dx * ppm, -dy * ppm)];
      hex.addPolygon(pts, true);
      if (drawTiles) tiles.addPolygon([for (final p in pts) center + (p - center) * 0.86], true);
    }

    Path? areaPath;
    final a = area;
    if (a != null) {
      areaPath = Path()..fillType = PathFillType.evenOdd;
      for (final ring in a.ringsXY) {
        if (ring.length < 3) continue;
        areaPath.addPolygon([for (final (x, y) in ring) px(x, y)], true);
      }
    }

    // Sương + vùng đang xem, rồi khoét các ô đã khám phá.
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = _fog);
    if (areaPath != null) canvas.drawPath(areaPath, Paint()..color = _areaShade);
    canvas.drawPath(
      hex,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = Colors.black,
    );
    canvas.restore();

    // Mặt ô lục giác sáng trên đường đã đi.
    if (drawTiles) {
      canvas.drawPath(tiles, Paint()..color = Colors.white.withValues(alpha: 0.38));
      canvas.drawPath(
        tiles,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.95),
      );
    }

    if (areaPath != null) {
      // Quầng sáng mềm quanh ranh giới, như mép kính phát sáng.
      canvas.drawPath(
        areaPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..color = AppColors.brand.withValues(alpha: 0.28),
      );
      canvas.drawPath(
        areaPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.85),
      );
      canvas.drawPath(
        areaPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.brand,
      );
    }
  }

  @override
  bool shouldRepaint(_FogPainter old) =>
      old.camera != camera || old.revision != revision || old.area != area || old.cells != cells;
}
