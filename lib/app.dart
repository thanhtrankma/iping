import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/explore_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/push_router.dart';
import 'services/settings_service.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/glass.dart';

class IPingApp extends StatelessWidget {
  const IPingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPing',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      navigatorKey: navigatorKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        return SignedInShell(key: ValueKey(user.uid), uid: user.uid);
      },
    );
  }
}

/// Màn chờ khi đang kiểm tra đăng nhập: logo phát sáng trên nền kính.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.brand.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 4),
                  ],
                ),
                child: const AppLogo(size: 84),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator.adaptive(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Khởi động các service cần đăng nhập rồi hiển thị danh sách nhóm.
class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key, required this.uid});
  final String uid;

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  @override
  void initState() {
    super.initState();
    SettingsService.instance.load();
    LocationService.instance.init(widget.uid);
    ExploreService.instance.init(widget.uid);
    NotificationService.instance.init(widget.uid);
    // Bấm push (app ở nền / đã tắt) → mở đúng màn hình.
    PushRouter.instance.init();
  }

  @override
  Widget build(BuildContext context) => HomeScreen(uid: widget.uid);
}
