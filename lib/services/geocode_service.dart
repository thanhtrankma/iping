import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';

/// Đổi toạ độ thành địa chỉ bằng geocoder của hệ điều hành (miễn phí, không cần key).
/// Kết quả được cache theo ô ~100 m.
class GeocodeService {
  GeocodeService._();
  static final instance = GeocodeService._();

  final _geocoder = Geocoding(locale: const Locale('vi', 'VN'));
  final Map<String, Future<Placemark?>> _cache = {};

  String _key(double lat, double lng) => '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  Future<Placemark?> _lookup(double lat, double lng) =>
      _cache.putIfAbsent(_key(lat, lng), () async {
        try {
          final res = await _geocoder.placemarkFromCoordinates(lat, lng);
          return res.isEmpty ? null : res.first;
        } catch (_) {
          return null;
        }
      });

  /// Địa chỉ đầy đủ: "Số nhà Đường, Phường, Quận, Tỉnh".
  Future<String> address(double lat, double lng) async {
    final p = await _lookup(lat, lng);
    if (p == null) return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    final parts = <String>[
      if ((p.street ?? '').isNotEmpty) p.street!,
      if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
      if ((p.locality ?? '').isNotEmpty) p.locality!,
      if ((p.subAdministrativeArea ?? '').isNotEmpty) p.subAdministrativeArea!,
      if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
    ];
    // Android thường trả cả dòng địa chỉ trong `street`: bỏ các phần đã có trong đó.
    final unique = <String>[];
    for (final s in parts) {
      if (!unique.any((u) => u.contains(s))) unique.add(s);
    }
    return unique.isEmpty ? (p.name ?? '') : unique.join(', ');
  }

  /// Tên khu vực ngắn: "Hải Phòng", "Quận 1"...
  Future<String> area(double lat, double lng) async {
    final p = await _lookup(lat, lng);
    if (p == null) return '';
    for (final s in [p.administrativeArea, p.subAdministrativeArea, p.locality]) {
      if ((s ?? '').isNotEmpty) return s!;
    }
    return '';
  }
}

/// Hiển thị địa chỉ của một toạ độ, tự tải bất đồng bộ.
class AddressText extends StatelessWidget {
  const AddressText(this.lat, this.lng, {super.key, this.short = false, this.style, this.maxLines = 2});
  final double lat;
  final double lng;
  final bool short;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final svc = GeocodeService.instance;
    return FutureBuilder<String>(
      future: short ? svc.area(lat, lng) : svc.address(lat, lng),
      builder: (context, snap) => Text(
        snap.data ?? '…',
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
