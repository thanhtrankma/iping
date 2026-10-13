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
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Bảo mật & Bạn bè')),
      body: GlassBackground(
        child: StreamBuilder<List<Group>>(
          stream: _groups,
          builder: (context, snap) {
            final groups = snap.data;
            return ValueListenableBuilder<PauseSchedule>(
              valueListenable: PrivacyService.instance.paused,
              builder: (context, schedule, _) => ListView(
                padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 40),
                children: [
                  const SharingSwitchCard(),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Chia sẻ theo nhóm', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Tạm ẩn vị trí với một nhóm mà không ảnh hưởng các nhóm khác.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 12),
                  if (snap.hasError)
                    Text('Lỗi tải nhóm: ${snap.error}')
                  else if (groups == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (groups.isEmpty)
                    const EmptyState(icon: Icons.diversity_3_rounded, title: 'Chưa có nhóm nào')
                  else
                    for (final g in groups) ...[
                      _GroupPrivacyCard(group: g, uid: widget.uid, paused: schedule.isPaused(g.id, DateTime.now())),
                      const SizedBox(height: 12),
                    ],
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
    return Glass(
      radius: 26,
      opacity: 0.6,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
            leading: Icon(paused ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: paused ? AppColors.warning : AppColors.brand),
            title: Text(group.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(pauseStatus(group.id)),
            trailing: Switch(
              value: !paused,
              onChanged: (on) => on ? resumeGroup(context, group) : showPauseSheet(context, group),
            ),
            onTap: () => showPauseSheet(context, group),
          ),
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
            leading: const Icon(Icons.group_outlined),
            title: Text(group.isOwner(uid) ? 'Thành viên & danh sách chặn' : 'Thành viên',
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            trailing: Text('${group.memberIds.length}', style: TextStyle(color: scheme.onSurfaceVariant)),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => GroupMembersScreen(groupId: group.id))),
          ),
        ],
      ),
    );
  }
}
