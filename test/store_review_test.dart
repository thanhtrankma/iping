import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/config/map_tiles.dart';
import 'package:gan_nhau/screens/location_disclosure.dart';
import 'package:gan_nhau/services/area_service.dart';

void main() {
  group('Nominatim', () {
    test('làm tròn toạ độ còn 3 chữ số (~100 m)', () {
      expect(AreaService.coarse(21.0285123), '21.029');
      expect(AreaService.coarse(105.8048456), '105.805');
      expect(AreaService.coarse(-0.0004), '-0.000');
    });

    test('User-Agent có phiên bản khớp pubspec và email liên hệ', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec)!.group(1);
      expect(AreaService.appVersion, version);
      expect(AreaService.userAgent, startsWith('IPing/$version (contact: '));
      expect(AreaService.userAgent, contains('@'));
    });
  });

  group('Bản đồ', () {
    tearDown(() => allowKeylessTileFallback = !kReleaseMode);

    testWidgets('bản phát hành chưa có key: không gọi máy chủ OSM / Esri công cộng', (tester) async {
      allowKeylessTileFallback = false;
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      final street = streetTileLayer(ctx);
      expect(street.urlTemplate, isNull);
      for (final layer in satelliteTileLayers(ctx)) {
        expect((layer as dynamic).urlTemplate, isNull);
      }
    });

    testWidgets('bản debug chưa có key vẫn dùng máy chủ công cộng để phát triển', (tester) async {
      allowKeylessTileFallback = true;
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(streetTileLayer(ctx).urlTemplate, contains('tile.openstreetmap.org'));
    });
  });

  group('Màn giải thích quyền vị trí', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LocationDisclosureSheet())));
    }

    testWidgets('Android: có nút đồng ý và từ chối, nói rõ thu thập khi app đóng', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pump(tester);
      expect(find.text('Đồng ý và tiếp tục'), findsOneWidget);
      expect(find.text('Không, cảm ơn'), findsOneWidget);
      expect(find.textContaining('thu thập dữ liệu vị trí'), findsOneWidget);
      expect(find.textContaining('kể cả khi ứng dụng đã đóng hoặc không được sử dụng'), findsOneWidget);
      expect(find.textContaining('Dừng chia sẻ'), findsOneWidget);
      for (final f in backgroundLocationFeatures) {
        expect(find.text(f), findsOneWidget);
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS: chỉ một nút "Tiếp tục" dẫn tới hộp thoại hệ thống', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pump(tester);
      expect(find.text('Tiếp tục'), findsOneWidget);
      expect(find.text('Không, cảm ơn'), findsNothing);
      expect(find.text('Đồng ý và tiếp tục'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Cấu hình nền tảng', () {
    test('iOS Info.plist khai báo đủ cho App Review', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      for (final key in [
        'NSMotionUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'ITSAppUsesNonExemptEncryption',
      ]) {
        expect(plist, contains('<key>$key</key>'));
      }
      expect(plist, isNot(contains('<string>fetch</string>')));
      expect(plist, isNot(contains('UIInterfaceOrientationLandscape')));
      expect(File('ios/Runner/PrivacyInfo.xcprivacy').existsSync(), isTrue);
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, contains('PrivacyInfo.xcprivacy in Resources'));
      expect(pbx, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    });

    test('Android manifest không sao lưu dữ liệu và gỡ quyền sinh trắc học', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android.permission.USE_BIOMETRIC" tools:node="remove"'));
      expect(manifest, contains('android.permission.USE_FINGERPRINT" tools:node="remove"'));
      expect(manifest, contains('ACCESS_BACKGROUND_LOCATION'));
    });
  });
}
