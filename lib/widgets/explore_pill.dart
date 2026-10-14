import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/area_service.dart';
import '../services/explore_service.dart';
import '../services/hex_grid.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'glass.dart';

/// Viên "x% đã khám phá" kiểu Bump trên màn hình chính.
/// Chạm vào phần chữ để mở bản đồ khám phá, chạm nút tròn để xem bảng xếp hạng.
class ExplorePill extends StatefulWidget {
  const ExplorePill({super.key, required this.onOpen, required this.onLeaderboard});
  final VoidCallback onOpen;
  final VoidCallback onLeaderboard;

  @override
  State<ExplorePill> createState() => _ExplorePillState();
}

class _ExplorePillState extends State<ExplorePill> {
  final _explore = ExploreService.instance;
  ExploreArea? _area;
  double? _percent;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    _explore.revision.addListener(_recount);
    LocationService.instance.lastPosition.addListener(_onMove);
    _onMove();
  }

  @override
  void dispose() {
    _explore.revision.removeListener(_recount);
    LocationService.instance.lastPosition.removeListener(_onMove);
    super.dispose();
  }

  Future<void> _onMove() async {
    if (_looking) return;
    // Khi đang tắt chia sẻ thì chưa có luồng vị trí: lấy vị trí hiện tại một lần.
    final p = LocationService.instance.lastPosition.value ?? await LocationService.instance.currentPosition();
    if (p == null || !mounted) return;
    final me = LatLng(p.latitude, p.longitude);
    if (_area?.contains(me) ?? false) return;
    _looking = true;
    // Ưu tiên ranh giới đã lưu; chỉ hỏi Nominatim khi sang khu vực mới.
    final area = await AreaService.instance.cachedAt(me) ?? await AreaService.instance.areaAt(me);
    _looking = false;
    if (!mounted || area == null) return;
    _area = area;
    _recount();
  }

  // Đếm dồn: chỉ kiểm tra các ô mới thêm từ lần trước (cells chỉ tăng, giữ thứ tự thêm vào).
  // Đếm lại toàn bộ mỗi khi có ô mới tốn O(số ô × số đỉnh ranh giới) trên luồng UI.
  ExploreArea? _countedArea;
  int _processed = 0;
  int _inArea = 0;
  HexCell? _first;

  void _recount() {
    final a = _area;
    if (a == null || a.totalCells == 0 || !mounted) return;
    final cells = _explore.cells;
    // Đổi khu vực, hoặc tập ô bị xoá và nạp lại (đổi tài khoản): đếm lại từ đầu.
    if (!identical(a, _countedArea) || cells.length < _processed || (cells.isNotEmpty && cells.first != _first)) {
      _countedArea = a;
      _first = cells.isEmpty ? null : cells.first;
      _processed = 0;
      _inArea = 0;
    }
    if (cells.length > _processed) {
      _inArea += a.exploredIn(cells.skip(_processed));
      _processed = cells.length;
    }
    setState(() => _percent = math.min(100, _inArea * 100 / a.totalCells));
  }

  @override
  Widget build(BuildContext context) {
    final p = _percent;
    final value = p == null ? null : (p > 0 && p < 0.05 ? '<0,1%' : percentLabel(p));
    final scheme = Theme.of(context).colorScheme;
    // Viên kính cao 50px như các nút bản đồ; nút tròn bên phải đồng tâm (50 − 2×4).
    return Glass(
      capsule: true,
      opacity: 0.6,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassPressable(
            onTap: widget.onOpen,
            shape: const StadiumBorder(),
            scale: 0.95,
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                child: value == null
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.explore_rounded, color: AppColors.brand, size: 22),
                          SizedBox(width: 6),
                          Text('Khám phá', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(value,
                              style: const TextStyle(
                                  fontSize: 19,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6)),
                          Text('đã khám phá',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface.withValues(alpha: 0.55))),
                        ],
                      ),
              ),
            ),
          ),
          Tooltip(
            message: 'Bảng xếp hạng',
            child: GlassPressable(
              onTap: widget.onLeaderboard,
              shape: const CircleBorder(),
              scale: 0.88,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.8),
                  boxShadow: [
                    BoxShadow(color: AppColors.brand.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: const Icon(Icons.leaderboard_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
