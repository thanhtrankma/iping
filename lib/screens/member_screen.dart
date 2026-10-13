import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/models.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/trip_analyzer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';
import 'chat_tab.dart';
import 'driving_screen.dart';
import 'group_actions.dart';
import 'history_screen.dart';
import 'home_screen.dart' show BatteryPill;

const _pings = [
  ('love', '❤️', 'Yêu nhé!'),
  ('boo', '👻', 'Ú òa!'),
  ('poke', '💩', 'Chọc!'),
  ('arrived', '📍', 'Tới rồi'),
  ('call', '📞', 'Gọi lại nhé'),
  ('home', '🏠', 'Về nhà chưa?'),
];

/// Chi tiết một thành viên: vị trí, địa chỉ, pin, ping nhanh và chuyến đi gần đây.
class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key, required this.groupId, required this.uid});
  final String groupId;
  final String uid;

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  final _map = MapController();
  final _myUid = FirebaseAuth.instance.currentUser?.uid;
  late final Stream<Group?> _group = GroupService.instance.group(widget.groupId);
  late final Stream<List<MemberLocation>> _locations = GroupService.instance.locations(widget.groupId);
  late final Stream<List<Place>> _places = GroupService.instance.places(widget.groupId);
  late final Future<Trip?> _recentTrip = () async {
    final now = DateTime.now();
    final pts = await GroupService.instance
        .history(widget.groupId, widget.uid, now.subtract(const Duration(days: 2)), now);
    final trips = buildTimeline(pts).whereType<Trip>();
    return trips.isEmpty ? null : trips.last;
  }();

  bool _centered = false;
  // Đẩy ghim lên phần bản đồ không bị bảng thông tin che.
  static const _pinOffset = Offset(0, -170);

  /// Lần đầu có vị trí thì đưa bản đồ về đó (lúc tạo bản đồ dữ liệu chưa về).
  void _centerOnce(MemberLocation? loc) {
    if (_centered || loc == null) return;
    _centered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.move(loc.point, 17, offset: _pinOffset);
    });
  }

  // Yêu cầu vị trí: chờ `updatedAt` của thành viên thay đổi.
  bool _locating = false;
  DateTime? _locateBase;

  Future<void> _requestLocation(MemberLocation? loc) async {
    try {
      await GroupService.instance.sendPing(widget.groupId, widget.uid, 'locate');
      setState(() {
        _locating = true;
        _locateBase = loc?.updatedAt;
      });
      if (mounted) showMessage(context, 'Đã gửi yêu cầu');
    } catch (e) {
      if (mounted) showMessage(context, 'Không gửi được: $e');
    }
  }

  void _checkLocated(MemberLocation? loc) {
    final t = loc?.updatedAt;
    if (!_locating || t == null || t == _locateBase) return;
    _locating = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      showMessage(context, 'Vị trí đã được cập nhật');
      _map.move(loc!.point, 17, offset: _pinOffset);
    });
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _ping(String type, String label) async {
    try {
      await GroupService.instance.sendPing(widget.groupId, widget.uid, type);
      if (mounted) showMessage(context, 'Đã gửi "$label"');
    } catch (e) {
      if (mounted) showMessage(context, 'Không gửi được: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Group?>(
        stream: _group,
        builder: (context, gSnap) => StreamBuilder<List<Place>>(
          stream: _places,
          builder: (context, pSnap) => StreamBuilder<List<MemberLocation>>(
            stream: _locations,
            builder: (context, lSnap) {
              final group = gSnap.data;
              final loc = lSnap.data?.where((l) => l.uid == widget.uid).firstOrNull;
              final name = loc?.name ?? group?.nameOf(widget.uid) ?? '';
              final isMe = widget.uid == _myUid;
              final center = loc?.point ?? defaultCenter;
              _centerOnce(loc);
              _checkLocated(loc);
              return Stack(
                children: [
                  Positioned.fill(
                    child: IPingMap(
                      controller: _map,
                      center: center,
                      zoom: 17,
                      layers: [
                        ...placeLayers(pSnap.data ?? const []),
                        if (loc != null)
                          MarkerLayer(markers: [memberMarker(loc, size: 66, label: timeAgo(loc.updatedAt))]),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GlassButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                          const Spacer(),
                          Column(
                            children: [
                              if (group != null)
                                GlassButton(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  tooltip: 'Trò chuyện',
                                  onTap: () => _push(SubPage(title: group.name, child: ChatTab(group: group))),
                                ),
                              const SizedBox(height: 14),
                              GlassButton(
                                icon: Icons.person_pin_circle_outlined,
                                tooltip: 'Về vị trí của $name',
                                onTap: () => _map.move(center, 17, offset: _pinOffset),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  DraggableScrollableSheet(
                    initialChildSize: 0.5,
                    minChildSize: 0.3,
                    maxChildSize: 0.92,
                    snap: true,
                    snapSizes: const [0.5],
                    builder: (context, scroll) => ListView(
                      controller: scroll,
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 16 + MediaQuery.paddingOf(context).bottom),
                      children: [
                        if (!isMe)
                          SizedBox(
                            height: 62,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                              itemCount: _pings.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                if (i == 0) {
                                  return GlassPill(
                                    onTap: () => _requestLocation(loc),
                                    child: Text(_locating ? '📡  Đã gửi yêu cầu' : '📡  Cập nhật vị trí',
                                        style: const TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.brand)),
                                  );
                                }
                                final (type, emoji, label) = _pings[i - 1];
                                return GlassPill(
                                  onTap: () => _ping(type, '$emoji $label'),
                                  child: Text('$emoji  $label',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                );
                              },
                            ),
                          ),
                        _DetailCard(
                          name: isMe ? '$name (Bạn)' : name,
                          location: loc,
                          isMe: isMe,
                          onHistory: () => _push(HistoryScreen(groupId: widget.groupId, uid: widget.uid, name: name, fallbackCenter: loc?.point)),
                          onDriving: () => _push(DrivingScreen(groupId: widget.groupId, uid: widget.uid, name: name)),
                          onPlaces: () =>
                              _push(MemberPlacesScreen(groupId: widget.groupId, uid: widget.uid, name: name)),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<Trip?>(
                          future: _recentTrip,
                          builder: (context, snap) {
                            final trip = snap.data;
                            if (trip == null) {
                              return Glass(
                                radius: 30,
                                opacity: 0.7,
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  children: [
                                    const Icon(Icons.route_rounded, color: AppColors.brand),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        snap.connectionState == ConnectionState.done
                                            ? 'Chưa có chuyến đi nào trong 2 ngày qua'
                                            : 'Đang tải chuyến đi gần đây…',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return TripCard(
                              trip: trip,
                              title: 'Chuyến đi gần đây',
                              onTap: () => _push(TripDetailScreen(trip: trip)),
                              footer: GlassPill(
                                onTap: () =>
                                    _push(HistoryScreen(groupId: widget.groupId, uid: widget.uid, name: name, fallbackCenter: loc?.point)),
                                child: const Text('Xem toàn bộ lịch sử →',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.name,
    required this.location,
    required this.isMe,
    required this.onHistory,
    required this.onDriving,
    required this.onPlaces,
  });

  final String name;
  final MemberLocation? location;
  final bool isMe;
  final VoidCallback onHistory;
  final VoidCallback onDriving;
  final VoidCallback onPlaces;

  @override
  Widget build(BuildContext context) {
    final loc = location;
    final scheme = Theme.of(context).colorScheme;
    final me = LocationService.instance.lastPosition.value;
    final distance = (loc == null || me == null || isMe)
        ? null
        : distanceBetween(me.latitude, me.longitude, loc.lat, loc.lng);

    return Glass(
      radius: 32,
      opacity: 0.7,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
              if (loc?.battery != null) BatteryPill(level: loc!.battery!),
            ],
          ),
          const SizedBox(height: 6),
          if (loc == null)
            Text('Thành viên này chưa chia sẻ vị trí', style: TextStyle(color: scheme.onSurfaceVariant))
          else ...[
            AddressText(loc.lat, loc.lng, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(loc.sharing ? timeAgo(loc.updatedAt) : 'Đã tắt chia sẻ · ${timeAgo(loc.updatedAt)}',
                    style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                if (loc.speed != null && loc.speed! > 2) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.speed_rounded, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${(loc.speed! * 3.6).round()} km/h',
                      style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: GlassTile(icon: Icons.history_rounded, label: 'Lịch sử', onTap: onHistory)),
              const SizedBox(width: 10),
              Expanded(child: GlassTile(icon: Icons.directions_car_outlined, label: 'Lái xe', onTap: onDriving)),
              const SizedBox(width: 10),
              Expanded(child: GlassTile(icon: Icons.place_outlined, label: 'Địa điểm', onTap: onPlaces)),
              const SizedBox(width: 10),
              Expanded(
                child: GlassTile(
                  icon: Icons.turn_right_rounded,
                  label: distance == null ? '—' : distanceLabel(distance).replaceAll('.', ','),
                  onTap: null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
