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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Quản lý nhóm'),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: GlassPill(
        tint: AppColors.brand,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        onTap: () => GroupActions.create(context),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Tạo nhóm',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2),
            ),
          ],
        ),
      ),
      body: GlassBackground(
        child: StreamBuilder<List<Group>>(
          stream: _groups,
          builder: (context, snap) {
            final groups = snap.data;
            return ValueListenableBuilder<String?>(
              valueListenable: SettingsService.instance.selectedGroupId,
              builder: (context, selectedId, _) => ListView(
                padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 60 + 8, 16, 120),
                children: [
                  GlassSection(
                    margin: const EdgeInsets.only(bottom: 24),
                    children: [
                      ListTile(
                        horizontalTitleGap: 14,
                        leading: const GlassIconBadge(icon: Icons.vpn_key_rounded, color: AppColors.orange),
                        title: const Text('Tham gia bằng mã mời', style: TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
                        onTap: () => GroupActions.join(context),
                      ),
                    ],
                  ),
                  if (groups != null && groups.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                      child: Text(
                        'NHÓM CỦA BẠN',
                        style: TextStyle(
                          fontSize: 12.5,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  if (snap.hasError)
                    Text('Lỗi tải nhóm: ${snap.error}')
                  else if (groups == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    )
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassPressable(
      onTap: onTap,
      shape: glassShape(radius: 28),
      scale: 0.97,
      child: Glass(
        radius: 28,
        opacity: selected ? 0.78 : 0.62,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: ShapeDecoration(
                    gradient: AppColors.brandGradient,
                    shape: glassShape(radius: 17),
                    shadows: [
                      BoxShadow(color: AppColors.brand.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    group.name.isEmpty ? '?' : group.name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800),
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
                            child: Text(
                              group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                            ),
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
                          Flexible(
                            child: Text(
                              '${group.memberIds.length} thành viên',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Tuỳ chọn',
                  icon: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.6),
                    ),
                    child: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.onSurface.withValues(alpha: 0.75)),
                  ),
                  onSelected: (v) {
                    if (v == 'invite') GroupActions.invite(context, group);
                    if (v == 'members') {
                      Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => GroupMembersScreen(groupId: group.id)));
                    }
                    if (v == 'leave') GroupActions.leave(context, group);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'invite',
                      child: _MenuRow(icon: Icons.person_add_alt_1_rounded, label: 'Mời thành viên'),
                    ),
                    PopupMenuItem(
                      value: 'members',
                      child: _MenuRow(icon: Icons.group_rounded, label: 'Thành viên & chặn'),
                    ),
                    PopupMenuDivider(height: 8),
                    PopupMenuItem(
                      value: 'leave',
                      child: _MenuRow(icon: Icons.logout_rounded, label: 'Rời nhóm', color: AppColors.sos),
                    ),
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

/// Dòng trong menu ngữ cảnh kiểu iOS: chữ bên trái, biểu tượng bên phải.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        const SizedBox(width: 16),
        Icon(icon, size: 20, color: color),
      ],
    );
  }
}
