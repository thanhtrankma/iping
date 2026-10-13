import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pause_schedule.dart';
import '../services/privacy_service.dart';
import '../theme.dart';
import 'common.dart';
import 'glass.dart';

/// Bảng chọn thời gian tạm dừng chia sẻ với một nhóm.
Future<void> showPauseSheet(BuildContext context, Group group) async {
  final privacy = PrivacyService.instance;
  final paused = privacy.isPaused(group.id);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ẩn vị trí với "${group.name}"',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Thành viên nhóm này sẽ thấy bạn "Đã tắt chia sẻ". Các nhóm khác không bị ảnh hưởng.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final p in PausePreset.values)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(p == PausePreset.forever ? Icons.visibility_off_rounded : Icons.timer_outlined),
                title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, p.name),
              ),
            if (paused) ...[
              const Divider(height: 20),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const Icon(Icons.location_on_rounded, color: AppColors.brand),
                title: const Text('Chia sẻ lại ngay',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
                onTap: () => Navigator.pop(ctx, 'resume'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'resume') return resumeGroup(context, group);
  final preset = PausePreset.values.byName(choice);
  await privacy.pause(group.id, pauseUntil(preset, DateTime.now()));
  if (context.mounted) showMessage(context, 'Đã ẩn vị trí với "${group.name}"');
}

/// Chia sẻ lại với nhóm và báo cho người dùng.
Future<void> resumeGroup(BuildContext context, Group group) async {
  await PrivacyService.instance.resume(group.id);
  if (context.mounted) showMessage(context, 'Đã chia sẻ lại với "${group.name}"');
}

/// Mô tả trạng thái chia sẻ của mình với một nhóm.
String pauseStatus(String gid) {
  final s = PrivacyService.instance.paused.value;
  final now = DateTime.now();
  return s.isPaused(gid, now) ? pauseLabel(s.untilOf(gid), now) : 'Đang hiện vị trí với nhóm này';
}

/// Nhãn nhỏ trên màn chính khi đang ẩn vị trí với nhóm đang xem.
class PausedGroupChip extends StatelessWidget {
  const PausedGroupChip({super.key, required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PauseSchedule>(
      valueListenable: PrivacyService.instance.paused,
      builder: (context, schedule, _) {
        final now = DateTime.now();
        if (!schedule.isPaused(group.id, now)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GlassPill(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            onTap: () => showPauseSheet(context, group),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_off_rounded, size: 18, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(_short(schedule.untilOf(group.id), now), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );
      },
    );
  }

  String _short(DateTime? until, DateTime now) {
    if (until == null) return 'Đang ẩn với nhóm';
    final two = until.minute.toString().padLeft(2, '0');
    final sameDay = until.year == now.year && until.month == now.month && until.day == now.day;
    return 'Ẩn đến ${until.hour}:$two${sameDay ? '' : ' mai'}';
  }
}
