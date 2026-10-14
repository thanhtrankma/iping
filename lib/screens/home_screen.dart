import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/all_friends_service.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/safe_trip_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/explore_pill.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';
import '../widgets/privacy_widgets.dart';
import '../widgets/safe_trip_widgets.dart';
import 'activity_tab.dart';
import 'all_friends_actions.dart';
import 'meetup_screen.dart';
import 'moments_screen.dart';
import 'chat_tab.dart';
import 'explore_leaderboard_screen.dart';
import 'explore_screen.dart';
import 'group_actions.dart';
import 'member_screen.dart';
import 'menu_screen.dart';
import 'places_tab.dart';
import 'safe_trip_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.uid});
  final String uid;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<List<Group>> _groups = GroupService.instance.myGroups(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Group>>(
      stream: _groups,
      builder: (context, snap) {
        final groups = snap.data;
        return ValueListenableBuilder<String?>(
          valueListenable: SettingsService.instance.selectedGroupId,
          builder: (context, selectedId, _) {
            Group? group;
            if (groups != null && groups.isNotEmpty) {
              group = AllFriendsService.isAllMode(selectedId, groups)
                  ? AllFriendsService.virtualGroup(groups)
                  : groups.firstWhere((g) => g.id == selectedId, orElse: () => groups.first);
            }
            // Chế độ tất cả bạn bè: dựng lại khi danh sách nhóm / thành viên đổi.
            final key = group != null && AllFriendsService.isVirtual(group)
                ? 'all:${groups!.map((g) => '${g.id}/${g.memberIds.length}').join(',')}'
                : group?.id ?? 'none';
            return Scaffold(
              body: _GroupMapView(
                key: ValueKey(key),
                uid: widget.uid,
                group: group,
                groups: groups ?? const [],
                loading: groups == null,
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupMapView extends StatefulWidget {
  const _GroupMapView({
    super.key,
    required this.uid,
    required this.group,
    required this.groups,
    required this.loading,
  });
  final String uid;
  final Group? group;
  final List<Group> groups;
  final bool loading;

  @override
  State<_GroupMapView> createState() => _GroupMapViewState();
}

class _GroupMapViewState extends State<_GroupMapView> {
  final _map = MapController();
  Stream<List<MemberLocation>>? _locations;
  Stream<List<Place>>? _places;
  Stream<List<Moment>>? _moments;
  Stream<List<Meetup>>? _meetups;
  Stream<List<GroupSafeTrip>>? _safeTrips;
  // Đếm ngược "Về an toàn": dựng lại định kỳ khi có chuyến đang mở (màu quá giờ trên bản đồ).
  Timer? _safeTick;
  bool _hasSafeTrips = false;
  // Chế độ tất cả bạn bè: uid -> nhóm có vị trí mới nhất.
  Map<String, String> _groupOf = const {};
  bool get _all => widget.group != null && AllFriendsService.isVirtual(widget.group!);

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    if (g != null && _all) {
      _locations = AllFriendsService.instance.watch(widget.groups).map((m) {
        _groupOf = m.groupOf;
        return m.locations;
      });
    } else if (g != null) {
      _locations = GroupService.instance.locations(g.id);
      _places = GroupService.instance.places(g.id);
      _moments = GroupService.instance.moments(g.id);
      _meetups = GroupService.instance.activeMeetups(g.id);
    }
    if (g != null) {
      _safeTrips = _watchSafeTrips(_all ? widget.groups.map((x) => x.id).toList() : [g.id]);
      _safeTick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && _hasSafeTrips) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    _safeTick?.cancel();
    super.dispose();
  }

  /// Gộp các chuyến "Về an toàn" đang mở của một hoặc nhiều nhóm.
  static Stream<List<GroupSafeTrip>> _watchSafeTrips(List<String> gids) {
    final latest = <String, List<GroupSafeTrip>>{};
    final subs = <StreamSubscription<List<SafeTrip>>>[];
    late final StreamController<List<GroupSafeTrip>> controller;
    void emit() {
      final all = latest.values.expand((x) => x).toList()..sort((a, b) => a.trip.dueAt.compareTo(b.trip.dueAt));
      controller.add(all);
    }

    controller = StreamController<List<GroupSafeTrip>>(
      onListen: () {
        for (final gid in gids) {
          subs.add(SafeTripService.instance.open(gid).listen(
            (list) {
              latest[gid] = [for (final t in list) (gid: gid, trip: t)];
              emit();
            },
            // Lỗi quyền / mạng của một nhóm không làm hỏng banner của các nhóm khác.
            onError: (Object _) {},
          ));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  void _openMember(String uid, {String? groupId}) {
    final g = widget.group!;
    _push(MemberScreen(
        groupId: groupId ?? (_all ? AllFriendsService.groupFor(uid, widget.groups, _groupOf) ?? g.id : g.id),
        uid: uid));
  }

  void _openSafeTrip(GroupSafeTrip t) {
    if (t.trip.uid == widget.uid) {
      showMySafeTripSheet(context, t.gid);
    } else {
      _openMember(t.trip.uid, groupId: t.gid);
    }
  }

  /// Ô "Về an toàn": đang có chuyến thì mở bảng điều khiển, chưa có thì bắt đầu chuyến mới.
  void _startOrOpenSafeTrip(List<GroupSafeTrip> mine) {
    final g = widget.group;
    if (g == null) return;
    if (mine.isNotEmpty) {
      showMySafeTripSheet(context, mine.first.gid);
      return;
    }
    AllFriendsActions.open(context, g, widget.groups, (x) => SafeTripScreen(group: x),
        title: 'Về an toàn với nhóm nào?');
  }

  bool _centered = false;

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _focusMe() async {
    final pos = await LocationService.instance.currentPosition();
    if (pos != null) _map.move(LatLng(pos.latitude, pos.longitude), 16);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return StreamBuilder<List<GroupSafeTrip>>(
      stream: _safeTrips,
      builder: (context, safeSnap) => StreamBuilder<List<Moment>>(
        stream: _moments,
        builder: (context, momentSnap) => StreamBuilder<List<Meetup>>(
          stream: _meetups,
          builder: (context, meetupSnap) => StreamBuilder<List<Place>>(
            stream: _places,
            builder: (context, placeSnap) => StreamBuilder<List<MemberLocation>>(
              stream: _locations,
              builder: (context, locSnap) {
                final places = placeSnap.data ?? const <Place>[];
                final moments = momentSnap.data ?? const <Moment>[];
                final meetups = meetupSnap.data ?? const <Meetup>[];
                final locs = (locSnap.data ?? const <MemberLocation>[])
                    .where((l) => g?.memberIds.contains(l.uid) ?? false)
                    .toList();
                final me = LocationService.instance.lastPosition.value;
                final myLoc = locs.where((l) => l.uid == widget.uid).firstOrNull;
                // Chuyến "Về an toàn" đang mở của các thành viên đang xem.
                final safeTrips = (safeSnap.data ?? const <GroupSafeTrip>[])
                    .where((t) => g?.memberIds.contains(t.trip.uid) ?? false)
                    .toList();
                _hasSafeTrips = safeTrips.isNotEmpty;
                final mySafeTrips = safeTrips.where((t) => t.trip.uid == widget.uid).toList();
                final safeNow = DateTime.now();
                final travellerPos = <String, LatLng>{
                  for (final l in locs)
                    if (l.sharing) l.uid: l.point,
                  if (me != null) widget.uid: LatLng(me.latitude, me.longitude),
                };
                final center = me != null
                    ? LatLng(me.latitude, me.longitude)
                    : myLoc?.point ?? (locs.isNotEmpty ? locs.first.point : defaultCenter);
                // Bản đồ tạo trước khi dữ liệu về: đưa về đúng chỗ ở lần đầu có vị trí.
                if (!_centered && (me != null || locs.isNotEmpty)) {
                  _centered = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _map.move(center, 16);
                  });
                }

                return Stack(
                  children: [
                    Positioned.fill(
                      child: IPingMap(
                        controller: _map,
                        center: center,
                        zoom: 16,
                        layers: [
                          ...placeLayers(places),
                          ...safeTripLayers(safeTrips, current: travellerPos, now: safeNow, onTap: _openSafeTrip),
                          MarkerLayer(markers: [
                            for (final m in meetups)
                              Marker(
                                point: m.point,
                                width: 44,
                                height: 44,
                                alignment: Alignment.topCenter,
                                child: GestureDetector(
                                  onTap: () => _push(MeetupDetailScreen(group: g!, meetupId: m.id)),
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 3))
                                      ],
                                    ),
                                    child: Icon(Icons.flag_circle_rounded, size: 44, color: AppColors.sos),
                                  ),
                                ),
                              ),
                            for (final m in moments.where((m) => m.hasLocation))
                              momentMarker(m, () => _push(MomentsScreen(group: g!))),
                            for (final l in locs) memberMarker(l),
                          ]),
                        ],
                      ),
                    ),
                    // Lớp điều khiển nổi trên bản đồ, cách mép 14px như Apple Maps.
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                GlassButton(
                                  icon: Icons.menu_rounded,
                                  tooltip: 'Menu',
                                  onTap: () => _push(MenuScreen(uid: widget.uid, group: _all ? null : g)),
                                ),
                                if (g != null) ...[
                                  const SizedBox(height: 12),
                                  MapControlStack(controls: [
                                    MapControl(
                                      icon: Icons.person_add_alt_1_rounded,
                                      tooltip: 'Mời thành viên',
                                      onTap: () => AllFriendsActions.invite(context, g, widget.groups),
                                    ),
                                    MapControl(
                                      icon: Icons.where_to_vote_rounded,
                                      tooltip: 'Check-in',
                                      onTap: () => AllFriendsActions.checkIn(context, g, widget.groups),
                                    ),
                                  ]),
                                  const SizedBox(height: 12),
                                  GlassButton(
                                    tooltip: 'Gửi SOS',
                                    tint: AppColors.sos,
                                    onTap: () => AllFriendsActions.sos(context, g, widget.groups),
                                    child: const Text('SOS',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            letterSpacing: -0.3)),
                                  ),
                                ],
                              ],
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Column(
                                  children: [
                                    ExplorePill(
                                      onOpen: () => _push(const ExploreScreen()),
                                      onLeaderboard: () => g == null
                                          ? _push(const ExploreScreen())
                                          : AllFriendsActions.open(context, g, widget.groups,
                                              (x) => ExploreLeaderboardScreen(groupId: x.id, myUid: widget.uid)),
                                    ),
                                    const _SharingBadge(),
                                    if (g != null) PausedGroupChip(group: g),
                                    if (safeTrips.isNotEmpty)
                                      _SafeTripBanner(
                                        trips: safeTrips,
                                        myUid: widget.uid,
                                        positions: travellerPos,
                                        nameOf: (uid) =>
                                            locs.where((l) => l.uid == uid).firstOrNull?.name ?? g?.nameOf(uid),
                                        onOpen: _openSafeTrip,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                ValueListenableBuilder<MapStyle>(
                                  valueListenable: SettingsService.instance.mapStyle,
                                  builder: (context, style, _) => MapControlStack(controls: [
                                    MapControl(
                                      icon: style == MapStyle.satellite
                                          ? Icons.map_outlined
                                          : Icons.satellite_alt_rounded,
                                      tooltip: 'Đổi kiểu bản đồ',
                                      onTap: SettingsService.instance.toggleMapStyle,
                                    ),
                                    MapControl(
                                      icon: Icons.near_me_rounded,
                                      tooltip: 'Vị trí của tôi',
                                      color: AppColors.brand,
                                      onTap: _focusMe,
                                    ),
                                  ]),
                                ),
                                if (g != null) ...[
                                  const SizedBox(height: 12),
                                  GlassButton(
                                    icon: Icons.chat_bubble_rounded,
                                    tooltip: 'Trò chuyện',
                                    onTap: () => AllFriendsActions.open(context, g, widget.groups,
                                        (x) => SubPage(title: x.name, child: ChatTab(group: x)),
                                        title: 'Trò chuyện với nhóm nào?'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.loading)
                      const Center(
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: Glass(circle: true, child: Center(child: CircularProgressIndicator.adaptive())),
                        ),
                      )
                    else if (g == null)
                      const _Onboarding()
                    else
                      _MembersSheet(
                        group: g,
                        groups: widget.groups,
                        locations: locs,
                        places: places,
                        meetups: meetups,
                        momentCount: moments.length,
                        myUid: widget.uid,
                        onOpenMember: _openMember,
                        onOpenPage: _push,
                        hasSafeTrip: mySafeTrips.isNotEmpty,
                        onSafeTrip: () => _startOrOpenSafeTrip(mySafeTrips),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhãn nhỏ phía trên cho biết đang tắt chia sẻ.
class _SharingBadge extends StatelessWidget {
  const _SharingBadge();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LocationService.instance.sharing,
      builder: (context, on, _) => on
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GlassPill(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                onTap: () async {
                  final err = await LocationService.instance.start();
                  if (err != null && context.mounted) showMessage(context, err);
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off_rounded, size: 18, color: AppColors.warning),
                    SizedBox(width: 6),
                    Text('Bật chia sẻ', style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Glass(
            radius: 38,
            opacity: 0.75,
            blur: 20,
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 64),
                const SizedBox(height: 16),
                const Text('Bắt đầu với IPing',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                const SizedBox(height: 6),
                Text(
                  'Tạo nhóm cho gia đình, bạn bè hoặc nhập mã mời để xem mọi người đang ở đâu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.35, color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('Tạo nhóm mới'),
                  onPressed: () => GroupActions.create(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.vpn_key_rounded),
                  label: const Text('Tham gia bằng mã mời'),
                  onPressed: () => GroupActions.join(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nút tròn trong sheet kính: nền trong mờ thay vì lồng thêm một lớp kính.
class _SheetCircleButton extends StatelessWidget {
  const _SheetCircleButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? Theme.of(context).colorScheme.primary : AppColors.brand;
    return Tooltip(
      message: tooltip,
      child: GlassPressable(
        onTap: onTap,
        shape: const CircleBorder(),
        scale: 0.88,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: dark ? 0.22 : 0.12)),
          child: Icon(icon, size: 22, color: accent),
        ),
      ),
    );
  }
}

class _MembersSheet extends StatelessWidget {
  const _MembersSheet({
    required this.group,
    required this.groups,
    required this.locations,
    required this.places,
    required this.meetups,
    required this.momentCount,
    required this.myUid,
    required this.onOpenMember,
    required this.onOpenPage,
    this.hasSafeTrip = false,
    this.onSafeTrip,
  });

  final Group group;
  final List<Group> groups;
  final List<MemberLocation> locations;
  final List<Place> places;
  final List<Meetup> meetups;
  final int momentCount;
  final String myUid;
  final ValueChanged<String> onOpenMember;
  final ValueChanged<Widget> onOpenPage;

  /// Mình đang có chuyến "Về an toàn" mở.
  final bool hasSafeTrip;
  final VoidCallback? onSafeTrip;

  // Sheet nổi: bo 38, cách mép 10; nội dung bên trong lùi 12 nên bo trong = 38 − 12 = 26.
  static const _radius = 38.0;
  static const _inset = 12.0;

  @override
  Widget build(BuildContext context) {
    final byUid = {for (final l in locations) l.uid: l};
    final members = [...group.memberIds]..sort((a, b) => (a == myUid ? 0 : 1).compareTo(b == myUid ? 0 : 1));
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.2,
      maxChildSize: 0.88,
      snap: true,
      snapSizes: const [0.42],
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.fromLTRB(10, 0, 10, floatingBottomGap(context, min: 10)),
        child: Glass(
          radius: _radius,
          opacity: 0.7,
          blur: 20,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(_inset, 8, _inset, _inset + 4),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: scheme.onSurface.withValues(alpha: 0.22),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GlassPressable(
                        onTap: () => GroupActions.pickGroup(context, groups, group.id),
                        shape: glassShape(radius: 14),
                        scale: 0.97,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(group.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: scheme.onSurface.withValues(alpha: 0.08),
                                    ),
                                    child: Icon(Icons.keyboard_arrow_down_rounded,
                                        size: 20, color: scheme.onSurface.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                              Text('${members.length} thành viên',
                                  style: TextStyle(fontSize: 14, color: scheme.onSurface.withValues(alpha: 0.55))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _SheetCircleButton(
                    icon: Icons.person_add_alt_1_rounded,
                    tooltip: 'Mời thành viên',
                    onTap: () => AllFriendsActions.invite(context, group, groups),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TileRow(
                children: [
                  GlassTile(
                    icon: hasSafeTrip ? Icons.shield_rounded : Icons.shield_outlined,
                    color: AppColors.online,
                    label: hasSafeTrip ? 'Đang về' : 'Về an toàn',
                    onTap: onSafeTrip,
                  ),
                  GlassTile(
                    icon: Icons.auto_awesome_rounded,
                    color: AppColors.purple,
                    label: momentCount > 0 ? 'Khoảnh khắc ($momentCount)' : 'Khoảnh khắc',
                    onTap: () => AllFriendsActions.open(context, group, groups, (g) => MomentsScreen(group: g)),
                  ),
                  GlassTile(
                    icon: Icons.handshake_rounded,
                    color: AppColors.orange,
                    label: 'Meetup',
                    onTap: () => AllFriendsActions.open(context, group, groups, (g) => MeetupListScreen(group: g)),
                  ),
                  GlassTile(
                    icon: Icons.place_rounded,
                    color: AppColors.teal,
                    label: 'Địa điểm',
                    onTap: () => AllFriendsActions.open(
                        context, group, groups, (g) => SubPage(title: 'Địa điểm', child: PlacesTab(group: g))),
                  ),
                  GlassTile(
                    icon: Icons.notifications_rounded,
                    color: AppColors.pink,
                    label: 'Hoạt động',
                    onTap: () => AllFriendsActions.open(
                        context, group, groups, (g) => SubPage(title: 'Hoạt động', child: ActivityTab(group: g))),
                  ),
                ],
              ),
              for (final m in meetups) ...[
                const SizedBox(height: 12),
                MeetupCard(group: group, meetup: m),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 7),
                child: Text(
                  'THÀNH VIÊN',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              InsetGroup(
                radius: _radius - _inset,
                dividerIndent: 80,
                children: [
                  for (final uid in members)
                    _MemberRow(
                      uid: uid,
                      name: byUid[uid]?.name ?? group.nameOf(uid),
                      isMe: uid == myUid,
                      location: byUid[uid],
                      place: _placeOf(byUid[uid]),
                      onTap: () => onOpenMember(uid),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Place? _placeOf(MemberLocation? l) {
    if (l == null) return null;
    for (final p in places) {
      if (distanceBetweenLatLng(l.point, p.point) <= p.radius) return p;
    }
    return null;
  }
}

double distanceBetweenLatLng(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b);

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.uid,
    required this.name,
    required this.isMe,
    required this.location,
    required this.place,
    required this.onTap,
  });

  final String uid;
  final String name;
  final bool isMe;
  final MemberLocation? location;
  final Place? place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = location;
    final sub = TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), fontSize: 14, letterSpacing: -0.1);
    final when = loc == null
        ? null
        : isFresh(loc.updatedAt) && DateTime.now().difference(loc.updatedAt!).inMinutes < 2
            ? 'Bây giờ'
            : timeAgo(loc.updatedAt);

    Widget subtitle;
    if (loc == null) {
      subtitle = Text('Chưa chia sẻ vị trí', style: sub);
    } else if (!loc.sharing) {
      subtitle = Text('Đã tắt chia sẻ · $when', style: sub);
    } else if (place != null) {
      subtitle = Text('Ở ${place!.name} · $when', style: sub, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else {
      subtitle = Row(
        children: [
          Flexible(child: AddressText(loc.lat, loc.lng, short: true, style: sub, maxLines: 1)),
          Text(' · $when', style: sub),
        ],
      );
    }

    return GlassPressable(
      onTap: onTap,
      shape: const RoundedRectangleBorder(),
      scale: 0.98,
      haptic: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 60,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  MemberAvatar(uid: uid, name: name, radius: 27, dimmed: loc == null || !loc.sharing),
                  if (loc?.battery != null)
                    Positioned(bottom: 0, child: BatteryPill(level: loc!.battery!, compact: true)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: ShapeDecoration(
                            shape: const StadiumBorder(),
                            color: scheme.primary.withValues(alpha: 0.14),
                          ),
                          child: Text('Bạn',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  subtitle,
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

/// Nhãn pin: dạng viên thuốc nhỏ (compact, đặt dưới avatar) hoặc chip có phần trăm.
class BatteryPill extends StatelessWidget {
  const BatteryPill({super.key, required this.level, this.compact = false});
  final int level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final low = level <= 20;
    final color = low ? AppColors.sos : AppColors.online;
    final outline = (dark && !compact ? Colors.white : Colors.black).withValues(alpha: 0.35);
    final bar = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 16 : 22,
          height: compact ? 8 : 11,
          padding: const EdgeInsets.all(1.3),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border.all(color: outline, width: 0.8),
            borderRadius: BorderRadius.circular(compact ? 2.5 : 3.5),
          ),
          child: FractionallySizedBox(
            widthFactor: (level / 100).clamp(0.1, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(compact ? 1.2 : 2)),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: compact ? 3.5 : 4.5,
          margin: const EdgeInsets.only(left: 0.8),
          decoration: BoxDecoration(
            color: outline,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(1)),
          ),
        ),
      ],
    );
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 0.8)),
          color: Colors.white.withValues(alpha: 0.95),
          shadows: [BoxShadow(blurRadius: 6, color: Colors.black.withValues(alpha: 0.18), offset: const Offset(0, 2))],
        ),
        child: bar,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: (low ? AppColors.sos : (dark ? Colors.white : Colors.black)).withValues(alpha: low ? 0.14 : 0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          const SizedBox(width: 7),
          Text('$level%',
              style: TextStyle(
                  color: low ? AppColors.sos : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

/// Hàng ô hành động trong sheet: chia đều nếu đủ chỗ, chật thì cuộn ngang
/// (ô cuối lấp ló ở mép để gợi ý cuộn, như các hàng thẻ của iOS).
class _TileRow extends StatelessWidget {
  const _TileRow({required this.children});
  final List<Widget> children;

  static const _gap = 8.0;
  static const _minWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = children.length;
      final even = (c.maxWidth - _gap * (n - 1)) / n;
      if (even >= _minWidth) {
        return Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(width: _minWidth, child: children[i]),
            ],
          ],
        ),
      );
    });
  }
}

/// Banner "Về an toàn" nổi phía trên bản đồ (giữa hai cột nút):
/// chuyến của mình có đếm ngược, tiến độ và nút điều khiển; của người khác là một dòng trạng thái.
/// Nhiều chuyến: hiện chuyến quan trọng nhất kèm "+N", chạm để mở rộng.
class _SafeTripBanner extends StatefulWidget {
  const _SafeTripBanner({
    required this.trips,
    required this.myUid,
    required this.positions,
    required this.nameOf,
    required this.onOpen,
  });

  final List<GroupSafeTrip> trips;
  final String myUid;
  final Map<String, LatLng> positions;
  final String? Function(String uid) nameOf;
  final ValueChanged<GroupSafeTrip> onOpen;

  @override
  State<_SafeTripBanner> createState() => _SafeTripBannerState();
}

class _SafeTripBannerState extends State<_SafeTripBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SafeTripTicker(builder: (context, now) {
      // Quá giờ lên đầu, rồi chuyến của mình, rồi theo giờ dự kiến.
      final trips = [...widget.trips]..sort((a, b) {
          final late = (b.trip.isLate(now) ? 1 : 0).compareTo(a.trip.isLate(now) ? 1 : 0);
          if (late != 0) return late;
          final mine = (b.trip.uid == widget.myUid ? 1 : 0).compareTo(a.trip.uid == widget.myUid ? 1 : 0);
          if (mine != 0) return mine;
          return a.trip.dueAt.compareTo(b.trip.dueAt);
        });
      final shown = _expanded ? trips : trips.take(1).toList();
      final more = trips.length - 1;
      final anyLate = shown.any((t) => t.trip.isLate(now));
      final dark = Theme.of(context).brightness == Brightness.dark;
      final divider = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Glass(
          radius: 26,
          opacity: 0.7,
          blur: 18,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Container(
              // Quá giờ: phủ một lớp đỏ trong mờ bên trong kính (không lồng kính).
              color: anyLate ? AppColors.sos.withValues(alpha: dark ? 0.2 : 0.12) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0)
                      Container(height: 0.5, margin: const EdgeInsets.symmetric(horizontal: 12), color: divider),
                    _item(
                      context,
                      shown[i],
                      now,
                      trailing: i == 0 && more > 0 ? _moreChip(context, more) : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _moreChip(BuildContext context, int more) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPressable(
      onTap: () => setState(() => _expanded = !_expanded),
      shape: const StadiumBorder(),
      scale: 0.9,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: ShapeDecoration(shape: const StadiumBorder(), color: scheme.onSurface.withValues(alpha: 0.1)),
        child: Text(_expanded ? 'Thu gọn' : '+$more',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
      ),
    );
  }

  Widget _item(BuildContext context, GroupSafeTrip t, DateTime now, {Widget? trailing}) {
    final trip = t.trip;
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    final late = trip.isLate(now);
    final color = safeTripColor(trip, now);
    final countdown = safeTripCountdown(trip, now);

    if (trip.uid == widget.myUid) {
      final pos = widget.positions[trip.uid];
      final progress = pos == null || trip.start == null ? null : trip.progress(pos);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onOpen(t),
              child: Row(
                children: [
                  Icon(late ? Icons.warning_rounded : Icons.shield_rounded, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Đang về ${trip.destName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 6), trailing],
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${countdown[0].toUpperCase()}${countdown.substring(1)} · ${clock(trip.dueAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: -0.1,
                color: late ? AppColors.sos : secondary,
                fontWeight: late ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              SafeTripProgressBar(value: progress, color: color, height: 5),
            ],
            const SizedBox(height: 10),
            _CompactControls(gid: t.gid, trip: trip, now: now),
          ],
        ),
      );
    }

    final name = widget.nameOf(trip.uid) ?? trip.name;
    final style = TextStyle(fontSize: 14, height: 1.25, letterSpacing: -0.2, color: scheme.onSurface);
    return GlassPressable(
      onTap: () => widget.onOpen(t),
      shape: const RoundedRectangleBorder(),
      scale: 0.98,
      haptic: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Row(
          children: [
            MemberAvatar(uid: trip.uid, name: name, radius: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                late
                    ? TextSpan(children: [
                        TextSpan(text: '⚠️ $name', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' quá giờ, chưa tới ${trip.destName}'),
                      ])
                    : TextSpan(children: [
                        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' đang về ${trip.destName}'),
                        TextSpan(text: ' · $countdown', style: TextStyle(color: secondary)),
                      ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: late ? style.copyWith(color: AppColors.sos, fontWeight: FontWeight.w600) : style,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }
}

/// Nút điều khiển gọn cho banner hẹp: Đã tới · +15' · Kết thúc / Tôi ổn.
class _CompactControls extends StatelessWidget {
  const _CompactControls({required this.gid, required this.trip, required this.now});
  final String gid;
  final SafeTrip trip;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final late = trip.isLate(now);
    Widget pill(String label, VoidCallback onTap, {Color? color, bool filled = false}) => Expanded(
          child: SafeTripPillButton(label: label, onTap: onTap, color: color, filled: filled),
        );
    return Row(
      children: [
        pill('Đã tới', () => SafeTripActions.arrive(context, gid), color: AppColors.online, filled: true),
        const SizedBox(width: 5),
        pill("+${SafeTripService.extendStep.inMinutes}'", () => SafeTripActions.extend(context, gid, trip)),
        const SizedBox(width: 5),
        pill(late ? 'Tôi ổn' : 'Kết thúc', () => SafeTripActions.end(context, gid, trip),
            color: late ? AppColors.online : null),
      ],
    );
  }
}
