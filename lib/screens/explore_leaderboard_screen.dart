import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/explore_service.dart';
import '../services/group_service.dart';
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
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: const GlassAppBar(title: 'Bảng xếp hạng'),
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
                    : const Center(child: CircularProgressIndicator.adaptive());
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
                padding: EdgeInsets.fromLTRB(
                  0,
                  MediaQuery.paddingOf(context).top + 60 + 8,
                  0,
                  40 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Center(
                    child: _GlassSegmented<_Rank>(
                      values: const [_Rank.area, _Rank.percent],
                      labels: const ['Diện tích', '% khu vực'],
                      icons: const [Icons.hexagon_outlined, Icons.percent_rounded],
                      selected: _rank,
                      onChanged: (r) => setState(() => _rank = r),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _Podium(top: rows.take(3).toList(), label: label, group: g),
                  ),
                  const SizedBox(height: 24),
                  GlassSection(
                    header: 'Tất cả thành viên',
                    dividerIndent: 108,
                    footer: _rank == _Rank.area
                        ? 'Xếp theo tổng diện tích các ô lục giác đã đi qua.'
                        : 'Xếp theo % đã khám phá của khu vực mỗi người mở gần nhất trong màn Khám phá.',
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        _Row(
                          rank: i + 1,
                          score: rows[i],
                          name: g.nameOf(rows[i].uid),
                          isMe: rows[i].uid == widget.myUid,
                          value: label(rows[i]),
                          secondary: secondary,
                        ),
                    ],
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

/// Bộ chọn phân đoạn dạng viên kính, có "thấu kính" trượt theo lựa chọn.
class _GlassSegmented<T> extends StatelessWidget {
  const _GlassSegmented({
    required this.values,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });
  final List<T> values;
  final List<String> labels;
  final List<IconData> icons;
  final T selected;
  final ValueChanged<T> onChanged;

  static const _segment = 138.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final index = values.indexOf(selected);
    return Glass(
      capsule: true,
      opacity: 0.65,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: _segment * values.length,
        height: 40,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              left: _segment * index,
              top: 0,
              bottom: 0,
              width: _segment,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: dark ? Colors.white.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.9),
                  shadows: dark
                      ? null
                      : [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))
                        ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < values.length; i++)
                  SizedBox(
                    width: _segment,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i == index) return;
                        HapticFeedback.selectionClick();
                        onChanged(values[i]);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icons[i],
                              size: 17, color: i == index ? scheme.primary : scheme.onSurface.withValues(alpha: 0.6)),
                          const SizedBox(width: 6),
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: i == index ? FontWeight.w700 : FontWeight.w600,
                              letterSpacing: -0.2,
                              color: i == index ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
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

  /// Vàng, bạc, đồng.
  static const _colors = [Color(0xFFFFC53D), Color(0xFFAEB8CC), Color(0xFFE0975A)];

  @override
  Widget build(BuildContext context) {
    // Thứ tự hiển thị: hạng 2 - hạng 1 - hạng 3.
    const order = [1, 0, 2];
    const heights = [124.0, 92.0, 72.0];
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
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
                      if (i == 0) const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFB800), size: 26),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: _colors[i].withValues(alpha: 0.55), blurRadius: 16)],
                        ),
                        child: MemberAvatar(
                            uid: top[i].uid, name: group.nameOf(top[i].uid), radius: i == 0 ? 36 : 28, ring: true),
                      ),
                      const SizedBox(height: 8),
                      Text(group.nameOf(top[i].uid),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.3)),
                      Text(label(top[i]),
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: secondary)),
                      const SizedBox(height: 8),
                      // Bục: khối màu bo squircle phía trên, có vệt sáng như kính.
                      Container(
                        height: heights[i],
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: ShapeDecoration(
                          shape: const RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.lerp(_colors[i], Colors.white, 0.15)!,
                              _colors[i].withValues(alpha: 0.35),
                            ],
                          ),
                          shadows: [
                            BoxShadow(
                                color: _colors[i].withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6)),
                          ],
                        ),
                        foregroundDecoration: ShapeDecoration(
                          shape: const RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: const Alignment(0, -0.2),
                            colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0)],
                          ),
                        ),
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              shadows: [Shadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 1))],
                            )),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rank,
    required this.score,
    required this.name,
    required this.isMe,
    required this.value,
    required this.secondary,
  });
  final int rank;
  final ExploreScore score;
  final String name;
  final bool isMe;
  final String value;
  final Color secondary;

  static const _medals = [Color(0xFFFFB800), Color(0xFF9AA5BB), Color(0xFFD9823F)];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = [
      '${score.count} ô',
      if (score.areaName != null && score.percent != null)
        '${shortAreaName(score.areaName!)} ${percentLabel(score.percent!)}',
    ].join(' · ');
    return Container(
      color: isMe ? scheme.primary.withValues(alpha: 0.08) : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: rank <= 3 ? _medals[rank - 1] : secondary,
                )),
          ),
          const SizedBox(width: 10),
          MemberAvatar(uid: score.uid, name: name, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '$name (Bạn)' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: isMe ? scheme.primary : null,
                    )),
                const SizedBox(height: 1),
                Text(sub,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: secondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        ],
      ),
    );
  }
}
