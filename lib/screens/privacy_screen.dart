import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_consent.dart';
import '../services/group_service.dart';
import '../services/moderation_service.dart';
import '../services/pause_schedule.dart';
import '../services/privacy_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/privacy_widgets.dart';
import 'group_actions.dart';
import 'group_consent_screen.dart';
import 'member_admin.dart';
import 'moderation_sheets.dart';

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
  void initState() {
    super.initState();
    ModerationService.instance.watch();
  }

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
                      'Mỗi nhóm chỉ nhận vị trí của bạn khi bạn bật "Chia sẻ với nhóm này". '
                      'Bạn có thể tạm ẩn, thôi chia sẻ hoặc rời nhóm bất cứ lúc nào mà không ảnh hưởng các nhóm khác.',
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
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: GroupConsent.instance.consented,
                      builder: (context, consented, _) => Column(
                        children: [
                          for (final g in groups)
                            _GroupPrivacyCard(
                              group: g,
                              uid: widget.uid,
                              consented: consented.contains(g.id),
                              paused: schedule.isPaused(g.id, DateTime.now()),
                            ),
                        ],
                      ),
                    ),
                  _BlockedUsersSection(groups: groups ?? const []),
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
  const _GroupPrivacyCard({required this.group, required this.uid, required this.consented, required this.paused});
  final Group group;
  final String uid;

  /// Người dùng đã đồng ý chia sẻ vị trí với nhóm này ([GroupConsent]).
  final bool consented;
  final bool paused;

  Future<void> _setSharing(BuildContext context, bool on) async {
    if (on) {
      await shareWithGroup(context, group.id);
      if (context.mounted) showMessage(context, 'Đã chọn chia sẻ vị trí với "${group.name}"');
    } else {
      await stopSharingWithGroup(group.id);
      if (context.mounted) showMessage(context, 'Đã thôi chia sẻ vị trí với "${group.name}"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return GlassSection(
      header: group.name,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      dividerIndent: 16 + 30 + 14,
      children: [
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          secondary: GlassIconBadge(
            icon: consented ? Icons.location_on_rounded : Icons.location_off_rounded,
            color: consented ? AppColors.brand : AppColors.gray,
          ),
          title: const Text('Chia sẻ với nhóm này', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            consented ? 'Nhóm nhận vị trí, pin và lịch sử khi bạn bật chia sẻ' : 'Nhóm không nhận vị trí của bạn',
            style: TextStyle(color: secondary),
          ),
          value: consented,
          onChanged: (on) => _setSharing(context, on),
        ),
        if (consented)
          ListTile(
            horizontalTitleGap: 14,
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            leading: GlassIconBadge(
              icon: paused ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: paused ? AppColors.warning : AppColors.online,
            ),
            title: const Text('Hiện vị trí', style: TextStyle(fontWeight: FontWeight.w600)),
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
        ListTile(
          horizontalTitleGap: 14,
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
          leading: const GlassIconBadge(icon: Icons.logout_rounded, color: AppColors.sos),
          title: const Text('Rời nhóm', style: TextStyle(color: AppColors.sos)),
          onTap: () => GroupActions.leave(context, group),
        ),
      ],
    );
  }
}

/// "Đã chặn": người dùng mình đã chặn (ẩn tin nhắn, tin nhắn riêng, khoảnh khắc) · Bỏ chặn.
class _BlockedUsersSection extends StatelessWidget {
  const _BlockedUsersSection({required this.groups});
  final List<Group> groups;

  String _nameOf(String uid) {
    for (final g in groups) {
      final n = g.memberNames[uid] ?? g.blockedNames[uid];
      if (n != null && n.isNotEmpty) return n;
    }
    return 'Người dùng';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: ModerationService.instance.blocked,
      builder: (context, blocked, _) {
        if (blocked.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: GlassSection(
            header: 'Đã chặn',
            footer: 'Bạn không thấy tin nhắn, tin nhắn riêng và khoảnh khắc của người đã chặn, '
                'và họ không thể nhắn tin riêng cho bạn.',
            children: [
              for (final uid in blocked)
                Builder(builder: (context) {
                  final name = _nameOf(uid);
                  return ListTile(
                    horizontalTitleGap: 14,
                    contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                    leading: MemberAvatar(uid: uid, name: name, radius: 15),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: () => unblockUser(context, uid: uid, name: name),
                      child: const Text('Bỏ chặn', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
