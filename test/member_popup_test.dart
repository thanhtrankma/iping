import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/screens/member_popup.dart';

void main() {
  final loc = MemberLocation(
    uid: 'u2',
    name: 'Nguyễn Văn Một Cái Tên Rất Dài',
    lat: 20.83,
    lng: 106.58,
    accuracy: 5,
    speed: 12,
    battery: 15,
    sharing: true,
    updatedAt: DateTime.now(),
  );

  Future<void> pump(WidgetTester tester, {String? myUid}) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MemberPopup(groupId: 'g', location: loc, myUid: myUid, myLat: 20.84, myLng: 106.59),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('popup thành viên khác: đủ thông tin và 3 nút, không tràn ở màn 360px', (tester) async {
    await pump(tester, myUid: 'me');
    expect(tester.takeException(), isNull);
    expect(find.text('15%'), findsOneWidget);
    expect(find.text('Chi tiết'), findsOneWidget);
    expect(find.text('Chỉ đường'), findsOneWidget);
    expect(find.text('Nhắn tin'), findsOneWidget);
    expect(find.textContaining('km/h'), findsOneWidget);
    expect(find.text('Báo cáo / Chặn'), findsOneWidget);
  });

  testWidgets('popup của chính mình: chỉ có nút Chi tiết, có nhãn Bạn', (tester) async {
    await pump(tester, myUid: 'u2');
    expect(tester.takeException(), isNull);
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('Chỉ đường'), findsNothing);
    expect(find.text('Nhắn tin'), findsNothing);
    expect(find.text('Báo cáo / Chặn'), findsNothing);
  });
}
