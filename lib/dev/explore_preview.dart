// Xem thử hiệu ứng ô lục giác của màn Khám phá mà không cần đăng nhập / Firebase.
//
//   flutter run -t lib/dev/explore_preview.dart
//
// Dữ liệu giả: một vùng đã đi quanh Hồ Gươm, rồi mô phỏng đang đi bộ để thấy các ô mới "nổ".
// Chạm vào bản đồ để mở thêm một cụm ô. Không ghi gì vào tài khoản.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/hex_grid.dart';
import '../theme.dart';
import '../widgets/explore_fog.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: const ExplorePreview(),
    ));

class ExplorePreview extends StatefulWidget {
  const ExplorePreview({super.key});

  @override
  State<ExplorePreview> createState() => _ExplorePreviewState();
}

class _ExplorePreviewState extends State<ExplorePreview> with TickerProviderStateMixin {
  late final _reveal = HexRevealController(vsync: this);
  final _cells = <HexCell>{};
  int _rev = 0;
  Timer? _walk;
  var _step = 0;

  // Đường đi giả: vòng quanh Hồ Gươm rồi ra phố cổ.
  static const _route = [
    LatLng(21.0287, 105.8524),
    LatLng(21.0300, 105.8530),
    LatLng(21.0312, 105.8522),
    LatLng(21.0322, 105.8508),
    LatLng(21.0333, 105.8496),
    LatLng(21.0345, 105.8489),
    LatLng(21.0356, 105.8481),
    LatLng(21.0366, 105.8470),
    LatLng(21.0372, 105.8455),
  ];
  static const _home = LatLng(21.0285, 105.8542);

  @override
  void initState() {
    super.initState();
    // Vùng đã khám phá sẵn: dải phố quanh hồ.
    _cells.addAll(HexGrid.trackCells([
      for (final (i, p) in const [
        LatLng(21.0250, 105.8500),
        LatLng(21.0262, 105.8545),
        LatLng(21.0285, 105.8542),
        LatLng(21.0275, 105.8590),
        LatLng(21.0240, 105.8600),
      ].indexed)
        (p, DateTime(2026, 1, 1, 8, i)),
    ], radius: 1));
    _walk = Timer.periodic(const Duration(milliseconds: 1400), (_) => _next());
  }

  void _next() {
    if (_step >= _route.length - 1) {
      _walk?.cancel();
      return;
    }
    final a = _route[_step], b = _route[_step + 1];
    _step++;
    final added = HexGrid.trackCells([(a, DateTime(2026, 1, 1, 9, _step)), (b, DateTime(2026, 1, 1, 9, _step, 20))],
            radius: 1)
        .where(_cells.add)
        .toList();
    if (added.isEmpty) return;
    _reveal.pop(added, origin: HexGrid.cellAt(b.latitude, b.longitude));
    setState(() => _rev++);
  }

  @override
  void dispose() {
    _walk?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(21.0305, 105.8525),
          initialZoom: 15.6,
          onTap: (_, p) {
            final c = HexGrid.cellAt(p.latitude, p.longitude);
            final added = HexGrid.disk(c, 2).where(_cells.add).toList();
            _reveal.pop(added, origin: c);
            setState(() => _rev++);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.iping.app',
          ),
          ExploreFogLayer(
            cells: _cells,
            revision: _rev,
            reveal: _reveal,
            origin: HexGrid.cellAt(_home.latitude, _home.longitude),
          ),
        ],
      ),
    );
  }
}
