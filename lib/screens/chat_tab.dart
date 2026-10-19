import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/content_filter.dart';
import '../services/group_service.dart';
import '../services/moderation_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'moderation_sheets.dart';

/// Kiểm tra văn bản trước khi gửi (tin nhắn nhóm, tin 1-1, chú thích khoảnh khắc).
///
/// Văn bản sạch → trả về nguyên văn. Có từ không phù hợp → hỏi "Sửa lại" (mặc định, trả về null)
/// hoặc "Vẫn gửi" (trả về bản đã che "***").
Future<String?> checkOutgoingText(BuildContext context, String text) async {
  if (!ContentFilter.isFlagged(text)) return text;
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: const Text(
        'Tin nhắn có từ ngữ không phù hợp',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      ),
      content: const Text(
        'Hãy giữ IPing thân thiện với cả gia đình. Nếu vẫn gửi, những từ này sẽ được che bằng ***.',
        textAlign: TextAlign.center,
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              autofocus: true,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Sửa lại'),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vẫn gửi (sẽ được che)'),
            ),
          ],
        ),
      ],
    ),
  );
  return send == true ? ContentFilter.mask(text) : null;
}

/// Chiều cao ước tính của thanh soạn tin nổi (để chừa chỗ cho danh sách).
const double _composerHeight = 64;

class ChatTab extends StatefulWidget {
  /// Chat nhóm.
  const ChatTab({super.key, required Group this.group})
      : messages = null,
        onSend = null,
        dmId = null,
        otherUid = null,
        otherName = null;

  /// Chat với nguồn tin nhắn tuỳ chọn (vd. chat 1-1).
  /// Với chat 1-1, truyền [dmId] / [otherUid] để xoá, báo cáo và chặn.
  const ChatTab.custom({
    super.key,
    required Stream<List<ChatMessage>> this.messages,
    required this.onSend,
    this.dmId,
    this.otherUid,
    this.otherName,
  }) : group = null;

  final Group? group;
  final Stream<List<ChatMessage>>? messages;
  final Future<void> Function(String text)? onSend;

  /// Id cuộc trò chuyện 1-1 (`dms/{dmId}`), nếu đây là chat 1-1.
  final String? dmId;

