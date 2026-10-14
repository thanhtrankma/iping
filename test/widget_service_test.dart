import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/services/widget_service.dart';
import 'package:latlong2/latlong.dart';

MemberLocation loc(String uid, double lat, double lng, {bool sharing = true, DateTime? at}) => MemberLocation(
      uid: uid,
      name: uid.toUpperCase(),
      lat: lat,
      lng: lng,
      accuracy: 10,
      battery: 80,
      sharing: sharing,
      updatedAt: at ?? DateTime(2026, 1, 1, 12),
    );

void main() {
  final group = Group(
    id: 'g',
    name: 'Gia đình',
    ownerId: 'me',
    inviteCode: 'ABC234',
    memberIds: const ['a', 'b', 'me', 'c', 'd', 'e'],
    memberNames: const {'me': 'Tôi', 'a': 'An', 'b': 'Bình', 'c': 'Chi', 'd': 'Dũng', 'e': 'Em'},
  );
  final home = Place(id: 'p', name: 'Nhà', lat: 21.0, lng: 105.8, radius: 150);

  test('tối đa 4 người, bạn đứng đầu, rồi người cập nhật gần nhất', () {
    final members = buildWidgetMembers(
      group: group,
      locations: [
        loc('me', 21.0, 105.8),
        loc('a', 21.0, 105.8, at: DateTime(2026, 1, 1, 8)),
        loc('b', 21.0, 105.8, at: DateTime(2026, 1, 1, 11)),
        loc('c', 21.0, 105.8, at: DateTime(2026, 1, 1, 10)),
      ],
      places: const [],
      myUid: 'me',
    );
    expect(members, hasLength(4));
    // Tên lấy từ memberNames của nhóm (server đồng bộ), không phải tên lưu kèm vị trí.
    expect(members.map((m) => m.name), ['Tôi (Bạn)', 'Bình', 'Chi', 'An']);
  });

  test('trạng thái: ở địa điểm, khoảng cách, chưa chia sẻ, tắt chia sẻ', () {
    final g = Group(
      id: 'g',
      name: 'Nhóm',
      ownerId: 'me',
      inviteCode: 'ABC234',
      memberIds: const ['me', 'a', 'b', 'c'],
      memberNames: const {'c': 'Chi'},
    );
    final members = buildWidgetMembers(
      group: g,
      locations: [
        loc('me', 21.0, 105.8),
        loc('a', 21.0, 105.8, at: DateTime(2026, 1, 1, 11)),
        loc('b', 21.02, 105.8, at: DateTime(2026, 1, 1, 10)),
      ],
      places: [home],
      myUid: 'me',
      me: const LatLng(21.0, 105.8),
    );
    final byName = {for (final m in members) m.name: m};
    expect(byName['A']!.status, 'Ở Nhà');
    expect(byName['A']!.at, isNotNull);
    expect(byName['B']!.status, 'Cách 2,2 km');
    expect(byName['B']!.at, isNull);
    expect(byName['Chi']!.status, 'Chưa chia sẻ vị trí');
    expect(byName['Chi']!.initial, 'C');
  });

  test('thành viên tắt chia sẻ', () {
    final members = buildWidgetMembers(
      group: group,
      locations: [loc('a', 21.0, 105.8, sharing: false)],
      places: const [],
      myUid: 'me',
    );
    expect(members.firstWhere((m) => m.name == 'An').status, 'Đã tắt chia sẻ');
  });
}
