import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/trip_analyzer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';

String durationText(Duration d) {
  if (d.inMinutes < 1) return '<1 phút';
  if (d.inHours < 1) return '${d.inMinutes} phút';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} giờ' : '${d.inHours} giờ $m phút';
}

String kmh(double ms) => '${(ms * 3.6).round()} km/h';

List<LatLng> tripLatLngs(Trip t) => [for (final p in t.points) LatLng(p.lat, p.lng)];

/// Lớp vẽ tuyến đường của chuyến đi kèm điểm đầu/cuối.
List<Widget> tripLayers(Trip t, {Color color = AppColors.brand}) {
  final pts = tripLatLngs(t);
  return [
    PolylineLayer(polylines: [
      Polyline(points: pts, strokeWidth: 6, color: color, borderColor: Colors.white, borderStrokeWidth: 2.5),
    ]),
    CircleLayer(circles: [
      CircleMarker(point: pts.first, radius: 7, color: Colors.white, borderColor: color, borderStrokeWidth: 4),
      CircleMarker(point: pts.last, radius: 8, color: color, borderColor: Colors.white, borderStrokeWidth: 3),
    ]),
  ];
}

CameraFit fitPoints(List<LatLng> pts, {double padding = 40}) => pts.length == 1
    ? CameraFit.coordinates(coordinates: pts, maxZoom: 16)
    : CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: EdgeInsets.all(padding), maxZoom: 17);

/// Màu theo điểm an toàn: xanh ≥ 85, cam ≥ 60, đỏ còn lại.
Color _scoreColor(int score) => score >= 85
    ? AppColors.online
    : score >= 60
        ? AppColors.warning
        : AppColors.sos;

/// Màu chữ phụ kiểu iOS (~55% độ đậm).
Color _secondary(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

/// Nền mờ bên trong thẻ kính (thay cho việc lồng kính trong kính).
Color _innerFill(BuildContext context, {Color? tint, double strength = 1}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (tint != null) return tint.withValues(alpha: (dark ? 0.22 : 0.13) * strength);
  return dark ? Colors.white.withValues(alpha: 0.07 * strength) : Colors.white.withValues(alpha: 0.5 * strength);
}

/// Bản đồ nhỏ không tương tác hiển thị một chuyến đi.
class TripMiniMap extends StatefulWidget {
  const TripMiniMap({super.key, required this.trip, this.height = 200});
  final Trip trip;
  final double height;

  @override
  State<TripMiniMap> createState() => _TripMiniMapState();
}

class _TripMiniMapState extends State<TripMiniMap> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final pts = tripLatLngs(trip);
    return SizedBox(
      height: widget.height,
      child: IgnorePointer(
        child: IPingMap(
          controller: _map,
          center: pts.first,
          fit: fitPoints(pts, padding: 30),
          interactive: false,
          layers: tripLayers(trip),
        ),
      ),
    );
  }
}

/// Thẻ "Chuyến đi gần đây" giống iSharing.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.title = 'Chuyến đi', this.onTap, this.footer});
  final Trip trip;
  final String title;
  final VoidCallback? onTap;
  final Widget? footer;

  static const _radius = 30.0;
  static const _inset = 8.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text(
                      '${clock(trip.start)} ~ ${clock(trip.end)} · ${durationText(trip.duration)}',
                      style: TextStyle(color: _secondary(context), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (onTap != null) const _ChevronCircle(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GlassIconBadge(
                icon: trip.isDrive ? Icons.directions_car_rounded : Icons.directions_walk_rounded,
                color: trip.isDrive ? AppColors.brand : AppColors.teal,
                size: 44,
              ),
              const SizedBox(width: 14),
              Text(
                distanceLabel(trip.distance).replaceAll('.', ','),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('TỐI ĐA',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: _secondary(context))),
                  Text(kmh(trip.maxSpeed),
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: scheme.onSurface)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Route(from: trip.from, to: trip.to),
        ],
      ),
    );

    return Glass(
      radius: _radius,
      opacity: 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onTap != null)
            GlassPressable(onTap: onTap, scale: 0.98, shape: glassShape(radius: _radius), child: header)
          else
            header,
          // Bản đồ thụt vào trong thẻ, góc bo đồng tâm với thẻ.
          Padding(
            padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, _inset),
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: glassShape(radius: _radius - _inset)),
              child: Stack(
                children: [
                  TripMiniMap(trip: trip),
                  if (footer != null) Positioned(right: 12, bottom: 12, child: footer!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút mũi tên tròn nhỏ, nền mờ (không phải kính để tránh kính lồng kính).
class _ChevronCircle extends StatelessWidget {
  const _ChevronCircle({this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(shape: const CircleBorder(), color: scheme.onSurface.withValues(alpha: 0.07)),
      child: Icon(Icons.chevron_right_rounded, size: size * 0.62, color: scheme.onSurface.withValues(alpha: 0.6)),
    );
  }
}

/// Điểm đi → điểm đến, nối bằng đường chấm dọc như bản đồ Apple.
class _Route extends StatelessWidget {
  const _Route({required this.from, required this.to});
  final TrackPoint from;
  final TrackPoint to;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.18);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 4),
                const _Dot(filled: false),
                Expanded(child: Center(child: Container(width: 2, color: line))),
                const _Dot(filled: true),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressText(from.lat, from.lng,
                    maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                AddressText(to.lat, to.lng,
                    maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppColors.brand : Colors.white,
        border: Border.all(color: filled ? Colors.white : AppColors.brand, width: filled ? 2.5 : 3.5),
        boxShadow: filled ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.4), blurRadius: 6)] : null,
      ),
    );
  }
}

