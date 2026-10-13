import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/area_service.dart';
import '../services/auth_service.dart';
import '../services/explore_service.dart';
import '../services/hex_grid.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/explore_fog.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';

/// Màn "Khám phá": bản đồ phủ sương, mở dần theo những nơi đã đi qua.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _map = MapController();
  final _explore = ExploreService.instance;

  LatLng? _me;
  ExploreArea? _area;
  bool _loadingArea = false;
  bool _areaFailed = false;
  int _explored = 0;

  double get _percent {
    final a = _area;
    if (a == null || a.totalCells == 0) return 0;
    return math.min(100, _explored * 100 / a.totalCells);
  }

  @override
  void initState() {
    super.initState();
    final p = LocationService.instance.lastPosition.value;
    if (p != null) _me = LatLng(p.latitude, p.longitude);
    _explore.revision.addListener(_recount);
    LocationService.instance.lastPosition.addListener(_onMove);
    _start();
  }

  @override
  void dispose() {
    _explore.revision.removeListener(_recount);
    LocationService.instance.lastPosition.removeListener(_onMove);
    super.dispose();
  }

  Future<void> _start() async {
    final pos = await LocationService.instance.currentPosition();
    if (!mounted) return;
    if (pos != null) {
      _me = LatLng(pos.latitude, pos.longitude);
      // Mở luôn ô hiện tại kể cả khi đang tắt chia sẻ.
      _explore.record(pos.latitude, pos.longitude, accuracy: pos.accuracy, time: pos.timestamp);
      _map.move(_me!, 15);
      setState(() {});
    }
    await _loadArea();
  }

  void _onMove() {
    final p = LocationService.instance.lastPosition.value;
    if (p == null || !mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    final a = _area;
    if (a != null && !a.contains(_me!)) _loadArea();
  }

  Future<void> _loadArea() async {
    final me = _me;
    if (me == null || _loadingArea) return;
    setState(() {
      _loadingArea = true;
      _areaFailed = false;
    });
    final area = await AreaService.instance.areaAt(me);
    if (!mounted) return;
    if (area != null && area.id != _area?.id) _fitArea(area);
    setState(() {
      _loadingArea = false;
      _areaFailed = area == null;
      if (area != null) _area = area;
    });
    _recount();
  }

  void _recount() {
    final a = _area;
    if (a == null || !mounted) return;
    setState(() => _explored = a.exploredIn(_explore.cells));
  }

  /// Đưa cả khu vực vào khung nhìn (không thu nhỏ quá mức 11 với khu vực lớn).
  void _fitArea(ExploreArea a) {
    final (x0, y0, x1, y1) = a.bboxXY;
    final bounds = LatLngBounds(HexGrid.unproject(x0, y0), HexGrid.unproject(x1, y1));
    final pad = MediaQuery.paddingOf(context);
    final fit = CameraFit.bounds(
      bounds: bounds,
      padding: EdgeInsets.fromLTRB(70, pad.top + 90, 30, pad.bottom + 110),
      minZoom: 11,
    ).fit(_map.camera);
    final me = _me;
    // Khu vực quá lớn: giữ người dùng ở giữa thay vì tâm khu vực.
    _map.move(fit.zoom <= 11 && me != null ? me : fit.center, fit.zoom);
  }

  void _focusMe() {
    final me = _me;
    if (me != null) _map.move(me, 16);
  }

  void _showDetails() {
    final a = _area;
    if (a == null) return;
    final cellArea = HexGrid.areaM2(HexGrid.cellAt(a.labelPoint.latitude, a.labelPoint.longitude));
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              if (a.displayName.isNotEmpty)
                Text(a.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _percent / 100, minHeight: 12),
              ),
              const SizedBox(height: 18),
              _StatRow(label: 'Đã khám phá', value: percentLabel(_percent)),
              _StatRow(label: 'Số ô đã đi qua', value: '$_explored / ${a.totalCells}'),
              _StatRow(label: 'Diện tích đã khám phá', value: areaLabel(_explored * cellArea)),
              _StatRow(label: 'Diện tích khu vực', value: areaLabel(a.totalCells * cellArea)),
              _StatRow(label: 'Tổng số ô bạn đã mở', value: '${_explore.cells.length}'),
              const SizedBox(height: 10),
              Text(
                'Mỗi ô lục giác rộng khoảng 70 m. Đi qua đâu, sương sẽ tan ở đó.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final name = AuthService.instance.displayName;
    final a = _area;
    final pad = MediaQuery.paddingOf(context);
    final percent = _percent > 0 && _percent < 0.05 ? '< 0,1%' : percentLabel(_percent);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IPingMap(
              controller: _map,
              center: _me ?? defaultCenter,
              zoom: 15,
              style: MapStyle.standard,
              layers: [
                ValueListenableBuilder<int>(
                  valueListenable: _explore.revision,
                  builder: (context, rev, _) => ExploreFogLayer(cells: _explore.cells, revision: rev, area: a),
                ),
                MarkerLayer(markers: [
                  if (_me != null)
                    Marker(
                      point: _me!,
                      width: 52,
                      height: 52,
                      child: MemberAvatar(uid: uid, name: name, radius: 22, ring: true),
                    ),
                  if (a != null)
                    Marker(
                      point: a.labelPoint,
                      width: 140,
                      height: 44,
                      child: Center(child: _PercentBubble(text: percent, onTap: _showDetails)),
                    ),
                ]),
              ],
            ),
          ),
          // Tên khu vực.
          Positioned(
            left: 18,
            right: 18,
            top: pad.top + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a != null)
                  _StickerText(shortAreaName(a.name), fontSize: 40)
                else
                  _StickerText(_loadingArea ? 'Đang tìm khu vực…' : 'Khám phá', fontSize: 30),
                if (_areaFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GlassPill(
                      onTap: _loadArea,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: const Text('Không tải được ranh giới khu vực · Thử lại',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          // Thước đo tiến độ bên trái.
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Center(child: _Gauge(percent: _percent, uid: uid, name: name)),
          ),
          // Thanh dưới cùng.
          Positioned(
            left: 16,
            right: 16,
            bottom: pad.bottom + 16,
            child: Row(
              children: [
                GlassButton(icon: Icons.close_rounded, tooltip: 'Đóng', onTap: () => Navigator.pop(context)),
                const Spacer(),
                GlassPill(
                  onTap: _showDetails,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text(
                    a == null ? 'Đang tính…' : '$percent đã khám phá',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                GlassButton(icon: Icons.near_me_rounded, tooltip: 'Vị trí của tôi', onTap: _focusMe),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Chữ trắng viền đậm kiểu sticker.
class _StickerText extends StatelessWidget {
  const _StickerText(this.text, {this.fontSize = 36});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.5);
    return Stack(
      children: [
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = fontSize * 0.18
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF1B2547),
          ),
        ),
        Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: base.copyWith(color: Colors.white)),
      ],
    );
  }
}

/// Bong bóng phần trăm trên khu vực: "7,2% ›".
class _PercentBubble extends StatelessWidget {
  const _PercentBubble({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: const TextStyle(color: AppColors.brandDeep, fontSize: 16, fontWeight: FontWeight.w900)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.brandDeep, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Thước dọc: avatar nằm ở mức % đã khám phá (thang căn bậc hai để mức nhỏ vẫn thấy rõ).
class _Gauge extends StatelessWidget {
  const _Gauge({required this.percent, required this.uid, required this.name});
  final double percent;
  final String uid;
  final String name;

  static const _height = 260.0;
  static const _avatar = 18.0;

  @override
  Widget build(BuildContext context) {
    final frac = math.sqrt((percent / 100).clamp(0, 1));
    const track = _height - _avatar * 2;
    return SizedBox(
      width: 48,
      height: _height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: _avatar,
            bottom: _avatar,
            child: SizedBox(
              width: 14,
              child: Glass(
                radius: 7,
                opacity: 0.7,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 14,
                    height: math.max(14, track * frac),
                    decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(7)),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            bottom: track * frac,
            child: MemberAvatar(uid: uid, name: name, radius: _avatar, ring: true),
          ),
        ],
      ),
    );
  }
}
