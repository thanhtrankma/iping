import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Một loại cảnh báo người dùng bật/tắt được.
class AlertType {
  const AlertType(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

/// Các loại cảnh báo. Khoá phải khớp với functions/alert_prefs.js.
const alertTypes = [
  AlertType('place', 'Đến / rời địa điểm', Icons.place_outlined),
  AlertType('sos', 'SOS', Icons.sos_rounded),
  AlertType('safe', 'Về an toàn', Icons.shield_outlined),
  AlertType('message', 'Tin nhắn', Icons.chat_bubble_outline_rounded),
  AlertType('moment', 'Khoảnh khắc', Icons.auto_awesome_outlined),
  AlertType('meetup', 'Meetup', Icons.handshake_outlined),
  AlertType('ping', 'Ping', Icons.waving_hand_outlined),
  AlertType('battery', 'Pin yếu', Icons.battery_alert_rounded),
  AlertType('join', 'Thành viên mới', Icons.group_add_outlined),
];

/// `data.type` của thông báo đẩy -> khoá cài đặt (null nếu không lọc được).
String? alertPrefKeyFor(String type) => switch (type) {
      'arrive' || 'leave' => 'place',
      'sos' => 'sos',
      'join' => 'join',
      'meetup_arrive' || 'meetup' => 'meetup',
      'message' => 'message',
      'moment' => 'moment',
      'ping' => 'ping',
      'low_battery' => 'battery',
      'safe_start' || 'safe_arrive' || 'safe_end' || 'safe_ok' || 'safe_extend' => 'safe',
      // Quá giờ "Về an toàn" là cảnh báo khẩn: đi theo công tắc SOS.
      'safe_overdue' => 'sos',
      _ => null,
    };

/// Cảnh báo khẩn: không bị chặn bởi "tắt cảnh báo từ người này". Khớp `CRITICAL` phía server.
const criticalAlertTypes = {'sos', 'safe_overdue'};

/// Cài đặt cảnh báo, lưu ở `users/{uid}.alertPrefs`.
class AlertPrefs {
  const AlertPrefs({this.types = const {}, this.mutedUids = const []});

  final Map<String, bool> types;
  final List<String> mutedUids;

  /// Mặc định mọi loại đều bật.
  bool isOn(String key) => types[key] ?? true;
  bool isMuted(String uid) => mutedUids.contains(uid);

  /// Giống `wantsAlert` phía server: cảnh báo khẩn vẫn đến dù đã tắt người gửi.
  bool wants(String type, String? senderUid) {
    final key = alertPrefKeyFor(type);
    if (key != null && !isOn(key)) return false;
    if (!criticalAlertTypes.contains(type) && senderUid != null && isMuted(senderUid)) return false;
    return true;
  }

  factory AlertPrefs.fromMap(Object? raw) {
    if (raw is! Map) return const AlertPrefs();
    final t = raw['types'];
    final m = raw['mutedUids'];
    return AlertPrefs(
      types: t is Map
          ? {
              for (final e in t.entries)
                if (e.value is bool) '${e.key}': e.value as bool
            }
          : const {},
      mutedUids: m is List ? m.whereType<String>().toList() : const [],
    );
  }

  Map<String, dynamic> toMap() => {'types': types, 'mutedUids': mutedUids};
}

class AlertPrefsService {
  AlertPrefsService._();
  static final instance = AlertPrefsService._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.doc('users/$uid');

  Stream<AlertPrefs> watch(String uid) => _doc(uid).snapshots().map((d) => AlertPrefs.fromMap(d.data()?['alertPrefs']));

  Future<void> setType(String uid, String key, bool on) => _doc(uid).set({
        'alertPrefs': {
          'types': {key: on},
        },
      }, SetOptions(merge: true));

  Future<void> setMuted(String uid, String member, bool muted) => _doc(uid).set({
        'alertPrefs': {
          'mutedUids': muted ? FieldValue.arrayUnion([member]) : FieldValue.arrayRemove([member]),
        },
      }, SetOptions(merge: true));
}
