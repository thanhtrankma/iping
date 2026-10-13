import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Chiều cao ước tính của thanh soạn tin nổi (để chừa chỗ cho danh sách).
const double _composerHeight = 64;

class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.group});
  final Group group;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  late final Stream<List<ChatMessage>> _messages = GroupService.instance.messages(widget.group.id);
  final _input = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await GroupService.instance.sendMessage(widget.group.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Nếu trang chủ dùng extendBodyBehindAppBar, padding.top đã gồm cả thanh tiêu đề.
    final topInset = mq.padding.top + 8;
    final bottomInset = mq.padding.bottom + _composerHeight + 16;

    return ColoredBox(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Nội dung cuộn bên dưới thanh tiêu đề và thanh soạn tin nổi.
          Positioned.fill(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Padding(
                    padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                final msgs = snap.data!;
                if (msgs.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                    child: const EmptyState(
                      icon: Icons.forum_rounded,
                      title: 'Chưa có tin nhắn',
                      text: 'Gửi lời chào đến cả nhóm nhé!',
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(12, topInset, 12, bottomInset),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    // Danh sách đảo ngược: i+1 là tin nhắn trước đó.
                    final firstOfRun = i == msgs.length - 1 || msgs[i + 1].uid != m.uid;
                    final lastOfRun = i == 0 || msgs[i - 1].uid != m.uid;
                    return _Bubble(
                      message: m,
                      mine: m.uid == _uid,
                      firstOfRun: firstOfRun,
                      lastOfRun: lastOfRun,
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: _Composer(controller: _input, onSend: _send),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bong bóng tin nhắn kiểu iOS: của mình là gradient thương hiệu, của người khác
/// là mặt nền mờ đặc (không phải kính) để nội dung luôn dễ đọc.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.firstOfRun,
    required this.lastOfRun,
  });

  final ChatMessage message;
  final bool mine;
  final bool firstOfRun;
  final bool lastOfRun;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Phía người gửi: góc nối giữa các tin liên tiếp nhỏ lại, tin cuối có "đuôi".
    const big = Radius.circular(20);
    const joined = Radius.circular(8);
    const tail = Radius.circular(5);
    final sideTop = firstOfRun ? big : joined;
    final sideBottom = lastOfRun ? tail : joined;
    final radius = BorderRadius.only(
      topLeft: mine ? big : sideTop,
      topRight: mine ? sideTop : big,
      bottomLeft: mine ? big : sideBottom,
      bottomRight: mine ? sideBottom : big,
    );
    final otherFill = dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.82);

    return Padding(
      padding: EdgeInsets.only(top: firstOfRun ? 12 : 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 38,
              child: lastOfRun ? MemberAvatar(uid: m.uid, name: m.name, radius: 15) : null,
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine && firstOfRun)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 3),
                    child: Text(
                      m.name,
                      style: TextStyle(fontWeight: FontWeight.w600, color: avatarColor(m.uid), fontSize: 12),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
                  decoration: BoxDecoration(
                    gradient: mine ? AppColors.brandGradient : null,
                    color: mine ? null : otherFill,
                    borderRadius: radius,
                    boxShadow: dark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        child: Text(
                          m.text,
                          style: TextStyle(
                            color: mine ? Colors.white : scheme.onSurface,
                            fontSize: 16,
                            height: 1.3,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        clock(m.createdAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: mine
                              ? Colors.white.withValues(alpha: 0.7)
                              : scheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thanh soạn tin nổi kiểu iOS 26 Messages: một khối kính bo tròn chứa ô nhập
/// và nút gửi tròn ở bên phải.
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const none = OutlineInputBorder(borderSide: BorderSide.none);
    return Glass(
      radius: 26,
      opacity: 0.7,
      padding: const EdgeInsets.fromLTRB(4, 4, 5, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 1000,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(fontSize: 16, letterSpacing: -0.2),
              decoration: InputDecoration(
                hintText: 'Nhắn cho cả nhóm...',
                hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)),
                counterText: '',
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                border: none,
                enabledBorder: none,
                focusedBorder: none,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final active = value.text.trim().isNotEmpty;
              return GlassPressable(
                onTap: onSend,
                shape: const CircleBorder(),
                scale: 0.88,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: active ? AppColors.brandGradient : null,
                    color: active ? null : scheme.onSurface.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 22,
                    color: active ? Colors.white : scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
