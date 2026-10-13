import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/explore_service.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

enum _Rank { area, percent }

/// Bảng xếp hạng khám phá của các thành viên trong nhóm.
class ExploreLeaderboardScreen extends StatefulWidget {
  const ExploreLeaderboardScreen({super.key, required this.groupId, required this.myUid});
  final String groupId;
  final String myUid;

  @override
  State<ExploreLeaderboardScreen> createState() => _ExploreLeaderboardScreenState();
}

class _ExploreLeaderboardScreenState extends State<ExploreLeaderboardScreen> {
  late final _group = GroupService.instance.group(widget.groupId);
  late final _scores = ExploreService.instance.scores(widget.groupId);
  _Rank _rank = _Rank.area;

  @override
  void initState() {
    super.initState();
    // Cập nhật điểm của chính mình trước khi xem.
    ExploreService.instance.flush().then((_) => ExploreService.instance.publishScore());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('Bảng xếp hạng', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: GlassBackground(
        child: StreamBuilder<Group?>(
          stream: _group,
          builder: (context, gSnap) => StreamBuilder<List<ExploreScore>>(
            stream: _scores,
            builder: (context, sSnap) {
              final g = gSnap.data;
              if (g == null || !sSnap.hasData) {
                return gSnap.hasData || sSnap.hasError
                    ? const EmptyState(icon: Icons.group_off_outlined, title: 'Không tải được nhóm')
                    : const Center(child: CircularProgressIndicator());
              }
              final byUid = {for (final s in sSnap.data!) s.uid: s};
              final rows = [
                for (final uid in g.memberIds)
                  byUid[uid] ?? ExploreScore(uid: uid, name: g.nameOf(uid), count: 0, areaKm2: 0),
              ];
              double value(ExploreScore s) => _rank == _Rank.area ? s.areaKm2 : (s.percent ?? 0);
              rows.sort((a, b) => value(b).compareTo(value(a)));
              String label(ExploreScore s) =>
                  _rank == _Rank.area ? areaLabel(s.areaKm2 * 1e6) : percentLabel(s.percent ?? 0);

              return ListView(
                padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 40),
                children: [
                  Center(
                    child: SegmentedButton<_Rank>(
                      segments: const [
                        ButtonSegment(value: _Rank.area, label: Text('Diện tích'), icon: Icon(Icons.hexagon_outlined)),
                        ButtonSegment(value: _Rank.percent, label: Text('% khu vực'), icon: Icon(Icons.percent)),
                      ],
                      selected: {_rank},
                      onSelectionChanged: (s) => setState(() => _rank = s.first),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Podium(top: rows.take(3).toList(), label: label, group: g),
                  const SizedBox(height: 20),
                  Glass(
                    radius: 26,
                    opacity: 0.6,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          _Row(
                            rank: i + 1,
                            score: rows[i],
                            name: g.nameOf(rows[i].uid),
                            isMe: rows[i].uid == widget.myUid,
                            value: label(rows[i]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _rank == _Rank.area
                        ? 'Xếp theo tổng diện tích các ô lục giác đã đi qua.'
                        : 'Xếp theo % đã khám phá của khu vực mỗi người mở gần nhất trong màn Khám phá.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

class _Podium extends StatelessWidget {
  const _Podium({required this.top, required this.label, required this.group});
  final List<ExploreScore> top;
  final String Function(ExploreScore) label;
  final Group group;

  static const _colors = [Color(0xFFFFC53D), Color(0xFFB8C2D6), Color(0xFFE0975A)];

  @override
  Widget build(BuildContext context) {
    // Thứ tự hiển thị: hạng 2 - hạng 1 - hạng 3.
    const order = [1, 0, 2];
    const heights = [120.0, 90.0, 70.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in order)
          Expanded(
            child: i >= top.length
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MemberAvatar(uid: top[i].uid, name: group.nameOf(top[i].uid), radius: i == 0 ? 36 : 28, ring: true),
                      const SizedBox(height: 6),
                      Text(group.nameOf(top[i].uid),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(label(top[i]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Container(
                        height: heights[i],
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_colors[i], _colors[i].withValues(alpha: 0.55)],
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        ),
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.rank, required this.score, required this.name, required this.isMe, required this.value});
  final int rank;
  final ExploreScore score;
  final String name;
  final bool isMe;
  final String value;

  @override
  Widget build(BuildContext context) {
    final sub = [
      '${score.count} ô',
      if (score.areaName != null && score.percent != null)
        '${shortAreaName(score.areaName!)} ${percentLabel(score.percent!)}',
    ].join(' · ');
    return ListTile(
      leading: SizedBox(
        width: 84,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: rank <= 3 ? AppColors.brand : null)),
            ),
            const SizedBox(width: 6),
            MemberAvatar(uid: score.uid, name: name, radius: 22),
          ],
        ),
      ),
      title: Text(isMe ? '$name (Bạn)' : name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
    );
  }
}
