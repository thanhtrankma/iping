import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Loại nội dung bị báo cáo (`reports/{id}.kind`).
enum ReportKind { message, dm, moment, user }

/// Lý do báo cáo (`reports/{id}.reason`).
enum ReportReason { spam, harassment, sexual, violence, other }

extension ReportReasonLabel on ReportReason {
  String get label => switch (this) {
        ReportReason.spam => 'Spam hoặc lừa đảo',
        ReportReason.harassment => 'Quấy rối, bắt nạt hoặc theo dõi',
        ReportReason.sexual => 'Nội dung khiêu dâm',
        ReportReason.violence => 'Bạo lực hoặc đe doạ',
        ReportReason.other => 'Lý do khác',
      };
}

/// Báo cáo nội dung, chặn người dùng và xoá tin nhắn (UGC: Google Play / Apple 1.2).
///
/// Dữ liệu:
/// - `reports/{autoId}`: chỉ tạo, client không đọc được (Cloud Functions báo cho quản trị viên).
/// - `users/{myUid}.blockedUids`: danh sách uid mình đã chặn (chỉ chính chủ đọc/ghi).
/// - Xoá: `groups/{gid}/messages/{id}`, `dms/{dmId}/messages/{id}`, `groups/{gid}/moments/{id}`.
class ModerationService {
  ModerationService._();
  static final instance = ModerationService._();

  /// Giới hạn độ dài (khớp với rules).
  static const maxNote = 500;
  static const maxText = 1000;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Các uid mình đã chặn. Cập nhật theo thời gian thực sau khi gọi [watch].
  final ValueNotifier<Set<String>> blocked = ValueNotifier(const {});

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _watching;

  /// Bắt đầu theo dõi danh sách chặn của người đang đăng nhập (gọi nhiều lần cũng được).
  void watch() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == _watching) return;
    _sub?.cancel();
    _sub = null;
    _watching = uid;
    blocked.value = const {};
    if (uid == null) return;
    _sub = _db.doc('users/$uid').snapshots().listen(
          (s) => blocked.value = parseBlocked(s.data()),
          onError: (_) {},
        );
  }

  /// Đọc `blockedUids` từ dữ liệu hồ sơ người dùng.
  static Set<String> parseBlocked(Map<String, dynamic>? data) {
    final raw = data?['blockedUids'];
    if (raw is! List) return const {};
    return raw.whereType<String>().where((s) => s.isNotEmpty).toSet();
  }

  bool isBlocked(String uid) => blocked.value.contains(uid);

  Future<void> block(String uid) async {
    if (uid.isEmpty || uid == _uid) return;
    // Cập nhật ngay trên giao diện, không chờ máy chủ.
    blocked.value = {...blocked.value, uid};
    await _db.doc('users/$_uid').set({
      'blockedUids': FieldValue.arrayUnion([uid]),
    }, SetOptions(merge: true));
  }

  Future<void> unblock(String uid) async {
    blocked.value = {...blocked.value}..remove(uid);
    await _db.doc('users/$_uid').set({
      'blockedUids': FieldValue.arrayRemove([uid]),
    }, SetOptions(merge: true));
  }

  /// Dữ liệu một báo cáo (tách riêng để kiểm thử).
  static Map<String, dynamic> reportData({
    required String reporterUid,
    required ReportKind kind,
    required String targetUid,
    required ReportReason reason,
    String? groupId,
    String? dmId,
    String? targetId,
    String? note,
    String? text,
  }) {
    final n = note?.trim() ?? '';
    final t = text ?? '';
    return {
      'reporterUid': reporterUid,
      'kind': kind.name,
      if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
      if (dmId != null && dmId.isNotEmpty) 'dmId': dmId,
      if (targetId != null && targetId.isNotEmpty) 'targetId': targetId,
      'targetUid': targetUid,
      'reason': reason.name,
      if (n.isNotEmpty) 'note': n.length > maxNote ? n.substring(0, maxNote) : n,
      if (t.isNotEmpty) 'text': t.length > maxText ? t.substring(0, maxText) : t,
    };
  }

  Future<void> report({
    required ReportKind kind,
    required String targetUid,
    required ReportReason reason,
    String? groupId,
    String? dmId,
    String? targetId,
    String? note,
    String? text,
  }) =>
      _db.collection('reports').add({
        ...reportData(
          reporterUid: _uid,
          kind: kind,
          targetUid: targetUid,
          reason: reason,
          groupId: groupId,
          dmId: dmId,
          targetId: targetId,
          note: note,
          text: text,
        ),
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Người gửi xoá tin của mình; chủ nhóm xoá được mọi tin trong nhóm.
  Future<void> deleteGroupMessage(String groupId, String messageId) =>
      _db.doc('groups/$groupId/messages/$messageId').delete();

  /// Người gửi xoá tin nhắn 1-1 của mình.
  /// Xoá tin 1-1 của mình, rồi cập nhật bản xem trước (`lastText`) theo tin còn lại mới nhất
  /// để danh sách trò chuyện không còn hiện nội dung đã xoá.
  Future<void> deleteDmMessage(String dmId, String messageId) async {
    await _db.doc('dms/$dmId/messages/$messageId').delete();
    try {
      final last = await _db.collection('dms/$dmId/messages').orderBy('createdAt', descending: true).limit(1).get();
      final d = last.docs.isEmpty ? null : last.docs.first.data();
      await _db.doc('dms/$dmId').update({
        'lastText': d?['text'] as String? ?? '',
        'lastUid': d?['uid'] as String? ?? _uid,
      });
    } catch (e) {
      debugPrint('Update DM preview $dmId: $e');
    }
  }

  /// Tác giả hoặc chủ nhóm xoá khoảnh khắc.
  Future<void> deleteMoment(String groupId, String momentId) => _db.doc('groups/$groupId/moments/$momentId').delete();

  /// Có được xoá nội dung của [authorUid] không: của mình, hoặc mình là chủ nhóm.
  static bool canDelete({required String? myUid, required String authorUid, bool isGroupOwner = false}) =>
      myUid != null && (authorUid == myUid || isGroupOwner);
}
