import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'locate_background.dart';
import 'location_service.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Đăng ký token push (FCM) và hiển thị thông báo khi app đang mở.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _msgSub;
  String? _token;

  Future<void> init(String uid) async {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await _messaging.requestPermission();
    try {
      _token = await _messaging.getToken();
    } catch (e) {
      // Ví dụ: iOS Simulator không có APNs.
      debugPrint('FCM token unavailable: $e');
    }
    if (_token != null) await _save(uid, _token!);

    await _refreshSub?.cancel();
    _refreshSub = _messaging.onTokenRefresh.listen((t) {
      _token = t;
      _save(uid, t);
    });

    await _msgSub?.cancel();
    _msgSub = FirebaseMessaging.onMessage.listen((m) {
      // Yêu cầu vị trí khi app đang mở: gửi ngay (nếu đang bật chia sẻ).
      if (m.data['type'] == 'locate') LocationService.instance.pushNow();
      final n = m.notification;
      if (n == null) return;
      final isSos = m.data['type'] == 'sos';
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        backgroundColor: isSos ? Colors.red : null,
        duration: Duration(seconds: isSos ? 10 : 4),
        content: Text([n.title, n.body].whereType<String>().join('\n')),
      ));
    });
  }

  Future<void> unregister(String uid) async {
    await _refreshSub?.cancel();
    await _msgSub?.cancel();
    final t = _token;
    if (t != null) {
      await _db.doc('users/$uid').set({
        'fcmTokens': FieldValue.arrayRemove([t]),
      }, SetOptions(merge: true));
    }
    _token = null;
  }

  Future<void> _save(String uid, String token) => _db.doc('users/$uid').set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
}
