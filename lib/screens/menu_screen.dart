import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'activity_tab.dart';
import 'explore_screen.dart';
import 'group_actions.dart';
import 'groups_screen.dart';
import 'meetup_screen.dart';
import 'moments_screen.dart';
import 'places_tab.dart';
import 'privacy_screen.dart';
import 'profile_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.uid, required this.group});
  final String uid;
  final Group? group;

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = AuthService.instance.displayName;
    final g = group;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('Menu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: GlassBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 40),
          children: [
            Glass(
              radius: 26,
              opacity: 0.6,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () => _push(context, const ProfileScreen()),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        MemberAvatar(uid: uid, name: name, radius: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                              Text(user?.email ?? '',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SharingSwitchCard(),
            const SizedBox(height: 16),
            _Section(children: [
              _Item(
                icon: Icons.groups_2_outlined,
                title: 'Quản lý nhóm',
                onTap: () => _push(context, GroupsScreen(uid: uid)),
              ),
              _Item(
                icon: Icons.shield_outlined,
                title: 'Bảo mật & Bạn bè',
                onTap: () => _push(context, PrivacyScreen(uid: uid)),
              ),
              _Item(
                icon: Icons.explore_outlined,
                title: 'Khám phá',
                onTap: () => _push(context, const ExploreScreen()),
              ),
              if (g != null) ...[
                _Item(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Khoảnh khắc',
                  onTap: () => _push(context, MomentsScreen(group: g)),
                ),
                _Item(
                  icon: Icons.handshake_outlined,
                  title: 'Meetup',
                  onTap: () => _push(context, MeetupListScreen(group: g)),
                ),
                _Item(
                  icon: Icons.place_outlined,
                  title: 'Địa điểm của "${g.name}"',
                  onTap: () => _push(context, SubPage(title: 'Địa điểm', child: PlacesTab(group: g))),
                ),
                _Item(
                  icon: Icons.notifications_none_rounded,
                  title: 'Cảnh báo & hoạt động',
                  onTap: () => _push(context, SubPage(title: 'Hoạt động', child: ActivityTab(group: g))),
                ),
              ],
              ValueListenableBuilder<MapStyle>(
                valueListenable: SettingsService.instance.mapStyle,
                builder: (context, style, _) => SwitchListTile(
                  secondary: const Icon(Icons.satellite_alt_outlined),
                  title: const Text('Bản đồ vệ tinh', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: style == MapStyle.satellite,
                  onChanged: (_) => SettingsService.instance.toggleMapStyle(),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const Glass(
              radius: 26,
              tint: AppColors.brand,
              opacity: 0.85,
              padding: EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Tất cả tính năng Premium đều miễn phí: lịch sử 30 ngày, báo cáo lái xe, địa điểm không giới hạn, không quảng cáo.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(children: [
              _Item(
                icon: Icons.logout_rounded,
                title: 'Đăng xuất',
                color: AppColors.sos,
                onTap: () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  AuthService.instance.signOut();
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 26,
      opacity: 0.6,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: children),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.onTap, this.color});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      trailing: color == null ? const Icon(Icons.chevron_right_rounded) : null,
      onTap: onTap,
    );
  }
}
