import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key bản đồ. Key là loại phía client (vẫn nằm trong APK như API key Firebase), không phải bí mật.
///
/// Thứ tự ưu tiên: `config/maps` trên Firestore (đổi key không cần phát hành lại app, ví dụ khi key
/// ArcGIS hết hạn sau 1 năm) → bản lưu lần trước trên máy → `--dart-define` lúc build.
///
/// - `MAPTILER_KEY`: cloud.maptiler.com → API keys. Bản đồ đường phố.
/// - `ARCGIS_KEY`: ArcGIS Location Platform (quyền Basemaps). Ảnh vệ tinh Esri, mới và nét hơn
///   ảnh vệ tinh của MapTiler ở Việt Nam.
class MapKeys extends ChangeNotifier {
  MapKeys._();
  static final instance = MapKeys._();

  static const _buildMapTiler = String.fromEnvironment('MAPTILER_KEY', defaultValue: '');
  static const _buildArcgis = String.fromEnvironment('ARCGIS_KEY', defaultValue: '');
  static const _prefsMapTiler = 'map_key_maptiler';
  static const _prefsArcgis = 'map_key_arcgis';

  String mapTiler = _buildMapTiler;
  String arcgis = _buildArcgis;

  /// Esri lỗi liên tục (key hết hạn / hết hạn mức) thì chuyển sang ảnh vệ tinh MapTiler.
  bool arcgisFailed = false;
  int _arcgisErrors = 0;

  bool get usingMapTiler => mapTiler.isNotEmpty;
  bool get usingArcgis => arcgis.isNotEmpty && !arcgisFailed;

  /// Gọi một lần khi mở app, không chặn giao diện.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _set(prefs.getString(_prefsMapTiler), prefs.getString(_prefsArcgis));
      final doc = await FirebaseFirestore.instance.doc('config/maps').get();
      final mt = doc.data()?['maptilerKey'] as String?;
      final ag = doc.data()?['arcgisKey'] as String?;
      if (mt != null) await prefs.setString(_prefsMapTiler, mt);
      if (ag != null) await prefs.setString(_prefsArcgis, ag);
      _set(mt, ag);
    } catch (e) {
      debugPrint('MapKeys.load: $e');
    }
  }

  void _set(String? mt, String? ag) {
    var changed = false;
    if (mt != null && mt.isNotEmpty && mt != mapTiler) {
      mapTiler = mt;
      changed = true;
    }
    if (ag != null && ag.isNotEmpty && ag != arcgis) {
      arcgis = ag;
      arcgisFailed = false;
      _arcgisErrors = 0;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _onArcgisError(TileImage tile, Object error, StackTrace? stack) {
    // Vài ô lỗi lẻ tẻ do mạng thì bỏ qua; nhiều ô lỗi liền nhau thường là key hết hạn.
    if (arcgisFailed || ++_arcgisErrors < 6 || !usingMapTiler) return;
    arcgisFailed = true;
    debugPrint('ArcGIS lỗi liên tục, chuyển sang MapTiler: $error');
    // Đổi lớp bản đồ sau khung hình hiện tại, không gọi rebuild giữa lúc đang vẽ.
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }
}

const _ua = 'com.iping.app';

TileLayer _mapTiler(BuildContext context, String map, String ext) => TileLayer(
      // {r} = "@2x" trên màn hình mật độ cao (MapTiler tính như một lượt tải).
      urlTemplate: 'https://api.maptiler.com/maps/$map/256/{z}/{x}/{y}{r}.$ext?key=${MapKeys.instance.mapTiler}',
      retinaMode: RetinaMode.isHighDensity(context),
      userAgentPackageName: _ua,
      maxNativeZoom: 20,
    );

/// Ảnh vệ tinh kèm tên đường / địa danh.
List<Widget> satelliteTileLayers(BuildContext context) {
  final keys = MapKeys.instance;
  if (keys.usingArcgis) {
    return [
      TileLayer(
        urlTemplate: 'https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
            '?token=${keys.arcgis}',
        userAgentPackageName: _ua,
        maxNativeZoom: 19,
        errorTileCallback: keys._onArcgisError,
      ),
      // Lớp tên đường, địa danh (tiếng Việt) vẽ đè lên ảnh. Ô 512 px nên lùi một mức zoom.
      TileLayer(
        urlTemplate: 'https://static-map-tiles-api.arcgis.com/arcgis/rest/services/static-basemap-tiles-service/v1'
            '/arcgis/imagery/labels/static/tile/{z}/{y}/{x}?token=${keys.arcgis}',
        userAgentPackageName: _ua,
        tileSize: 512,
        zoomOffset: -1,
        maxNativeZoom: 19,
      ),
    ];
  }
  if (keys.usingMapTiler) return [_mapTiler(context, 'hybrid', 'jpg')];
  // Chỉ dùng khi phát triển: Esri không key không được phép dùng trong app phát hành.
  return [
    for (final service in ['World_Imagery', 'Reference/World_Boundaries_and_Places'])
      TileLayer(
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/$service/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: _ua,
        maxNativeZoom: 19,
      ),
  ];
}

/// Bản đồ đường phố thường.
TileLayer streetTileLayer(BuildContext context) => MapKeys.instance.usingMapTiler
    ? _mapTiler(context, 'streets-v2', 'png')
    // Chỉ dùng khi phát triển: chính sách tile của OSM không cho app phát hành dùng máy chủ công cộng.
    : TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: _ua);

/// Dòng ghi nguồn bắt buộc hiển thị trên bản đồ.
String mapAttribution({required bool satellite}) {
  final keys = MapKeys.instance;
  if (satellite && (keys.usingArcgis || !keys.usingMapTiler)) {
    return 'Powered by Esri · Esri, Vantor, Earthstar Geographics · © OpenStreetMap contributors';
  }
  return keys.usingMapTiler ? '© MapTiler © OpenStreetMap contributors' : '© OpenStreetMap contributors';
}
