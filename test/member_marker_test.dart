import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show Marker;
import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/models/models.dart';
import 'package:gan_nhau/widgets/map_view.dart';

void main() {
  final loc = MemberLocation(
    uid: 'u1',
    name: 'Thành',
    lat: 20.83,
    lng: 106.58,
    accuracy: 5,
    battery: 71,
    sharing: true,
    updatedAt: DateTime(2026, 10, 14),
  );

  Future<void> pumpMarker(WidgetTester tester, Marker m) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: m.width, height: m.height, child: m.child),
          ),
        ),
      ));

  testWidgets('chạm vào ghim gọi onTap, chạm vùng trống bên cạnh thì không', (tester) async {
    var taps = 0;
    final m = memberMarker(loc, onTap: () => taps++);
    await pumpMarker(tester, m);

    expect(find.text('71%'), findsOneWidget);
    await tester.tap(find.byType(MemberPin));
    expect(taps, 1);

    // Góc trái dưới của khung marker 140px nằm ngoài ghim.
    await tester.tapAt(Offset(4, m.height - 4));
    expect(taps, 1);
  });

  testWidgets('không truyền onTap thì ghim không bắt chạm', (tester) async {
    await pumpMarker(tester, memberMarker(loc));
    expect(find.byType(GestureDetector), findsNothing);
  });
}
