import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

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
        'checkin' => (Icons.where_to_vote_rounded, AppColors.brand, 'đã check-in tại ${e.placeName ?? ''}'),
        'join' => (Icons.group_add_rounded, AppColors.indigo, 'đã tham gia nhóm'),
        'leave_group' => (Icons.group_remove_rounded, AppColors.gray, 'đã rời nhóm'),
        'low_battery' => (Icons.battery_alert_rounded, AppColors.warning, 'sắp hết pin (${e.battery ?? '?'}%)'),
        'removed' => (Icons.person_remove_rounded, AppColors.sos, 'đã bị xoá khỏi nhóm'),
        // "Về an toàn".
        'safe_start' => (
            Icons.shield_rounded,
            AppColors.online,
            'đang về ${e.placeName ?? ''}${e.dueAt != null ? ' · dự kiến ${clock(e.dueAt)}' : ''}'
          ),
        'safe_arrive' => (Icons.verified_user_rounded, AppColors.online, 'đã về ${e.placeName ?? ''} an toàn ✅'),
        'safe_end' => (Icons.shield_outlined, AppColors.gray, 'đã kết thúc chuyến về ${e.placeName ?? ''}'),
        'safe_ok' => (Icons.verified_user_rounded, AppColors.online, 'báo đã an toàn (chuyến về ${e.placeName ?? ''})'),
        'safe_extend' => (
            Icons.more_time_rounded,
            AppColors.warning,
            'gia hạn chuyến về ${e.placeName ?? ''}${e.dueAt != null ? ' tới ${clock(e.dueAt)}' : ''}'
          ),
        'safe_overdue' => (Icons.warning_rounded, AppColors.sos, 'chưa tới ${e.placeName ?? ''} đúng giờ!'),
        _ => (Icons.info_outline_rounded, AppColors.gray, ''),
      };

  /// Tiêu đề nhóm theo ngày, như danh sách thông báo của iOS.
  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ColoredBox(
      color: Colors.transparent,
      child: StreamBuilder<List<GroupEvent>>(
        stream: _events,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final events = snap.data!;
          if (events.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_active_rounded,
              title: 'Chưa có hoạt động',
              text: 'Đến/rời địa điểm, SOS, Về an toàn\nvà thành viên mới sẽ hiện ở đây.',
            );
          }

          // Gom theo ngày, giữ nguyên thứ tự gốc.
          final groups = <String, List<GroupEvent>>{};
          for (final e in events) {
            groups.putIfAbsent(_dayLabel(e.createdAt ?? DateTime.now()), () => []).add(e);
          }

          return ListView(
            padding: EdgeInsets.only(top: mq.padding.top + 12, bottom: mq.padding.bottom + 24),
            children: [
              for (final entry in groups.entries)
                GlassSection(
                  header: entry.key,
                  dividerIndent: 72,
                  children: [for (final e in entry.value) _EventRow(event: e, info: _describe(e))],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.info});
  final GroupEvent event;
  final (IconData, Color, String) info;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final (icon, color, action) = info;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Sự kiện khẩn: SOS và "Về an toàn" quá giờ.
    final isSos = e.type == 'sos' || e.type == 'safe_overdue';
    final hasPos = e.lat != null && e.lng != null;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);

    return Container(
      color: isSos ? AppColors.sos.withValues(alpha: dark ? 0.18 : 0.1) : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              MemberAvatar(uid: e.uid, name: e.name, radius: 21),
              Positioned(
                right: -5,
                bottom: -5,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(color, Colors.white, 0.18)!, color],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: dark ? const Color(0xFF1E2129) : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Icon(icon, size: 11, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
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
                    height: 1.3,
                    letterSpacing: -0.2,
                    color: isSos ? AppColors.sos : scheme.onSurface,
                    fontWeight: isSos ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (isSos && (hasPos || (e.type == 'safe_overdue' && e.battery != null))) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (hasPos) '${e.lat!.toStringAsFixed(5)}, ${e.lng!.toStringAsFixed(5)}',
                      if (e.type == 'safe_overdue' && e.battery != null) 'Pin ${e.battery}%',
                    ].join(' · '),
                    style: TextStyle(color: secondary, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(clock(e.createdAt),
                  style: TextStyle(color: secondary, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(timeAgo(e.createdAt), style: TextStyle(color: secondary, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}
