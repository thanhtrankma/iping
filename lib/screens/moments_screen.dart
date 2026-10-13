import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Khoảnh khắc')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ComposeMomentScreen(group: widget.group),
        )),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Đăng khoảnh khắc', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GlassBackground(
        child: StreamBuilder<List<Moment>>(
          stream: _moments,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Lỗi: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final moments = snap.data!;
            if (moments.isEmpty) {
              return const EmptyState(
                icon: Icons.auto_awesome_rounded,
                title: 'Chưa có khoảnh khắc nào',
                text: 'Chia sẻ một bức ảnh hay một dòng trạng thái.\nKhoảnh khắc tự ẩn sau 24 giờ.',
              );
            }
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 16, 110),
              itemCount: moments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) => MomentCard(groupId: widget.group.id, moment: moments[i]),
            );
          },
        ),
      ),
    );
  }
}

class MomentCard extends StatelessWidget {
  const MomentCard({super.key, required this.groupId, required this.moment});
  final String groupId;
  final Moment moment;

  @override
  Widget build(BuildContext context) {
    final m = moment;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final liked = m.likes.contains(me);
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      radius: 28,
      opacity: 0.65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
            child: Row(
              children: [
                MemberAvatar(uid: m.uid, name: m.name, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Row(
                        children: [
                          Text(timeAgo(m.createdAt),
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                          if (m.hasLocation) ...[
                            Text(' · ', style: TextStyle(color: scheme.onSurfaceVariant)),
                            Icon(Icons.place_rounded, size: 13, color: scheme.onSurfaceVariant),
                            Flexible(
                              child: AddressText(m.lat!, m.lng!,
                                  short: true,
                                  maxLines: 1,
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (m.uid == me)
                  IconButton(
                    tooltip: 'Xoá',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => GroupService.instance.deleteMoment(groupId, m.id),
                  ),
              ],
            ),
          ),
          if (m.photoUrl != null)
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _PhotoViewer(url: m.photoUrl!),
              )),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: CachedNetworkImage(
                  imageUrl: m.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.black12),
                ),
              ),
            ),
          if (m.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(m.text,
                  style: TextStyle(fontSize: m.photoUrl == null ? 20 : 15, fontWeight: m.photoUrl == null ? FontWeight.w700 : null)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 16, 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: liked ? AppColors.sos : null),
                  onPressed: () => GroupService.instance.toggleLike(groupId, m),
                ),
                Text(m.likes.isEmpty ? 'Thả tim' : '${m.likes.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
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
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: InteractiveViewer(child: Center(child: CachedNetworkImage(imageUrl: url))),
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
    final source = await pickImageSource(context);
    if (source == null) return;
    final f = await ProfileService.instance.pickImage(source);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty && _photo == null) {
      showMessage(context, 'Hãy viết gì đó hoặc chọn một bức ảnh');
      return;
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Khoảnh khắc mới'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              onPressed: _posting ? null : _post,
              child: _posting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Đăng'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(uid: uid, name: FirebaseAuth.instance.currentUser?.displayName ?? '', radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: 'Bạn đang làm gì ở ${widget.group.name}?'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_photo != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image(image: FileImage(File(_photo!.path)), fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GlassButton(size: 40, icon: Icons.close_rounded, onTap: () => setState(() => _photo = null)),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(120),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Thêm ảnh'),
              onPressed: _pick,
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.place_rounded, color: AppColors.brand),
            title: const Text('Gắn vị trí hiện tại'),
            subtitle: const Text('Khoảnh khắc sẽ hiện trên bản đồ của nhóm'),
            value: _withLocation,
            onChanged: (v) => setState(() => _withLocation = v),
          ),
          const SizedBox(height: 4),
          Text('Chỉ thành viên "${widget.group.name}" thấy được. Tự ẩn sau 24 giờ.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
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
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: m.photoUrl != null
                ? CachedNetworkImage(imageUrl: m.photoUrl!, fit: BoxFit.cover)
                : Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    child: Text(
                      m.text,
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
