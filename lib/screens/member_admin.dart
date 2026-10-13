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
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.person_remove_rounded, color: AppColors.sos),
                title: const Text('Xoá khỏi nhóm', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.block_rounded, color: AppColors.sos),
                title: const Text('Chặn', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.sos)),
                subtitle: const Text('Xoá và không cho tham gia lại'),
                onTap: () => Navigator.pop(ctx, 'block'),
              ),
            ],
          ),
        ),
      ),
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
    return StreamBuilder<Group?>(
      stream: _group,
      builder: (context, snap) {
        final g = snap.data;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(backgroundColor: Colors.transparent, title: Text(g == null ? 'Thành viên' : g.name)),
          body: GlassBackground(
            child: g == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 40),
                    children: [
                      _Section(
                        title: '${g.memberIds.length} thành viên',
                        children: [
                          for (final uid in g.memberIds)
                            ListTile(
                              leading: MemberAvatar(uid: uid, name: g.nameOf(uid)),
                              title: Text(uid == _myUid ? '${g.nameOf(uid)} (Bạn)' : g.nameOf(uid),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: uid == g.ownerId ? const Text('Chủ nhóm') : null,
                              trailing: g.isOwner(_myUid) && uid != _myUid
                                  ? IconButton(
                                      icon: const Icon(Icons.more_horiz_rounded),
                                      tooltip: 'Quản lý thành viên',
                                      onPressed: () => MemberAdmin.showActions(context, g, uid, g.nameOf(uid)),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                      if (g.isOwner(_myUid)) ...[
                        const SizedBox(height: 16),
                        _Section(
                          title: 'Đã chặn',
                          children: [
                            if (g.blockedIds.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                child: Text('Chưa chặn ai.', style: TextStyle(color: scheme.onSurfaceVariant)),
                              ),
                            for (final uid in g.blockedIds)
                              ListTile(
                                leading: const Icon(Icons.block_rounded, color: AppColors.sos),
                                title: Text(g.blockedNames[uid] ?? 'Thành viên',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: TextButton(
                                  onPressed: () => MemberAdmin.unblock(context, g, uid, g.blockedNames[uid] ?? 'Thành viên'),
                                  child: const Text('Bỏ chặn'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 26,
      opacity: 0.6,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          ...children,
        ],
      ),
    );
  }
}
