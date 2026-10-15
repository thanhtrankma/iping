import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'group_consent.dart';
import 'location_gates.dart';
import 'location_service.dart';
import 'pause_schedule.dart';
import 'privacy_service.dart';

/// Xử lý push khi app ở nền / đã tắt (chạy trong isolate riêng).
/// Với yêu cầu vị trí: nếu đang bật chia sẻ thì lấy một vị trí và ghi vào nhóm yêu cầu.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'locate') return;
  final gid = message.data['groupId'] as String?;
  if (gid == null || gid.isEmpty) return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    // Tắt chia sẻ thì chỉ hiện thông báo (hệ thống tự hiện), không gửi vị trí.
    if (!(prefs.getBool(LocationService.sharingPrefKey) ?? false)) return;
    // Nhóm đang tạm ẩn vị trí: không gửi toạ độ thật.
    final raw = prefs.getString(PrivacyService.prefKey);
    if (raw != null &&
        PauseSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>).isPaused(gid, DateTime.now())) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (user == null) return;
    // Chưa đồng ý chia sẻ với nhóm này (vd. vừa vào bằng mã mời): không gửi vị trí.
    // Chưa có dữ liệu đồng ý thì KHÔNG gửi (an toàn về quyền riêng tư).
    if (!backgroundConsentAllows(prefs.getString(GroupConsent.prefKey(user.uid)), gid, GroupConsent.parse)) return;

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    final p = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20));

    int? battery;
    try {
      battery = await Battery().batteryLevel;
    } catch (_) {}

    await FirebaseFirestore.instance.doc('groups/$gid/locations/${user.uid}').set({
      'name': user.displayName ?? 'Thành viên',
      'photoUrl': user.photoURL,
      'lat': p.latitude,
      'lng': p.longitude,
      'accuracy': p.accuracy,
      if (p.speed >= 0) 'speed': p.speed,
      if (battery != null) 'battery': battery,
      'sharing': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'clientAt': Timestamp.fromDate(p.timestamp),
    }, SetOptions(merge: true));
  } catch (e) {
    debugPrint('Background locate: $e');
  }
}
