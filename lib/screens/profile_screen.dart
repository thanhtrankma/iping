import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Hiện lựa chọn nguồn ảnh: chụp mới hoặc chọn từ thư viện.
Future<ImageSource?> pickImageSource(BuildContext context, {bool allowRemove = false}) {
  return showModalBottomSheet<ImageSource?>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _user = FirebaseAuth.instance.currentUser!;
  late final _name = TextEditingController(text: _user.displayName ?? '');
  bool _uploading = false;
  bool _savingName = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final source = await pickImageSource(context);
    if (source == null) return;
    final file = await ProfileService.instance.pickImage(source, maxSize: 512);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await ProfileService.instance.updateAvatar(file);
      if (mounted) showMessage(context, 'Đã cập nhật ảnh đại diện');
    } catch (e) {
      if (mounted) showMessage(context, 'Không tải ảnh lên được: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    await ProfileService.instance.removeAvatar();
    if (mounted) showMessage(context, 'Đã xoá ảnh đại diện');
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await ProfileService.instance.updateName(name);
      if (mounted) showMessage(context, 'Đã đổi tên');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Hồ sơ')),
      body: GlassBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 16, 20, 40),
          children: [
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: _uploading ? null : _changePhoto,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(blurRadius: 18, color: Colors.black26, offset: Offset(0, 6))],
                      ),
                      child: MemberAvatar(uid: _user.uid, name: _name.text, radius: 64),
                    ),
                  ),
                  if (_uploading)
                    const Positioned.fill(
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: GlassButton(
                      size: 44,
                      icon: Icons.photo_camera_rounded,
                      color: AppColors.brand,
                      onTap: _uploading ? () {} : _changePhoto,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<Map<String, String>>(
              valueListenable: AvatarRegistry.instance,
              builder: (context, photos, _) => photos[_user.uid] == null
                  ? const SizedBox(height: 8)
                  : Center(
                      child: TextButton(onPressed: _removePhoto, child: const Text('Xoá ảnh đại diện')),
                    ),
            ),
            const SizedBox(height: 16),
            Glass(
              radius: 26,
              opacity: 0.6,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Tên hiển thị', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
                    onSubmitted: (_) => _saveName(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _savingName ? null : _saveName,
                    child: const Text('Lưu tên'),
                  ),
                  const SizedBox(height: 14),
                  Text('Email: ${_user.email ?? ''}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
