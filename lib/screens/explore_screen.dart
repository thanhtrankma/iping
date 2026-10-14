import 'dart:async';

import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
import 'explore_leaderboard_screen.dart';

/// Màn "Khám phá": bản đồ phủ sương, mở dần theo những nơi đã đi qua.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> with TickerProviderStateMixin {
  final _map = MapController();
  final _explore = ExploreService.instance;
  late final _reveal = HexRevealController(vsync: this);
  StreamSubscription<List<HexCell>>? _revealSub;

  LatLng? _me;
  ExploreArea? _area;
  bool _loadingArea = false;
  bool _areaFailed = false;
  int _explored = 0;

  /// Đã có quyền vị trí chưa (`null` = đang kiểm tra). Màn này KHÔNG tự xin quyền.
  bool? _permitted;
  bool _starting = false;

  /// Đang tắt chia sẻ nhưng đã có quyền: lấy vị trí định kỳ CHỈ khi màn này đang mở ở tiền cảnh.
  Timer? _poll;
  bool _polling = false;
  static const _pollEvery = Duration(seconds: 15);

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
    _explore.screenVisible = true;
    _explore.revision.addListener(_recount);
    LocationService.instance.lastPosition.addListener(_onMove);
    // Ô mới mở khi đang đi: "nổ" lần lượt từ chỗ mình đứng ra ngoài.
    _revealSub = _explore.revealed.listen((cells) {
      final me = _me;
      _reveal.pop(cells, origin: me == null ? null : HexGrid.cellAt(me.latitude, me.longitude));
    });
    _start();
  }

  @override
  void dispose() {
    _explore.screenVisible = false;
    _poll?.cancel();
    _map.dispose();
    _revealSub?.cancel();
    _reveal.dispose();
    _explore.revision.removeListener(_recount);
    LocationService.instance.lastPosition.removeListener(_onMove);
    super.dispose();
  }

  Future<void> _start() async {
    final loc = LocationService.instance;
    final permitted = await loc.hasPermission();
    if (!mounted) return;
    setState(() => _permitted = permitted);
    if (!permitted) return; // Hiện nút "Bật chia sẻ vị trí…" thay vì hỏi quyền.
    // Căn bản đồ bằng vị trí đã có (không bật GPS, không hỏi gì).
    final pos = await loc.devicePosition();
    if (!mounted) return;
    if (pos != null && _me == null) {
      _me = LatLng(pos.latitude, pos.longitude);
      _map.move(_me!, 15);
      setState(() {});
    }
    _startPolling();
    await _loadArea();
  }

  /// Mở sương ở chỗ đang đứng khi màn Khám phá đang mở mà chưa bật chia sẻ.
  /// Không dùng luồng vị trí (geolocator dùng chung một luồng với chia sẻ nền) và dừng khi rời màn hình.
  void _startPolling() {
    _poll?.cancel();
    _pollOnce();
    _poll = Timer.periodic(_pollEvery, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    // Đang chia sẻ thì vị trí đến từ luồng chia sẻ ([_onMove]); app ở nền thì không lấy.
    if (_polling || !mounted || LocationService.instance.sharing.value || !_explore.mayRecord) return;
    _polling = true;
    try {
      final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 12));
      if (!mounted || !_explore.mayRecord) return;
      final first = _me == null;
      setState(() => _me = LatLng(p.latitude, p.longitude));
      _explore.record(p.latitude, p.longitude, accuracy: p.accuracy, time: p.timestamp);
      if (first) _map.move(_me!, 15);
      final a = _area;
      if (a == null || !a.contains(_me!)) _loadArea();
    } catch (e) {
      debugPrint('Explore position: $e');
    } finally {
      _polling = false;
    }
  }

  /// Chưa có quyền vị trí: đi theo đúng luồng bật chia sẻ (màn giải thích → quyền hệ thống).
  Future<void> _enableSharing() async {
    if (_starting) return;
    setState(() => _starting = true);
    final err = await LocationService.instance.start();
    if (!mounted) return;
    setState(() => _starting = false);
    if (err != null) {
      showMessage(context, err);
      return;
    }
    setState(() => _permitted = true);
    _onMove();
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
    _explore.publishArea(a.name, _percent);
  }

  void _openLeaderboard() {
    final groups = LocationService.instance.groups;
    final selected = SettingsService.instance.selectedGroupId.value;
    final gid = groups.any((g) => g.id == selected) ? selected : groups.firstOrNull?.id;
    if (gid == null) {
      showMessage(context, 'Hãy tạo hoặc tham gia một nhóm để xem bảng xếp hạng.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExploreLeaderboardScreen(groupId: gid, myUid: FirebaseAuth.instance.currentUser!.uid),
    ));
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
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    showGlassSheet<void>(
      context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              if (a.displayName.isNotEmpty)
                Text(a.displayName,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: secondary, fontSize: 14)),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(percentLabel(_percent),
                      style: const TextStyle(
                          fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -2, color: AppColors.brand)),
                  const SizedBox(width: 8),
                  Text('đã khám phá', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: secondary)),
                ],
              ),
              const SizedBox(height: 10),
              _ProgressCapsule(value: _percent / 100),
              const SizedBox(height: 18),
              _StatGroup(rows: [
                _StatRow(label: 'Số ô đã đi qua', value: '$_explored / ${a.totalCells}'),
                _StatRow(label: 'Diện tích đã khám phá', value: areaLabel(_explored * cellArea)),
                _StatRow(label: 'Diện tích khu vực', value: areaLabel(a.totalCells * cellArea)),
                _StatRow(label: 'Tổng số ô bạn đã mở', value: '${_explore.cells.length}'),
              ]),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Mỗi ô lục giác rộng khoảng 70 m. Đi qua đâu, sương sẽ tan ở đó.',
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
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

    return BackdropGroup(child: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IPingMap(
              controller: _map,
              center: _me ?? defaultCenter,
              zoom: 15,
              style: MapStyle.standard,
              showAttribution: false,
              // Bản debug: chạm bản đồ để xem thử hiệu ứng nổ ô (không lưu vào dữ liệu khám phá).
              onTap: kDebugMode
                  ? (_, p) => _reveal.pop(HexGrid.disk(HexGrid.cellAt(p.latitude, p.longitude), 2),
                      origin: HexGrid.cellAt(p.latitude, p.longitude), demoOnly: true)
                  : null,
              layers: [
                ValueListenableBuilder<int>(
                  valueListenable: _explore.revision,
                  builder: (context, rev, _) => ExploreFogLayer(
                    cells: _explore.cells,
                    revision: rev,
                    area: a,
                    reveal: _reveal,
                    origin: _me == null ? null : HexGrid.cellAt(_me!.latitude, _me!.longitude),
                  ),
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
          // Ghi nguồn bản đồ ngay trên thanh dưới, không bị che.
          Positioned(
            left: 16,
            bottom: pad.bottom + 16 + 50 + 10,
            child: const MapAttribution(style: MapStyle.standard),
          ),
          // Thanh dưới cùng.
          Positioned(
            left: 16,
            right: 16,
            bottom: pad.bottom + 16,
            child: Row(
              children: [
                GlassButton(icon: Icons.close_rounded, tooltip: 'Đóng', onTap: () => Navigator.pop(context)),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Glass(
                        capsule: true,
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: GlassPressable(
                                onTap: _showDetails,
                                shape: const StadiumBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                                  child: a == null
                                      ? const Text('Đang tính…',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))
                                      : Text.rich(
                                          TextSpan(children: [
                                            TextSpan(
                                              text: percent,
                                              style: const TextStyle(
                                                  fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                                            ),
                                            TextSpan(
                                              text: ' đã khám phá',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                                              ),
                                            ),
                                          ]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Bảng xếp hạng',
                              child: GlassPressable(
                                onTap: _openLeaderboard,
                                shape: const CircleBorder(),
                                scale: 0.9,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.brandGradient,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.brand.withValues(alpha: 0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.leaderboard_rounded, color: Colors.white, size: 22),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                GlassButton(icon: Icons.near_me_rounded, tooltip: 'Vị trí của tôi', onTap: _focusMe),
              ],
            ),
          ),
          if (_permitted == false)
            Positioned(
              left: 24,
              right: 24,
              bottom: pad.bottom + 90,
              child: _EnableSharingCard(busy: _starting, onTap: _enableSharing),
            ),
        ],
      ),
    ));
  }
}

/// Chưa có quyền vị trí: giải thích và mời bật chia sẻ (không tự hỏi quyền).
class _EnableSharingCard extends StatelessWidget {
  const _EnableSharingCard({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Glass(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Bật chia sẻ vị trí để mở bản đồ khám phá',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Sương chỉ tan ở nơi bạn đi qua khi đang chia sẻ vị trí với nhóm hoặc khi màn này đang mở.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.35, color: secondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : onTap,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.location_on_rounded),
            label: const Text('Bật chia sẻ vị trí'),
          ),
        ],
      ),
    );
  }
}

