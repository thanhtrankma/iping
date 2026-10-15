import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/screens/moderation_sheets.dart';
import 'package:gan_nhau/services/moderation_service.dart';
import 'package:gan_nhau/widgets/legal_links.dart';

void main() {
  group('ModerationService (thuần)', () {
    test('parseBlocked đọc blockedUids, bỏ giá trị rỗng / sai kiểu', () {
      expect(ModerationService.parseBlocked(null), isEmpty);
      expect(ModerationService.parseBlocked({'blockedUids': 'x'}), isEmpty);
      expect(ModerationService.parseBlocked({
        'blockedUids': ['a', '', 3, 'b', 'a'],
      }), {'a', 'b'});
    });

    test('reportData đúng hợp đồng dữ liệu, cắt note/text', () {
      final d = ModerationService.reportData(
        reporterUid: 'me',
        kind: ReportKind.message,
        targetUid: 'u2',
        reason: ReportReason.harassment,
        groupId: 'g1',
        targetId: 'm1',
        note: '  ${'n' * 600}  ',
        text: 't' * 1200,
      );
      expect(d['reporterUid'], 'me');
      expect(d['kind'], 'message');
      expect(d['groupId'], 'g1');
      expect(d.containsKey('dmId'), isFalse);
      expect(d['targetId'], 'm1');
      expect(d['targetUid'], 'u2');
      expect(d['reason'], 'harassment');
      expect((d['note'] as String).length, 500);
      expect((d['text'] as String).length, 1000);
      expect(d.containsKey('createdAt'), isFalse); // thêm serverTimestamp khi gửi
    });

    test('reportData người dùng: không có note/text rỗng', () {
      final d = ModerationService.reportData(
        reporterUid: 'me',
        kind: ReportKind.user,
        targetUid: 'u2',
        reason: ReportReason.other,
        dmId: 'a_b',
        note: '   ',
      );
      expect(d.keys.toSet(), {'reporterUid', 'kind', 'dmId', 'targetUid', 'reason'});
      expect(d['kind'], 'user');
    });

    test('canDelete: của mình hoặc chủ nhóm', () {
      expect(ModerationService.canDelete(myUid: 'a', authorUid: 'a'), isTrue);
      expect(ModerationService.canDelete(myUid: 'a', authorUid: 'b'), isFalse);
      expect(ModerationService.canDelete(myUid: 'a', authorUid: 'b', isGroupOwner: true), isTrue);
      expect(ModerationService.canDelete(myUid: null, authorUid: 'b', isGroupOwner: true), isFalse);
    });
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('bảng thao tác: tin của người khác có Báo cáo / Chặn, không có Xoá', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showContentActions(ctx, canDelete: false, isMine: false);
    await tester.pumpAndSettle();
    expect(find.text('Sao chép'), findsOneWidget);
    expect(find.text('Báo cáo'), findsOneWidget);
    expect(find.text('Chặn người này'), findsOneWidget);
    expect(find.text('Xoá'), findsNothing);
  });

  testWidgets('bảng thao tác: tin của mình chỉ có Sao chép và Xoá', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    showContentActions(ctx, canDelete: true, isMine: true);
    await tester.pumpAndSettle();
    expect(find.text('Xoá'), findsOneWidget);
    expect(find.text('Báo cáo'), findsNothing);
    expect(find.text('Chặn người này'), findsNothing);
  });

  testWidgets('sheet báo cáo: phải chọn lý do mới gửi được, gửi kèm chặn', (tester) async {
    ReportReason? reason;
    String? note;
    bool? block;
    await tester.pumpWidget(host(SingleChildScrollView(
      child: ReportSheet(
        kind: ReportKind.message,
        targetName: 'An',
        onSubmit: (r, n, b) async {
          reason = r;
          note = n;
          block = b;
        },
      ),
    )));
    final send = find.widgetWithText(FilledButton, 'Gửi báo cáo');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.text(ReportReason.spam.label));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'quảng cáo');
    await tester.tap(find.text('Chặn An'));
    await tester.pump();
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    await tester.pump();
    expect(reason, ReportReason.spam);
    expect(note, 'quảng cáo');
    expect(block, isTrue);
  });

  testWidgets('dòng đồng ý điều khoản có hai liên kết', (tester) async {
    await tester.pumpWidget(host(const LegalConsentText()));
    final text = tester.widget<Text>(find.byType(Text)).textSpan!.toPlainText();
    expect(text, contains('đủ 13 tuổi'));
    expect(text, contains('Điều khoản sử dụng'));
    expect(text, contains('Chính sách quyền riêng tư'));
    expect(termsUrl, startsWith('https://iping-share.web.app/'));
  });
}