  /// Người còn lại trong chat 1-1: khi đã chặn, ô soạn tin được thay bằng thông báo.
  final String? otherUid;
  final String? otherName;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  late final Stream<List<ChatMessage>> _messages = widget.messages ?? GroupService.instance.messages(widget.group!.id);
  final _input = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    ModerationService.instance.watch();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;
    final text = await checkOutgoingText(context, raw);
    // "Sửa lại": giữ nguyên ô soạn tin để người dùng sửa.
    if (text == null || !mounted) return;
    _input.clear();
    final send = widget.onSend;
    try {
      if (send != null) {
        await send(text);
      } else {
        await GroupService.instance.sendMessage(widget.group!.id, text);
      }
    } catch (_) {
      if (!mounted) return;
      if (_input.text.isEmpty) _input.text = text;
      showMessage(context, 'Không gửi được tin nhắn. Có thể người này không nhận tin nhắn từ bạn.');
    }
  }

  /// Nhấn giữ một bong bóng: Sao chép · Xoá · Báo cáo · Chặn.
  Future<void> _onLongPress(ChatMessage m) async {
    final mine = m.uid == _uid;
    final group = widget.group;
    final canDelete = ModerationService.canDelete(
      myUid: _uid,
      authorUid: m.uid,
      isGroupOwner: group != null && group.isOwner(_uid),
    );
    final action = await showContentActions(context, canDelete: canDelete, isMine: mine, deleteLabel: 'Xoá tin nhắn');
    if (action == null || !mounted) return;
    switch (action) {
      case ContentAction.copy:
        await copyText(context, ContentFilter.mask(m.text));
      case ContentAction.delete:
        if (!await confirmDelete(context, title: 'Xoá tin nhắn?', content: 'Tin nhắn sẽ bị xoá với mọi người.')) {
          return;
        }
        try {
          if (group != null) {
            await ModerationService.instance.deleteGroupMessage(group.id, m.id);
          } else if (widget.dmId != null) {
            await ModerationService.instance.deleteDmMessage(widget.dmId!, m.id);
          }
        } catch (e) {
          if (mounted) showMessage(context, 'Không xoá được tin nhắn: $e');
        }
      case ContentAction.report:
        await showReportSheet(
          context,
          kind: group != null ? ReportKind.message : ReportKind.dm,
          targetUid: m.uid,
          targetName: m.name,
          groupId: group?.id,
          dmId: widget.dmId,
          targetId: m.id,
          text: m.text,
        );
      case ContentAction.block:
        await blockUser(context, uid: m.uid, name: m.name);
    }
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
                return ValueListenableBuilder<Set<String>>(
                  valueListenable: ModerationService.instance.blocked,
                  builder: (context, blocked, _) => ListView.builder(
                    reverse: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(12, topInset, 12, bottomInset),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final m = msgs[i];
                      // Danh sách đảo ngược: i+1 là tin nhắn trước đó.
                      final firstOfRun = i == msgs.length - 1 || msgs[i + 1].uid != m.uid;
                      final lastOfRun = i == 0 || msgs[i - 1].uid != m.uid;
                      if (m.uid != _uid && blocked.contains(m.uid)) {
                        // Gộp cả chuỗi tin của người đã chặn thành một dòng.
                        return lastOfRun ? const _BlockedPlaceholder() : const SizedBox.shrink();
                      }
                      return _Bubble(
                        message: m,
                        mine: m.uid == _uid,
                        firstOfRun: firstOfRun,
                        lastOfRun: lastOfRun,
                        onLongPress: () => _onLongPress(m),
                      );
                    },
                  ),
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
                child: widget.otherUid == null
                    ? _Composer(controller: _input, onSend: _send)
                    : ValueListenableBuilder<Set<String>>(
                        valueListenable: ModerationService.instance.blocked,
                        builder: (context, blocked, _) => blocked.contains(widget.otherUid)
                            ? _BlockedBar(
                                onUnblock: () =>
                                    unblockUser(context, uid: widget.otherUid!, name: widget.otherName ?? 'người này'),
                              )
                            : _Composer(controller: _input, onSend: _send, hint: 'Nhắn tin...'),
                      ),
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
    this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final bool firstOfRun;
  final bool lastOfRun;
  final VoidCallback? onLongPress;

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
                      ContentFilter.mask(m.name),
                      style: TextStyle(fontWeight: FontWeight.w600, color: avatarColor(m.uid), fontSize: 12),
                    ),
                  ),
                GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
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
                            // Che khi hiển thị: lọc cả tin cũ gửi trước khi có bộ lọc.
                            ContentFilter.mask(m.text),
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
                            color:
                                mine ? Colors.white.withValues(alpha: 0.7) : scheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
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

/// Một dòng thu gọn thay cho tin nhắn của người đã chặn.
class _BlockedPlaceholder extends StatelessWidget {
  const _BlockedPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const SizedBox(width: 38),
          Icon(Icons.block_rounded, size: 14, color: scheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Text('Tin nhắn từ người bạn đã chặn',
              style: TextStyle(
                  fontSize: 13, fontStyle: FontStyle.italic, color: scheme.onSurface.withValues(alpha: 0.45))),
        ],
      ),
    );
  }
}

/// Thay ô soạn tin khi đã chặn người còn lại trong chat 1-1.
class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.onUnblock});
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      radius: 26,
      opacity: 0.7,
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: [
          Icon(Icons.block_rounded, size: 18, color: scheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Bạn đã chặn người này',
                style: TextStyle(fontSize: 15, color: scheme.onSurface.withValues(alpha: 0.7))),
          ),
          TextButton(
            onPressed: onUnblock,
            child: const Text('Bỏ chặn', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Thanh soạn tin nổi kiểu iOS 26 Messages: một khối kính bo tròn chứa ô nhập
/// và nút gửi tròn ở bên phải.
class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend, this.hint = 'Nhắn cho cả nhóm...'});
  final TextEditingController controller;
  final VoidCallback onSend;
  final String hint;

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
                hintText: hint,
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
