import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/screens/group_consent_screen.dart';
import 'package:gan_nhau/theme.dart';

final _group = Group(
  id: 'g1',
  name: 'Gia đình',
  ownerId: 'mom',
  inviteCode: 'ABC123',
  memberIds: const ['mom', 'me', 'dad'],
  memberNames: const {'mom': 'Nguyễn Thị Lan', 'me': 'Trần Minh', 'dad': 'Trần Văn Hùng'},
);

Future<void> _pump(
  WidgetTester tester, {
  Group? group,
  VoidCallback? onShare,
  VoidCallback? onJoinOnly,
  VoidCallback? onLeave,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: GroupConsentView(
      group: group,
      myUid: 'me',
      onShare: onShare ?? () {},
      onJoinOnly: onJoinOnly ?? () {},
      onLeave: onLeave,
    ),
  ));
}

void main() {
  testWidgets('hiện tên nhóm, thành viên và những gì nhóm sẽ thấy', (tester) async {
    await _pump(tester, group: _group, onLeave: () {});
    expect(find.text('Tham gia “Gia đình”'), findsOneWidget);
    expect(find.text('Thành viên (3)'.toUpperCase()), findsOneWidget);
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('Lan'), findsOneWidget);
    expect(find.text('Hùng'), findsOneWidget);
    for (final item in GroupConsentView.sharedItems) {
      await tester.scrollUntilVisible(find.text(item.$3), 100, scrollable: find.byType(Scrollable).first);
      expect(find.text(item.$3), findsOneWidget);
    }
    expect(find.text('Chia sẻ vị trí với nhóm này'), findsOneWidget);
    expect(find.text('Tham gia nhưng chưa chia sẻ'), findsOneWidget);
    expect(find.text('Rời nhóm'), findsOneWidget);
  });

  testWidgets('mỗi lựa chọn gọi đúng hành động', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      group: _group,
      onShare: () => calls.add('share'),
      onJoinOnly: () => calls.add('join'),
      onLeave: () => calls.add('leave'),
    );
    await tester.tap(find.text('Tham gia nhưng chưa chia sẻ'));
    await tester.tap(find.text('Chia sẻ vị trí với nhóm này'));
    await tester.tap(find.text('Rời nhóm'));
    expect(calls, ['join', 'share', 'leave']);
  });

  testWidgets('đang tải nhóm: chưa cho rời nhóm', (tester) async {
    await _pump(tester);
    expect(find.text('Tham gia nhóm'), findsOneWidget);
    final leave = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Rời nhóm'));
    expect(leave.onPressed, isNull);
  });
}
