import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'activity_tab.dart';
import 'alert_settings_screen.dart';
import 'explore_screen.dart';
import 'group_actions.dart';
import 'groups_screen.dart';
import 'meetup_screen.dart';
import 'moments_screen.dart';
import 'places_tab.dart';
import 'privacy_screen.dart';
import 'profile_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.uid, required this.group});
  final String uid;
  final Group? group;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

/// Theo dõi danh sách nhóm để menu không giữ nhóm cũ sau khi đã rời / bị xoá khỏi nhóm.
class _MenuScreenState extends State<MenuScreen> {
  late final Stream<List<Group>> _groups = GroupService.instance.myGroups(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Group>>(
      stream: _groups,
      builder: (context, snap) {
        final initial = widget.group;
        final groups = snap.data;
        // Chưa có dữ liệu thì dùng nhóm được truyền vào; có rồi thì lấy bản mới nhất (hoặc null nếu đã rời).
        final current = initial == null || groups == null
            ? initial
            : groups.where((g) => g.id == initial.id).firstOrNull;
        return _MenuView(uid: widget.uid, group: current);
      },
    );
  }
}

class _MenuView extends StatelessWidget {
  const _MenuView({required this.uid, required this.group});
  final String uid;
  final Group? group;

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = AuthService.instance.displayName;
    final g = group;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Menu',
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: GlassButton(
              size: 42,
              icon: Icons.close_rounded,
              tooltip: 'Đóng',
              onTap: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: GlassBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, MediaQuery.paddingOf(context).top + 60 + 8, 0, 40),
          children: [
            // Thẻ hồ sơ: kính nổi, chạm để mở Hồ sơ.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GlassPressable(
                onTap: () => _push(context, const ProfileScreen()),
                shape: glassShape(radius: 28),
                scale: 0.97,
                child: Glass(
                  radius: 28,
                  opacity: 0.7,
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                  child: Row(
                    children: [
                      MemberAvatar(uid: uid, name: name, radius: 32, ring: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SharingSwitchCard(),
            ),
            const SizedBox(height: 24),
            GlassSection(
              dividerIndent: _rowIndent,
              children: [
                _Item(
                  icon: Icons.groups_2_rounded,
                  color: AppColors.brand,
                  title: 'Quản lý nhóm',
                  onTap: () => _push(context, GroupsScreen(uid: uid)),
                ),
                _Item(
                  icon: Icons.shield_rounded,
                  color: AppColors.online,
                  title: 'Bảo mật & Bạn bè',
                  onTap: () => _push(context, PrivacyScreen(uid: uid)),
                ),
                _Item(
                  icon: Icons.explore_rounded,
                  color: AppColors.orange,
                  title: 'Khám phá',
                  onTap: () => _push(context, const ExploreScreen()),
                ),
                _Item(
                  icon: Icons.notifications_active_rounded,
                  color: AppColors.sos,
                  title: 'Quản lý cảnh báo',
                  onTap: () => _push(context, AlertSettingsScreen(uid: uid)),
                ),
              ],
            ),
            if (g != null)
              GlassSection(
                header: g.name,
                dividerIndent: _rowIndent,
                children: [
                  _Item(
                    icon: Icons.auto_awesome_rounded,
                    color: AppColors.pink,
                    title: 'Khoảnh khắc',
                    onTap: () => _push(context, MomentsScreen(group: g)),
                  ),
                  _Item(
                    icon: Icons.handshake_rounded,
                    color: AppColors.purple,
                    title: 'Meetup',
                    onTap: () => _push(context, MeetupListScreen(group: g)),
                  ),
                  _Item(
                    icon: Icons.place_rounded,
                    color: AppColors.teal,
                    title: 'Địa điểm của "${g.name}"',
                    onTap: () => _push(context, SubPage(title: 'Địa điểm', child: PlacesTab(group: g))),
                  ),
                  _Item(
                    icon: Icons.notifications_rounded,
                    color: AppColors.warning,
                    title: 'Cảnh báo & hoạt động',
                    onTap: () => _push(context, SubPage(title: 'Hoạt động', child: ActivityTab(group: g))),
                  ),
                ],
              ),
            GlassSection(
              dividerIndent: _rowIndent,
              children: [
                ValueListenableBuilder<MapStyle>(
                  valueListenable: SettingsService.instance.mapStyle,
                  builder: (context, style, _) => SwitchListTile(
                    horizontalTitleGap: 14,
                    secondary: const GlassIconBadge(icon: Icons.satellite_alt_rounded, color: AppColors.indigo),
                    title: const Text('Bản đồ vệ tinh'),
                    value: style == MapStyle.satellite,
                    onChanged: (_) => SettingsService.instance.toggleMapStyle(),
                  ),
                ),
              ],
            ),
            // Thẻ Premium: kính có tint thương hiệu.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Glass(
                radius: 26,
                tint: AppColors.brand,
                opacity: 0.85,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: ShapeDecoration(
                        shape: glassShape(radius: 14),
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Tất cả tính năng Premium đều miễn phí: lịch sử 30 ngày, báo cáo lái xe, địa điểm không giới hạn, không quảng cáo.',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.35, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GlassSection(
              children: [
                ListTile(
                  title: const Text(
                    'Đăng xuất',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.sos, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    AuthService.instance.signOut();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lề trái của đường kẻ giữa các dòng: thẳng hàng với chữ, bỏ qua icon.
const double _rowIndent = 16 + 30 + 14;

/// Một dòng kiểu iOS Settings: ô icon màu + tiêu đề + mũi tên.
class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.onTap, required this.color});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      horizontalTitleGap: 14,
      leading: GlassIconBadge(icon: icon, color: color),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      onTap: onTap,
    );
  }
}
