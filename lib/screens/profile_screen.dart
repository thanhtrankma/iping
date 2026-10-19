import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'account_dialogs.dart';

/// Hiện lựa chọn nguồn ảnh: chụp mới hoặc chọn từ thư viện. [title]: tiêu đề sheet
/// (mặc định "Ảnh đại diện"; nơi khác như Khoảnh khắc truyền tiêu đề riêng).
Future<ImageSource?> pickImageSource(BuildContext context, {bool allowRemove = false, String title = 'Ảnh đại diện'}) {
  return showGlassSheet<ImageSource?>(
    context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3),
              ),
            ),
            _SheetGroup(children: [
              ListTile(
                horizontalTitleGap: 14,
                leading: const GlassIconBadge(icon: Icons.photo_camera_rounded, color: AppColors.gray),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                horizontalTitleGap: 14,
                leading: const GlassIconBadge(icon: Icons.photo_library_rounded, color: AppColors.brand),
                title: const Text('Chọn từ thư viện'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ]),
            const SizedBox(height: 10),
            _SheetGroup(children: [
              ListTile(
                title: Text(
                  'Huỷ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
            ]),
          ],
        ),
      );
    },
  );
}

/// Nhóm dòng bên trong sheet kính: nền mờ nhẹ (không lồng kính trong kính), góc bo đồng tâm.
class _SheetGroup extends StatelessWidget {
  const _SheetGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final shape = glassShape(radius: 26);
    return Material(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.55),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 0.5, thickness: 0.5, indent: 60, color: scheme.onSurface.withValues(alpha: 0.12)),
            children[i],
          ],
        ],
      ),
    );
  }
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
    if (source == null || !mounted) return;
    final file = await ProfileService.instance.pickImage(source, maxSize: 512);
    if (file == null || !mounted) return;
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
    try {
      await ProfileService.instance.removeAvatar();
      if (mounted) showMessage(context, 'Đã xoá ảnh đại diện');
    } catch (e) {
      if (mounted) showMessage(context, 'Không xoá được ảnh: $e');
    }
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await ProfileService.instance.updateName(name);
      if (mounted) showMessage(context, 'Đã đổi tên');
    } catch (e) {
      if (mounted) showMessage(context, 'Không lưu được tên: $e');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Hồ sơ'),
      body: GlassBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, MediaQuery.paddingOf(context).top + 60 + 20, 0, 40),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _uploading ? null : _changePhoto,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.9),
                        boxShadow: [
                          BoxShadow(color: AppColors.brand.withValues(alpha: 0.28), blurRadius: 36, spreadRadius: 2),
                          const BoxShadow(blurRadius: 16, color: Colors.black26, offset: Offset(0, 6)),
                        ],
                      ),
                      child: MemberAvatar(uid: _user.uid, name: _name.text, radius: 64),
                    ),
                  ),
                  if (_uploading)
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.3)),
                        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 2,
                    child: GlassButton(
                      size: 44,
                      icon: Icons.photo_camera_rounded,
                      tint: AppColors.brand,
                      tooltip: 'Đổi ảnh đại diện',
                      onTap: _uploading ? () {} : _changePhoto,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _name,
              builder: (context, v, _) => Text(
                v.text.trim().isEmpty ? ' ' : v.text.trim(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(_user.email ?? _user.phoneNumber ?? '',
                textAlign: TextAlign.center, style: TextStyle(color: secondary, fontSize: 15)),
            ValueListenableBuilder<Map<String, String>>(
              valueListenable: AvatarRegistry.instance,
              builder: (context, photos, _) => photos[_user.uid] == null
                  ? const SizedBox(height: 20)
                  : Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Center(
                        child: TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppColors.sos),
                          onPressed: _removePhoto,
                          child: const Text('Xoá ảnh đại diện'),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            GlassSection(
              header: 'Tên hiển thị',
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.2),
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Tên hiển thị',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 10, right: 12),
                        child: GlassIconBadge(icon: Icons.person_rounded, color: AppColors.brand),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _name,
                        builder: (context, v, _) => v.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                icon: Icon(Icons.cancel_rounded, size: 20, color: scheme.onSurface.withValues(alpha: 0.3)),
                                onPressed: _name.clear,
                              ),
                      ),
                    ),
                    onSubmitted: (_) => _saveName(),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: FilledButton(
                onPressed: _savingName ? null : _saveName,
                child: _savingName
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Lưu tên'),
              ),
            ),
            GlassSection(
              header: 'Tài khoản',
              dividerIndent: 60,
              children: [
                ListTile(
                  horizontalTitleGap: 14,
                  leading: GlassIconBadge(
                      icon: _user.email != null ? Icons.mail_rounded : Icons.phone_rounded, color: AppColors.teal),
                  title: Text(_user.email != null ? 'Email' : 'Số điện thoại'),
                  trailing: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                    child: Text(
                      _user.email ?? _user.phoneNumber ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 15),
                    ),
                  ),
                ),
                ListTile(
                  horizontalTitleGap: 14,
                  leading: const GlassIconBadge(icon: Icons.delete_forever_rounded, color: AppColors.sos),
                  title: const Text('Xoá tài khoản', style: TextStyle(color: AppColors.sos)),
                  onTap: () => confirmDeleteAccount(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
