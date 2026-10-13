import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/trip_analyzer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'history_screen.dart';

Color _scoreColor(int score) => score >= 85
    ? AppColors.online
    : score >= 60
        ? AppColors.warning
        : AppColors.sos;

Color _secondary(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

/// Khoảng đệm phía trên nội dung khi dùng [GlassAppBar] với extendBodyBehindAppBar.
double _topPad(BuildContext context) => MediaQuery.paddingOf(context).top + 60 + 8;

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
    final pts =
        await GroupService.instance.history(widget.groupId, widget.uid, now.subtract(const Duration(days: 7)), now);
    return buildTimeline(pts).whereType<Trip>().where((t) => t.isDrive).toList().reversed.toList();
  }();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: 'Lái xe · ${widget.name}'),
      body: GlassBackground(
        child: FutureBuilder<List<Trip>>(
          future: _drives,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Không tải được dữ liệu: ${snap.error}',
                      textAlign: TextAlign.center, style: TextStyle(color: _secondary(context))),
                ),
              );
            }
            final drives = snap.data!;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, _topPad(context), 16, 32 + MediaQuery.paddingOf(context).bottom),
              children: [
                _Summary(drives: drives),
                const SizedBox(height: 28),
                if (drives.isEmpty)
                  const EmptyState(
                    icon: Icons.directions_car_rounded,
                    title: 'Chưa có chuyến lái xe',
                    text: 'Các chuyến đi có tốc độ trên 20 km/h\nsẽ được ghi nhận ở đây.',
                  )
                else
                  GlassSection(
                    header: 'Các chuyến lái xe',
                    margin: EdgeInsets.zero,
                    dividerIndent: 74,
                    children: [for (final t in drives) _DriveRow(trip: t)],
                  ),
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
    final score = drives.isEmpty ? 100 : (drives.fold(0, (a, t) => a + t.safetyScore) / drives.length).round();
    final maxSpeed = drives.fold(0.0, (a, t) => t.maxSpeed > a ? t.maxSpeed : a);
    final speeding = drives.fold(0, (a, t) => a + t.speedingEvents);
    final brakes = drives.fold(0, (a, t) => a + t.hardBrakes);

    return Glass(
      radius: 34,
      opacity: 0.65,
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      child: Column(
        children: [
          Center(child: _ScoreRing(score: score)),
          const SizedBox(height: 18),
          Text(
            '7 NGÀY QUA',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: _secondary(context)),
          ),
          const SizedBox(height: 2),
          const Text('Điểm lái xe an toàn',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              score >= 85
                  ? 'Lái xe rất an toàn trong 7 ngày qua 👍'
                  : score >= 60
                      ? 'Khá ổn, cần chú ý tốc độ và phanh.'
                      : 'Cần lái xe cẩn thận hơn.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: _secondary(context)),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _Metric(icon: Icons.route_rounded, value: distanceLabel(km), label: 'Đã lái', badge: AppColors.brand),
              const SizedBox(width: 8),
              _Metric(
                  icon: Icons.directions_car_rounded,
                  value: '${drives.length}',
                  label: 'Chuyến',
                  badge: AppColors.teal),
              const SizedBox(width: 8),
              _Metric(icon: Icons.speed_rounded, value: kmh(maxSpeed), label: 'Tối đa', badge: AppColors.indigo),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Metric(
                icon: Icons.warning_amber_rounded,
                value: '$speeding',
                label: 'Quá ${(speedLimit * 3.6).round()} km/h',
                badge: AppColors.sos,
                color: speeding > 0 ? AppColors.sos : null,
              ),
              const SizedBox(width: 8),
              _Metric(
                icon: Icons.front_hand_rounded,
                value: '$brakes',
                label: 'Phanh gấp',
                badge: AppColors.warning,
                color: brakes > 0 ? AppColors.warning : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vòng điểm lớn kiểu Apple Fitness: rãnh mờ + cung gradient bo tròn, số to ở giữa.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});
  final int score;

  static const _size = 196.0;
  static const _stroke = 22.0;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _FitnessRingPainter(progress: t, color: color, stroke: _stroke),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(t * 100).round()}',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -3,
                    height: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text('/ 100',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FitnessRingPainter extends CustomPainter {
  _FitnessRingPainter({required this.progress, required this.color, required this.stroke});
  final double progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final center = rect.center;
    final r = rect.width / 2;

    // Rãnh nền.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.16),
    );
    if (progress <= 0) return;

    final sweep = math.pi * 2 * progress;
    final light = Color.lerp(color, Colors.white, 0.35)!;
    // Xoay để gradient bắt đầu tại 12 giờ.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 2);
    canvas.translate(-center.dx, -center.dy);

    // Quầng sáng mờ dưới cung.
    canvas.drawArc(
      rect,
      0,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..color = color.withValues(alpha: 0.35),
    );
    canvas.drawArc(
      rect,
      0,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [light, color],
          stops: [0, math.max(progress, 0.01)],
        ).createShader(rect),
    );
    canvas.restore();
    // Nắp đầu cung (tránh gradient quấn vòng làm nắp đầu bị tối).
    canvas.drawCircle(Offset(center.dx, center.dy - r), stroke / 2, Paint()..color = light);

    // Đầu cung có bóng nhẹ, như vòng Activity khi chồng lên chính nó.
    final end = -math.pi / 2 + sweep;
    final tip = Offset(center.dx + r * math.cos(end), center.dy + r * math.sin(end));
    canvas.drawCircle(
      tip + Offset(math.cos(end + math.pi / 2), math.sin(end + math.pi / 2)) * 2,
      stroke / 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(tip, stroke / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FitnessRingPainter old) => old.progress != progress || old.color != color || old.stroke != stroke;
}

/// Ô chỉ số trên nền mờ trong thẻ kính (góc bo đồng tâm với thẻ).
class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label, required this.badge, this.color});
  final IconData icon;
  final String value;
  final String label;
  final Color badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        decoration: ShapeDecoration(
          shape: glassShape(radius: 22),
          color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassIconBadge(icon: icon, color: badge, size: 26),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _secondary(context))),
          ],
        ),
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
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            ScoreBadge(score: trip.safetyScore),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${distanceLabel(trip.distance)} · ${durationText(trip.duration)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}/${d.month} ${clock(trip.start)} · tối đa ${kmh(trip.maxSpeed)}'
                    '${trip.hardBrakes > 0 ? ' · ${trip.hardBrakes} phanh gấp' : ''}',
                    style: TextStyle(fontSize: 13, color: _secondary(context)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          ],
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
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: 'Địa điểm · ${widget.name}'),
      body: GlassBackground(
        child: StreamBuilder<List<GroupEvent>>(
          stream: _events,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator.adaptive());
            final visits = snap.data!.where((e) => e.type == 'arrive' || e.type == 'leave').toList();
            if (visits.isEmpty) {
              return const EmptyState(
                icon: Icons.place_rounded,
                title: 'Chưa có lượt đến/rời',
                text: 'Khi thành viên đến hoặc rời các địa điểm\ncủa nhóm, lịch sử sẽ hiện ở đây.',
              );
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(0, _topPad(context), 0, 32 + MediaQuery.paddingOf(context).bottom),
              children: [
                GlassSection(
                  dividerIndent: 64,
                  children: [
                    for (final e in visits) _VisitRow(event: e),
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

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.event});
  final GroupEvent event;

  @override
  Widget build(BuildContext context) {
    final arrive = event.type == 'arrive';
    final color = arrive ? AppColors.online : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GlassIconBadge(icon: arrive ? Icons.login_rounded : Icons.logout_rounded, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${arrive ? 'Đến' : 'Rời'} ${event.placeName ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text('${clock(event.createdAt)} · ${timeAgo(event.createdAt)}',
                    style: TextStyle(fontSize: 13, color: _secondary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
