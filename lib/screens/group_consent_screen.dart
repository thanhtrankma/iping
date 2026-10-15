import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_consent.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'group_actions.dart';

/// Lựa chọn của người dùng trên màn đồng ý sau khi vào nhóm bằng mã mời.
enum GroupConsentChoice { shared, notShared, left }

/// Người dùng chọn chia sẻ với nhóm [gid]: ghi nhận đồng ý, rồi nếu chia sẻ vị trí chung đang tắt
/// thì HỎI có bật không (không tự bật). Bật thì đi qua màn giải thích + xin quyền của [LocationService].
Future<void> shareWithGroup(BuildContext context, String gid) async {
  await GroupConsent.instance.grant(gid);
  final loc = LocationService.instance;
  if (loc.sharing.value) {
    await loc.refresh();
    return;
  }
  if (!context.mounted) return;
  final turnOn = await showGlassSheet<bool>(context, builder: (ctx) => const _TurnOnSharingSheet());
  if (turnOn != true || !context.mounted) return;
  final err = await loc.start();
  if (err != null && context.mounted) showMessage(context, err);
}

/// Thôi chia sẻ với nhóm [gid]: nhóm không nhận vị trí mới, không còn thấy mình "đang chia sẻ",
/// vị trí cuối (toạ độ, tốc độ, pin) bị xoá và lịch sử vị trí trong nhóm này bị xoá trên server.
Future<void> stopSharingWithGroup(String gid) async {
  await GroupConsent.instance.revoke(gid);
  await LocationService.instance.hideFrom(gid);
  try {
    await GroupService.instance.forgetMyLocationInGroup(gid).timeout(const Duration(seconds: 30));
  } catch (e) {
    // Offline / lỗi mạng: vị trí cuối đã ẩn; lịch sử vẫn tự xoá sau 30 ngày (TTL).
    debugPrint('forgetMyLocationInGroup $gid: $e');
  }
  await LocationService.instance.refresh();
}

/// Màn xác nhận sau khi nhập mã mời / mở link / quét QR.
///
/// Chính sách Google Play: vào nhóm không tự động gửi vị trí. Người dùng thấy nhóm có ai,
/// nhóm sẽ thấy gì, rồi tự chọn chia sẻ, chỉ tham gia, hoặc rời nhóm.
class GroupConsentScreen extends StatefulWidget {
  const GroupConsentScreen({super.key, required this.groupId});
  final String groupId;

  /// Mở màn đồng ý. Đóng màn mà không chọn gì = tham gia nhưng chưa chia sẻ.
  static Future<GroupConsentChoice> open(BuildContext context, String gid) async {
    final choice = await Navigator.of(context).push<GroupConsentChoice>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => GroupConsentScreen(groupId: gid)),
    );
    return choice ?? GroupConsentChoice.notShared;
  }

  @override
  State<GroupConsentScreen> createState() => _GroupConsentScreenState();
}

class _GroupConsentScreenState extends State<GroupConsentScreen> {
  late final Stream<Group?> _group = GroupService.instance.group(widget.groupId);
  final _me = FirebaseAuth.instance.currentUser?.uid;
  bool _busy = false;

