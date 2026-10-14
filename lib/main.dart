import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/invite_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Vẽ tràn dưới thanh trạng thái / điều hướng; thanh điều hướng Android trong suốt, không có lớp
  // phủ trắng hệ thống tự thêm (kính phía dưới tự chừa chỗ bằng floatingBottomGap).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Nghe link mời iping://join?code=… (kể cả link mở app lần đầu).
  InviteLinkService.instance.init();
  runApp(const IPingApp());
}
