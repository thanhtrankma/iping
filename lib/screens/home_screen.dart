import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/all_friends_service.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/explore_pill.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';
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
    return StreamBuilder<List<Moment>>(
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
                        MarkerLayer(markers: [
                          for (final m in meetups)
                            Marker(
                              point: m.point,
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                onTap: () => _push(MeetupDetailScreen(group: g!, meetupId: m.id)),
                                child: const Icon(Icons.flag_circle_rounded, size: 44, color: AppColors.sos),
                              ),
                            ),
                          for (final m in moments.where((m) => m.hasLocation))
                            momentMarker(m, () => _push(MomentsScreen(group: g!))),
                          for (final l in locs) memberMarker(l),
                        ]),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
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
                                const SizedBox(height: 14),
                                GlassButton(
                                  icon: Icons.person_add_alt_1_rounded,
                                  tooltip: 'Mời thành viên',
                                  onTap: () => AllFriendsActions.invite(context, g, widget.groups),
                                ),
                                const SizedBox(height: 14),
                                GlassButton(
                                  tooltip: 'Gửi SOS',
                                  onTap: () => AllFriendsActions.sos(context, g, widget.groups),
                                  child: const Text('SOS',
                                      style:
                                          TextStyle(color: AppColors.sos, fontWeight: FontWeight.w900, fontSize: 16)),
                                ),
                                const SizedBox(height: 14),
                                GlassButton(
                                  icon: Icons.where_to_vote_rounded,
                                  tooltip: 'Check-in',
                                  onTap: () => AllFriendsActions.checkIn(context, g, widget.groups),
                                ),
                              ],
                            ],
                          ),
                          const Spacer(),
                          Column(
                            children: [
                              ExplorePill(
                                onOpen: () => _push(const ExploreScreen()),
                                onLeaderboard: () => g == null
                                    ? _push(const ExploreScreen())
                                    : AllFriendsActions.open(context, g, widget.groups,
                                        (x) => ExploreLeaderboardScreen(groupId: x.id, myUid: widget.uid)),
                              ),
                              const _SharingBadge(),
                            ],
                          ),
                          const Spacer(),
                          Column(
                            children: [
                              ValueListenableBuilder<MapStyle>(
                                valueListenable: SettingsService.instance.mapStyle,
                                builder: (context, style, _) => GlassButton(
                                  icon: style == MapStyle.satellite ? Icons.map_outlined : Icons.satellite_alt_rounded,
                                  tooltip: 'Đổi kiểu bản đồ',
                                  onTap: SettingsService.instance.toggleMapStyle,
                                ),
                              ),
                              const SizedBox(height: 14),
                              GlassButton(icon: Icons.near_me_rounded, tooltip: 'Vị trí của tôi', onTap: _focusMe),
                              if (g != null) ...[
                                const SizedBox(height: 14),
                                GlassButton(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  tooltip: 'Trò chuyện',
                                  onTap: () => AllFriendsActions.open(
                                      context, g, widget.groups, (x) => SubPage(title: x.name, child: ChatTab(group: x)),
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
                    const Center(child: CircularProgressIndicator())
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
                      onOpenMember: (uid) => _push(MemberScreen(
                          groupId: _all ? AllFriendsService.groupFor(uid, widget.groups, _groupOf) ?? g.id : g.id,
                          uid: uid)),
                      onOpenPage: _push,
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
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Glass(
            radius: 32,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 64),
                const SizedBox(height: 16),
                Text('Bắt đầu với IPing',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'Tạo nhóm cho gia đình, bạn bè hoặc nhập mã mời để xem mọi người đang ở đâu.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('Tạo nhóm mới'),
                  onPressed: () => GroupActions.create(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
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

  @override
  Widget build(BuildContext context) {
    final byUid = {for (final l in locations) l.uid: l};
    final members = [...group.memberIds]..sort((a, b) => (a == myUid ? 0 : 1).compareTo(b == myUid ? 0 : 1));
    final dark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.2,
      maxChildSize: 0.88,
      snap: true,
      snapSizes: const [0.42],
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Glass(
          radius: 34,
          opacity: 0.6,
          child: ListView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => GroupActions.pickGroup(context, groups, group.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(group.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GlassButton(
                    size: 48,
                    icon: Icons.person_add_alt_1_rounded,
                    color: AppColors.brand,
                    tooltip: 'Mời thành viên',
                    onTap: () => AllFriendsActions.invite(context, group, groups),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GlassTile(
                      icon: Icons.auto_awesome_outlined,
                      label: momentCount > 0 ? 'Khoảnh khắc ($momentCount)' : 'Khoảnh khắc',
                      onTap: () => AllFriendsActions.open(context, group, groups, (g) => MomentsScreen(group: g)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassTile(
                      icon: Icons.handshake_outlined,
                      label: 'Meetup',
                      onTap: () => AllFriendsActions.open(context, group, groups, (g) => MeetupListScreen(group: g)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassTile(
                      icon: Icons.place_outlined,
                      label: 'Địa điểm',
                      onTap: () => AllFriendsActions.open(
                          context, group, groups, (g) => SubPage(title: 'Địa điểm', child: PlacesTab(group: g))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassTile(
                      icon: Icons.notifications_none_rounded,
                      label: 'Hoạt động',
                      onTap: () => AllFriendsActions.open(
                          context, group, groups, (g) => SubPage(title: 'Hoạt động', child: ActivityTab(group: g))),
                    ),
                  ),
                ],
              ),
              for (final m in meetups) ...[
                const SizedBox(height: 12),
                MeetupCard(group: group, meetup: m),
              ],
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
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
    final sub = TextStyle(color: scheme.onSurfaceVariant, fontSize: 14);
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

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              height: 66,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  MemberAvatar(uid: uid, name: name, radius: 30, dimmed: loc == null || !loc.sharing),
                  if (loc?.battery != null)
                    Positioned(bottom: 0, child: BatteryPill(level: loc!.battery!, compact: true)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isMe ? '$name (Bạn)' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  subtitle,
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Nhãn pin kiểu iSharing.
class BatteryPill extends StatelessWidget {
  const BatteryPill({super.key, required this.level, this.compact = false});
  final int level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = level <= 20 ? AppColors.sos : const Color(0xFF2EC4A6);
    final bar = Container(
      width: compact ? 16 : 20,
      height: compact ? 8 : 11,
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: (level / 100).clamp(0.1, 1),
        child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5))),
      ),
    );
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)],
        ),
        child: bar,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          const SizedBox(width: 8),
          Text('$level%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ),
    );
  }
}
