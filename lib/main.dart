import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/invite_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Nghe link mời iping://join?code=… (kể cả link mở app lần đầu).
  InviteLinkService.instance.init();
  runApp(const IPingApp());
}
