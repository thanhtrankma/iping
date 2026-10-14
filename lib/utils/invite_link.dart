/// Link mời dạng scheme riêng (chưa có tên miền): iping://join?code=XXXXXX.
const inviteScheme = 'iping';
const inviteHost = 'join';

final _bareCode = RegExp(r'^[A-Z0-9]{6}$');

String inviteLink(String code) => '$inviteScheme://$inviteHost?code=${code.toUpperCase()}';

/// Tin nhắn chia sẻ: kèm cả mã để người chưa cài app vẫn dùng được.
String inviteMessage(String groupName, String code) =>
    'Tham gia nhóm "$groupName" trên IPing để cùng chia sẻ vị trí!\n'
    'Mở link: ${inviteLink(code)}\n'
    'Hoặc mở IPing, chọn "Tham gia bằng mã mời" và nhập mã: ${code.toUpperCase()}';

/// Lấy mã mời từ link iping://join?code=… hoặc từ mã 6 ký tự trần. Trả về null nếu không hợp lệ.
String? parseInviteCode(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;

  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme.isNotEmpty) {
    if (uri.scheme.toLowerCase() != inviteScheme || uri.host.toLowerCase() != inviteHost) return null;
    return _normalize(uri.queryParameters['code']);
  }
  return _normalize(text.replaceAll(RegExp(r'[\s-]'), ''));
}

/// Mã có trong link mời (nếu có) — để nhận link nằm giữa một đoạn tin nhắn dán vào.
String? findInviteCode(String text) {
  final direct = parseInviteCode(text);
  if (direct != null) return direct;
  final m = RegExp(r'iping://join\S*', caseSensitive: false).firstMatch(text);
  return m == null ? null : parseInviteCode(m.group(0));
}

String? _normalize(String? code) {
  final c = code?.trim().toUpperCase();
  return c != null && _bareCode.hasMatch(c) ? c : null;
}
