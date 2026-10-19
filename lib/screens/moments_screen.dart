import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/content_filter.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/moderation_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'chat_tab.dart' show checkOutgoingText;
import 'moderation_sheets.dart';
import 'profile_screen.dart' show pickImageSource;

/// Danh sách khoảnh khắc 24 giờ qua của nhóm.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key, required this.group});
  final Group group;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  late final Stream<List<Moment>> _moments = GroupService.instance.moments(widget.group.id);

  @override
  void initState() {
    super.initState();
    ModerationService.instance.watch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Khoảnh khắc'),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: GlassPill(
        tint: AppColors.brand,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ComposeMomentScreen(group: widget.group),
        )),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Đăng khoảnh khắc',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2)),
          ],
        ),
      ),
      body: GlassBackground(
        child: StreamBuilder<List<Moment>>(
          stream: _moments,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ValueListenableBuilder<Set<String>>(
              valueListenable: ModerationService.instance.blocked,
              builder: (context, blocked, _) => _list(context, snap.data!, blocked),
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<Moment> all, Set<String> blocked) {
    // Ẩn khoảnh khắc của người mình đã chặn.
    final moments = all.where((m) => !blocked.contains(m.uid)).toList();
    if (moments.isEmpty) {
      return const EmptyState(
        icon: Icons.auto_awesome_rounded,
        title: 'Chưa có khoảnh khắc nào',
        text: 'Chia sẻ một bức ảnh hay một dòng trạng thái.\nKhoảnh khắc tự ẩn sau 24 giờ.',
      );
    }
    final mq = MediaQuery.of(context);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, mq.padding.top + 60 + 12, 16, mq.padding.bottom + 110),
      itemCount: moments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) => MomentCard(
        groupId: widget.group.id,
        moment: moments[i],
        isGroupOwner: widget.group.isOwner(FirebaseAuth.instance.currentUser?.uid),
      ),
    );
  }
}

class MomentCard extends StatelessWidget {
  const MomentCard({super.key, required this.groupId, required this.moment, this.isGroupOwner = false});
  final String groupId;
  final Moment moment;

  /// Chủ nhóm được xoá khoảnh khắc của mọi người.
  final bool isGroupOwner;

