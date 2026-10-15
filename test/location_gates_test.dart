import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/services/group_consent.dart';
import 'package:gan_nhau/services/location_gates.dart';
import 'package:shared_preferences/shared_preferences.dart';

Group _g(String id) => Group(
      id: id,
      name: id,
      ownerId: 'o',
      inviteCode: 'ABCDEF',
      memberIds: const ['me'],
      memberNames: const {'me': 'Tôi'},
    );

void main() {
  group('writableGroups', () {
    List<String> run(List<String> ids, {Set<String> allowed = const {}, Set<String> paused = const {}}) =>
        writableGroups(ids, id: (g) => g, allowed: allowed.contains, paused: paused.contains);

    test('chỉ nhóm đã đồng ý và không tạm ẩn', () {
      expect(run(['a', 'b', 'c', 'd'], allowed: {'a', 'b', 'c'}, paused: {'b'}), ['a', 'c']);
    });

    test('chưa đồng ý nhóm nào (vd. vừa vào bằng mã mời) thì không ghi gì', () {
      expect(run(['a', 'b']), isEmpty);
    });

    test('dùng với GroupConsent thật', () async {
      SharedPreferences.setMockInitialValues({GroupConsent.prefKey('u'): GroupConsent.encode({'a'})});
      await GroupConsent.instance.load('u');
      addTearDown(GroupConsent.instance.reset);
      final out = writableGroups([_g('a'), _g('b')],
          id: (g) => g.id, allowed: GroupConsent.instance.allows, paused: (_) => false);
      expect(out.map((g) => g.id), ['a']);
    });
  });

  group('exploreMayRecord', () {
    test('đang chia sẻ: luôn ghi (cùng phiên dịch vụ nền)', () {
      expect(exploreMayRecord(sharing: true, screenVisible: false, appInForeground: false), isTrue);
    });

    test('tắt chia sẻ: chỉ ghi khi màn Khám phá mở ở tiền cảnh', () {
      expect(exploreMayRecord(sharing: false, screenVisible: true, appInForeground: true), isTrue);
      expect(exploreMayRecord(sharing: false, screenVisible: true, appInForeground: false), isFalse);
      expect(exploreMayRecord(sharing: false, screenVisible: false, appInForeground: true), isFalse);
      expect(exploreMayRecord(sharing: false, screenVisible: false, appInForeground: false), isFalse);
    });
  });

  group('backgroundConsentAllows', () {
    test('chưa có dữ liệu đồng ý: không gửi', () {
      expect(backgroundConsentAllows(null, 'a', GroupConsent.parse), isFalse);
    });

    test('có dữ liệu: chỉ nhóm trong danh sách', () {
      final raw = GroupConsent.encode({'a'});
      expect(backgroundConsentAllows(raw, 'a', GroupConsent.parse), isTrue);
      expect(backgroundConsentAllows(raw, 'b', GroupConsent.parse), isFalse);
    });

    test('dữ liệu hỏng: không gửi', () {
      expect(backgroundConsentAllows('oops', 'a', GroupConsent.parse), isFalse);
    });
  });

  test('GroupConsent: đồng ý nhóm vừa tạo không bị mất vì danh sách nhóm cũ đến sau', () async {
    SharedPreferences.setMockInitialValues({GroupConsent.prefKey('u'): GroupConsent.encode({'a'})});
    final consent = GroupConsent.instance;
    await consent.load('u');
    addTearDown(consent.reset);
    await consent.grant('new');
    await consent.onGroups([_g('a')]); // danh sách chưa có nhóm mới
    expect(consent.allows('new'), isTrue);
    await consent.onGroups([_g('a'), _g('new')]);
    await consent.onGroups([_g('a')]); // rời nhóm thật
    expect(consent.allows('new'), isFalse);
  });
}