/// Lịch sử vị trí theo ngày: bản đồ tuyến đường + dòng thời gian dừng / di chuyển.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.groupId, required this.uid, required this.name, this.fallbackCenter});
  final String groupId;
  final String uid;
  final String name;

  /// Tâm bản đồ khi ngày được chọn không có dữ liệu.
  final LatLng? fallbackCenter;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }
  late DateTime _day = _startOfDay(DateTime.now());
  Future<List<Segment>>? _timeline;
  int? _selected;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _selected = null;
    _timeline = GroupService.instance
        .history(widget.groupId, widget.uid, _day, _day.add(const Duration(days: 1)))
        .then(buildTimeline);
  }

  String _dayLabel(DateTime d) {
    final today = _startOfDay(DateTime.now());
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    const wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return '${wd[d.weekday - 1]} ${d.day}/${d.month}';
  }

  void _select(int i, List<Segment> segs) {
    setState(() => _selected = i);
    final s = segs[i];
    final pts = s is Trip ? tripLatLngs(s) : [LatLng((s as Stay).lat, s.lng)];
    _map.fitCamera(fitPoints(pts, padding: 60));
  }

  @override
  Widget build(BuildContext context) {
    final today = _startOfDay(DateTime.now());
    return BackdropGroup(child: Scaffold(
      body: FutureBuilder<List<Segment>>(
        future: _timeline,
        builder: (context, snap) {
          final segs = snap.data ?? const <Segment>[];
          final trips = segs.whereType<Trip>().toList();
          final allPts = [for (final t in trips) ...tripLatLngs(t)];
          for (final s in segs.whereType<Stay>()) {
            allPts.add(LatLng(s.lat, s.lng));
          }
          return Stack(
            children: [
              Positioned.fill(
                child: IPingMap(
                  key: ValueKey('$_day-${segs.length}'),
                  controller: _map,
                  center: allPts.isEmpty ? (widget.fallbackCenter ?? defaultCenter) : allPts.first,
                  fit: allPts.isEmpty ? null : fitPoints(allPts, padding: 60),
                  layers: [
                    for (var i = 0; i < segs.length; i++)
                      if (segs[i] is Trip)
                        ...tripLayers(segs[i] as Trip,
                            color: _selected == null || _selected == i
                                ? AppColors.brand
                                : AppColors.brand.withValues(alpha: 0.35)),
                    MarkerLayer(markers: [
                      for (final s in segs.whereType<Stay>())
                        Marker(
                          point: LatLng(s.lat, s.lng),
                          width: 32,
                          height: 32,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.indigo,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                            ),
                            child: const Icon(Icons.home_work_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
              // Thanh trên nổi: nút quay lại + tiêu đề dạng viên thuốc.
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Row(
                    children: [
                      GlassButton(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Quay lại',
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Glass(
                          capsule: true,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          child: Text('Lịch sử của ${widget.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DraggableScrollableSheet(
                initialChildSize: 0.45,
                minChildSize: 0.2,
                maxChildSize: 0.88,
                builder: (context, scroll) => Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, floatingBottomGap(context)),
                  child: Glass(
                    radius: 38,
                    opacity: 0.72,
                    blur: 20,
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        children: [
                          const _Grabber(),
                          _DayPicker(
                            days: [for (var i = 0; i < 7; i++) today.subtract(Duration(days: i))],
                            selected: _day,
                            label: _dayLabel,
                            onChanged: (d) => setState(() {
                              _day = d;
                              _load();
                            }),
                          ),
                          const SizedBox(height: 16),
                          if (snap.connectionState != ConnectionState.done)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator.adaptive()),
                            )
                          else if (snap.hasError)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Không tải được lịch sử: ${snap.error}',
                                  textAlign: TextAlign.center, style: TextStyle(color: _secondary(context))),
                            )
                          else if (segs.isEmpty)
                            const EmptyState(
                              icon: Icons.timeline_rounded,
                              title: 'Không có dữ liệu',
                              text: 'Chưa có lịch sử di chuyển trong ngày này.',
                            )
                          else ...[
                            _DaySummary(trips: trips),
                            const SizedBox(height: 18),
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text('DÒNG THỜI GIAN',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      letterSpacing: 0.3,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                            ),
                            for (var i = segs.length - 1; i >= 0; i--)
                              _TimelineItem(
                                segment: segs[i],
                                selected: _selected == i,
                                isFirst: i == segs.length - 1,
                                isLast: i == 0,
                                onTap: () => _select(i, segs),
                                onOpenTrip: segs[i] is Trip
                                    ? () => Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => TripDetailScreen(trip: segs[i] as Trip),
                                        ))
                                    : null,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ));
  }
}

/// Tay nắm kéo sheet.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 12),
        width: 36,
        height: 5,
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

/// Bộ chọn ngày dạng rãnh viên thuốc: ngày đang chọn là "thấu kính" màu thương hiệu.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.days, required this.selected, required this.label, required this.onChanged});
  final List<DateTime> days;
  final DateTime selected;
  final String Function(DateTime) label;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: scheme.onSurface.withValues(alpha: 0.06)),
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: StadiumBorder()),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(4),
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 2),
          itemBuilder: (context, i) {
            final d = days[i];
            final sel = d == selected;
            return GlassPressable(
              onTap: sel ? null : () => onChanged(d),
              shape: const StadiumBorder(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  gradient: sel ? AppColors.brandGradient : null,
                  shadows: sel
                      ? [
                          BoxShadow(
                              color: AppColors.brand.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ]
                      : null,
                ),
                child: Text(
                  label(d),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: -0.2,
                    color: sel ? Colors.white : scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.trips});
  final List<Trip> trips;

  @override
  Widget build(BuildContext context) {
    final dist = trips.fold(0.0, (a, t) => a + t.distance);
    final time = trips.fold(Duration.zero, (a, t) => a + t.duration);
    return _StatPanel(
      rows: [
        [
          _Stat(value: distanceLabel(dist), label: 'Quãng đường', color: AppColors.brand),
          _Stat(value: '${trips.length}', label: 'Chuyến đi', color: AppColors.teal),
          _Stat(value: durationText(time), label: 'Di chuyển', color: AppColors.orange),
        ],
      ],
    );
  }
}

/// Khối chỉ số trên nền mờ, ngăn bằng đường kẻ mảnh (kiểu Apple Fitness).
class _StatPanel extends StatelessWidget {
  const _StatPanel({required this.rows});
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);
    return Container(
      decoration: ShapeDecoration(shape: glassShape(radius: 22), color: _innerFill(context)),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) Divider(height: 0.5, thickness: 0.5, indent: 16, endIndent: 16, color: line),
            IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) VerticalDivider(width: 0.5, thickness: 0.5, indent: 14, endIndent: 14, color: line),
                    Expanded(child: rows[r][i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style:
                  TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1, color: color),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _secondary(context)),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.segment,
    required this.selected,
    required this.onTap,
    this.onOpenTrip,
    this.isFirst = false,
    this.isLast = false,
  });
  final Segment segment;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onOpenTrip;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final s = segment;
    final scheme = Theme.of(context).colorScheme;
    final isTrip = s is Trip;
    final color = isTrip ? (s.isDrive ? AppColors.brand : AppColors.teal) : AppColors.indigo;
    final rail = scheme.onSurface.withValues(alpha: 0.14);
    final shape = glassShape(radius: 22);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Đường ray dòng thời gian nối các mục.
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Expanded(child: Container(width: 2, color: isFirst ? Colors.transparent : rail)),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? color : scheme.surface,
                    border: Border.all(color: color, width: 2.5),
                  ),
                ),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : rail)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GlassPressable(
                onTap: onTap,
                scale: 0.97,
                shape: shape,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: ShapeDecoration(
                    shape: shape,
                    color: selected ? _innerFill(context, tint: color) : _innerFill(context, strength: 0.9),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Row(
                    children: [
                      GlassIconBadge(
                        icon: isTrip
                            ? (s.isDrive ? Icons.directions_car_rounded : Icons.directions_walk_rounded)
                            : Icons.home_work_rounded,
                        color: color,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s is Trip)
                              Text('${s.isDrive ? 'Lái xe' : 'Di chuyển'} ${distanceLabel(s.distance)}',
                                  style:
                                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: -0.3))
                            else
                              AddressText((s as Stay).lat, s.lng,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: -0.3)),
                            const SizedBox(height: 2),
                            Text('${clock(s.start)} – ${clock(s.end)} · ${durationText(s.duration)}',
                                style: TextStyle(color: _secondary(context), fontSize: 13)),
                          ],
                        ),
                      ),
                      if (onOpenTrip != null)
                        GlassPressable(
                          onTap: onOpenTrip,
                          shape: const CircleBorder(),
                          scale: 0.88,
                          child: const Padding(padding: EdgeInsets.all(4), child: _ChevronCircle(size: 32)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chi tiết một chuyến đi: bản đồ + chỉ số lái xe.
class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key, required this.trip});
  final Trip trip;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final pts = tripLatLngs(trip);
    final color = trip.isDrive ? AppColors.brand : AppColors.teal;
    return BackdropGroup(child: Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IPingMap(
              controller: _map,
              center: pts.first,
              fit: fitPoints(pts, padding: 70),
              layers: tripLayers(trip),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: GlassButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Quay lại',
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Glass(
                  radius: 34,
                  opacity: 0.72,
                  blur: 20,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 4, 0),
                        child: Row(
                          children: [
                            GlassIconBadge(
                              icon: trip.isDrive ? Icons.directions_car_rounded : Icons.directions_walk_rounded,
                              color: color,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(trip.isDrive ? 'Lái xe' : 'Di chuyển',
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                                  Text('${clock(trip.start)} ~ ${clock(trip.end)} · ${durationText(trip.duration)}',
                                      style: TextStyle(color: _secondary(context), fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            if (trip.isDrive) ScoreBadge(score: trip.safetyScore, size: 52),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _StatPanel(
                        rows: [
                          [
                            _Stat(value: distanceLabel(trip.distance), label: 'Quãng đường', color: color),
                            _Stat(value: kmh(trip.avgSpeed), label: 'Trung bình'),
                            _Stat(value: kmh(trip.maxSpeed), label: 'Tối đa'),
                          ],
                          if (trip.isDrive)
                            [
                              _Stat(
                                value: '${trip.speedingEvents}',
                                label: 'Quá tốc độ',
                                color: trip.speedingEvents > 0 ? AppColors.sos : null,
                              ),
                              _Stat(
                                value: '${trip.hardBrakes}',
                                label: 'Phanh gấp',
                                color: trip.hardBrakes > 0 ? AppColors.warning : null,
                              ),
                              _Stat(
                                  value: '${trip.safetyScore}',
                                  label: 'Điểm an toàn',
                                  color: _scoreColor(trip.safetyScore)),
                            ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                        child: _Route(from: trip.from, to: trip.to),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

/// Điểm an toàn dạng vòng tiến độ nhỏ (kiểu vòng Apple Fitness).
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.size = 44});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    final stroke = math.max(3.5, size * 0.1);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          progress: (score / 100).clamp(0.0, 1.0),
          color: color,
          stroke: stroke,
          track: color.withValues(alpha: 0.18),
        ),
        child: Center(
          child: Text(
            '$score',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.34,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter({required this.progress, required this.color, required this.stroke, required this.track});
  final double progress;
  final Color color;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke || old.track != track;
}
