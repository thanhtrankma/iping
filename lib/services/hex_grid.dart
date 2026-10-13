import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Một ô lục giác (toạ độ trục q, r).
class HexCell {
  const HexCell(this.q, this.r);
  final int q;
  final int r;

  /// Mã ô dạng "q_r", dùng để lưu trữ.
  String get id => '${q}_$r';

  static HexCell? tryParse(String id) {
    final i = id.length < 3 ? -1 : id.indexOf('_', 1);
    if (i < 0) return null;
    final q = int.tryParse(id.substring(0, i));
    final r = int.tryParse(id.substring(i + 1));
    return q == null || r == null ? null : HexCell(q, r);
  }

  @override
  bool operator ==(Object other) => other is HexCell && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'HexCell($q, $r)';
}

/// Lưới lục giác đỉnh nhọn trên phép chiếu Web Mercator (đơn vị mét Mercator).
///
/// Ô có bán kính ngoại tiếp [size] = 45 m Mercator, tức rộng ~78 m Mercator
/// (~73 m thật ở Việt Nam, ~62 m ở vĩ độ 37°).
class HexGrid {
  HexGrid._();

  static const earthRadius = 6378137.0;
  static const size = 45.0;
  static const _maxLat = 85.05112878;
  static final _sqrt3 = math.sqrt(3);

  /// Số ô mỗi chiều của một "bucket" lưu trữ (64 x 64 ô ≈ 5 x 4 km).
  static const bucketBits = 6;

  // ---- Phép chiếu ----

  static (double, double) project(double lat, double lng) {
    final la = lat.clamp(-_maxLat, _maxLat) * math.pi / 180;
    final x = earthRadius * lng * math.pi / 180;
    final y = earthRadius * math.log(math.tan(math.pi / 4 + la / 2));
    return (x, y);
  }

  static LatLng unproject(double x, double y) {
    final lng = x / earthRadius * 180 / math.pi;
    final lat = (2 * math.atan(math.exp(y / earthRadius)) - math.pi / 2) * 180 / math.pi;
    return LatLng(lat, lng);
  }

  // ---- Ô <-> toạ độ ----

  static HexCell cellAt(double lat, double lng) {
    final (x, y) = project(lat, lng);
    return cellAtXY(x, y);
  }

  static HexCell cellAtXY(double x, double y) {
    final fq = (_sqrt3 / 3 * x - y / 3) / size;
    final fr = (2 / 3 * y) / size;
    return _round(fq, fr);
  }

  static HexCell _round(double fq, double fr) {
    final fs = -fq - fr;
    var q = fq.round();
    var r = fr.round();
    final s = fs.round();
    final dq = (q - fq).abs();
    final dr = (r - fr).abs();
    final ds = (s - fs).abs();
    if (dq > dr && dq > ds) {
      q = -r - s;
    } else if (dr > ds) {
      r = -q - s;
    }
    return HexCell(q, r);
  }

  static (double, double) centerXY(HexCell c) => (size * _sqrt3 * (c.q + c.r / 2), size * 1.5 * c.r);

  static LatLng center(HexCell c) {
    final (x, y) = centerXY(c);
    return unproject(x, y);
  }

  /// Độ lệch 6 đỉnh so với tâm (mét Mercator), bắt đầu từ đỉnh trên cùng.
  static final List<(double, double)> cornerOffsets = [
    for (var i = 0; i < 6; i++)
      (size * math.cos(math.pi / 180 * (60 * i - 90)), -size * math.sin(math.pi / 180 * (60 * i - 90))),
  ];

  static List<LatLng> corners(HexCell c) {
    final (x, y) = centerXY(c);
    return [for (final (dx, dy) in cornerOffsets) unproject(x + dx, y + dy)];
  }

  /// Diện tích thật (m²) của ô, theo hệ số co của Mercator tại tâm ô.
  static double areaM2(HexCell c) {
    final lat = center(c).latitude * math.pi / 180;
    final k = math.cos(lat);
    return 1.5 * _sqrt3 * size * size * k * k;
  }

  // ---- Láng giềng ----

