import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/services/group_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

Group _g(String id, {String owner = 'o'}) => Group(
      id: id,
      name: id,
      ownerId: owner,
      inviteCode: 'ABCDEF',
      memberIds: const ['me'],
      memberNames: const {'me': 'Tôi'},
    );

void main() {
  final consent = GroupConsent.instance;
  tearDown(consent.reset);

  test('cài mới / chưa từng chia sẻ: chỉ tự đồng ý nhóm mình tạo, nhóm vào bằng mã thì không', () async {
    SharedPreferences.setMockInitialValues({});
    await consent.load('u1');
    await consent.onGroups([_g('mine', owner: 'u1'), _g('joined')]);
    expect(consent.allows('mine'), isTrue);
    expect(consent.allows('joined'), isFalse);
  });

  test('bản cũ đang bật chia sẻ: các nhóm đang có được giữ nguyên', () async {
    SharedPreferences.setMockInitialValues({GroupConsent.legacySharingKey: true});
    await consent.load('u1');
    expect(consent.allows('a'), isFalse);
    await consent.onGroups([_g('a'), _g('b')]);
    expect(consent.allows('a'), isTrue);
    expect(consent.allows('b'), isTrue);
    // Nhóm vào sau đó KHÔNG tự đồng ý.
    await consent.onGroups([_g('a'), _g('b'), _g('c')]);
    expect(consent.allows('c'), isFalse);
  });

  test('đã có dữ liệu: nhóm mới vào không được tự chia sẻ; grant / revoke', () async {
    SharedPreferences.setMockInitialValues({GroupConsent.prefKey('u1'): GroupConsent.encode({'a'})});
    await consent.load('u1');
    await consent.onGroups([_g('a'), _g('new')]);
    expect(consent.allows('a'), isTrue);
    expect(consent.allows('new'), isFalse);
    await consent.grant('new');
    expect(consent.allows('new'), isTrue);
    await consent.revoke('a');
    expect(consent.allows('a'), isFalse);
    // Lưu bền.
    final raw = (await SharedPreferences.getInstance()).getString(GroupConsent.prefKey('u1'))!;
    expect(GroupConsent.parse(raw), {'new'});
  });

  test('rời nhóm thì xoá khỏi danh sách đồng ý', () async {
    SharedPreferences.setMockInitialValues({GroupConsent.prefKey('u1'): GroupConsent.encode({'a', 'b'})});
    await consent.load('u1');
    await consent.onGroups([_g('b')]);
    expect(consent.consented.value, {'b'});
  });

  test('dữ liệu hỏng: không đồng ý nhóm nào', () {
    expect(GroupConsent.parse('not json'), isEmpty);
    expect(GroupConsent.parse('{"groups": 3}'), isEmpty);
  });

  test('tài khoản khác trên cùng máy không thừa hưởng đồng ý', () async {
    SharedPreferences.setMockInitialValues({GroupConsent.prefKey('u1'): GroupConsent.encode({'a'})});
    await consent.load('u1');
    expect(consent.allows('a'), isTrue);
    consent.reset();
    SharedPreferences.setMockInitialValues({
      GroupConsent.prefKey('u1'): GroupConsent.encode({'a'}),
      GroupConsent.prefKey('u2'): GroupConsent.encode({}),
    });
    await consent.load('u2');
    expect(consent.allows('a'), isFalse);
  });
}
