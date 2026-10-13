import 'package:flutter/material.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String timeAgo(DateTime? t) {
  if (t == null) return 'chưa rõ';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inHours < 1) return '${d.inMinutes} phút trước';
  if (d.inDays < 1) return '${d.inHours} giờ trước';
  return '${d.inDays} ngày trước';
}

String clock(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final time = '${_two(t.hour)}:${_two(t.minute)}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return time;
  return '$time ${_two(t.day)}/${_two(t.month)}';
}

const _avatarColors = [
  Colors.teal,
  Colors.indigo,
  Colors.deepOrange,
  Colors.purple,
  Colors.blue,
  Colors.pink,
  Colors.green,
  Colors.brown,
];

Color avatarColor(String uid) =>
    _avatarColors[uid.codeUnits.fold<int>(0, (a, b) => a + b) % _avatarColors.length];

String initial(String name) => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

/// Vị trí được coi là "đang online" nếu cập nhật trong 10 phút gần nhất.
bool isFresh(DateTime? t) => t != null && DateTime.now().difference(t).inMinutes < 10;

String distanceLabel(double meters) =>
    meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';

/// Phần trăm kiểu Việt Nam: 7,2%.
String percentLabel(double p) => '${p.toStringAsFixed(1).replaceAll('.', ',')}%';

String areaLabel(double m2) {
  final km2 = m2 / 1e6;
  return km2 < 1 ? '${km2.toStringAsFixed(2).replaceAll('.', ',')} km²' : '${km2.toStringAsFixed(1).replaceAll('.', ',')} km²';
}

/// Bỏ tiền tố hành chính cho tiêu đề ngắn: "Xã An Lão" -> "An Lão".
String shortAreaName(String name) {
  const prefixes = ['Thành phố ', 'Thị trấn ', 'Thị xã ', 'Phường ', 'Quận ', 'Huyện ', 'Tỉnh ', 'Xã ', 'Đặc khu '];
  for (final p in prefixes) {
    if (name.startsWith(p) && name.length > p.length) return name.substring(p.length);
  }
  return name;
}
