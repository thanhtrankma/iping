import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Người dùng đã đồng ý chia sẻ vị trí với những nhóm nào (theo từng máy, từng tài khoản).
///
/// Chính sách Google Play: vào nhóm bằng mã mời KHÔNG được tự động gửi vị trí cho nhóm đó.
/// [LocationService] chỉ ghi vị trí vào nhóm có trong danh sách này.
/// - Nhóm do mình tạo: đồng ý ngay khi tạo ([grant]).
/// - Nhóm vào bằng mã mời: chỉ đồng ý qua màn xác nhận sau khi nhập mã.
/// - Người dùng cũ (cập nhật app): mọi nhóm đang có được coi là đã đồng ý, giữ nguyên hành vi cũ.
class GroupConsent {
  GroupConsent._();
  static final instance = GroupConsent._();

  /// Khoá "đang bật chia sẻ" của LocationService (bản cũ chia sẻ cho mọi nhóm).
  static const legacySharingKey = 'sharing_enabled';

  /// Định dạng: JSON `{"groups": [gid...], "v": 1}` tại `group_consent_<uid>`.
  static String prefKey(String uid) => 'group_consent_$uid';

  /// Đổi giá trị mỗi khi danh sách thay đổi (để giao diện cập nhật).
  final consented = ValueNotifier<Set<String>>(const {});

  String? _uid;
  bool _loaded = false;

  /// Chưa từng lưu: lần nhận danh sách nhóm đầu tiên sẽ chuyển đổi một lần (xem [load]).
  bool _migrate = false;

  /// Bản cũ đang bật chia sẻ (gửi vị trí cho mọi nhóm): giữ nguyên cho mọi nhóm đang có.
  /// Ngược lại (cài mới, hoặc chưa từng bật) chỉ tự đồng ý nhóm do chính mình tạo — nhóm vào
  /// bằng mã mời luôn phải qua màn xác nhận, kể cả khi danh sách nhóm đầu tiên đã có nó.
  bool _legacySharing = false;

  bool get loaded => _loaded;

  /// Nhóm vừa đồng ý (vd. vừa tạo / vừa vào) nhưng danh sách nhóm chưa kịp có nó:
  /// không được dọn đi chỉ vì một lần cập nhật danh sách cũ đến sau.
  final Set<String> _pendingGrants = {};

  Future<void> load(String uid) async {
    _uid = uid;
    final raw = (await SharedPreferences.getInstance()).getString(prefKey(uid));
    if (raw == null) {
      _migrate = true;
      _legacySharing = (await SharedPreferences.getInstance()).getBool(legacySharingKey) ?? false;
      consented.value = const {};
    } else {
      _migrate = false;
      consented.value = parse(raw);
    }
    _loaded = true;
  }

  /// Gọi mỗi khi danh sách nhóm thay đổi: chuyển đổi cho người dùng cũ, dọn nhóm đã rời.
  Future<void> onGroups(List<Group> groups) async {
    if (!_loaded || _uid == null) return;
    final ids = groups.map((g) => g.id).toSet();
    _pendingGrants.removeAll(ids);
    var next = consented.value;
    if (_migrate) {
      _migrate = false;
      next = {
        ...next,
        for (final g in groups)
          if (_legacySharing || g.ownerId == _uid) g.id,
      };
    } else {
      next = next.where((g) => ids.contains(g) || _pendingGrants.contains(g)).toSet();
      if (next.length == consented.value.length) return;
    }
    await _save(next);
  }

  bool allows(String gid) => consented.value.contains(gid);

  Future<void> grant(String gid) {
    _pendingGrants.add(gid);
    return _save({...consented.value, gid});
  }

  Future<void> revoke(String gid) {
    _pendingGrants.remove(gid);
    return _save({...consented.value}..remove(gid));
  }

  void reset() {
    _uid = null;
    _loaded = false;
    _migrate = false;
    _legacySharing = false;
    _pendingGrants.clear();
    consented.value = const {};
  }

  Future<void> _save(Set<String> next) async {
    consented.value = Set.unmodifiable(next);
    final uid = _uid;
    if (uid == null) return;
    await (await SharedPreferences.getInstance()).setString(prefKey(uid), encode(next));
  }

  @visibleForTesting
  static String encode(Set<String> ids) => jsonEncode({'v': 1, 'groups': ids.toList()..sort()});

  /// Dữ liệu hỏng thì coi như chưa đồng ý nhóm nào (an toàn về quyền riêng tư).
  static Set<String> parse(String raw) {
    try {
      final d = jsonDecode(raw);
      if (d is Map && d['groups'] is List) return Set.unmodifiable((d['groups'] as List).whereType<String>());
    } catch (_) {}
    return const {};
  }
}
