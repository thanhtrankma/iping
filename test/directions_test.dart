import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/utils/directions.dart';

void main() {
  test('iOS dùng Apple Maps', () {
    final u = directionsUri(20.85, 106.68, ios: true);
    expect(u.host, 'maps.apple.com');
    expect(u.queryParameters['daddr'], '20.850000,106.680000');
  });

  test('Android dùng Google Maps', () {
    final u = directionsUri(20.85, 106.68, ios: false);
    expect(u.host, 'www.google.com');
    expect(u.path, '/maps/dir/');
    expect(u.queryParameters['destination'], '20.850000,106.680000');
    expect(u.queryParameters['api'], '1');
  });
}