  static const _dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];

  static List<HexCell> neighbours(HexCell c) => [for (final (dq, dr) in _dirs) HexCell(c.q + dq, c.r + dr)];

  /// Mọi ô cách [c] không quá [radius] bước (kể cả [c]).
  static List<HexCell> disk(HexCell c, int radius) => [
        for (var dq = -radius; dq <= radius; dq++)
          for (var dr = math.max(-radius, -dq - radius); dr <= math.min(radius, -dq + radius); dr++)
            HexCell(c.q + dq, c.r + dr),
      ];

  static int distance(HexCell a, HexCell b) {
    final dq = a.q - b.q;
    final dr = a.r - b.r;
    return (dq.abs() + dr.abs() + (dq + dr).abs()) ~/ 2;
  }

  /// Các ô nằm trên đoạn thẳng từ [a] đến [b] (toạ độ độ).
  static List<HexCell> line(LatLng a, LatLng b) {
    final (x0, y0) = project(a.latitude, a.longitude);
    final (x1, y1) = project(b.latitude, b.longitude);
    final n = math.max(1, (math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2)) / (size * 0.75)).ceil());
    final out = <HexCell>{};
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      out.add(cellAtXY(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t));
    }
    return out.toList();
  }

  /// Các ô được mở ra khi đi qua một chuỗi điểm theo thời gian: ô tại mỗi điểm và
  /// [radius] vòng xung quanh; hai điểm liên tiếp gần nhau (≤ [maxGap] m, ≤ [maxTime])
  /// được nối bằng đường thẳng để lấp kín đoạn đường đã đi.
  static Set<HexCell> trackCells(
    List<(LatLng, DateTime)> points, {
    int radius = 1,
    double maxGap = 1500,
    Duration maxTime = const Duration(minutes: 15),
  }) {
    final core = <HexCell>{};
    for (var i = 0; i < points.length; i++) {
      final (p, t) = points[i];
      if (i > 0) {
        final (prev, pt) = points[i - 1];
        final gap = const Distance().as(LengthUnit.Meter, prev, p);
        if (gap <= maxGap && t.difference(pt).abs() <= maxTime) {
          core.addAll(line(prev, p));
          continue;
        }
      }
      core.add(cellAt(p.latitude, p.longitude));
    }
    if (radius == 0) return core;
    return {for (final c in core) ...disk(c, radius)};
  }

  // ---- Bucket lưu trữ ----

  static String bucketOf(HexCell c) => 'b${c.q >> bucketBits}_${c.r >> bucketBits}';

  // ---- Đa giác ----

  /// Chiếu các vòng của một (đa) đa giác sang mét Mercator.
  static List<List<(double, double)>> projectRings(List<List<LatLng>> rings) => [
        for (final ring in rings) [for (final p in ring) project(p.latitude, p.longitude)],
      ];

  /// Điểm (x, y) có nằm trong đa giác không (quy tắc chẵn-lẻ, hỗ trợ lỗ và nhiều mảnh).
  static bool containsXY(List<List<(double, double)>> rings, double x, double y) {
    var inside = false;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final (xi, yi) = ring[i];
        final (xj, yj) = ring[j];
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
      }
    }
    return inside;
  }

  /// Các ô có tâm nằm trong đa giác.
  static List<HexCell> cellsInPolygon(List<List<LatLng>> rings) {
    final out = <HexCell>[];
    _scan(projectRings(rings), (r, q0, q1) {
      for (var q = q0; q <= q1; q++) {
        out.add(HexCell(q, r));
      }
    });
    return out;
  }

  /// Số ô có tâm nằm trong đa giác, không cần tạo danh sách ô.
  static int countCellsInPolygon(List<List<LatLng>> rings) => countCellsInRingsXY(projectRings(rings));

  static int countCellsInRingsXY(List<List<(double, double)>> rings) {
    var n = 0;
    _scan(rings, (r, q0, q1) => n += q1 - q0 + 1);
    return n;
  }

  /// Quét từng hàng ô: tìm giao điểm của đường ngang qua tâm hàng với các cạnh.
  static void _scan(List<List<(double, double)>> rings, void Function(int r, int q0, int q1) emit) {
    var minY = double.infinity, maxY = -double.infinity;
    for (final ring in rings) {
      for (final (_, y) in ring) {
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
    if (minY > maxY) return;
    final w = size * _sqrt3;
    final xs = <double>[];
    for (var r = (minY / (1.5 * size)).ceil(); r <= (maxY / (1.5 * size)).floor(); r++) {
      final y = 1.5 * size * r;
      xs.clear();
      for (final ring in rings) {
        for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          final (xi, yi) = ring[i];
          final (xj, yj) = ring[j];
          if ((yi > y) != (yj > y)) xs.add((xj - xi) * (y - yi) / (yj - yi) + xi);
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        // Tâm ô: x = w * (q + r/2), lấy x0 <= x < x1 cho khớp với containsXY.
        final q0 = (xs[k] / w - r / 2).ceil();
        final q1 = (xs[k + 1] / w - r / 2).ceil() - 1;
        if (q1 >= q0) emit(r, q0, q1);
      }
    }
  }
}
