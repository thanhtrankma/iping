import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/alert_prefs.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// "Quản lý cảnh báo": chọn loại thông báo đẩy muốn nhận và tắt cảnh báo từ từng thành viên.
class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key, required this.uid});
  final String uid;

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  late final _prefs = AlertPrefsService.instance.watch(widget.uid);
  late final _groups = GroupService.instance.myGroups(widget.uid);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không lưu được cài đặt, hãy thử lại.')));
    }
  }

  Future<void> _setType(String key, bool on) async {
    if (key == 'sos' && !on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.sos, size: 36),
          title: const Text('Tắt cảnh báo SOS?'),
          content: const Text(
              'Bạn sẽ KHÔNG nhận được thông báo khi người thân gửi SOS cần trợ giúp. Chỉ nên tắt nếu bạn chắc chắn.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Giữ bật')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.sos),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vẫn tắt'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() => AlertPrefsService.instance.setType(widget.uid, key, on));
  }

  /// Thành viên của mọi nhóm (trừ chính mình), không trùng lặp.
  List<(String, String)> _members(List<Group> groups) {
    final seen = <String, String>{};
    for (final g in groups) {
      for (final m in g.memberIds) {
        if (m != widget.uid) seen.putIfAbsent(m, () => g.nameOf(m));
      }
    }
    final list = seen.entries.map((e) => (e.key, e.value)).toList();
    list.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    return list;
  }

  /// Màu ô icon cho từng loại thông báo, như ứng dụng Cài đặt của iOS.
  static Color _badgeColor(String key) => switch (key) {
        'place' => AppColors.teal,
        'sos' => AppColors.sos,
        'safe' => AppColors.online,
        'message' => AppColors.online,
        'moment' => AppColors.pink,
        'meetup' => AppColors.purple,
        'ping' => AppColors.orange,
        'battery' => AppColors.warning,
        'join' => AppColors.indigo,
        _ => AppColors.brand,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Quản lý cảnh báo'),
      body: GlassBackground(
        child: StreamBuilder<AlertPrefs>(
          stream: _prefs,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator.adaptive());
            final prefs = snap.data!;
            return ListView(
              padding: EdgeInsets.fromLTRB(0, MediaQuery.paddingOf(context).top + 60 + 12, 0, 40),
              children: [
                GlassSection(
                  header: 'Thông báo đẩy',
                  dividerIndent: 16 + 30 + 14,
                  margin: EdgeInsets.fromLTRB(16, 0, 16, prefs.isOn('sos') ? 24 : 12),
                  children: [
                    for (final t in alertTypes)
                      SwitchListTile(
                        horizontalTitleGap: 14,
                        secondary: GlassIconBadge(icon: t.icon, color: _badgeColor(t.key)),
                        title: Text(
                          t.label,
                          style: t.key == 'sos' ? const TextStyle(fontWeight: FontWeight.w700) : null,
                        ),
                        value: prefs.isOn(t.key),
                        onChanged: (v) => _setType(t.key, v),
                      ),
                  ],
                ),
                if (!prefs.isOn('sos'))
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Glass(
                      radius: 24,
                      tint: AppColors.sos,
                      opacity: 0.85,
                      padding: EdgeInsets.fromLTRB(14, 14, 16, 14),
                      child: Row(
                        children: [
                          Icon(Icons.warning_rounded, color: Colors.white, size: 26),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Cảnh báo SOS đang tắt. Bạn sẽ không biết khi người thân cần trợ giúp.',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                StreamBuilder<List<Group>>(
                  stream: _groups,
                  builder: (context, gsnap) {
                    final members = _members(gsnap.data ?? const []);
                    return GlassSection(
                      header: 'Tắt cảnh báo từ thành viên',
                      footer: 'Cảnh báo SOS từ thành viên đã tắt vẫn được gửi tới bạn để đảm bảo an toàn.',
                      dividerIndent: 16 + 36 + 14,
                      children: [
                        if (members.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                            child: Text(
                              gsnap.hasData ? 'Chưa có thành viên nào khác.' : 'Đang tải…',
                              style: TextStyle(color: secondary),
                            ),
                          )
                        else
                          for (final (uid, name) in members)
                            SwitchListTile(
                              horizontalTitleGap: 14,
                              secondary: MemberAvatar(uid: uid, name: name, radius: 18),
                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: const Text('Tắt cảnh báo từ người này'),
                              value: prefs.isMuted(uid),
                              onChanged: (v) => _run(() => AlertPrefsService.instance.setMuted(widget.uid, uid, v)),
                            ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
