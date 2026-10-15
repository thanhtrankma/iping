import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/moderation_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Các thao tác trên một tin nhắn / khoảnh khắc.
enum ContentAction { copy, delete, report, block }

/// Nhóm hàng trong sheet kính (giống bảng thao tác của iOS).
class ModerationSheetGroup extends StatelessWidget {
  const ModerationSheetGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      shape: glassShape(radius: 26),
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

Widget _cancelGroup(BuildContext ctx) {
  final scheme = Theme.of(ctx).colorScheme;
  return ModerationSheetGroup(children: [
    ListTile(
      title: Text('Huỷ',
          textAlign: TextAlign.center, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
      onTap: () => Navigator.pop(ctx),
    ),
  ]);
}

Widget _actionTile(BuildContext ctx, IconData icon, Color color, String label, Object value, {bool danger = false}) =>
    ListTile(
      horizontalTitleGap: 14,
      leading: GlassIconBadge(icon: icon, color: color),
      title: Text(label, style: danger ? const TextStyle(fontWeight: FontWeight.w600, color: AppColors.sos) : null),
      onTap: () => Navigator.pop(ctx, value),
    );

/// Bảng thao tác khi nhấn giữ tin nhắn hoặc chạm "⋯" trên khoảnh khắc.
Future<ContentAction?> showContentActions(
  BuildContext context, {
  bool canCopy = true,
  required bool canDelete,
  required bool isMine,
  String deleteLabel = 'Xoá',
}) {
  return showGlassSheet<ContentAction>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModerationSheetGroup(children: [
            if (canCopy) _actionTile(ctx, Icons.copy_rounded, AppColors.brand, 'Sao chép', ContentAction.copy),
            if (canDelete)
              _actionTile(ctx, Icons.delete_rounded, AppColors.sos, deleteLabel, ContentAction.delete, danger: true),
            if (!isMine) _actionTile(ctx, Icons.flag_rounded, AppColors.orange, 'Báo cáo', ContentAction.report),
            if (!isMine)
              _actionTile(ctx, Icons.block_rounded, AppColors.sos, 'Chặn người này', ContentAction.block, danger: true),
          ]),
          const SizedBox(height: 10),
          _cancelGroup(ctx),
        ],
      ),
    ),
  );
}

/// Hỏi xác nhận xoá. Trả về true nếu đồng ý.
Future<bool> confirmDelete(BuildContext context, {required String title, String? content}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content == null ? null : Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.sos),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Hỏi xác nhận rồi chặn [uid]. Trả về true nếu đã chặn.
Future<bool> blockUser(BuildContext context, {required String uid, required String name}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Chặn $name?'),
      content: Text('Bạn sẽ không còn thấy tin nhắn, tin nhắn riêng và khoảnh khắc của $name. '
          '$name không thể nhắn tin riêng cho bạn. Bạn có thể bỏ chặn trong "Bảo mật & Bạn bè".'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.sos),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Chặn'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return _run(context, () => ModerationService.instance.block(uid), 'Đã chặn $name');
}

Future<bool> unblockUser(BuildContext context, {required String uid, required String name}) =>
    _run(context, () => ModerationService.instance.unblock(uid), 'Đã bỏ chặn $name');

Future<bool> _run(BuildContext context, Future<void> Function() action, String done) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    messenger?.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Có lỗi xảy ra: $e')));
    return false;
  }
}

/// Sao chép văn bản vào bộ nhớ tạm.
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, 'Đã sao chép');
}

/// Bảng "⋯" cho một người dùng: Báo cáo người dùng · Chặn/Bỏ chặn.
Future<void> showUserModerationSheet(
  BuildContext context, {
  required String uid,
  required String name,
  String? groupId,
  String? dmId,
}) async {
  ModerationService.instance.watch();
  final isBlocked = ModerationService.instance.isBlocked(uid);
  final action = await showGlassSheet<String>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: MemberAvatar(uid: uid, name: name, radius: 26)),
          const SizedBox(height: 8),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 14),
          ModerationSheetGroup(children: [
            _actionTile(ctx, Icons.flag_rounded, AppColors.orange, 'Báo cáo người dùng', 'report'),
            isBlocked
                ? _actionTile(ctx, Icons.lock_open_rounded, AppColors.online, 'Bỏ chặn', 'unblock')
                : _actionTile(ctx, Icons.block_rounded, AppColors.sos, 'Chặn người này', 'block', danger: true),
          ]),
          const SizedBox(height: 10),
          _cancelGroup(ctx),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'report':
      await showReportSheet(context,
          kind: ReportKind.user, targetUid: uid, targetName: name, groupId: groupId, dmId: dmId);
    case 'block':
      await blockUser(context, uid: uid, name: name);
    case 'unblock':
      await unblockUser(context, uid: uid, name: name);
  }
}

/// Sheet báo cáo: chọn lý do, ghi chú tuỳ chọn, có thể chặn luôn.
Future<void> showReportSheet(
  BuildContext context, {
  required ReportKind kind,
  required String targetUid,
  required String targetName,
  String? groupId,
  String? dmId,
  String? targetId,
  String? text,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sent = await showGlassSheet<bool>(
    context,
    builder: (ctx) => ReportSheet(
      kind: kind,
      targetName: targetName,
      onSubmit: (reason, note, alsoBlock) async {
        await ModerationService.instance.report(
          kind: kind,
          targetUid: targetUid,
          reason: reason,
          groupId: groupId,
          dmId: dmId,
          targetId: targetId,
          note: note,
          text: text,
        );
        if (alsoBlock) await ModerationService.instance.block(targetUid);
      },
    ),
  );
  if (sent == true) {
    messenger?.showSnackBar(const SnackBar(content: Text('Cảm ơn, chúng tôi sẽ xem xét trong 24 giờ.')));
  }
}

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.kind, required this.targetName, required this.onSubmit});
  final ReportKind kind;
  final String targetName;
  final Future<void> Function(ReportReason reason, String note, bool alsoBlock) onSubmit;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  bool _block = false;
  bool _sending = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSubmit(reason, _note.text, _block);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        showMessage(context, 'Không gửi được báo cáo: $e');
      }
    }
  }

  String get _title => switch (widget.kind) {
        ReportKind.message || ReportKind.dm => 'Báo cáo tin nhắn',
        ReportKind.moment => 'Báo cáo khoảnh khắc',
        ReportKind.user => 'Báo cáo ${widget.targetName}',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(_title, subtitle: 'Báo cáo được gửi ẩn danh tới đội ngũ IPing. Chúng tôi xem xét trong 24 giờ.'),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: ModerationSheetGroup(children: [
                for (final r in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: r,
                    title: Text(r.label),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            ModerationSheetGroup(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  controller: _note,
                  maxLength: ModerationService.maxNote,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Mô tả thêm (không bắt buộc)',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              CheckboxListTile(
                value: _block,
                onChanged: (v) => setState(() => _block = v ?? false),
                title: Text('Chặn ${widget.targetName}'),
                subtitle: Text('Ẩn mọi nội dung của người này với bạn', style: TextStyle(color: secondary)),
              ),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.sos,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              onPressed: _reason == null || _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Gửi báo cáo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
