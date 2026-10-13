import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _messages,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final msgs = snap.data!;
              if (msgs.isEmpty) {
                return const EmptyState(
                  icon: Icons.forum_rounded,
                  title: 'Chưa có tin nhắn',
                  text: 'Gửi lời chào đến cả nhóm nhé!',
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final m = msgs[i];
                  final mine = m.uid == _uid;
                  // Danh sách đảo ngược: i+1 là tin nhắn trước đó.
                  final firstOfRun = i == msgs.length - 1 || msgs[i + 1].uid != m.uid;
                  final lastOfRun = i == 0 || msgs[i - 1].uid != m.uid;
                  return Padding(
                    padding: EdgeInsets.only(top: firstOfRun ? 10 : 2),
                    child: Row(
                      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!mine)
                          SizedBox(
                            width: 36,
                            child: lastOfRun ? MemberAvatar(uid: m.uid, name: m.name, radius: 15) : null,
                          ),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              gradient: mine ? AppColors.brandGradient : null,
                              color: mine ? null : Theme.of(context).cardTheme.color,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(mine || !lastOfRun ? 18 : 4),
                                bottomRight: Radius.circular(!mine || !lastOfRun ? 18 : 4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!mine && firstOfRun)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(m.name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: avatarColor(m.uid),
                                            fontSize: 12)),
                                  ),
                                Text(m.text,
                                    style: TextStyle(
                                        color: mine ? Colors.white : scheme.onSurface, fontSize: 15, height: 1.3)),
                                const SizedBox(height: 2),
                                Text(clock(m.createdAt),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: mine ? Colors.white70 : scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          color: Theme.of(context).cardTheme.color,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Nhắn cho cả nhóm...',
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      fixedSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
