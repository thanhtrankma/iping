import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hex_grid.dart';

/// Một khu vực hành chính (phường / xã / quận...) có đường biên.
class ExploreArea {
  ExploreArea({required this.id, required this.name, required this.displayName, required this.rings});

  final String id;
  final String name;
  final String displayName;
  final List<List<LatLng>> rings;

  late final List<List<(double, double)>> ringsXY = HexGrid.projectRings(rings);
  late final (double, double, double, double) bboxXY = () {
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final ring in ringsXY) {
      for (final (x, y) in ring) {
        if (x < x0) x0 = x;
        if (y < y0) y0 = y;
        if (x > x1) x1 = x;
        if (y > y1) y1 = y;
      }
    }
    return (x0, y0, x1, y1);
  }();

  /// Tổng số ô lục giác có tâm nằm trong khu vực.
  late final int totalCells = HexGrid.countCellsInRingsXY(ringsXY);

  bool containsXY(double x, double y) {
    final (x0, y0, x1, y1) = bboxXY;
    if (x < x0 || x > x1 || y < y0 || y > y1) return false;
    return HexGrid.containsXY(ringsXY, x, y);
  }

  bool contains(LatLng p) {
    final (x, y) = HexGrid.project(p.latitude, p.longitude);
    return containsXY(x, y);
  }

  /// Số ô đã khám phá nằm trong khu vực.
  int exploredIn(Iterable<HexCell> cells) {
    var n = 0;
    for (final c in cells) {
      final (x, y) = HexGrid.centerXY(c);
      if (containsXY(x, y)) n++;
    }
    return n;
  }

  /// Điểm đặt nhãn: tâm ô gần trọng tâm khung bao nhất mà vẫn nằm trong khu vực.
  late final LatLng labelPoint = () {
    final (x0, y0, x1, y1) = bboxXY;
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    if (containsXY(cx, cy)) return HexGrid.unproject(cx, cy);
    final start = HexGrid.cellAtXY(cx, cy);
    for (var radius = 1; radius < 200; radius += 2) {
      for (final c in HexGrid.disk(start, radius)) {
        final (x, y) = HexGrid.centerXY(c);
        if (containsXY(x, y)) return HexGrid.unproject(x, y);
      }
    }
    return rings.first.first;
  }();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'displayName': displayName,
        'rings': [
          for (final r in rings) [for (final p in r) [p.longitude, p.latitude]],
        ],
      };

  factory ExploreArea.fromJson(Map<String, dynamic> j) => ExploreArea(
        id: j['id'] as String,
        name: j['name'] as String,
        displayName: j['displayName'] as String? ?? '',
        rings: _parseRings(j['rings'] as List),
      );

  static List<List<LatLng>> _parseRings(List rings) => [
        for (final r in rings)
          [for (final p in r as List) LatLng(((p as List)[1] as num).toDouble(), (p[0] as num).toDouble())],
      ];

  /// Đọc kết quả `reverse` của Nominatim (cần `polygon_geojson=1`), `null` nếu không có đường biên.
  static ExploreArea? fromNominatim(Map<String, dynamic> j) {
    final geo = j['geojson'] as Map<String, dynamic>?;
    if (geo == null) return null;
    final coords = geo['coordinates'] as List?;
    final List<List<LatLng>> rings;
    switch (geo['type']) {
      case 'Polygon':
        rings = _parseRings(coords!);
      case 'MultiPolygon':
        rings = [for (final poly in coords!) ..._parseRings(poly as List)];
      default:
        return null;
    }
    if (rings.isEmpty) return null;
    final name = (j['name'] as String?)?.trim();
    return ExploreArea(
      id: '${j['osm_type']}${j['osm_id']}',
      name: (name == null || name.isEmpty) ? (j['display_name'] as String? ?? '').split(',').first : name,
      displayName: j['display_name'] as String? ?? '',
      rings: rings,
    );
  }
}

