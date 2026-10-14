import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/hex_grid.dart';
import 'package:gan_nhau/widgets/explore_fog.dart';

void main() {
  test('cạnh thứ i của ô giáp đúng ô láng giềng hexEdgeNeighbour[i]', () {
    const c = HexCell(3, -2);
    final (x, y) = HexGrid.centerXY(c);
    for (var i = 0; i < 6; i++) {
      final (ax, ay) = HexGrid.cornerOffsets[i];
      final (bx, by) = HexGrid.cornerOffsets[(i + 1) % 6];
      // Tâm ô láng giềng = tâm ô + 2 lần trung điểm cạnh chung.
      final (dq, dr) = hexEdgeNeighbour[i];
      final (nx, ny) = HexGrid.centerXY(HexCell(c.q + dq, c.r + dr));
      expect(nx - x, closeTo(ax + bx, 1e-6), reason: 'cạnh $i (x)');
      expect(ny - y, closeTo(ay + by, 1e-6), reason: 'cạnh $i (y)');
    }
  });

  test('hexEdgeNeighbour là đủ 6 láng giềng, không trùng', () {
    const c = HexCell(0, 0);
    final fromEdges = {for (final (dq, dr) in hexEdgeNeighbour) HexCell(dq, dr)};
    expect(fromEdges, HexGrid.neighbours(c).toSet());
  });
}
