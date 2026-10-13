import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/pause_schedule.dart';
import '../services/privacy_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/privacy_widgets.dart';
import 'member_admin.dart';

/// "Bảo mật & Bạn bè": công tắc chia sẻ chung và ẩn vị trí theo từng nhóm.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.uid});
  final String uid;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final Stream<List<Group>> _groups = GroupService.instance.myGroups(widget.uid);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Bảo mật & Bạn bè'),
      body: GlassBackground(
        child: StreamBuilder<List<Group>>(
          stream: _groups,
          builder: (context, snap) {
            final groups = snap.data;
            return ValueListenableBuilder<PauseSchedule>(
              valueListenable: PrivacyService.instance.paused,
              builder: (context, schedule, _) => ListView(
                padding: EdgeInsets.fromLTRB(0, MediaQuery.paddingOf(context).top + 60 + 8, 0, 40),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SharingSwitchCard(),
                  ),
                  const SizedBox(height: 28),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Chia sẻ theo nhóm',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Tạm ẩn vị trí với một nhóm mà không ảnh hưởng các nhóm khác.',
                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (snap.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Lỗi tải nhóm: ${snap.error}'),
                    )
                  else if (groups == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    )
                  else if (groups.isEmpty)
                    const EmptyState(icon: Icons.diversity_3_rounded, title: 'Chưa có nhóm nào')
                  else
                    for (final g in groups)
                      _GroupPrivacyCard(group: g, uid: widget.uid, paused: schedule.isPaused(g.id, DateTime.now())),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GroupPrivacyCard extends StatelessWidget {
  const _GroupPrivacyCard({required this.group, required this.uid, required this.paused});
  final Group group;
  final String uid;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return GlassSection(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      dividerIndent: 16 + 30 + 14,
      children: [
        ListTile(
          horizontalTitleGap: 14,
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          leading: GlassIconBadge(
            icon: paused ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: paused ? AppColors.warning : AppColors.online,
          ),
          title: Text(
            group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            pauseStatus(group.id),
            style: TextStyle(color: paused ? AppColors.warning : secondary),
          ),
          trailing: Switch(
            value: !paused,
            onChanged: (on) => on ? resumeGroup(context, group) : showPauseSheet(context, group),
          ),
          onTap: () => showPauseSheet(context, group),
        ),
        ListTile(
          horizontalTitleGap: 14,
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          leading: const GlassIconBadge(icon: Icons.group_rounded, color: AppColors.indigo),
          title: Text(group.isOwner(uid) ? 'Thành viên & danh sách chặn' : 'Thành viên'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${group.memberIds.length}', style: TextStyle(color: secondary, fontSize: 15)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => GroupMembersScreen(groupId: group.id))),
        ),
      ],
    );
  }
}
