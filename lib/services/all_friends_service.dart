import 'dart:async';

import '../models/models.dart';
import 'group_service.dart';
import 'settings_service.dart';

/// Vị trí đã gộp từ nhiều nhóm, kèm nhóm nguồn của từng thành viên.
class MergedLocations {
  const MergedLocations(this.locations, this.groupOf);
  final List<MemberLocation> locations;

  /// uid -> id nhóm có vị trí mới nhất của người đó.
  final Map<String, String> groupOf;
}

/// Chế độ "Tất cả bạn bè": gộp thành viên và vị trí của mọi nhóm.
class AllFriendsService {
  AllFriendsService._();
  static final instance = AllFriendsService._();

  /// Có đang xem tất cả bạn bè không (mặc định khi có từ 2 nhóm trở lên).
  static bool isAllMode(String? selectedId, List<Group> groups) {
    if (groups.length < 2) return false;
    return selectedId == null || selectedId == SettingsService.allGroups || !groups.any((g) => g.id == selectedId);
  }

  /// Nhóm ảo chứa mọi thành viên (không trùng) của các nhóm.
  static Group virtualGroup(List<Group> groups) {
    final ids = <String>[];
    final names = <String, String>{};
    final photos = <String, String?>{};
    for (final g in groups) {
      for (final uid in g.memberIds) {
        if (!names.containsKey(uid)) ids.add(uid);
        names.putIfAbsent(uid, () => g.nameOf(uid));
        if (photos[uid] == null && g.memberPhotos[uid] != null) photos[uid] = g.memberPhotos[uid];
      }
    }
    return Group(
      id: SettingsService.allGroups,
      name: 'Tất cả bạn bè',
      ownerId: '',
      inviteCode: '',
      memberIds: ids,
      memberNames: names,
      memberPhotos: photos,
    );
  }

  static bool isVirtual(Group g) => g.id == SettingsService.allGroups;

  /// Gộp vị trí theo uid, giữ bản mới nhất (theo `updatedAt`).
  static MergedLocations merge(Map<String, List<MemberLocation>> byGroup) {
    final best = <String, MemberLocation>{};
    final groupOf = <String, String>{};
    for (final e in byGroup.entries) {
      for (final l in e.value) {
        final cur = best[l.uid];
        if (cur == null || _newer(l, cur)) {
          best[l.uid] = l;
          groupOf[l.uid] = e.key;
        }
      }
    }
    return MergedLocations(best.values.toList(), groupOf);
  }

  static bool _newer(MemberLocation a, MemberLocation b) {
    final ta = a.updatedAt, tb = b.updatedAt;
    if (ta == null) return false;
    return tb == null || ta.isAfter(tb);
  }

  /// Nhóm dùng để mở chi tiết một thành viên.
  static String? groupFor(String uid, List<Group> groups, [Map<String, String> groupOf = const {}]) =>
      groupOf[uid] ?? groups.where((g) => g.memberIds.contains(uid)).firstOrNull?.id;

  /// Lắng nghe vị trí của mọi nhóm và phát ra bản đã gộp.
  Stream<MergedLocations> watch(List<Group> groups) {
    final latest = <String, List<MemberLocation>>{};
    final subs = <StreamSubscription<List<MemberLocation>>>[];
    late final StreamController<MergedLocations> ctrl;
    ctrl = StreamController<MergedLocations>(
      onListen: () {
        for (final g in groups) {
          subs.add(GroupService.instance.locations(g.id).listen((locs) {
            // Chỉ giữ thành viên hiện tại của nhóm đó.
            latest[g.id] = locs.where((l) => g.memberIds.contains(l.uid)).toList();
            ctrl.add(merge(latest));
          }, onError: ctrl.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return ctrl.stream;
  }
}
