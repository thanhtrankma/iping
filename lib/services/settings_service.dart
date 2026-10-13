import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapStyle { satellite, standard }

/// Cài đặt cục bộ của người dùng.
class SettingsService {
  SettingsService._();
  static final instance = SettingsService._();

  /// Giá trị chọn đặc biệt: xem "Tất cả bạn bè" của mọi nhóm.
  static const allGroups = '__all__';

  final mapStyle = ValueNotifier<MapStyle>(MapStyle.satellite);
  final selectedGroupId = ValueNotifier<String?>(null);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mapStyle.value = prefs.getString('map_style') == 'standard' ? MapStyle.standard : MapStyle.satellite;
    selectedGroupId.value = prefs.getString('selected_group');
  }

  Future<void> toggleMapStyle() async {
    mapStyle.value = mapStyle.value == MapStyle.satellite ? MapStyle.standard : MapStyle.satellite;
    (await SharedPreferences.getInstance()).setString('map_style', mapStyle.value.name);
  }

  Future<void> selectGroup(String? gid) async {
    selectedGroupId.value = gid;
    final prefs = await SharedPreferences.getInstance();
    if (gid == null) {
      await prefs.remove('selected_group');
    } else {
      await prefs.setString('selected_group', gid);
    }
  }
}
