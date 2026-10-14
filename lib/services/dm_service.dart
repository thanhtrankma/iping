import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/models.dart';

/// Chat 1-1 giữa hai thành viên cùng nhóm: `dms/{uidA_uidB}` (uid xếp tăng dần) + `messages`.
class DmService {
  DmService._();
  static final instance = DmService._();

  final _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _name => FirebaseAuth.instance.currentUser?.displayName ?? 'Thành viên';

  /// Id cuộc trò chuyện của hai người, không phụ thuộc ai mở trước.
  static String threadId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  /// Tạo cuộc trò chuyện nếu chưa có. [groupId] là nhóm chung (rules kiểm tra cả hai đều là thành viên).
  Future<String> ensureThread(String otherUid, String groupId) async {
    final id = threadId(_uid, otherUid);
    final ref = _db.doc('dms/$id');
    final snap = await ref.get();
    if (!snap.exists) {
      final members = [_uid, otherUid]..sort();
      await ref.set({'members': members, 'groupId': groupId, 'createdAt': FieldValue.serverTimestamp()});
    } else if (snap.data()?['groupId'] != groupId) {
      // Nhóm cũ có thể không còn chung: chuyển cuộc trò chuyện sang nhóm chung hiện tại.
      try {
        await ref.update({'groupId': groupId});
      } catch (_) {}
    }
    return id;
  }

  Stream<List<ChatMessage>> messages(String id) => _db
      .collection('dms/$id/messages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> send(String id, String text) async {
    final batch = _db.batch();
    batch.set(_db.collection('dms/$id/messages').doc(), {
      'uid': _uid,
      'name': _name,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.doc('dms/$id'), {'lastText': text, 'lastUid': _uid, 'lastAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }
}