/// Tìm khu vực hành chính chứa một điểm bằng Nominatim (OpenStreetMap).
///
/// Theo chính sách của Nominatim: tối đa 1 yêu cầu/giây, có User-Agent riêng,
/// và cache kết quả (ở đây lưu cả đường biên vào máy để dùng lại khi offline).
/// Chỉ gửi toạ độ đã làm tròn (~100 m), không kèm danh tính người dùng.
class AreaService {
  AreaService._();
  static final instance = AreaService._();

  static const _prefKey = 'explore_areas';
  static const _maxCached = 30;
  /// Phiên bản app, khớp `version` trong pubspec.yaml (test kiểm tra).
  static const appVersion = '0.1.0';

  /// User-Agent riêng theo chính sách Nominatim: tên app/phiên bản + email liên hệ.
  static const userAgent = 'IPing/$appVersion (contact: beatgone2503@gmail.com)';

  /// Làm tròn toạ độ gửi cho Nominatim còn 3 chữ số thập phân (~100 m): không gửi vị trí chính xác
  /// của người dùng ra bên thứ ba, vẫn đủ để biết phường/xã.
  static String coarse(double v) => v.toStringAsFixed(3);
  // Nominatim: 14 ≈ phường/xã, 12 ≈ quận/huyện, 10 ≈ tỉnh/thành phố.
  static const _zooms = [14, 12, 10];

  List<ExploreArea>? _areas;
  Future<void> _queue = Future.value();
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<List<ExploreArea>> _load() async {
    if (_areas != null) return _areas!;
    final raw = (await SharedPreferences.getInstance()).getString(_prefKey);
    final list = <ExploreArea>[];
    if (raw != null) {
      try {
        for (final j in jsonDecode(raw) as List) {
          list.add(ExploreArea.fromJson(j as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('Area cache: $e');
      }
    }
    return _areas = list;
  }

  Future<void> _save() async {
    final list = _areas ?? const [];
    (await SharedPreferences.getInstance()).setString(_prefKey, jsonEncode([for (final a in list) a.toJson()]));
  }

  /// Khu vực đã cache có chứa điểm [p] (không gọi mạng).
  Future<ExploreArea?> cachedAt(LatLng p) async {
    for (final a in await _load()) {
      if (a.contains(p)) return a;
    }
    return null;
  }

  /// Khu vực nhỏ nhất chứa [p]: ưu tiên cache, sau đó hỏi Nominatim.
  Future<ExploreArea?> areaAt(LatLng p) async {
    final cached = await cachedAt(p);
    if (cached != null) return cached;
    for (final zoom in _zooms) {
      final j = await _reverse(p, zoom);
      if (j == null) return null; // lỗi mạng: thử lại lần sau
      final area = ExploreArea.fromNominatim(j);
      if (area != null && area.contains(p)) {
        final list = await _load();
        list
          ..removeWhere((a) => a.id == area.id)
          ..insert(0, area);
        if (list.length > _maxCached) list.removeRange(_maxCached, list.length);
        await _save();
        return area;
      }
    }
    return null;
  }

  /// Gọi `reverse` lần lượt, cách nhau ít nhất 1,1 giây.
  Future<Map<String, dynamic>?> _reverse(LatLng p, int zoom) {
    final c = Completer<Map<String, dynamic>?>();
    _queue = _queue.then((_) async {
      final wait = _lastRequest.add(const Duration(milliseconds: 1100)).difference(DateTime.now());
      if (!wait.isNegative) await Future<void>.delayed(wait);
      _lastRequest = DateTime.now();
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'format': 'jsonv2',
          'lat': coarse(p.latitude),
          'lon': coarse(p.longitude),
          'zoom': '$zoom',
          'polygon_geojson': '1',
          'polygon_threshold': '0.0001',
          'accept-language': 'vi',
        });
        final res = await http
            .get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json'})
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          debugPrint('Nominatim ${res.statusCode}');
          c.complete(null);
          return;
        }
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        c.complete(j is Map<String, dynamic> && j['error'] == null ? j : <String, dynamic>{});
      } catch (e) {
        debugPrint('Nominatim: $e');
        c.complete(null);
      }
    });
    return c.future;
  }
}
