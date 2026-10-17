// Xem / chụp các màn giải thích quyền vị trí mà không cần đăng nhập / Firebase.
//
//   flutter run -t lib/dev/disclosure_preview.dart
//
// Dùng để chụp ảnh cho người duyệt hoặc video khai báo quyền vị trí nền.
import 'package:flutter/material.dart';

import '../screens/location_disclosure.dart';
import '../theme.dart';
import '../widgets/glass.dart';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: const _Preview(),
    ));

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => showGlassSheet<bool>(context, builder: (_) => const LocationDisclosureSheet()),
                  child: const Text('1. Giải thích trước khi xin quyền'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => showGlassSheet<bool>(context, builder: (_) => const BackgroundLocationSheet()),
                  child: const Text('2. Giải thích quyền vị trí nền'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
