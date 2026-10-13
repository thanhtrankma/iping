import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/trip_analyzer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'history_screen.dart';

/// Báo cáo lái xe 7 ngày gần nhất (tính năng trả phí của iSharing).
class DrivingScreen extends StatefulWidget {
  const DrivingScreen({super.key, required this.groupId, required this.uid, required this.name});
  final String groupId;
  final String uid;
  final String name;

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen> {
  late final Future<List<Trip>> _drives = () async {
    final now = DateTime.now();
    final pts = await GroupService.instance
        .history(widget.groupId, widget.uid, now.subtract(const Duration(days: 7)), now);
    return buildTimeline(pts).whereType<Trip>().where((t) => t.isDrive).toList().reversed.toList();
  }();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Lái xe · ${widget.name}')),
      body: GlassBackground(
        child: FutureBuilder<List<Trip>>(
          future: _drives,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('Không tải được dữ liệu: ${snap.error}'));
            final drives = snap.data!;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 32),
              children: [
                _Summary(drives: drives),
                const SizedBox(height: 20),
                Text('Các chuyến lái xe',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (drives.isEmpty)
                  const EmptyState(
                    icon: Icons.directions_car_rounded,
                    title: 'Chưa có chuyến lái xe',
                    text: 'Các chuyến đi có tốc độ trên 20 km/h\nsẽ được ghi nhận ở đây.',
                  )
                else
                  for (final t in drives) _DriveRow(trip: t),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.drives});
  final List<Trip> drives;

  @override
  Widget build(BuildContext context) {
    final km = drives.fold(0.0, (a, t) => a + t.distance);
    final score = drives.isEmpty
        ? 100
        : (drives.fold(0, (a, t) => a + t.safetyScore) / drives.length).round();
    final maxSpeed = drives.fold(0.0, (a, t) => t.maxSpeed > a ? t.maxSpeed : a);
    final speeding = drives.fold(0, (a, t) => a + t.speedingEvents);
    final brakes = drives.fold(0, (a, t) => a + t.hardBrakes);

    return Glass(
      radius: 30,
      opacity: 0.65,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              ScoreBadge(score: score, size: 84),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Điểm lái xe an toàn',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      score >= 85
                          ? 'Lái xe rất an toàn trong 7 ngày qua 👍'
                          : score >= 60
                              ? 'Khá ổn, cần chú ý tốc độ và phanh.'
                              : 'Cần lái xe cẩn thận hơn.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _Metric(icon: Icons.route_rounded, value: distanceLabel(km), label: 'Đã lái'),
              _Metric(icon: Icons.directions_car_rounded, value: '${drives.length}', label: 'Chuyến'),
              _Metric(icon: Icons.speed_rounded, value: kmh(maxSpeed), label: 'Tối đa'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                  icon: Icons.warning_amber_rounded,
                  value: '$speeding',
                  label: 'Quá ${(speedLimit * 3.6).round()} km/h',
                  color: speeding > 0 ? AppColors.sos : null),
              _Metric(
                  icon: Icons.front_hand_rounded,
                  value: '$brakes',
                  label: 'Phanh gấp',
                  color: brakes > 0 ? AppColors.warning : null),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label, this.color});
  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brand;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: c),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DriveRow extends StatelessWidget {
  const _DriveRow({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final d = trip.start;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 22,
        opacity: 0.6,
        shadow: false,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: ScoreBadge(score: trip.safetyScore),
          title: Text('${distanceLabel(trip.distance)} · ${durationText(trip.duration)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
              '${d.day}/${d.month} ${clock(trip.start)} · tối đa ${kmh(trip.maxSpeed)}'
              '${trip.hardBrakes > 0 ? ' · ${trip.hardBrakes} phanh gấp' : ''}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip))),
        ),
      ),
    );
  }
}

/// Lịch sử ra/vào các địa điểm của một thành viên.
class MemberPlacesScreen extends StatefulWidget {
  const MemberPlacesScreen({super.key, required this.groupId, required this.uid, required this.name});
  final String groupId;
  final String uid;
  final String name;

  @override
  State<MemberPlacesScreen> createState() => _MemberPlacesScreenState();
}

class _MemberPlacesScreenState extends State<MemberPlacesScreen> {
  late final Stream<List<GroupEvent>> _events = GroupService.instance.memberEvents(widget.groupId, widget.uid);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text('Địa điểm · ${widget.name}')),
      body: GlassBackground(
        child: StreamBuilder<List<GroupEvent>>(
          stream: _events,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final visits = snap.data!.where((e) => e.type == 'arrive' || e.type == 'leave').toList();
            if (visits.isEmpty) {
              return const EmptyState(
                icon: Icons.place_rounded,
                title: 'Chưa có lượt đến/rời',
                text: 'Khi thành viên đến hoặc rời các địa điểm\ncủa nhóm, lịch sử sẽ hiện ở đây.',
              );
            }
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 32),
              itemCount: visits.length,
              itemBuilder: (context, i) {
                final e = visits[i];
                final arrive = e.type == 'arrive';
                final color = arrive ? AppColors.online : AppColors.warning;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Glass(
                    radius: 22,
                    opacity: 0.6,
                    shadow: false,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(arrive ? Icons.login_rounded : Icons.logout_rounded, color: color),
                      ),
                      title: Text('${arrive ? 'Đến' : 'Rời'} ${e.placeName ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${clock(e.createdAt)} · ${timeAgo(e.createdAt)}'),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
