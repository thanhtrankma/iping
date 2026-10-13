import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'group_actions.dart';
import 'member_admin.dart';

/// Quản lý nhóm: chọn nhóm đang xem, mời, rời, tạo / tham gia nhóm.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.uid});
  final String uid;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final Stream<List<Group>> _groups = GroupService.instance.myGroups(widget.uid);

  void _open(Group g) {
    SettingsService.instance.selectGroup(g.id);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Quản lý nhóm')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => GroupActions.create(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tạo nhóm', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: GlassBackground(
        child: StreamBuilder<List<Group>>(
          stream: _groups,
          builder: (context, snap) {
            final groups = snap.data;
            return ValueListenableBuilder<String?>(
              valueListenable: SettingsService.instance.selectedGroupId,
              builder: (context, selectedId, _) => ListView(
                padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 110),
                children: [
                  GlassPill(
                    onTap: () => GroupActions.join(context),
                    child: const Row(
                      children: [
                        Icon(Icons.vpn_key_rounded, color: AppColors.brand),
                        SizedBox(width: 12),
                        Text('Tham gia bằng mã mời', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Spacer(),
                        Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (snap.hasError)
                    Text('Lỗi tải nhóm: ${snap.error}')
                  else if (groups == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (groups.isEmpty)
                    const EmptyState(
                      icon: Icons.diversity_3_rounded,
                      title: 'Chưa có nhóm nào',
                      text: 'Tạo nhóm cho gia đình hoặc nhập mã mời.',
                    )
                  else
                    for (final g in groups) ...[
                      _GroupCard(
                        group: g,
                        selected: g.id == (selectedId ?? groups.first.id),
                        onTap: () => _open(g),
                      ),
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

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.selected, required this.onTap});
  final Group group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      radius: 26,
      opacity: 0.6,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    group.name.isEmpty ? '?' : group.name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 18),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          AvatarStack(
                            members: [for (final uid in group.memberIds) (uid, group.nameOf(uid))],
                            radius: 11,
                          ),
                          const SizedBox(width: 6),
                          Text('${group.memberIds.length} thành viên',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'invite') GroupActions.invite(context, group);
                    if (v == 'members') {
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => GroupMembersScreen(groupId: group.id)));
                    }
                    if (v == 'leave') GroupActions.leave(context, group);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'invite', child: Text('Mời thành viên')),
                    PopupMenuItem(value: 'members', child: Text('Thành viên & chặn')),
                    PopupMenuItem(value: 'leave', child: Text('Rời nhóm', style: TextStyle(color: AppColors.sos))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