  /// Menu "⋯": Báo cáo · Chặn người này · Xoá.
  Future<void> _showMenu(BuildContext context, String? me) async {
    final m = moment;
    final action = await showContentActions(
      context,
      canCopy: false,
      canDelete: ModerationService.canDelete(myUid: me, authorUid: m.uid, isGroupOwner: isGroupOwner),
      isMine: m.uid == me,
      deleteLabel: 'Xoá khoảnh khắc',
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case ContentAction.copy:
        break;
      case ContentAction.delete:
        if (!await confirmDelete(context, title: 'Xoá khoảnh khắc?', content: 'Khoảnh khắc sẽ bị xoá với cả nhóm.')) {
          return;
        }
        try {
          await GroupService.instance.deleteMoment(groupId, m.id);
        } catch (e) {
          if (context.mounted) showMessage(context, 'Không xoá được: $e');
        }
      case ContentAction.report:
        await showReportSheet(
          context,
          kind: ReportKind.moment,
          targetUid: m.uid,
          targetName: m.name,
          groupId: groupId,
          targetId: m.id,
          text: m.text,
        );
      case ContentAction.block:
        await blockUser(context, uid: m.uid, name: m.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = moment;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final liked = m.likes.contains(me);
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    // Ảnh lồng trong thẻ: lề 8 px, góc bo đồng tâm (30 - 8 = 22).
    // Ảnh vuông bo góc lớn kiểu Locket.
    final photoShape = glassShape(radius: 34);
    return Glass(
      radius: 30,
      opacity: 0.6,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
              child: Row(
                children: [
                  MemberAvatar(uid: m.uid, name: m.name, radius: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ContentFilter.mask(m.name),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2)),
                        Row(
                          children: [
                            Text(timeAgo(m.createdAt), style: TextStyle(color: secondary, fontSize: 12.5)),
                            if (m.hasLocation) ...[
                              Text(' · ', style: TextStyle(color: secondary, fontSize: 12.5)),
                              Icon(Icons.place_rounded, size: 13, color: secondary),
                              Flexible(
                                child: AddressText(m.lat!, m.lng!,
                                    short: true,
                                    maxLines: 1,
                                    style: TextStyle(color: secondary, fontSize: 12.5)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tuỳ chọn',
                    icon: Icon(Icons.more_horiz_rounded, color: secondary, size: 24),
                    onPressed: () => _showMenu(context, me),
                  ),
                ],
              ),
            ),
            if (m.photoUrl != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GlassPressable(
                  shape: photoShape,
                  scale: 0.98,
                  haptic: false,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _PhotoViewer(url: m.photoUrl!),
                  )),
                  child: ClipPath(
                    clipper: ShapeBorderClipper(shape: photoShape),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: m.photoUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => ColoredBox(color: scheme.onSurface.withValues(alpha: 0.08)),
                          ),
                          if (m.text.isNotEmpty)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 14,
                              child: Center(child: LocketCaption(ContentFilter.mask(m.text))),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (m.text.isNotEmpty && m.photoUrl == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(ContentFilter.mask(m.text),
                    style: TextStyle(
                      fontSize: m.photoUrl == null ? 21 : 15.5,
                      height: 1.3,
                      letterSpacing: m.photoUrl == null ? -0.4 : -0.2,
                      fontWeight: m.photoUrl == null ? FontWeight.w700 : null,
                    )),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 16, 12),
              child: Row(
                children: [
                  _LikeChip(
                    liked: liked,
                    label: m.likes.isEmpty ? 'Thả tim' : '${m.likes.length}',
                    onTap: () => GroupService.instance.toggleLike(groupId, m),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút "thả tim" dạng viên thuốc, có hiệu ứng nảy khi bật.
class _LikeChip extends StatelessWidget {
  const _LikeChip({required this.liked, required this.label, required this.onTap});
  final bool liked;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = liked
        ? AppColors.sos.withValues(alpha: dark ? 0.22 : 0.12)
        : (dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.5));
    return GlassPressable(
      shape: const StadiumBorder(),
      scale: 0.92,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
        decoration: ShapeDecoration(shape: const StadiumBorder(), color: bg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: liked ? 1.15 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 20,
                color: liked ? AppColors.sos : scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: liked ? AppColors.sos : scheme.onSurface,
                )),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(child: Center(child: CachedNetworkImage(imageUrl: url))),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Theme(
                data: ThemeData.dark(useMaterial3: true),
                child: GlassButton(
                  size: 44,
                  icon: Icons.close_rounded,
                  tooltip: 'Đóng',
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ComposeMomentScreen extends StatefulWidget {
  const ComposeMomentScreen({super.key, required this.group});
  final Group group;

  @override
  State<ComposeMomentScreen> createState() => _ComposeMomentScreenState();
}

class _ComposeMomentScreenState extends State<ComposeMomentScreen> {
  final _text = TextEditingController();
  XFile? _photo;
  bool _withLocation = true;
  bool _posting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final source = await pickImageSource(context, title: 'Thêm ảnh');
    if (source == null) return;
    final f = await ProfileService.instance.pickImage(source);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _post() async {
    var text = _text.text.trim();
    if (text.isEmpty && _photo == null) {
      showMessage(context, 'Hãy viết gì đó hoặc chọn một bức ảnh');
      return;
    }
    if (text.isNotEmpty) {
      final checked = await checkOutgoingText(context, text);
      // "Sửa lại": ở lại màn hình soạn.
      if (checked == null || !mounted) return;
      text = checked;
    }
    setState(() => _posting = true);
    try {
      final pos = _withLocation ? await LocationService.instance.currentPosition() : null;
      await GroupService.instance.postMoment(widget.group.id,
          text: text, photo: _photo, lat: pos?.latitude, lng: pos?.longitude);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, 'Không đăng được: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    const none = OutlineInputBorder(borderSide: BorderSide.none);
    final photoShape = glassShape(radius: 40);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: 'Khoảnh khắc mới',
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: GlassButton(
              size: 42,
              icon: Icons.close_rounded,
              tooltip: 'Đóng',
              onTap: () => Navigator.pop(context),
            ),
          ),
        ),
        actions: [
          Center(
            child: GlassPill(
              tint: AppColors.brand,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              onTap: _posting ? () {} : _post,
              child: _posting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Đăng',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
            ),
          ),
        ],
      ),
      body: GlassBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, mq.padding.top + 60 + 12, 16, mq.padding.bottom + 24),
          children: [
            Glass(
              radius: 28,
              opacity: 0.65,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MemberAvatar(uid: uid, name: FirebaseAuth.instance.currentUser?.displayName ?? '', radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      maxLength: 300,
                      minLines: 3,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 17, height: 1.35, letterSpacing: -0.2),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Bạn đang làm gì ở ${widget.group.name}?',
                        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)),
                        filled: false,
                        contentPadding: const EdgeInsets.only(top: 8),
                        border: none,
                        enabledBorder: none,
                        focusedBorder: none,
                        counterStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 11.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_photo != null)
              Stack(
                children: [
                  ClipPath(
                    clipper: ShapeBorderClipper(shape: photoShape),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Image(image: FileImage(File(_photo!.path)), fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GlassButton(size: 40, icon: Icons.close_rounded, onTap: () => setState(() => _photo = null)),
                  ),
                ],
              )
            else
              GlassPressable(
                shape: photoShape,
                scale: 0.97,
                onTap: _pick,
                child: Glass(
                  radius: 40,
                  opacity: 0.5,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const GlassIconBadge(icon: Icons.add_a_photo_rounded, color: AppColors.purple, size: 44),
                        const SizedBox(height: 10),
                        Text('Thêm ảnh',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15.5, color: scheme.onSurface)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            GlassSection(
              margin: EdgeInsets.zero,
              footer: 'Chỉ thành viên "${widget.group.name}" thấy được. Tự ẩn sau 24 giờ.',
              children: [
                SwitchListTile(
                  secondary: const GlassIconBadge(icon: Icons.place_rounded, color: AppColors.brand),
                  title: const Text('Gắn vị trí hiện tại'),
                  subtitle: const Text('Khoảnh khắc sẽ hiện trên bản đồ của nhóm'),
                  value: _withLocation,
                  onChanged: (v) => setState(() => _withLocation = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bong bóng ảnh khoảnh khắc trên bản đồ.
Marker momentMarker(Moment m, VoidCallback onTap) => Marker(
      point: m.point!,
      width: 64,
      height: 64,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: ShapeDecoration(
            gradient: AppColors.brandGradient,
            shape: glassShape(radius: 20),
            shadows: const [BoxShadow(blurRadius: 10, offset: Offset(0, 3), color: Colors.black38)],
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: glassShape(radius: 17)),
            child: m.photoUrl != null
                ? CachedNetworkImage(imageUrl: m.photoUrl!, fit: BoxFit.cover)
                : Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    child: Text(
                      ContentFilter.mask(m.text),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                  ),
          ),
        ),
      ),
    );

/// Chú thích kiểu Locket: viên kính tối nằm trên đáy ảnh vuông.
class LocketCaption extends StatelessWidget {
  const LocketCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Glass(
      capsule: true,
      tint: Colors.black,
      opacity: 0.2,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      ),
    );
  }
}
