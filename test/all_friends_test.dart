import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/services/all_friends_service.dart';
import 'package:gan_nhau/services/settings_service.dart';

MemberLocation loc(String uid, double lat, DateTime? at) => MemberLocation(
      uid: uid,
      name: uid,
      lat: lat,
      lng: 0,
      accuracy: 5,
      battery: null,
      sharing: true,
      updatedAt: at,
    );

Group grp(String id, List<String> members) => Group(
      id: id,
      name: id,
      ownerId: members.first,
      inviteCode: 'ABC123',
      memberIds: members,
      memberNames: {for (final m in members) m: 'Tên $m'},
    );

void main() {
  final t0 = DateTime(2026, 1, 1, 10);
  final t1 = t0.add(const Duration(minutes: 5));

  group('merge', () {
    test('gộp theo uid, giữ vị trí mới nhất và nhóm nguồn', () {
      final m = AllFriendsService.merge({
        'g1': [loc('a', 1, t0), loc('b', 2, t1)],
        'g2': [loc('a', 3, t1), loc('b', 4, t0), loc('c', 5, null)],
      });
      final byUid = {for (final l in m.locations) l.uid: l};
      expect(byUid.keys.toSet(), {'a', 'b', 'c'});
      expect(byUid['a']!.lat, 3);
      expect(byUid['b']!.lat, 2);
      expect(m.groupOf, {'a': 'g2', 'b': 'g1', 'c': 'g2'});
    });

    test('vị trí có thời gian thắng vị trí không rõ thời gian', () {
      final m = AllFriendsService.merge({
        'g1': [loc('a', 1, null)],
        'g2': [loc('a', 2, t0)],
      });
      expect(m.locations.single.lat, 2);
      expect(m.groupOf['a'], 'g2');
    });

    test('bằng thời gian thì giữ bản đầu tiên', () {
      final m = AllFriendsService.merge({
        'g1': [loc('a', 1, t0)],
        'g2': [loc('a', 2, t0)],
      });
      expect(m.locations.single.lat, 1);
    });

    test('rỗng', () {
      final m = AllFriendsService.merge({});
      expect(m.locations, isEmpty);
      expect(m.groupOf, isEmpty);
    });
  });

  test('virtualGroup gộp thành viên không trùng', () {
    final v = AllFriendsService.virtualGroup([grp('g1', ['a', 'b']), grp('g2', ['b', 'c'])]);
    expect(v.id, SettingsService.allGroups);
    expect(v.name, 'Tất cả bạn bè');
    expect(v.memberIds, ['a', 'b', 'c']);
    expect(v.nameOf('c'), 'Tên c');
    expect(AllFriendsService.isVirtual(v), isTrue);
  });

  test('isAllMode: mặc định khi có từ 2 nhóm', () {
    final one = [grp('g1', ['a'])];
    final two = [grp('g1', ['a']), grp('g2', ['a'])];
    expect(AllFriendsService.isAllMode(null, one), isFalse);
    expect(AllFriendsService.isAllMode(SettingsService.allGroups, one), isFalse);
    expect(AllFriendsService.isAllMode(null, two), isTrue);
    expect(AllFriendsService.isAllMode(SettingsService.allGroups, two), isTrue);
    expect(AllFriendsService.isAllMode('g2', two), isFalse);
    expect(AllFriendsService.isAllMode('da-roi', two), isTrue);
  });

  test('groupFor ưu tiên nhóm nguồn, rồi nhóm đầu tiên chứa thành viên', () {
    final gs = [grp('g1', ['a']), grp('g2', ['a', 'b'])];
    expect(AllFriendsService.groupFor('a', gs, {'a': 'g2'}), 'g2');
    expect(AllFriendsService.groupFor('a', gs), 'g1');
    expect(AllFriendsService.groupFor('b', gs), 'g2');
    expect(AllFriendsService.groupFor('x', gs), isNull);
  });
}
