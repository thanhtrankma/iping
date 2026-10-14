import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/chat_tab.dart';
import '../screens/group_actions.dart';
import '../screens/meetup_screen.dart';
import '../screens/member_screen.dart';
import '../screens/moments_screen.dart';
import '../screens/safe_trip_screen.dart';
import 'group_service.dart';
import 'settings_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Màn hình cần mở khi bấm vào một push.
enum PushDest { member, chat, moments, meetup, safeTrip, home }

class PushTarget {
  const PushTarget(this.dest, this.groupId, {this.uid, this.meetupId});
  final PushDest dest;
  final String groupId;
  final String? uid;
  final String? meetupId;
}

/// Chọn màn hình theo `data.type` / `data.groupId` của push (hàm thuần, có test).
PushTarget? pushTargetFor(Map<String, dynamic> data) {
  final gid = data['groupId'] as String?;
  if (gid == null || gid.isEmpty) return null;
  String? s(String k) {
    final v = data[k] as String?;
    return (v == null || v.isEmpty) ? null : v;
  }

  return switch (data['type']) {
    'message' => PushTarget(PushDest.chat, gid),
    'moment' => PushTarget(PushDest.moments, gid),
    'meetup' => s('meetupId') == null
        ? PushTarget(PushDest.home, gid)
        : PushTarget(PushDest.meetup, gid, meetupId: s('meetupId')),
    'safe_self' => PushTarget(PushDest.safeTrip, gid),
    // Ping / yêu cầu vị trí: mở người gửi.
    'ping' ||
    'locate' =>
      s('from') == null ? PushTarget(PushDest.home, gid) : PushTarget(PushDest.member, gid, uid: s('from')),
    // Sự kiện của một thành viên (SOS, đến/rời, check-in, pin yếu, Về an toàn...): mở người đó.
    _ => s('uid') == null ? PushTarget(PushDest.home, gid) : PushTarget(PushDest.member, gid, uid: s('uid')),
  };
}

/// Mở đúng màn hình khi người dùng bấm vào push (app đang nền hoặc đã tắt).
class PushRouter {
  PushRouter._();
  static final instance = PushRouter._();

  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> init() async {
    await _openedSub?.cancel();
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((m) => open(m.data));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Đợi màn chính dựng xong rồi mới đẩy màn mới lên.
      WidgetsBinding.instance.addPostFrameCallback((_) => open(initial.data));
    }
  }

  Future<void> dispose() async {
    await _openedSub?.cancel();
    _openedSub = null;
  }

  Future<void> open(Map<String, dynamic> data) async {
    final t = pushTargetFor(data);
    final nav = navigatorKey.currentState;
    if (t == null || nav == null || FirebaseAuth.instance.currentUser == null) return;

    // Chuyển màn chính sang đúng nhóm của push.
    await SettingsService.instance.selectGroup(t.groupId);
    nav.popUntil((r) => r.isFirst);
    if (t.dest == PushDest.home) return;
    if (t.dest == PushDest.member) {
      nav.push(MaterialPageRoute(builder: (_) => MemberScreen(groupId: t.groupId, uid: t.uid!)));
      return;
    }

    Group? g;
    try {
      g = await GroupService.instance.group(t.groupId).first.timeout(const Duration(seconds: 10));
    } catch (_) {
      g = null;
    }
    if (g == null) return;
    final group = g;
    final Widget page = switch (t.dest) {
      PushDest.chat => SubPage(title: group.name, child: ChatTab(group: group)),
      PushDest.moments => MomentsScreen(group: group),
      PushDest.meetup => MeetupDetailScreen(group: group, meetupId: t.meetupId!),
      PushDest.safeTrip => SafeTripScreen(group: group),
      _ => const SizedBox.shrink(),
    };
    nav.push(MaterialPageRoute(builder: (_) => page));
  }
}
