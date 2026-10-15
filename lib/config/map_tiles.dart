import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

/// Chỉ bản debug/profile mới được dùng máy chủ công cộng không key (tile.openstreetmap.org,
/// server.arcgisonline.com) khi chưa có key. Bản phát hành KHÔNG BAO GIỜ gọi tới các máy chủ đó
/// (chính sách tile của OSM và điều khoản Esri): chưa có key thì vẽ nền trống.
@visibleForTesting
bool allowKeylessTileFallback = !kReleaseMode;

bool _loggedMissingKey = false;

void _logMissingKey() {
  if (_loggedMissingKey) return;
  _loggedMissingKey = true;
  debugPrint('Map tiles: chưa có MAPTILER_KEY / ARCGIS_KEY (config/maps hoặc --dart-define); bản đồ để trống.');
}

/// PNG 1x1 trong suốt: ô bản đồ "trống" khi chưa có key ở bản phát hành.
final Uint8List _transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, //
  0xAE, 0x42, 0x60, 0x82,
]);

/// Không tải gì qua mạng: mọi ô là ảnh trong suốt (nền của bản đồ hiện ra).
class _BlankTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_transparentPng);
}

/// Lớp bản đồ trống (bản phát hành chưa có key).
@visibleForTesting
TileLayer blankTileLayer() {
  _logMissingKey();
  return TileLayer(tileProvider: _BlankTileProvider(), userAgentPackageName: _ua);
}

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
  if (!allowKeylessTileFallback) return [blankTileLayer()];
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
TileLayer streetTileLayer(BuildContext context) {
  if (MapKeys.instance.usingMapTiler) return _mapTiler(context, 'streets-v2', 'png');
  if (!allowKeylessTileFallback) return blankTileLayer();
  // Chỉ dùng khi phát triển: chính sách tile của OSM không cho app phát hành dùng máy chủ công cộng.
  return TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: _ua);
}

/// Dòng ghi nguồn bắt buộc hiển thị trên bản đồ.
String mapAttribution({required bool satellite}) {
  final keys = MapKeys.instance;
  if (satellite && (keys.usingArcgis || !keys.usingMapTiler)) {
    return 'Powered by Esri · Esri, Vantor, Earthstar Geographics · © OpenStreetMap contributors';
  }
  return keys.usingMapTiler ? '© MapTiler © OpenStreetMap contributors' : '© OpenStreetMap contributors';
}
