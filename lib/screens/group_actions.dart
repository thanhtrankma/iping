import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Các thao tác nhóm dùng chung giữa nhiều màn hình.
class GroupActions {
  static Future<void> create(BuildContext context) async {
    final name = await promptText(context, title: 'Tạo nhóm mới', label: 'Tên nhóm (vd: Gia đình)');
    if (name == null || name.isEmpty || !context.mounted) return;
    await _run(context, () => GroupService.instance.createGroup(name));
  }

  static Future<void> join(BuildContext context) async {
    final code = await promptText(context, title: 'Tham gia nhóm', label: 'Nhập mã mời 6 ký tự', upperCase: true);
    if (code == null || code.isEmpty || !context.mounted) return;
    await _run(context, () => GroupService.instance.joinGroup(code));
  }

  static Future<void> _run(BuildContext context, Future<String> Function() action) async {
    try {
      final gid = await action();
      await SettingsService.instance.selectGroup(gid);
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showMessage(context, e.message ?? 'Có lỗi xảy ra.');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Có lỗi xảy ra: $e');
    }
  }

  static void invite(BuildContext context, Group g) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mời vào "${g.name}"',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Gửi mã này cho người bạn muốn mời. Họ chọn "Tham gia bằng mã mời" và nhập mã.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final ch in g.inviteCode.split(''))
                    Container(
                      width: 44,
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(ch,
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(ctx).colorScheme.onPrimaryContainer)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Sao chép mã'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: g.inviteCode));
                  Navigator.pop(ctx);
                  showMessage(context, 'Đã sao chép mã mời');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool> leave(BuildContext context, Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rời nhóm "${g.name}"?'),
        content: const Text('Bạn sẽ không còn thấy vị trí của nhóm và nhóm cũng không thấy vị trí của bạn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await GroupService.instance.leaveGroup(g.id);
    if (SettingsService.instance.selectedGroupId.value == g.id) {
      await SettingsService.instance.selectGroup(null);
    }
    return true;
  }

  static Future<void> sos(BuildContext context, Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: AppColors.sos.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.sos_rounded, color: AppColors.sos, size: 40),
        ),
        title: const Text('Gửi cảnh báo SOS?'),
        content: Text(
          'Tất cả thành viên "${g.name}" sẽ nhận thông báo khẩn cấp kèm vị trí hiện tại của bạn.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.sos, minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gửi SOS'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final pos = await LocationService.instance.currentPosition();
    await GroupService.instance.sendSos(g.id, lat: pos?.latitude, lng: pos?.longitude);
    if (context.mounted) showMessage(context, 'Đã gửi SOS đến cả nhóm');
  }

  /// Chọn nhóm đang xem, kèm lối tắt tạo / tham gia nhóm.
  static void pickGroup(BuildContext context, List<Group> groups, String? selectedId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              // Xem mọi người của mọi nhóm trên một bản đồ.
              if (groups.length > 1)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.brand,
                    child: Icon(Icons.people_alt_rounded, color: Colors.white),
                  ),
                  title: const Text('Tất cả bạn bè', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${groups.length} nhóm'),
                  trailing: selectedId == SettingsService.allGroups
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.brand)
                      : null,
                  onTap: () {
                    SettingsService.instance.selectGroup(SettingsService.allGroups);
                    Navigator.pop(ctx);
                  },
                ),
              for (final g in groups)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.brand,
                    child: Text(g.name.isEmpty ? '?' : g.name.characters.first.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${g.memberIds.length} thành viên'),
                  trailing: g.id == selectedId ? const Icon(Icons.check_circle_rounded, color: AppColors.brand) : null,
                  onTap: () {
                    SettingsService.instance.selectGroup(g.id);
                    Navigator.pop(ctx);
                  },
                ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.group_add_rounded),
                title: const Text('Tạo nhóm mới'),
                onTap: () {
                  Navigator.pop(ctx);
                  create(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_rounded),
                title: const Text('Tham gia bằng mã mời'),
                onTap: () {
                  Navigator.pop(ctx);
                  join(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trang con đơn giản có nền kính, dùng cho Trò chuyện / Địa điểm / Hoạt động.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: child,
    );
  }
}
