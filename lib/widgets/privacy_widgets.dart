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
  final choice = await showGlassSheet<String>(
    context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: GlassIconBadge(icon: Icons.visibility_off_rounded, color: AppColors.warning, size: 52)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Ẩn vị trí với "${group.name}"',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Thành viên nhóm này sẽ thấy bạn "Đã tắt chia sẻ". Các nhóm khác không bị ảnh hưởng.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), height: 1.35),
              ),
            ),
            const SizedBox(height: 18),
            _SheetGroup(children: [
              for (final p in PausePreset.values)
                ListTile(
                  horizontalTitleGap: 14,
                  leading: GlassIconBadge(
                    icon: p == PausePreset.forever ? Icons.visibility_off_rounded : Icons.timer_rounded,
                    color: p == PausePreset.forever ? AppColors.gray : AppColors.warning,
                  ),
                  title: Text(p.label),
                  onTap: () => Navigator.pop(ctx, p.name),
                ),
            ]),
            if (paused) ...[
              const SizedBox(height: 10),
              _SheetGroup(children: [
                ListTile(
                  horizontalTitleGap: 14,
                  leading: const GlassIconBadge(icon: Icons.location_on_rounded, color: AppColors.brand),
                  title: Text('Chia sẻ lại ngay',
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                  onTap: () => Navigator.pop(ctx, 'resume'),
                ),
              ]),
            ],
          ],
        ),
      );
    },
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
                const Icon(Icons.visibility_off_rounded, size: 17, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  _short(schedule.untilOf(group.id), now),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.2),
                ),
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
