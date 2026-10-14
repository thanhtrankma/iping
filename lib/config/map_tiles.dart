import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// API key MapTiler (cloud.maptiler.com → API keys). Đây là key phía client, vẫn nằm trong file APK
/// như các API key Firebase; giới hạn lạm dụng bằng hạn mức trong trang quản lý MapTiler.
/// Có thể ghi đè khi build: `--dart-define=MAPTILER_KEY=...`.
const _mapTilerKey = String.fromEnvironment('MAPTILER_KEY', defaultValue: '');

/// Đang dùng MapTiler (bản phát hành) hay nguồn tạm khi phát triển (Esri / OpenStreetMap).
bool get usingMapTiler => _mapTilerKey.isNotEmpty;

const _ua = 'com.iping.app';

TileLayer _mapTiler(BuildContext context, String map, String ext) => TileLayer(
      // {r} = "@2x" trên màn hình mật độ cao (MapTiler tính như một lượt tải).
      urlTemplate: 'https://api.maptiler.com/maps/$map/256/{z}/{x}/{y}{r}.$ext?key=$_mapTilerKey',
      retinaMode: RetinaMode.isHighDensity(context),
      userAgentPackageName: _ua,
      maxNativeZoom: 20,
    );

/// Ảnh vệ tinh kèm tên đường / địa danh.
List<Widget> satelliteTileLayers(BuildContext context) => usingMapTiler
    ? [_mapTiler(context, 'hybrid', 'jpg')]
    : [
        // Chỉ dùng khi phát triển: Esri không cho phép dùng trong app phát hành.
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: _ua,
          maxNativeZoom: 19,
        ),
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: _ua,
          maxNativeZoom: 19,
        ),
      ];

/// Bản đồ đường phố thường.
TileLayer streetTileLayer(BuildContext context) => usingMapTiler
    ? _mapTiler(context, 'streets-v2', 'png')
    // Chỉ dùng khi phát triển: chính sách tile của OSM không cho app phát hành dùng máy chủ công cộng.
    : TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: _ua);

/// Dòng ghi nguồn bắt buộc hiển thị trên bản đồ.
String mapAttribution({required bool satellite}) => usingMapTiler
    ? '© MapTiler © OpenStreetMap contributors'
    : (satellite ? '© Esri, Maxar' : '© OpenStreetMap contributors');
