import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/safe_trip_service.dart';
import '../services/trip_analyzer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';
import '../widgets/safe_trip_widgets.dart';
import 'chat_tab.dart';
import 'driving_screen.dart';
import 'group_actions.dart';
import 'history_screen.dart';
import 'member_admin.dart';
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

  // Chuyến "Về an toàn" đang mở của thành viên (null nếu không có).
  SafeTrip? _safeTrip;
  StreamSubscription<SafeTrip?>? _safeSub;

  @override
  void initState() {
    super.initState();
    _safeSub = SafeTripService.instance.of(widget.groupId, widget.uid).listen(
      (t) {
        if (mounted) setState(() => _safeTrip = t != null && t.isOpen ? t : null);
      },
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _safeSub?.cancel();
    super.dispose();
  }

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
      if (!mounted) return;
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
                        if (_safeTrip != null)
                          ...safeTripLayers(
                            [(gid: widget.groupId, trip: _safeTrip!)],
                            current: {
                              if (isMe && mySafeTripPosition() != null)
                                widget.uid: mySafeTripPosition()!
                              else if (loc != null && loc.sharing)
                                widget.uid: loc.point,
                            },
                            now: DateTime.now(),
                            onTap: (t) => _map.move(t.trip.dest, 16, offset: _pinOffset),
                          ),
                        if (loc != null)
                          MarkerLayer(markers: [memberMarker(loc, size: 66, label: timeAgo(loc.updatedAt))]),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GlassButton(
                            icon: Icons.chevron_left_rounded,
                            tooltip: 'Quay lại',
                            onTap: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          MapControlStack(controls: [
                            if (group != null)
                              MapControl(
                                icon: Icons.chat_bubble_rounded,
                                tooltip: 'Trò chuyện',
                                onTap: () => _push(SubPage(title: group.name, child: ChatTab(group: group))),
                              ),
                            // Chỉ chủ nhóm thấy nút xoá / chặn thành viên khác.
                            if (group != null && !isMe && group.isOwner(_myUid))
                              MapControl(
                                icon: Icons.manage_accounts_rounded,
                                tooltip: 'Quản lý thành viên',
                                onTap: () async {
                                  if (await MemberAdmin.showActions(context, group, widget.uid, name) &&
                                      context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                              ),
                            MapControl(
                              icon: Icons.person_pin_circle_rounded,
                              tooltip: 'Về vị trí của $name',
                              color: AppColors.brand,
                              onTap: () => _map.move(center, 17, offset: _pinOffset),
                            ),
                          ]),
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
                      padding: EdgeInsets.fromLTRB(10, 0, 10, 16 + MediaQuery.paddingOf(context).bottom),
                      children: [
                        // Hàng ping: các viên kính nổi phía trên thẻ, như hành động nhanh của Find My.
                        if (!isMe)
                          SizedBox(
                            height: 64,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
                              itemCount: _pings.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
                                if (i == 0) {
                                  return GlassPill(
                                    tint: AppColors.brand,
                                    padding: pad,
                                    onTap: () => _requestLocation(loc),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_locating ? Icons.check_circle_rounded : Icons.my_location_rounded,
                                            size: 18, color: Colors.white),
                                        const SizedBox(width: 6),
                                        Text(_locating ? 'Đã gửi yêu cầu' : 'Cập nhật vị trí',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -0.2,
                                                color: Colors.white)),
                                      ],
                                    ),
                                  );
                                }
                                final (type, emoji, label) = _pings[i - 1];
                                return GlassPill(
                                  padding: pad,
                                  onTap: () => _ping(type, '$emoji $label'),
                                  child: Text('$emoji  $label',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                                );
                              },
                            ),
                          ),
                        _DetailCard(
                          name: isMe ? '$name (Bạn)' : name,
                          location: loc,
                          isMe: isMe,
                          safeTrip: _safeTrip == null
                              ? null
                              : SafeTripStatusCard(
                                  gid: widget.groupId,
                                  trip: _safeTrip!,
                                  name: isMe ? null : name,
                                  current: isMe
                                      ? mySafeTripPosition()
                                      : (loc != null && loc.sharing ? LatLng(loc.lat, loc.lng) : null),
                                  controls: isMe,
                                ),
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
                                padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
                                child: Row(
                                  children: [
                                    const GlassIconBadge(icon: Icons.route_rounded, color: AppColors.indigo, size: 34),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        snap.connectionState == ConnectionState.done
                                            ? 'Chưa có chuyến đi nào trong 2 ngày qua'
                                            : 'Đang tải chuyến đi gần đây…',
                                        style: TextStyle(
                                            fontSize: 15,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
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
    this.safeTrip,
  });

  final String name;
  final MemberLocation? location;
  final bool isMe;
  final VoidCallback onHistory;
  final VoidCallback onDriving;
  final VoidCallback onPlaces;

  /// Thẻ trạng thái "Về an toàn" (nếu thành viên đang có chuyến mở).
  final Widget? safeTrip;

  @override
  Widget build(BuildContext context) {
    final loc = location;
    final scheme = Theme.of(context).colorScheme;
    final me = LocationService.instance.lastPosition.value;
    final distance = (loc == null || me == null || isMe)
        ? null
        : distanceBetween(me.latitude, me.longitude, loc.lat, loc.lng);

    final secondary = scheme.onSurface.withValues(alpha: 0.55);

    return Glass(
      radius: 38,
      opacity: 0.72,
      blur: 20,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: scheme.onSurface.withValues(alpha: 0.22),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              ),
              if (loc?.battery != null) BatteryPill(level: loc!.battery!),
            ],
          ),
          const SizedBox(height: 4),
          if (loc == null)
            Text('Thành viên này chưa chia sẻ vị trí', style: TextStyle(fontSize: 15, color: secondary))
          else ...[
            AddressText(loc.lat, loc.lng, style: TextStyle(fontSize: 16, letterSpacing: -0.2, color: secondary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: secondary),
                const SizedBox(width: 5),
                Text(loc.sharing ? timeAgo(loc.updatedAt) : 'Đã tắt chia sẻ · ${timeAgo(loc.updatedAt)}',
                    style: TextStyle(fontSize: 14.5, color: secondary)),
                if (loc.speed != null && loc.speed! > 2) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.speed_rounded, size: 16, color: secondary),
                  const SizedBox(width: 4),
                  Text('${(loc.speed! * 3.6).round()} km/h', style: TextStyle(fontSize: 14.5, color: secondary)),
                ],
              ],
            ),
          ],
          if (safeTrip != null) ...[
            const SizedBox(height: 14),
            safeTrip!,
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GlassTile(
                    icon: Icons.history_rounded, color: AppColors.indigo, label: 'Lịch sử', onTap: onHistory),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassTile(
                    icon: Icons.directions_car_rounded, color: AppColors.orange, label: 'Lái xe', onTap: onDriving),
              ),
              const SizedBox(width: 8),
              Expanded(
                child:
                    GlassTile(icon: Icons.place_rounded, color: AppColors.teal, label: 'Địa điểm', onTap: onPlaces),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassTile(
                  icon: Icons.turn_right_rounded,
                  color: AppColors.online,
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
