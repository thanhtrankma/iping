import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'locate_background.dart';
import 'location_service.dart';
import 'sos_alarm_service.dart';

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
  String? _uid;
  bool _asked = false;

  /// Đăng ký nhận push khi đăng nhập. KHÔNG hỏi quyền thông báo ở đây (không có ngữ cảnh):
  /// quyền được hỏi khi người dùng bật chia sẻ vị trí ([ensurePermission]).
  /// Token FCM vẫn được lấy và lưu nếu có (đã cấp quyền từ trước, hoặc Android < 13).
  Future<void> init(String uid) async {
    _uid = uid;
    _asked = false;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await _registerToken(uid);

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
      final isSos = m.data['type'] == 'sos' || m.data['type'] == 'safe_overdue';
      // App đang mở: hệ thống không phát âm thanh push, nên tự hú còi cho cảnh báo khẩn.
      if (isSos) SosAlarmService.instance.play();
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        backgroundColor: isSos ? Colors.red : null,
        duration: Duration(seconds: isSos ? 30 : 4),
        content: Text([n.title, n.body].whereType<String>().join('\n')),
        action: isSos
            ? SnackBarAction(label: 'Tắt còi', textColor: Colors.white, onPressed: SosAlarmService.instance.stop)
            : null,
      ));
    });
  }

  Future<void> _registerToken(String uid) async {
    try {
      _token = await _messaging.getToken();
    } catch (e) {
      // Ví dụ: iOS Simulator không có APNs.
      debugPrint('FCM token unavailable: $e');
    }
    if (_token != null) await _save(uid, _token!);
  }

  /// Hỏi quyền thông báo (POST_NOTIFICATIONS trên Android 13+, hộp thoại hệ thống trên iOS) khi người
  /// dùng vừa làm một thao tác cần thông báo (bật chia sẻ vị trí). Gọi thẳng hộp thoại hệ thống, không
  /// có màn hỏi trước. Đã cấp / đã từ chối thì hệ thống không hỏi lại; mỗi phiên chỉ gọi một lần.
  Future<void> ensurePermission() async {
    if (_asked) return;
    _asked = true;
    try {
      final settings = await _messaging.getNotificationSettings();
      final status = settings.authorizationStatus;
      if (status != AuthorizationStatus.authorized && status != AuthorizationStatus.provisional) {
        await _messaging.requestPermission();
      }
      final uid = _uid;
      if (uid != null && _token == null) await _registerToken(uid);
    } catch (e) {
      debugPrint('Notification permission: $e');
    }
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
    _uid = null;
    _asked = false;
  }

  Future<void> _save(String uid, String token) => _db.doc('users/$uid').set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
}
