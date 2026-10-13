import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'theme.dart';

class IPingApp extends StatelessWidget {
  const IPingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPing',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        return SignedInShell(key: ValueKey(user.uid), uid: user.uid);
      },
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
    NotificationService.instance.init(widget.uid);
  }

  @override
  Widget build(BuildContext context) => HomeScreen(uid: widget.uid);
}
