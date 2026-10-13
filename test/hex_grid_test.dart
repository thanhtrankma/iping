import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/hex_grid.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const hp = LatLng(20.8449, 106.6881); // Hải Phòng

  test('chiếu rồi chiếu ngược giữ nguyên toạ độ', () {
    final (x, y) = HexGrid.project(hp.latitude, hp.longitude);
    final back = HexGrid.unproject(x, y);
    expect(back.latitude, closeTo(hp.latitude, 1e-9));
    expect(back.longitude, closeTo(hp.longitude, 1e-9));
  });

  test('tâm ô thuộc chính ô đó, mã ô đọc lại được', () {
    final c = HexGrid.cellAt(hp.latitude, hp.longitude);
    final center = HexGrid.center(c);
    expect(HexGrid.cellAt(center.latitude, center.longitude), c);
    expect(HexCell.tryParse(c.id), c);
    expect(HexCell.tryParse('-12_-5'), const HexCell(-12, -5));
    expect(HexCell.tryParse('abc'), isNull);
    expect(HexCell.tryParse(''), isNull);
  });

  test('ô rộng khoảng 60–100 m ngoài thực địa', () {
    final c = HexGrid.cellAt(hp.latitude, hp.longitude);
    final a = HexGrid.center(c);
    final b = HexGrid.center(HexGrid.neighbours(c).first);
    final d = const Distance().as(LengthUnit.Meter, a, b);
    expect(d, inInclusiveRange(60, 100));
    // Diện tích một ô ~ 0,005 km².
    expect(HexGrid.areaM2(c), inInclusiveRange(3000, 7000));
  });

  test('6 đỉnh cách đều tâm và điểm gần đỉnh vẫn thuộc ô', () {
    final c = HexGrid.cellAt(hp.latitude, hp.longitude);
    final corners = HexGrid.corners(c);
    expect(corners, hasLength(6));
    final (cx, cy) = HexGrid.centerXY(c);
    for (final p in corners) {
      final (x, y) = HexGrid.project(p.latitude, p.longitude);
      // Lùi 10% về phía tâm.
      expect(HexGrid.cellAtXY(cx + (x - cx) * 0.9, cy + (y - cy) * 0.9), c);
    }
  });

  test('láng giềng và vòng tròn', () {
    const c = HexCell(10, -4);
    final n = HexGrid.neighbours(c);
    expect(n.toSet(), hasLength(6));
    expect(n.every((e) => HexGrid.distance(e, c) == 1), isTrue);
    expect(HexGrid.disk(c, 1).toSet(), {c, ...n});
    expect(HexGrid.disk(c, 2), hasLength(19));
  });

  test('đường thẳng đi qua các ô liền nhau', () {
    const b = LatLng(20.8549, 106.6981); // ~1,5 km về phía đông bắc
    final cells = HexGrid.line(hp, b);
    expect(cells.first, HexGrid.cellAt(hp.latitude, hp.longitude));
    expect(cells.last, HexGrid.cellAt(b.latitude, b.longitude));
    for (var i = 1; i < cells.length; i++) {
      expect(HexGrid.distance(cells[i - 1], cells[i]), 1);
    }
  });

  test('ô trong đa giác khớp với kiểm tra từng điểm', () {
    final square = [
      const LatLng(20.84, 106.68),
      const LatLng(20.84, 106.70),
      const LatLng(20.86, 106.70),
      const LatLng(20.86, 106.68),
    ];
    final hole = [
      const LatLng(20.845, 106.685),
      const LatLng(20.845, 106.69),
      const LatLng(20.85, 106.69),
      const LatLng(20.85, 106.685),
    ];
    final rings = [square, hole];
    final cells = HexGrid.cellsInPolygon(rings);
    expect(HexGrid.countCellsInPolygon(rings), cells.length);

    final xy = HexGrid.projectRings(rings);
    for (final c in cells) {
      final (x, y) = HexGrid.centerXY(c);
      expect(HexGrid.containsXY(xy, x, y), isTrue);
    }
    // Ô ở giữa lỗ không được tính.
    expect(cells.contains(HexGrid.cellAt(20.8475, 106.6875)), isFalse);

    // So với duyệt toàn bộ ô quanh hình.
    final all = <HexCell>{};
    final c0 = HexGrid.cellAt(20.85, 106.69);
    for (final c in HexGrid.disk(c0, 40)) {
      final (x, y) = HexGrid.centerXY(c);
      if (HexGrid.containsXY(xy, x, y)) all.add(c);
    }
    expect(cells.toSet(), all);
    // ~2,2 km x 2,1 km trừ lỗ, mỗi ô ~0,0046 km².
    expect(cells.length, inInclusiveRange(800, 1200));
  });

  test('bucket gom ô lân cận và tách ô xa', () {
    expect(HexGrid.bucketOf(const HexCell(0, 0)), HexGrid.bucketOf(const HexCell(63, 63)));
    expect(HexGrid.bucketOf(const HexCell(-1, 0)), isNot(HexGrid.bucketOf(const HexCell(0, 0))));
    expect(HexGrid.bucketOf(const HexCell(-1, -1)), 'b-1_-1');
  });

  test('đường đi nối các điểm gần nhau, bỏ qua bước nhảy xa', () {
    final t0 = DateTime(2026, 10, 13, 8);
    const a = LatLng(20.8449, 106.6881);
    const b = LatLng(20.8489, 106.6881); // ~450 m về phía bắc
    const far = LatLng(21.0285, 105.8542); // Hà Nội
    final cells = HexGrid.trackCells([
      (a, t0),
      (b, t0.add(const Duration(minutes: 1))),
      (far, t0.add(const Duration(minutes: 2))),
    ], radius: 0);
    final path = HexGrid.line(a, b).toSet();
    expect(cells.containsAll(path), isTrue);
    expect(cells, hasLength(path.length + 1));
    expect(cells.contains(HexGrid.cellAt(far.latitude, far.longitude)), isTrue);

    final wide = HexGrid.trackCells([(a, t0)]);
    expect(wide, hasLength(7));
  });
}
