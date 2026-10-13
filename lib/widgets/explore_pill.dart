import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/area_service.dart';
import '../services/explore_service.dart';
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

  void _recount() {
    final a = _area;
    if (a == null || a.totalCells == 0 || !mounted) return;
    setState(() => _percent = math.min(100, a.exploredIn(_explore.cells) * 100 / a.totalCells));
  }

  @override
  Widget build(BuildContext context) {
    final p = _percent;
    final value = p == null ? null : (p > 0 && p < 0.05 ? '<0,1%' : percentLabel(p));
    return Glass(
      radius: 30,
      opacity: 0.55,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 10, 7),
                child: value == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.explore_rounded, color: AppColors.brand, size: 22),
                            SizedBox(width: 6),
                            Text('Khám phá', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(value,
                              style: const TextStyle(
                                  fontSize: 20,
                                  height: 1.1,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: -0.5)),
                          const Text('đã khám phá', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Tooltip(
                message: 'Bảng xếp hạng',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onLeaderboard,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                    child: const Icon(Icons.leaderboard_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
