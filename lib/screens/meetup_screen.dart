import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
import 'history_screen.dart' show durationText, fitPoints;

/// Ước tính thời gian tới điểm hẹn: dùng tốc độ hiện tại nếu đang di chuyển,
/// nếu không thì giả định đi xe máy trong phố (~25 km/h). Quãng đường thực tế
/// thường dài hơn đường chim bay nên nhân thêm 1.3.
Duration estimateEta(double meters, double? speed) {
  final v = (speed != null && speed > 2) ? speed : 25 / 3.6;
  return Duration(seconds: (meters * 1.3 / v).round());
}

String _timeLabel(DateTime t) {
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return sameDay ? 'Hôm nay $hm' : '$hm ${t.day}/${t.month}';
}

(String, Color, IconData) statusInfo(MeetupStatus s) => switch (s) {
      MeetupStatus.going => ('Đang tới', AppColors.brand, Icons.directions_run_rounded),
      MeetupStatus.arrived => ('Đã tới', AppColors.online, Icons.check_circle_rounded),
      MeetupStatus.declined => ('Không đi', AppColors.gray, Icons.cancel_rounded),
      MeetupStatus.invited => ('Chưa trả lời', AppColors.warning, Icons.help_rounded),
    };

/// Danh sách meetup đang diễn ra của nhóm.
class MeetupListScreen extends StatefulWidget {
  const MeetupListScreen({super.key, required this.group});
  final Group group;

  @override
  State<MeetupListScreen> createState() => _MeetupListScreenState();
}

class _MeetupListScreenState extends State<MeetupListScreen> {
  late final Stream<List<Meetup>> _meetups = GroupService.instance.activeMeetups(widget.group.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Meetup'),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _FloatingAction(
        icon: Icons.add_location_alt_rounded,
        label: 'Tạo điểm hẹn',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CreateMeetupScreen(group: widget.group),
        )),
      ),
      body: GlassBackground(
        child: StreamBuilder<List<Meetup>>(
          stream: _meetups,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.handshake_rounded,
                title: 'Chưa có cuộc hẹn nào',
                text: 'Chọn một điểm hẹn và giờ hẹn.\nCả nhóm sẽ thấy ai đang tới và còn bao xa.',
              );
            }
            final mq = MediaQuery.of(context);
            return ListView(
              padding: EdgeInsets.only(top: mq.padding.top + 12, bottom: mq.padding.bottom + 110),
              children: [
                GlassSection(
                  header: 'Đang diễn ra',
                  dividerIndent: 76,
                  children: [
                    for (final m in list)
                      GlassPressable(
                        scale: 0.98,
                        shape: const RoundedRectangleBorder(),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MeetupDetailScreen(group: widget.group, meetupId: m.id),
                        )),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          child: _MeetupSummary(meetup: m),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Thẻ meetup nhỏ (dùng trên màn hình chính, nằm trong bảng kính).
/// Không dùng kính lồng kính: chỉ là lớp nền mờ nhẹ, góc bo đồng tâm.
class MeetupCard extends StatelessWidget {
  const MeetupCard({super.key, required this.group, required this.meetup});
  final Group group;
  final Meetup meetup;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = glassShape(radius: 22);
    return GlassPressable(
      shape: shape,
      scale: 0.97,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MeetupDetailScreen(group: group, meetupId: meetup.id),
      )),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: _MeetupSummary(meetup: meetup),
        ),
      ),
    );
  }
}

/// Nội dung một dòng meetup: biểu tượng cờ, tên, giờ hẹn và số người.
class _MeetupSummary extends StatelessWidget {
  const _MeetupSummary({required this.meetup});
  final Meetup meetup;

  @override
  Widget build(BuildContext context) {
    final m = meetup;
    final scheme = Theme.of(context).colorScheme;
    final going = m.participants.values.where((s) => s == MeetupStatus.going).length;
    final arrived = m.participants.values.where((s) => s == MeetupStatus.arrived).length;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: ShapeDecoration(shape: glassShape(radius: 14), gradient: AppColors.brandGradient),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text('${_timeLabel(m.time)} · $arrived đã tới · $going đang tới',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), fontSize: 13.5)),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
      ],
    );
  }
}

/// Nút hành động chính nổi dạng viên thuốc kính có màu thương hiệu.
class _FloatingAction extends StatelessWidget {
  const _FloatingAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      tint: AppColors.brand,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

/// Nhóm dòng bên trong một bảng kính: nền mờ nhẹ (không phải kính lồng kính),
/// ngăn cách bằng đường kẻ mảnh 0.5px.
class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.children, this.dividerIndent = 16});
  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = glassShape(radius: 20);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: dividerIndent,
                    color: scheme.onSurface.withValues(alpha: 0.12),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh nắm kéo của sheet kính.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
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

