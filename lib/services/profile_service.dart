import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';

/// Kho ảnh đại diện theo uid, lấy từ `memberPhotos` của các nhóm.
/// Mọi [MemberAvatar] đọc từ đây nên không cần truyền ảnh qua từng màn hình.
class AvatarRegistry extends ValueNotifier<Map<String, String>> {
  AvatarRegistry._() : super(const {});
  static final instance = AvatarRegistry._();

  void addGroups(List<Group> groups) {
    final next = {...value};
    for (final g in groups) {
      g.memberPhotos.forEach((uid, url) {
        if (url != null && url.isNotEmpty) next[uid] = url;
      });
    }
    if (!mapEquals(next, value)) value = next;
  }

  void set(String uid, String? url) {
    final next = {...value};
    if (url == null) {
      next.remove(uid);
    } else {
      next[uid] = url;
    }
    value = next;
  }
}

class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();

  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;
  final _db = FirebaseFirestore.instance;

  /// Chọn ảnh từ máy hoặc camera, đã thu nhỏ để tiết kiệm dung lượng.
  Future<XFile?> pickImage(ImageSource source, {double maxSize = 1280}) => _picker.pickImage(
        source: source,
        maxWidth: maxSize,
        maxHeight: maxSize,
        imageQuality: 82,
      );

  Future<String> uploadImage(String path, XFile file) async {
    final ref = _storage.ref(path);
    await ref.putFile(File(file.path), SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> updateAvatar(XFile file) async {
    final user = FirebaseAuth.instance.currentUser!;
    final url = await uploadImage('avatars/${user.uid}/avatar.jpg', file);
    await user.updatePhotoURL(url);
    // Cloud Function `onUserProfile` chép ảnh sang các nhóm.
    await _db.doc('users/${user.uid}').set({'photoUrl': url}, SetOptions(merge: true));
    AvatarRegistry.instance.set(user.uid, url);
  }

  Future<void> removeAvatar() async {
    final user = FirebaseAuth.instance.currentUser!;
    await user.updatePhotoURL(null);
    await _db.doc('users/${user.uid}').set({'photoUrl': null}, SetOptions(merge: true));
    AvatarRegistry.instance.set(user.uid, null);
  }

  Future<void> updateName(String name) async {
    final user = FirebaseAuth.instance.currentUser!;
    await user.updateDisplayName(name);
    await _db.doc('users/${user.uid}').set({'name': name}, SetOptions(merge: true));
  }
}
