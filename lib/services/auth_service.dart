import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'explore_service.dart';
import 'location_service.dart';
import 'notification_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  // Phải trùng region trong functions/index.js.
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  Future<void>? _googleInit;

  Stream<User?> authChanges() => _auth.authStateChanges();
  User? get user => _auth.currentUser;
  String get displayName => user?.displayName ?? 'Thành viên';

  /// Người dùng chưa có tên hiển thị (ví dụ vừa đăng nhập bằng số điện thoại).
  bool get needsName => (user?.displayName ?? '').trim().isEmpty;

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

  Future<void> sendPasswordReset(String email) {
    _auth.setLanguageCode('vi');
    return _auth.sendPasswordResetEmail(email: email);
  }

  // ---- Google ----

  /// Trả về `false` nếu người dùng tự huỷ.
  Future<bool> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    await _initGoogle();
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
    final u = cred.user!;
    await _ensureProfile(
      u,
      isNew: cred.additionalUserInfo?.isNewUser ?? false,
      name: u.displayName ?? account.displayName,
      photoUrl: u.photoURL ?? account.photoUrl,
    );
    return true;
  }

  // ---- Số điện thoại ----

  /// Gửi mã OTP. [onAutoVerified] được gọi khi Android tự đọc được mã và đã đăng nhập xong.
  Future<void> sendPhoneCode(
    String phone, {
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
    required VoidCallback onAutoVerified,
  }) {
    _auth.setLanguageCode('vi');
    return _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          if (await signInWithPhoneCredential(credential)) onAutoVerified();
        } on FirebaseAuthException catch (e) {
          onError(e);
        }
      },
      verificationFailed: onError,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<bool> verifyPhoneCode(String verificationId, String code) => signInWithPhoneCredential(
        PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code),
      );

  /// Trả về `false` nếu đã đăng nhập từ trước (tránh đăng nhập hai lần khi vừa tự xác minh vừa nhập tay).
  Future<bool> signInWithPhoneCredential(PhoneAuthCredential credential) async {
    if (user != null) return false;
    final cred = await _auth.signInWithCredential(credential);
    final u = cred.user!;
    await _ensureProfile(u, isNew: cred.additionalUserInfo?.isNewUser ?? false, name: u.displayName);
    return true;
  }

  /// Lưu tên cho người dùng mới (đăng nhập bằng số điện thoại).
  Future<void> setInitialName(String name) async {
    final u = user!;
    await u.updateDisplayName(name);
    await _db.doc('users/${u.uid}').set({'name': name}, SetOptions(merge: true));
  }

  /// Tạo hoặc bổ sung `users/{uid}` ở lần đăng nhập đầu, giống [register].
  Future<void> _ensureProfile(User u, {required bool isNew, String? name, String? photoUrl}) async {
    final ref = _db.doc('users/${u.uid}');
    if (!isNew && (await ref.get()).data()?['createdAt'] != null) return;
    await ref.set({
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (u.email != null) 'email': u.email,
      if (u.phoneNumber != null) 'phone': u.phoneNumber,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---- Đăng xuất / xoá tài khoản ----

  /// Dừng chia sẻ và gỡ token push trước khi mất quyền ghi.
  Future<void> _stopServices(String uid) async {
    await LocationService.instance.stop();
    await LocationService.instance.dispose();
    await ExploreService.instance.dispose();
    await NotificationService.instance.unregister(uid);
  }

  Future<void> signOut() async {
    final uid = user?.uid;
    if (uid != null) await _stopServices(uid);
    await _signOutGoogle();
    await _auth.signOut();
  }

  /// Xoá vĩnh viễn tài khoản qua Cloud Function `deleteAccount` rồi đăng xuất.
  Future<void> deleteAccount() async {
    final uid = user!.uid;
    await _stopServices(uid);
    try {
      await _fn
          .httpsCallable('deleteAccount', options: HttpsCallableOptions(timeout: const Duration(minutes: 5)))
          .call();
    } catch (_) {
      // Xoá thất bại: bật lại các service để app vẫn dùng được.
      LocationService.instance.init(uid);
      ExploreService.instance.init(uid);
      NotificationService.instance.init(uid);
      rethrow;
    }
    await _signOutGoogle();
    await _auth.signOut();
  }

  /// `initialize` chỉ được gọi một lần; nếu lỗi thì lần sau thử lại.
  Future<void> _initGoogle() async {
    try {
      await (_googleInit ??= GoogleSignIn.instance.initialize());
    } catch (_) {
      _googleInit = null;
      rethrow;
    }
  }

  /// Để lần sau người dùng được chọn lại tài khoản Google.
  Future<void> _signOutGoogle() async {
    if (!(user?.providerData.any((p) => p.providerId == 'google.com') ?? false)) return;
    try {
      await _initGoogle();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Google signOut: $e');
    }
  }
}
