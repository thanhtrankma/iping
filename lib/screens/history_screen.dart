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

/// Bản đồ nhỏ không tương tác hiển thị một chuyến đi.
class TripMiniMap extends StatelessWidget {
  const TripMiniMap({super.key, required this.trip, this.height = 200});
  final Trip trip;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pts = tripLatLngs(trip);
    return SizedBox(
      height: height,
      child: IgnorePointer(
        child: IPingMap(
          controller: MapController(),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      radius: 30,
      opacity: 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(
                              '${clock(trip.start)} ~ ${clock(trip.end)} (${durationText(trip.duration)})',
                              style: TextStyle(color: AppColors.brand.withValues(alpha: 0.8), fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      if (onTap != null)
                        const CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.arrow_forward_rounded, color: Colors.black87, size: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          trip.isDrive ? Icons.directions_car_rounded : Icons.directions_walk_rounded,
                          color: AppColors.brand,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(distanceLabel(trip.distance).replaceAll('.', ','),
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text('Tối đa ${kmh(trip.maxSpeed)}', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Endpoint(lat: trip.from.lat, lng: trip.from.lng, first: true),
                  _Endpoint(lat: trip.to.lat, lng: trip.to.lng, first: false),
                ],
              ),
            ),
          ),
          Stack(
            children: [
              TripMiniMap(trip: trip),
              if (footer != null) Positioned(right: 14, bottom: 14, child: footer!),
            ],
          ),
        ],
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.lat, required this.lng, required this.first});
  final double lat;
  final double lng;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(first ? Icons.radio_button_checked_rounded : Icons.location_on_rounded,
              color: AppColors.brand, size: 22),
          const SizedBox(width: 12),
          Expanded(child: AddressText(lat, lng, maxLines: 1, style: const TextStyle(fontSize: 15))),
        ],
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
    return Scaffold(
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
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.brandDeep,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(Icons.home_work_rounded, size: 13, color: Colors.white),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      GlassButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Glass(
                          radius: 27,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                          child: Text('Lịch sử của ${widget.name}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Glass(
                    radius: 34,
                    opacity: 0.65,
                    child: ListView(
                      controller: scroll,
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
                      children: [
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: 7,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final d = today.subtract(Duration(days: i));
                              final sel = d == _day;
                              return ChoiceChip(
                                label: Text(_dayLabel(d)),
                                selected: sel,
                                showCheckmark: false,
                                selectedColor: AppColors.brand,
                                labelStyle: TextStyle(
                                    color: sel ? Colors.white : null, fontWeight: FontWeight.w700),
                                shape: const StadiumBorder(),
                                onSelected: (_) => setState(() {
                                  _day = d;
                                  _load();
                                }),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (snap.connectionState != ConnectionState.done)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (snap.hasError)
                          Text('Không tải được lịch sử: ${snap.error}')
                        else if (segs.isEmpty)
                          const EmptyState(
                            icon: Icons.timeline_rounded,
                            title: 'Không có dữ liệu',
                            text: 'Chưa có lịch sử di chuyển trong ngày này.',
                          )
                        else ...[
                          _DaySummary(trips: trips),
                          const SizedBox(height: 12),
                          for (var i = segs.length - 1; i >= 0; i--)
                            _TimelineItem(
                              segment: segs[i],
                              selected: _selected == i,
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
            ],
          );
        },
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
    return Row(
      children: [
        _Stat(value: distanceLabel(dist), label: 'Quãng đường'),
        _Stat(value: '${trips.length}', label: 'Chuyến đi'),
        _Stat(value: durationText(time), label: 'Di chuyển'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.segment, required this.selected, required this.onTap, this.onOpenTrip});
  final Segment segment;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onOpenTrip;

  @override
  Widget build(BuildContext context) {
    final s = segment;
    final scheme = Theme.of(context).colorScheme;
    final isTrip = s is Trip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.brand.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isTrip ? AppColors.brand : AppColors.brandDeep.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isTrip
                        ? (s.isDrive ? Icons.directions_car_rounded : Icons.directions_walk_rounded)
                        : Icons.home_work_rounded,
                    color: isTrip ? Colors.white : AppColors.brandDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s is Trip)
                        Text('${s.isDrive ? 'Lái xe' : 'Di chuyển'} ${distanceLabel(s.distance)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))
                      else
                        AddressText((s as Stay).lat, s.lng,
                            maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${clock(s.start)} – ${clock(s.end)} · ${durationText(s.duration)}',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                if (onOpenTrip != null)
                  IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: onOpenTrip),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chi tiết một chuyến đi: bản đồ + chỉ số lái xe.
class TripDetailScreen extends StatelessWidget {
  const TripDetailScreen({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final pts = tripLatLngs(trip);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IPingMap(
              controller: MapController(),
              center: pts.first,
              fit: fitPoints(pts, padding: 70),
              layers: tripLayers(trip),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: GlassButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Glass(
                  radius: 32,
                  opacity: 0.7,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(trip.isDrive ? Icons.directions_car_rounded : Icons.directions_walk_rounded,
                              color: AppColors.brand),
                          const SizedBox(width: 8),
                          Text(trip.isDrive ? 'Lái xe' : 'Di chuyển',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          if (trip.isDrive) ScoreBadge(score: trip.safetyScore),
                        ],
                      ),
                      Text('${clock(trip.start)} ~ ${clock(trip.end)} (${durationText(trip.duration)})',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _Stat(value: distanceLabel(trip.distance), label: 'Quãng đường'),
                          _Stat(value: kmh(trip.avgSpeed), label: 'Trung bình'),
                          _Stat(value: kmh(trip.maxSpeed), label: 'Tối đa'),
                        ],
                      ),
                      if (trip.isDrive) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _Stat(value: '${trip.speedingEvents}', label: 'Quá tốc độ'),
                            _Stat(value: '${trip.hardBrakes}', label: 'Phanh gấp'),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _Endpoint(lat: trip.from.lat, lng: trip.from.lng, first: true),
                      _Endpoint(lat: trip.to.lat, lng: trip.to.lng, first: false),
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

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.size = 44});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = score >= 85
        ? AppColors.online
        : score >= 60
            ? AppColors.warning
            : AppColors.sos;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2.5),
      ),
      child: Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: size * 0.36)),
    );
  }
}
