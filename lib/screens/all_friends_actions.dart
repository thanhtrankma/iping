import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/all_friends_service.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'group_actions.dart';

/// Thao tác ở chế độ "Tất cả bạn bè" và check-in.
class AllFriendsActions {
  /// Hỏi người dùng chọn một nhóm.
  static Future<Group?> chooseGroup(BuildContext context, List<Group> groups, {String title = 'Chọn nhóm'}) {
    return showModalBottomSheet<Group>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
                  onTap: () => Navigator.pop(ctx, g),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Trả về nhóm thật: chính `g`, hoặc hỏi chọn nhóm nếu đang xem tất cả bạn bè.
  static Future<Group?> resolve(BuildContext context, Group g, List<Group> groups,
      {String title = 'Chọn nhóm'}) async {
    if (!AllFriendsService.isVirtual(g)) return g;
    if (groups.length == 1) return groups.first;
    return chooseGroup(context, groups, title: title);
  }

  /// Chọn nhóm (nếu cần) rồi mở trang của nhóm đó.
  static Future<void> open(BuildContext context, Group g, List<Group> groups, Widget Function(Group) page,
      {String title = 'Chọn nhóm'}) async {
    final target = await resolve(context, g, groups, title: title);
    if (target == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page(target)));
  }

  static Future<void> invite(BuildContext context, Group g, List<Group> groups) async {
    final target = await resolve(context, g, groups, title: 'Mời vào nhóm nào?');
    if (target != null && context.mounted) GroupActions.invite(context, target);
  }

  /// SOS: ở chế độ tất cả bạn bè thì gửi đến mọi nhóm sau khi xác nhận.
  static Future<void> sos(BuildContext context, Group g, List<Group> groups) async {
    if (!AllFriendsService.isVirtual(g)) return GroupActions.sos(context, g);
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
          'Thành viên của cả ${groups.length} nhóm sẽ nhận thông báo khẩn cấp kèm vị trí hiện tại của bạn.',
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
    final results = await Future.wait(groups.map((x) => GroupService.instance
        .sendSos(x.id, lat: pos?.latitude, lng: pos?.longitude)
        .then((_) => true, onError: (_) => false)));
    final sent = results.where((r) => r).length;
    if (context.mounted) {
      showMessage(
          context, sent == groups.length ? 'Đã gửi SOS đến tất cả nhóm' : 'Đã gửi SOS đến $sent/${groups.length} nhóm');
    }
  }

  /// Check-in: đăng vị trí và địa chỉ hiện tại thành sự kiện của nhóm (hoặc mọi nhóm).
  static Future<void> checkIn(BuildContext context, Group g, List<Group> groups) async {
    final targets = AllFriendsService.isVirtual(g) ? groups : [g];
    if (targets.isEmpty) return;
    final pos = await LocationService.instance.currentPosition();
    if (pos == null) {
      if (context.mounted) showMessage(context, 'Không lấy được vị trí hiện tại.');
      return;
    }
    final address = await GeocodeService.instance.address(pos.latitude, pos.longitude);
    if (!context.mounted) return;
    final who = targets.length == 1 ? 'Nhóm "${targets.first.name}"' : 'Cả ${targets.length} nhóm';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.where_to_vote_rounded, color: AppColors.brand, size: 40),
        title: const Text('Check-in tại đây?'),
        content: Text('$address\n\n$who sẽ nhận thông báo.', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check-in'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Future.wait(targets.map((x) => GroupService.instance
          .addEvent(x.id, type: 'checkin', placeName: address, lat: pos.latitude, lng: pos.longitude)));
      if (context.mounted) showMessage(context, 'Đã check-in');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không check-in được: $e');
    }
  }
}
