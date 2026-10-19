import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/screens/chat_tab.dart' show checkOutgoingText;
import 'package:gan_nhau/services/content_filter.dart';

/// Ca kiểm thử dùng chung với functions/content_filter.test.js (cùng kết quả ở client và server).
final _cases = jsonDecode(File('test/content_filter_cases.json').readAsStringSync()) as Map<String, dynamic>;

List<String> _section(String src, String name) {
  final m = RegExp('// BEGIN $name([\\s\\S]*?)// END $name').firstMatch(src);
  expect(m, isNotNull, reason: 'thiếu khối $name');
  final body = m!.group(1)!.replaceAll(RegExp(r'//.*$', multiLine: true), '');
  return [for (final x in RegExp(r"'([^']*)'").allMatches(body)) x.group(1)!];
}

void main() {
  test('câu bình thường không bị lọc', () {
    for (final t in (_cases['clean'] as List).cast<String>()) {
      expect(ContentFilter.isFlagged(t), isFalse, reason: '"$t" → "${ContentFilter.mask(t)}"');
      expect(ContentFilter.mask(t), t);
    }
  });

  test('từ không phù hợp bị che bằng ***', () {
    for (final e in (_cases['masked'] as Map).cast<String, String>().entries) {
      expect(ContentFilter.isFlagged(e.key), isTrue, reason: e.key);
      expect(ContentFilter.mask(e.key), e.value, reason: e.key);
      // Lần hai lấy từ bộ nhớ đệm.
      expect(ContentFilter.mask(e.key), e.value);
    }
  });

  test('null / rỗng', () {
    expect(ContentFilter.mask(null), '');
    expect(ContentFilter.isFlagged(''), isFalse);
  });

  test('danh sách từ giống hệt functions/content_filter.js', () {
    final js = File('functions/content_filter.js').readAsStringSync();
    expect(_section(js, 'WORDS'), ContentFilter.words);
    expect(_section(js, 'STRICT'), ContentFilter.strict);
  });

  group('checkOutgoingText', () {
    Future<String?> run(WidgetTester tester, String text, {String? tap}) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      String? result = 'pending';
      final f = checkOutgoingText(ctx, text).then((v) => result = v);
      await tester.pumpAndSettle();
      if (tap != null) {
        expect(find.text('Tin nhắn có từ ngữ không phù hợp'), findsOneWidget);
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      await f;
      return result;
    }

    testWidgets('văn bản sạch gửi ngay', (tester) async {
      expect(await run(tester, 'Đi đâu đấy?'), 'Đi đâu đấy?');
    });

    testWidgets('Sửa lại → không gửi', (tester) async {
      expect(await run(tester, 'fuck you', tap: 'Sửa lại'), isNull);
    });

    testWidgets('Vẫn gửi → gửi bản đã che', (tester) async {
      expect(await run(tester, 'fuck you', tap: 'Vẫn gửi (sẽ được che)'), '*** you');
    });
  });
}
