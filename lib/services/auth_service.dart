import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'location_service.dart';
import 'notification_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<User?> authChanges() => _auth.authStateChanges();
  User? get user => _auth.currentUser;
  String get displayName => user?.displayName ?? 'Thành viên';

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> register(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await cred.user!.updateDisplayName(name);
    await _db.doc('users/${cred.user!.uid}').set({
      'name': name,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    final uid = user?.uid;
    if (uid != null) {
      // Dừng chia sẻ và gỡ token push trước khi mất quyền ghi.
      await LocationService.instance.stop();
      await LocationService.instance.dispose();
      await NotificationService.instance.unregister(uid);
    }
    await _auth.signOut();
  }
}
