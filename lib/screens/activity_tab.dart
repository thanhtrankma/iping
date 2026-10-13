import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key, required this.group});
  final Group group;

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  late final Stream<List<GroupEvent>> _events = GroupService.instance.events(widget.group.id);

  (IconData, Color, String) _describe(GroupEvent e) => switch (e.type) {
        'arrive' => (Icons.login_rounded, AppColors.online, 'đã đến ${e.placeName ?? ''}'),
        'leave' => (Icons.logout_rounded, AppColors.warning, 'đã rời ${e.placeName ?? ''}'),
        'sos' => (Icons.sos_rounded, AppColors.sos, 'đã gửi cảnh báo SOS!'),
        'join' => (Icons.group_add_rounded, AppColors.brand, 'đã tham gia nhóm'),
        'leave_group' => (Icons.group_remove_rounded, Colors.grey, 'đã rời nhóm'),
        'removed' => (Icons.person_remove_rounded, AppColors.sos, 'đã bị xoá khỏi nhóm'),
        _ => (Icons.info_outline_rounded, Colors.grey, ''),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<GroupEvent>>(
      stream: _events,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final events = snap.data!;
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_active_rounded,
            title: 'Chưa có hoạt động',
            text: 'Đến/rời địa điểm, SOS và thành viên mới\nsẽ hiện ở đây.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final e = events[i];
            final (icon, color, action) = _describe(e);
            final isSos = e.type == 'sos';
            final hasPos = e.lat != null && e.lng != null;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSos ? AppColors.sos.withValues(alpha: 0.08) : Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(18),
                border: isSos ? Border.all(color: AppColors.sos.withValues(alpha: 0.4)) : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      MemberAvatar(uid: e.uid, name: e.name, radius: 22),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(icon, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: ' $action'),
                          ]),
                          style: TextStyle(
                            fontSize: 15,
                            color: isSos ? AppColors.sos : scheme.onSurface,
                            fontWeight: isSos ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            '${clock(e.createdAt)} · ${timeAgo(e.createdAt)}',
                            if (isSos && hasPos) '${e.lat!.toStringAsFixed(5)}, ${e.lng!.toStringAsFixed(5)}',
                          ].join('\n'),
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
