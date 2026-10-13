import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Thao tác của chủ nhóm với thành viên: xoá, chặn, bỏ chặn.
class MemberAdmin {
  /// Hỏi xác nhận rồi xoá (và chặn nếu [block]) thành viên. Trả về true nếu thành công.
  static Future<bool> remove(BuildContext context, Group g, String uid, String name, {bool block = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(block ? 'Chặn $name?' : 'Xoá $name khỏi nhóm?'),
        content: Text(block
            ? '$name sẽ bị xoá khỏi "${g.name}" cùng lịch sử vị trí trong nhóm, và không thể tham gia lại bằng mã mời.'
            : '$name sẽ bị xoá khỏi "${g.name}" cùng lịch sử vị trí trong nhóm. Họ vẫn có thể tham gia lại bằng mã mời.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(block ? 'Chặn' : 'Xoá khỏi nhóm'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    final done = await _run(context, () => GroupService.instance.removeMember(g.id, uid, block: block));
    if (done && context.mounted) showMessage(context, block ? 'Đã chặn $name' : 'Đã xoá $name khỏi nhóm');
    return done;
  }

  static Future<void> unblock(BuildContext context, Group g, String uid, String name) async {
    final done = await _run(context, () => GroupService.instance.unblockMember(g.id, uid));
    if (done && context.mounted) showMessage(context, 'Đã bỏ chặn $name');
  }

  /// Bảng thao tác cho chủ nhóm trên một thành viên. Trả về true nếu thành viên đã bị xoá.
  static Future<bool> showActions(BuildContext context, Group g, String uid, String name) async {
    final action = await showGlassSheet<String>(
      context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: MemberAvatar(uid: uid, name: name, radius: 28)),
              const SizedBox(height: 10),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              Text(
                g.name,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 16),
              _SheetGroup(children: [
                ListTile(
                  horizontalTitleGap: 14,
                  leading: const GlassIconBadge(icon: Icons.person_remove_rounded, color: AppColors.orange),
                  title: const Text('Xoá khỏi nhóm'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
                ListTile(
                  horizontalTitleGap: 14,
                  leading: const GlassIconBadge(icon: Icons.block_rounded, color: AppColors.sos),
                  title: const Text('Chặn', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.sos)),
                  subtitle: const Text('Xoá và không cho tham gia lại'),
                  onTap: () => Navigator.pop(ctx, 'block'),
                ),
              ]),
              const SizedBox(height: 10),
              _SheetGroup(children: [
                ListTile(
                  title: Text(
                    'Huỷ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
              ]),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return false;
    return remove(context, g, uid, name, block: action == 'block');
  }

  static Future<bool> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showMessage(context, e.message ?? 'Có lỗi xảy ra.');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Có lỗi xảy ra: $e');
    }
    return false;
  }
}

/// Thành viên của một nhóm: chủ nhóm xoá / chặn / bỏ chặn tại đây.
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.groupId});
  final String groupId;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late final Stream<Group?> _group = GroupService.instance.group(widget.groupId);
  final _myUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return StreamBuilder<Group?>(
      stream: _group,
      builder: (context, snap) {
        final g = snap.data;
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(title: g == null ? 'Thành viên' : g.name),
          body: GlassBackground(
            child: g == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView(
                    padding: EdgeInsets.fromLTRB(0, MediaQuery.paddingOf(context).top + 60 + 12, 0, 40),
                    children: [
                      GlassSection(
                        header: '${g.memberIds.length} thành viên',
                        dividerIndent: 16 + 40 + 14,
                        children: [
                          for (final uid in g.memberIds)
                            ListTile(
                              horizontalTitleGap: 14,
                              contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                              leading: MemberAvatar(uid: uid, name: g.nameOf(uid)),
                              title: Text(
                                uid == _myUid ? '${g.nameOf(uid)} (Bạn)' : g.nameOf(uid),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: uid == g.ownerId
                                  ? const Row(
                                      children: [
                                        Icon(Icons.star_rounded, size: 15, color: AppColors.warning),
                                        SizedBox(width: 3),
                                        Text('Chủ nhóm'),
                                      ],
                                    )
                                  : null,
                              trailing: g.isOwner(_myUid) && uid != _myUid
                                  ? IconButton(
                                      icon: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: scheme.onSurface.withValues(alpha: 0.07),
                                        ),
                                        child: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.onSurface.withValues(alpha: 0.75)),
                                      ),
                                      tooltip: 'Quản lý thành viên',
                                      onPressed: () => MemberAdmin.showActions(context, g, uid, g.nameOf(uid)),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                      if (g.isOwner(_myUid))
                        GlassSection(
                          header: 'Đã chặn',
                          footer: g.blockedIds.isEmpty
                              ? null
                              : 'Người bị chặn không thể tham gia lại nhóm bằng mã mời.',
                          dividerIndent: 16 + 30 + 14,
                          children: [
                            if (g.blockedIds.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                child: Text('Chưa chặn ai.', style: TextStyle(color: secondary)),
                              ),
                            for (final uid in g.blockedIds)
                              ListTile(
                                horizontalTitleGap: 14,
                                contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                                leading: const GlassIconBadge(icon: Icons.block_rounded, color: AppColors.sos),
                                title: Text(
                                  g.blockedNames[uid] ?? 'Thành viên',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                trailing: TextButton(
                                  onPressed: () =>
                                      MemberAdmin.unblock(context, g, uid, g.blockedNames[uid] ?? 'Thành viên'),
                                  child: const Text('Bỏ chặn'),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Nhóm dòng bên trong sheet kính: nền mờ nhẹ (không lồng kính trong kính), góc bo đồng tâm.
class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      shape: glassShape(radius: 26),
      clipBehavior: Clip.antiAlias,
      color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.55),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 0.5, thickness: 0.5, indent: 60, color: scheme.onSurface.withValues(alpha: 0.12)),
            children[i],
          ],
        ],
      ),
    );
  }
}
