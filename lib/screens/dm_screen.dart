import 'package:flutter/material.dart';

import '../services/dm_service.dart';
import '../services/moderation_service.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'chat_tab.dart';
import 'group_actions.dart';
import 'moderation_sheets.dart';

/// Chat 1-1 với một thành viên.
class DmScreen extends StatefulWidget {
  const DmScreen({super.key, required this.groupId, required this.otherUid, required this.otherName});
  final String groupId;
  final String otherUid;
  final String otherName;

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  late final Future<String> _thread = DmService.instance.ensureThread(widget.otherUid, widget.groupId);

  @override
  void initState() {
    super.initState();
    ModerationService.instance.watch();
  }

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: widget.otherName,
      actions: [
        GlassButton(
          size: 42,
          icon: Icons.more_horiz_rounded,
          tooltip: 'Tuỳ chọn',
          onTap: () async {
            String? dmId;
            try {
              dmId = await _thread;
            } catch (_) {}
            if (!context.mounted) return;
            await showUserModerationSheet(context,
                uid: widget.otherUid, name: widget.otherName, groupId: widget.groupId, dmId: dmId);
          },
        ),
      ],
      child: FutureBuilder<String>(
        future: _thread,
        builder: (context, snap) {
          if (snap.hasError) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Không mở được cuộc trò chuyện',
              text: 'Hai bạn cần cùng ở trong một nhóm.',
            );
          }
          final id = snap.data;
          if (id == null) return const Center(child: CircularProgressIndicator.adaptive());
          return ChatTab.custom(
            messages: DmService.instance.messages(id),
            onSend: (text) => DmService.instance.send(id, text),
            dmId: id,
            otherUid: widget.otherUid,
            otherName: widget.otherName,
          );
        },
      ),
    );
  }
}
