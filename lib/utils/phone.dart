/// Chuẩn hoá số điện thoại về dạng E.164 (ví dụ `0912 345 678` → `+84912345678`).
/// [countryCode] là mã quốc gia mặc định, dạng `+84` hoặc `84`.
/// Trả về `null` nếu số không hợp lệ.
String? normalizePhone(String input, {String countryCode = '+84'}) {
  final cc = countryCode.replaceAll(RegExp(r'\D'), '');
  var s = input.trim().replaceAll(RegExp(r'[\s.\-()]'), '');
  if (s.isEmpty || cc.isEmpty) return null;

  String digits;
  if (s.startsWith('+')) {
    digits = s.substring(1);
  } else if (s.startsWith('00')) {
    digits = s.substring(2);
  } else if (s.startsWith('0')) {
    // Số nội địa: bỏ số 0 đầu, thêm mã quốc gia.
    digits = cc + s.substring(1);
  } else if (s.startsWith(cc) && s.length > 10) {
    // Đã gõ sẵn mã quốc gia nhưng thiếu dấu +.
    digits = s;
  } else {
    digits = cc + s;
  }

  if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits)) return null;
  return '+$digits';
}