  Future<void> _share(Group? g) async {
    setState(() => _busy = true);
    try {
      await shareWithGroup(context, widget.groupId);
      if (!mounted) return;
      final on = LocationService.instance.sharing.value;
      showMessage(
        context,
        on
            ? 'Đang chia sẻ vị trí với "${g?.name ?? 'nhóm'}"'
            : 'Đã chọn chia sẻ với "${g?.name ?? 'nhóm'}". Vị trí chỉ được gửi khi bạn bật chia sẻ.',
      );
      Navigator.pop(context, GroupConsentChoice.shared);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _joinOnly(Group? g) {
    showMessage(context, 'Đã tham gia "${g?.name ?? 'nhóm'}". Bạn chưa chia sẻ vị trí với nhóm này.');
    Navigator.pop(context, GroupConsentChoice.notShared);
  }

  Future<void> _leave(Group g) async {
    setState(() => _busy = true);
    try {
      final left = await GroupActions.leave(context, g);
      if (!left || !mounted) return;
      await GroupConsent.instance.revoke(g.id);
      if (!mounted) return;
      showMessage(context, 'Đã rời nhóm "${g.name}"');
      Navigator.pop(context, GroupConsentChoice.left);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Group?>(
      stream: _group,
      builder: (context, snap) {
        final g = snap.data;
        return GroupConsentView(
          group: g,
          myUid: _me,
          busy: _busy,
          onShare: () => _share(g),
          onJoinOnly: () => _joinOnly(g),
          onLeave: g == null ? null : () => _leave(g),
        );
      },
    );
  }
}

/// Phần giao diện của màn đồng ý (tách riêng để test không cần Firebase).
class GroupConsentView extends StatelessWidget {
  const GroupConsentView({
    super.key,
    required this.group,
    required this.myUid,
    required this.onShare,
    required this.onJoinOnly,
    required this.onLeave,
    this.busy = false,
  });

  /// `null` khi đang tải thông tin nhóm.
  final Group? group;
  final String? myUid;
  final VoidCallback onShare;
  final VoidCallback onJoinOnly;
  final VoidCallback? onLeave;
  final bool busy;

  /// Những gì thành viên nhóm thấy khi mình chia sẻ (khớp với tính năng thật của app).
  static const sharedItems = <(IconData, Color, String, String)>[
    (
      Icons.my_location_rounded,
      AppColors.brand,
      'Vị trí chính xác theo thời gian thực',
      'Vị trí trên bản đồ, địa chỉ, tốc độ di chuyển và lúc cập nhật, kể cả khi app đóng nếu bạn bật chia sẻ vị trí.',
    ),
    (
      Icons.battery_5_bar_rounded,
      AppColors.online,
      'Mức pin',
      'Phần trăm pin của máy. Nhóm có thể nhận thông báo khi pin yếu hoặc máy mất kết nối.',
    ),
    (
      Icons.history_rounded,
      AppColors.indigo,
      'Lịch sử vị trí tới 30 ngày',
      'Các nơi đã dừng, chuyến đi và báo cáo lái xe (tốc độ, phanh gấp), tính từ khi bạn chia sẻ với nhóm này.',
    ),
    (
      Icons.notifications_active_rounded,
      AppColors.orange,
      'Thông báo đến và rời địa điểm',
      'Khi bạn đến hoặc rời Nhà, Trường, Công ty… đã lưu trong nhóm, và cảnh báo chạy quá tốc độ.',
    ),
    (
      Icons.explore_rounded,
      AppColors.teal,
      'Điểm Khám phá',
      'Số khu vực bạn đã đi qua trên bản đồ (phường, quận, tỉnh).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.6);
    final g = group;
    final name = g?.name ?? '';
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
                  children: [
                    // Tiêu đề: tên nhóm.
                    Center(child: GroupBadge(name: name, icon: g == null ? Icons.group_rounded : null, size: 76)),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        g == null ? 'Tham gia nhóm' : 'Tham gia “$name”',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        'Nhóm chưa nhận vị trí của bạn. Bạn tự quyết định có chia sẻ với nhóm này hay không.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15.5, height: 1.4, color: secondary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _MembersCard(group: g, myUid: myUid),
                    GlassSection(
                      header: 'Nếu chia sẻ, thành viên nhóm sẽ thấy',
                      footer: 'Tin nhắn, Ping, Khoảnh khắc và SOS chỉ được gửi khi bạn tự bấm.',
                      dividerIndent: 16 + 34 + 14,
                      children: [
                        for (final (icon, color, title, text) in sharedItems)
                          ListTile(
                            horizontalTitleGap: 14,
                            contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                            leading: GlassIconBadge(icon: icon, color: color, size: 34),
                            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(text, style: TextStyle(color: secondary, height: 1.3, fontSize: 13.5)),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Glass(
                        radius: 26,
                        opacity: 0.7,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const GlassIconBadge(icon: Icons.verified_user_rounded, color: AppColors.online, size: 34),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Bạn luôn có quyền quyết định',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: -0.2)),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Tắt chia sẻ với nhóm, tạm ẩn vị trí hoặc rời nhóm bất cứ lúc nào trong '
                                    'Menu → Bảo mật & Bạn bè.',
                                    style: TextStyle(color: secondary, height: 1.35, fontSize: 13.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Actions(busy: busy, onShare: onShare, onJoinOnly: onJoinOnly, onLeave: onLeave),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembersCard extends StatelessWidget {
  const _MembersCard({required this.group, required this.myUid});
  final Group? group;
  final String? myUid;

  static const _max = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = group;
    // Mình đứng đầu, sau đó là các thành viên khác.
    final ids = g == null ? const <String>[] : [...g.memberIds.where((u) => u == myUid), ...g.memberIds.where((u) => u != myUid)];
    final shown = ids.take(_max).toList();
    final extra = ids.length - shown.length;
    return GlassSection(
      header: g == null ? 'Thành viên' : 'Thành viên (${ids.length})',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: g == null
              ? const SizedBox(height: 72, child: Center(child: CircularProgressIndicator.adaptive()))
              : Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 12,
                  children: [
                    for (final uid in shown)
                      _MemberChip(
                        uid: uid,
                        name: uid == myUid ? 'Bạn' : g.nameOf(uid),
                        initialName: g.nameOf(uid),
                        photoUrl: g.memberPhotos[uid],
                      ),
                    if (extra > 0)
                      SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                              child: Text('+$extra', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 6),
                            Text('khác', style: TextStyle(fontSize: 12.5, color: scheme.onSurface.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.uid, required this.name, required this.initialName, this.photoUrl});
  final String uid;
  final String name;
  final String initialName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? Colors.white.withValues(alpha: 0.85) : Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: AvatarCircle(uid: uid, name: initialName, radius: 24, photoUrl: photoUrl),
          ),
          const SizedBox(height: 6),
          Text(
            name.split(' ').last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.2),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.busy, required this.onShare, required this.onJoinOnly, required this.onLeave});
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onJoinOnly;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 0,
      opacity: 0.8,
      padding: EdgeInsets.fromLTRB(20, 14, 20, 8 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
            ),
            icon: busy
                ? const SizedBox.square(
                    dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.location_on_rounded),
            label: const Text('Chia sẻ vị trí với nhóm này'),
            onPressed: busy ? null : onShare,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: busy ? null : onJoinOnly,
            child: const Text('Tham gia nhưng chưa chia sẻ'),
          ),
          const SizedBox(height: 2),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.sos, minimumSize: const Size.fromHeight(44)),
            onPressed: busy ? null : onLeave,
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
  }
}

/// Hỏi bật chia sẻ vị trí chung khi người dùng vừa chọn chia sẻ với một nhóm mà chia sẻ đang tắt.
class _TurnOnSharingSheet extends StatelessWidget {
  const _TurnOnSharingSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: GlassIconBadge(icon: Icons.location_on_rounded, color: AppColors.brand, size: 56)),
          const SizedBox(height: 14),
          const Text(
            'Bật chia sẻ vị trí?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Chia sẻ vị trí của bạn đang tắt, nên nhóm chưa nhận được vị trí. '
            'Bật lên để chia sẻ với các nhóm bạn đã chọn. Bạn có thể tắt bất cứ lúc nào.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 22),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bật chia sẻ'),
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
        ],
      ),
    );
  }
}