/// Dòng chỉ số trong nhóm (nhãn bên trái, giá trị đậm bên phải).
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15.5, letterSpacing: -0.2))),
          Text(value, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ],
      ),
    );
  }
}

/// Nhóm dòng kiểu inset-grouped trên nền mờ (sheet đã là kính nên không lồng kính).
class _StatGroup extends StatelessWidget {
  const _StatGroup({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: glassShape(radius: 22),
        color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.55),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 0.5, thickness: 0.5, indent: 16, color: scheme.onSurface.withValues(alpha: 0.12)),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Thanh tiến độ dạng viên thuốc với phần đã đạt màu gradient thương hiệu.
class _ProgressCapsule extends StatelessWidget {
  const _ProgressCapsule({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Container(
      height: 12,
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
      ),
      alignment: Alignment.centerLeft,
      child: v <= 0
          ? null
          : FractionallySizedBox(
              widthFactor: v < 0.03 ? 0.03 : v,
              child: const DecoratedBox(
                decoration: ShapeDecoration(shape: StadiumBorder(), gradient: AppColors.brandGradient),
                child: SizedBox.expand(),
              ),
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
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.1,
      letterSpacing: -fontSize * 0.025,
    );
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

/// Bong bóng phần trăm trên khu vực: "7,2% ›" — viên kính nhỏ nổi trên bản đồ.
class _PercentBubble extends StatelessWidget {
  const _PercentBubble({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GlassPill(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          Icon(Icons.chevron_right_rounded, color: color, size: 20),
        ],
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
  static const _track = 16.0;

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
              width: _track,
              child: Glass(
                capsule: true,
                opacity: 0.7,
                padding: const EdgeInsets.all(3),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    width: _track - 6,
                    height: math.max(_track - 6, (track - 6) * frac),
                    decoration: const ShapeDecoration(shape: StadiumBorder(), gradient: AppColors.brandGradient),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            bottom: track * frac,
            child: MemberAvatar(uid: uid, name: name, radius: _avatar, ring: true),
          ),
        ],
      ),
    );
  }
}
