import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/group_consent.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'group_consent_screen.dart';
import 'invite_screens.dart';
import '../widgets/glass.dart';

/// Các thao tác nhóm dùng chung giữa nhiều màn hình.
class GroupActions {
  static Future<void> create(BuildContext context) async {
    final name = await promptText(context, title: 'Tạo nhóm mới', label: 'Tên nhóm (vd: Gia đình)');
    if (name == null || name.isEmpty || !context.mounted) return;
    await _run(context, () async {
      final gid = await GroupService.instance.createGroup(name);
      // Tự tạo nhóm = đồng ý chia sẻ với nhóm đó.
      await GroupConsent.instance.grant(gid);
      return gid;
    });
  }

  static Future<void> join(BuildContext context) async {
    // Nhập mã, dán link mời hoặc quét QR.
    final code = await promptJoinCode(context);
    if (code == null || code.isEmpty || !context.mounted) return;
    await joinCode(context, code);
  }

  /// Tham gia bằng mã (nhập tay / link mời / QR). Trả về id nhóm nếu thành công và người dùng không rời nhóm.
  ///
  /// Vào nhóm KHÔNG tự chia sẻ vị trí: sau khi vào, màn [GroupConsentScreen] cho người dùng xem nhóm
  /// có ai, nhóm sẽ thấy gì, rồi tự chọn chia sẻ / chỉ tham gia / rời nhóm.
  static Future<String?> joinCode(BuildContext context, String code) async {
    final String gid;
    try {
      gid = await GroupService.instance.joinGroup(code);
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showMessage(context, e.message ?? 'Có lỗi xảy ra.');
      return null;
    } catch (e) {
      if (context.mounted) showMessage(context, 'Có lỗi xảy ra: $e');
      return null;
    }
    // Đã là thành viên và đã đồng ý từ trước thì không hỏi lại.
    if (!GroupConsent.instance.allows(gid) && context.mounted) {
      final choice = await GroupConsentScreen.open(context, gid);
      if (choice == GroupConsentChoice.left) return null;
    }
    await SettingsService.instance.selectGroup(gid);
    return gid;
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
    showGlassSheet<void>(
      context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GlassIconBadge(icon: Icons.person_add_alt_1_rounded, color: AppColors.brand, size: 56),
              const SizedBox(height: 14),
              Text('Mời vào "${g.name}"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text('Cho người bạn muốn mời quét mã QR, hoặc gửi link / mã 6 ký tự để họ "Tham gia bằng mã mời".',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.35, color: scheme.onSurface.withValues(alpha: 0.55))),
              const SizedBox(height: 20),
              InviteQr(code: g.inviteCode),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final ch in g.inviteCode.split(''))
                    Container(
                      width: 44,
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        shape: glassShape(radius: 14),
                        color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.6),
                      ),
                      child: Text(ch,
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: scheme.primary)),
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
              const SizedBox(height: 10),
              ShareInviteButton(group: g),
            ],
          ),
        );
      },
    );
  }

  /// Chủ nhóm đổi tên nhóm.
  static Future<void> rename(BuildContext context, Group g) async {
    final controller = TextEditingController(text: g.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên nhóm'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Tên nhóm'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (name == null || name == g.name || !context.mounted) return;
    if (name.isEmpty || name.length > 50) {
      showMessage(context, 'Tên nhóm cần từ 1 đến 50 ký tự.');
      return;
    }
    try {
      await GroupService.instance.renameGroup(g.id, name).timeout(const Duration(seconds: 10));
      if (context.mounted) showMessage(context, 'Đã đổi tên nhóm');
    } on TimeoutException {
      if (context.mounted) showMessage(context, 'Chưa có mạng: tên mới sẽ được lưu khi có kết nối.');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không đổi được tên: $e');
    }
  }

  static Future<bool> leave(BuildContext context, Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rời nhóm "${g.name}"?'),
        content: const Text('Nhóm sẽ không còn nhận vị trí của bạn và bạn cũng không còn thấy vị trí của nhóm. '
            'Vị trí và lịch sử của bạn trong nhóm này sẽ bị xoá.'),
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
    try {
      await GroupService.instance.leaveGroup(g.id);
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showMessage(context, e.message ?? 'Không rời nhóm được. Hãy thử lại.');
      return false;
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không rời nhóm được: $e');
      return false;
    }
    if (SettingsService.instance.selectedGroupId.value == g.id) {
      await SettingsService.instance.selectGroup(null);
    }
    return true;
  }

  static Future<void> sos(BuildContext context, Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const GlassIconBadge(icon: Icons.sos_rounded, color: AppColors.sos, size: 64),
        title: const Text('Gửi cảnh báo SOS?'),
        content: Text(
          'Tất cả thành viên "${g.name}" sẽ nhận thông báo khẩn cấp kèm vị trí hiện tại của bạn.\n\n'
          'SOS chỉ gửi tới thành viên nhóm, không gửi tới cơ quan cứu hộ và không thay thế cuộc gọi '
          '113 / 114 / 115. Thông báo có thể đến chậm hoặc không đến khi mất mạng.',
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
    try {
      final pos = await LocationService.instance.currentPosition();
      // Mất mạng thì Firestore giữ lệnh trong hàng đợi và tự gửi khi có mạng lại.
      await GroupService.instance
          .sendSos(g.id, lat: pos?.latitude, lng: pos?.longitude)
          .timeout(const Duration(seconds: 10));
      if (context.mounted) showMessage(context, 'Đã gửi SOS đến cả nhóm');
    } on TimeoutException {
      if (context.mounted) showMessage(context, 'Chưa có mạng: SOS sẽ tự gửi ngay khi có kết nối. Hãy gọi điện nếu khẩn cấp.');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không gửi được SOS: $e. Hãy gọi điện nếu khẩn cấp.');
    }
  }

  /// Chọn nhóm đang xem, kèm lối tắt tạo / tham gia nhóm.
  static void pickGroup(BuildContext context, List<Group> groups, String? selectedId) {
    showGlassSheet<void>(
      context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final check = Icon(Icons.check_rounded, color: scheme.primary);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            children: [
              const SheetTitle('Chọn nhóm'),
              InsetGroup(
                children: [
                  // Xem mọi người của mọi nhóm trên một bản đồ.
                  if (groups.length > 1)
                    ListTile(
                      leading: const GroupBadge(name: '', icon: Icons.people_alt_rounded, size: 38),
                      title: const Text('Tất cả bạn bè', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${groups.length} nhóm'),
                      trailing: selectedId == SettingsService.allGroups ? check : null,
                      onTap: () {
                        SettingsService.instance.selectGroup(SettingsService.allGroups);
                        Navigator.pop(ctx);
                      },
                    ),
                  for (final g in groups)
                    ListTile(
                      leading: GroupBadge(name: g.name, size: 38),
                      title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${g.memberIds.length} thành viên'),
                      trailing: g.id == selectedId ? check : null,
                      onTap: () {
                        SettingsService.instance.selectGroup(g.id);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              InsetGroup(
                dividerIndent: 58,
                children: [
                  ListTile(
                    leading: const GlassIconBadge(icon: Icons.group_add_rounded, color: AppColors.online),
                    title: const Text('Tạo nhóm mới'),
                    onTap: () {
                      Navigator.pop(ctx);
                      create(context);
                    },
                  ),
                  ListTile(
                    leading: const GlassIconBadge(icon: Icons.vpn_key_rounded, color: AppColors.orange),
                    title: const Text('Tham gia bằng mã mời'),
                    onTap: () {
                      Navigator.pop(ctx);
                      join(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(title: title, actions: actions),
        body: child,
      ),
    );
  }
}
