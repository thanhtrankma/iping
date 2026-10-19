import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Chuỗi hệ thống (Material) hiển thị bằng tiếng Việt', (tester) async {
    late MaterialLocalizations l10n;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        l10n = MaterialLocalizations.of(context);
        return const SizedBox();
      }),
    ));
    expect(GlobalMaterialLocalizations.delegate.isSupported(const Locale('vi')), isTrue);
    expect(l10n.cancelButtonLabel, isNot('Cancel'));
  });
}