/// Tạo meetup: chạm bản đồ để chọn điểm hẹn, đặt tên và giờ.
class CreateMeetupScreen extends StatefulWidget {
  const CreateMeetupScreen({super.key, required this.group});
  final Group group;

  @override
  State<CreateMeetupScreen> createState() => _CreateMeetupScreenState();
}

class _CreateMeetupScreenState extends State<CreateMeetupScreen> {
  final _title = TextEditingController();
  final _map = MapController();
  late LatLng _point;
  late DateTime _time = DateTime.now().add(const Duration(minutes: 30));
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = LocationService.instance.lastPosition.value;
    _point = p != null ? LatLng(p.latitude, p.longitude) : defaultCenter;
  }

  @override
  void dispose() {
    _map.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final tod = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
    if (tod == null) return;
    setState(() => _time = DateTime(date.year, date.month, date.day, tod.hour, tod.minute));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'Hãy đặt tên cho cuộc hẹn');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await GroupService.instance
          .createMeetup(widget.group.id, title: title, lat: _point.latitude, lng: _point.longitude, time: _time);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MeetupDetailScreen(group: widget.group, meetupId: id),
      ));
    } catch (e) {
      if (mounted) showMessage(context, 'Không tạo được: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IPingMap(
              controller: _map,
              center: _point,
              zoom: 16,
              onTap: (_, p) => setState(() => _point = p),
              layers: [
                MarkerLayer(markers: [
                  Marker(
                    point: _point,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.flag_circle_rounded, size: 56, color: AppColors.sos),
                  ),
                ]),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  GlassButton(
                    size: 46,
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Quay lại',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Glass(
                      capsule: true,
                      opacity: 0.65,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: AppColors.sos),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text('Chạm bản đồ để chọn điểm hẹn',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Glass(
                  radius: 34,
                  opacity: 0.78,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 6, bottom: 12),
                          child: Text('Điểm hẹn mới',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ),
                        TextField(
                          controller: _title,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Tên cuộc hẹn (vd: Cà phê cuối tuần)',
                            prefixIcon: Icon(Icons.flag_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _InsetGroup(
                          dividerIndent: 52,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Row(
                                children: [
                                  const GlassIconBadge(icon: Icons.place_rounded, color: AppColors.sos, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(child: AddressText(_point.latitude, _point.longitude, maxLines: 1)),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: _pickTime,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Row(
                                  children: [
                                    const GlassIconBadge(
                                        icon: Icons.schedule_rounded, color: AppColors.brand, size: 28),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(_timeLabel(_time),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                                    ),
                                    Text('Đổi giờ',
                                        style: TextStyle(
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.w600)),
                                    Icon(Icons.chevron_right_rounded,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded),
                          label: const Text('Tạo & mời cả nhóm'),
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
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

/// Chi tiết meetup: điểm hẹn, vị trí mọi người, khoảng cách và thời gian ước tính.
class MeetupDetailScreen extends StatefulWidget {
  const MeetupDetailScreen({super.key, required this.group, required this.meetupId});
  final Group group;
  final String meetupId;

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }
  final _me = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<Meetup?> _meetup = GroupService.instance.meetup(widget.group.id, widget.meetupId);
  late final Stream<List<MemberLocation>> _locations = GroupService.instance.locations(widget.group.id);
  bool _fitted = false;

  void _fitOnce(Meetup m, List<MemberLocation> locs) {
    if (_fitted) return;
    _fitted = true;
    final pts = [m.point, ...locs.map((l) => l.point)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.fitCamera(fitPoints(pts, padding: 80));
    });
  }

  Future<void> _end(Meetup m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc cuộc hẹn?'),
        content: const Text('Cuộc hẹn sẽ biến mất khỏi danh sách của cả nhóm.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await GroupService.instance.endMeetup(widget.group.id, m.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Meetup?>(
        stream: _meetup,
        builder: (context, mSnap) => StreamBuilder<List<MemberLocation>>(
          stream: _locations,
          builder: (context, lSnap) {
            final m = mSnap.data;
            if (m == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final locs = (lSnap.data ?? const <MemberLocation>[])
                .where((l) => widget.group.memberIds.contains(l.uid))
                .toList();
            if (lSnap.hasData) _fitOnce(m, locs);
            final byUid = {for (final l in locs) l.uid: l};
            final myStatus = m.statusOf(_me);

            return Stack(
              children: [
                Positioned.fill(
                  child: IPingMap(
                    controller: _map,
                    center: m.point,
                    zoom: 15,
                    layers: [
                      CircleLayer(circles: [
                        CircleMarker(
                          point: m.point,
                          radius: 100,
                          useRadiusInMeter: true,
                          color: AppColors.sos.withValues(alpha: 0.15),
                          borderColor: Colors.white,
                          borderStrokeWidth: 2,
                        ),
                      ]),
                      PolylineLayer(polylines: [
                        for (final l in locs)
                          if (m.statusOf(l.uid) == MeetupStatus.going)
                            Polyline(
                              points: [l.point, m.point],
                              strokeWidth: 3,
                              color: AppColors.brand.withValues(alpha: 0.8),
                              pattern: StrokePattern.dashed(segments: const [10, 8]),
                            ),
                      ]),
                      MarkerLayer(markers: [
                        for (final l in locs) memberMarker(l, size: 46),
                        Marker(
                          point: m.point,
                          width: 56,
                          height: 56,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.flag_circle_rounded, size: 56, color: AppColors.sos),
                        ),
                      ]),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        GlassButton(
                          size: 46,
                          icon: Icons.chevron_left_rounded,
                          tooltip: 'Quay lại',
                          onTap: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        if (m.createdBy == _me)
                          GlassPill(
                            onTap: () => _end(m),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                            child: const Text('Kết thúc',
                                style: TextStyle(color: AppColors.sos, fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                      ],
                    ),
                  ),
                ),
                DraggableScrollableSheet(
                  initialChildSize: 0.45,
                  minChildSize: 0.25,
                  maxChildSize: 0.85,
                  builder: (context, scroll) {
                    final scheme = Theme.of(context).colorScheme;
                    final secondary = scheme.onSurface.withValues(alpha: 0.55);
                    final bottom = MediaQuery.paddingOf(context).bottom;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, floatingBottomGap(context)),
                      child: Glass(
                        radius: 38,
                        opacity: 0.78,
                        blur: 20,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListView(
                            controller: scroll,
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom * 0.6),
                            children: [
                              const _Grabber(),
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.title,
                                        style: const TextStyle(
                                            fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.schedule_rounded, size: 17, color: AppColors.brand),
                                        const SizedBox(width: 6),
                                        Text(_timeLabel(m.time), style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Flexible(
                                          child: Text('  ·  ${m.createdByName} tạo',
                                              overflow: TextOverflow.ellipsis, style: TextStyle(color: secondary)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 1),
                                          child: Icon(Icons.place_rounded, size: 17, color: AppColors.sos),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: AddressText(m.lat, m.lng,
                                              maxLines: 2, style: TextStyle(color: secondary)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (myStatus != MeetupStatus.arrived)
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              myStatus == MeetupStatus.going ? AppColors.online : AppColors.brand,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: Icon(myStatus == MeetupStatus.going
                                            ? Icons.check_rounded
                                            : Icons.directions_run_rounded),
                                        label: Text(myStatus == MeetupStatus.going ? 'Đang tới' : 'Tôi sẽ tới'),
                                        onPressed: () => GroupService.instance
                                            .setMeetupStatus(widget.group.id, m.id, MeetupStatus.going),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                                          foregroundColor: myStatus == MeetupStatus.declined
                                              ? secondary
                                              : scheme.onSurface,
                                        ),
                                        onPressed: () => GroupService.instance
                                            .setMeetupStatus(widget.group.id, m.id, MeetupStatus.declined),
                                        child: Text(myStatus == MeetupStatus.declined ? 'Đã từ chối' : 'Không đi'),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 22),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                                child: Text('THÀNH VIÊN',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        letterSpacing: 0.3,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface.withValues(alpha: 0.5))),
                              ),
                              _InsetGroup(
                                dividerIndent: 70,
                                children: [
                                  for (final uid in widget.group.memberIds)
                                    _ParticipantRow(
                                      uid: uid,
                                      name: byUid[uid]?.name ?? widget.group.nameOf(uid),
                                      status: m.statusOf(uid),
                                      location: byUid[uid],
                                      meetup: m,
                                      onTap: byUid[uid] == null ? null : () => _map.move(byUid[uid]!.point, 16),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.uid,
    required this.name,
    required this.status,
    required this.location,
    required this.meetup,
    required this.onTap,
  });

  final String uid;
  final String name;
  final MeetupStatus status;
  final MemberLocation? location;
  final Meetup meetup;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = statusInfo(status);
    final loc = location;
    String detail;
    if (status == MeetupStatus.arrived) {
      detail = 'Đã có mặt';
    } else if (loc == null || !loc.sharing) {
      detail = 'Không rõ vị trí';
    } else {
      final d = distanceBetween(loc.lat, loc.lng, meetup.lat, meetup.lng);
      detail = 'Cách ${distanceLabel(d)}';
      if (status == MeetupStatus.going) detail += ' · ~${durationText(estimateEta(d, loc.speed))}';
    }
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            MemberAvatar(uid: uid, name: name, radius: 22, dimmed: status == MeetupStatus.declined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, letterSpacing: -0.2)),
                  const SizedBox(height: 1),
                  Text(detail, style: TextStyle(color: secondary, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: ShapeDecoration(shape: const StadiumBorder(), color: color.withValues(alpha: 0.14)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
