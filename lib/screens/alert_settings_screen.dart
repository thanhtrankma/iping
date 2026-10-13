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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant, fontSize: 13);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('Quản lý cảnh báo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: GlassBackground(
        child: StreamBuilder<AlertPrefs>(
          stream: _prefs,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final prefs = snap.data!;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 40),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text('THÔNG BÁO ĐẨY', style: title),
                ),
                Glass(
                  radius: 26,
                  opacity: 0.6,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final t in alertTypes)
                        SwitchListTile(
                          secondary: Icon(t.icon, color: t.key == 'sos' ? AppColors.sos : null),
                          title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          value: prefs.isOn(t.key),
                          onChanged: (v) => _setType(t.key, v),
                        ),
                    ],
                  ),
                ),
                if (!prefs.isOn('sos')) ...[
                  const SizedBox(height: 12),
                  const Glass(
                    radius: 20,
                    tint: AppColors.sos,
                    opacity: 0.85,
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.white),
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
                ],
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text('TẮT CẢNH BÁO TỪ THÀNH VIÊN', style: title),
                ),
                StreamBuilder<List<Group>>(
                  stream: _groups,
                  builder: (context, gsnap) {
                    final members = _members(gsnap.data ?? const []);
                    return Glass(
                      radius: 26,
                      opacity: 0.6,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: members.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                gsnap.hasData ? 'Chưa có thành viên nào khác.' : 'Đang tải…',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            )
                          : Column(
                              children: [
                                for (final (uid, name) in members)
                                  SwitchListTile(
                                    secondary: MemberAvatar(uid: uid, name: name, radius: 18),
                                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: const Text('Tắt cảnh báo từ người này'),
                                    value: prefs.isMuted(uid),
                                    onChanged: (v) =>
                                        _run(() => AlertPrefsService.instance.setMuted(widget.uid, uid, v)),
                                  ),
                              ],
                            ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                  child: Text(
                    'Cảnh báo SOS từ thành viên đã tắt vẫn được gửi tới bạn để đảm bảo an toàn.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
