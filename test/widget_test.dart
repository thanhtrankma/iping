import 'package:flutter_test/flutter_test.dart';
import 'package:gan_nhau/utils/format.dart';

void main() {
  test('timeAgo trả về "chưa rõ" khi không có thời gian', () {
    expect(timeAgo(null), 'chưa rõ');
  });
}
