import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../utils/format.dart';

/// Một dòng thành viên trên widget màn hình chính.
class WidgetMember {
  const WidgetMember({required this.name, required this.initial, required this.color, required this.status, this.at});

  final String name;
  final String initial;
  final int color;
  final String status;

  /// Mốc thời gian để widget tự ghi "· 5 phút trước" lúc vẽ; null nếu không cần.
  final DateTime? at;

  Map<String, Object?> toJson() =>
      {'name': name, 'initial': initial, 'color': color, 'status': status, 'at': at?.millisecondsSinceEpoch ?? 0};
}

const widgetMaxMembers = 4;

/// Tóm tắt tối đa 4 thành viên: bạn trước, rồi người cập nhật gần nhất.
List<WidgetMember> buildWidgetMembers({
  required Group group,
  required List<MemberLocation> locations,
  required List<Place> places,
  required String myUid,
  LatLng? me,
}) {
  final byUid = {for (final l in locations) l.uid: l};
  final uids = [...group.memberIds]..sort((a, b) {
      if (a == myUid || b == myUid) return a == myUid ? -1 : 1;
      final ta = byUid[a]?.updatedAt, tb = byUid[b]?.updatedAt;
      if (ta == null || tb == null) return ta == null ? (tb == null ? 0 : 1) : -1;
      return tb.compareTo(ta);
    });
  const distance = Distance();

  return [
    for (final uid in uids.take(widgetMaxMembers))
      () {
        final l = byUid[uid];
        // Tên trong nhóm do server đồng bộ khi đổi hồ sơ, mới hơn tên lưu kèm vị trí.
        final name = group.memberNames[uid] ?? l?.name ?? group.nameOf(uid);
        final isMe = uid == myUid;
        String status;
        DateTime? at;
        if (l == null) {
          status = 'Chưa chia sẻ vị trí';
        } else if (!l.sharing) {
          status = 'Đã tắt chia sẻ';
          at = l.updatedAt;
        } else {
          final place = places.where((p) => distance.as(LengthUnit.Meter, l.point, p.point) <= p.radius).firstOrNull;
          if (place != null) {
            status = 'Ở ${place.name}';
            at = l.updatedAt;
          } else if (!isMe && me != null) {
            status = 'Cách ${distanceLabel(distance.as(LengthUnit.Meter, me, l.point)).replaceAll('.', ',')}';
          } else {
            status = 'Đang chia sẻ vị trí';
            at = l.updatedAt;
          }
        }
        return WidgetMember(
          name: isMe ? '$name (Bạn)' : name,
          initial: initial(name),
          color: avatarColor(uid).toARGB32(),
          status: status,
          at: at,
        );
      }(),
  ];
}

/// Đẩy dữ liệu nhóm đang chọn sang widget Android, tối đa 30 giây một lần.
class WidgetService {
  WidgetService._();
  static final instance = WidgetService._();

  static const _androidProvider = 'com.iping.app.MembersWidgetProvider';
  static const _minInterval = Duration(seconds: 30);

  DateTime? _lastPush;
  Timer? _timer;
  String? _lastPayload;
  String? _pending;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void update({
    required Group group,
    required List<MemberLocation> locations,
    required List<Place> places,
    required String myUid,
    LatLng? me,
  }) {
    if (!_supported) return;
    final members = buildWidgetMembers(group: group, locations: locations, places: places, myUid: myUid, me: me);
    final payload = jsonEncode({
      'group': group.name,
      'members': [for (final m in members) m.toJson()]
    });
    if (payload == _lastPayload) return;
    _pending = payload;

    final last = _lastPush;
    final wait = last == null ? Duration.zero : _minInterval - DateTime.now().difference(last);
    if (wait <= Duration.zero) {
      _flush();
    } else {
      // Gom các lần cập nhật dồn dập, đẩy bản mới nhất khi hết 30 giây.
      _timer ??= Timer(wait, _flush);
    }
  }

  /// Xoá dữ liệu trên widget khi đăng xuất, để người khác cầm máy không thấy vị trí của nhóm.
  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _lastPayload = null;
    _lastPush = null;
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>('summary', null);
      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
    } catch (e) {
      debugPrint('Không xoá được widget: $e');
    }
  }

  Future<void> _flush() async {
    _timer?.cancel();
    _timer = null;
    final payload = _pending;
    if (payload == null) return;
    _pending = null;
    _lastPush = DateTime.now();
    _lastPayload = payload;
    try {
      await HomeWidget.saveWidgetData<String>('summary', payload);
      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
    } catch (e) {
      debugPrint('Không cập nhật được widget: $e');
    }
  }
}
