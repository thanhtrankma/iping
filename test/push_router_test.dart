import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/services/push_router.dart';

void main() {
  test('không có groupId thì bỏ qua', () {
    expect(pushTargetFor({'type': 'sos'}), isNull);
  });

  test('sự kiện của thành viên mở màn thành viên', () {
    final t = pushTargetFor({'groupId': 'g1', 'type': 'sos', 'uid': 'u1'})!;
    expect(t.dest, PushDest.member);
    expect(t.uid, 'u1');
  });

  test('ping mở người gửi; thiếu người gửi thì về màn chính', () {
    expect(pushTargetFor({'groupId': 'g1', 'type': 'ping', 'from': 'u2'})!.uid, 'u2');
    expect(pushTargetFor({'groupId': 'g1', 'type': 'ping'})!.dest, PushDest.home);
  });

  test('tin nhắn, khoảnh khắc, meetup, về an toàn', () {
    expect(pushTargetFor({'groupId': 'g', 'type': 'message', 'uid': 'u'})!.dest, PushDest.chat);
    expect(pushTargetFor({'groupId': 'g', 'type': 'moment'})!.dest, PushDest.moments);
    final m = pushTargetFor({'groupId': 'g', 'type': 'meetup', 'meetupId': 'm1'})!;
    expect((m.dest, m.meetupId), (PushDest.meetup, 'm1'));
    expect(pushTargetFor({'groupId': 'g', 'type': 'safe_self', 'uid': 'u'})!.dest, PushDest.safeTrip);
  });
}
