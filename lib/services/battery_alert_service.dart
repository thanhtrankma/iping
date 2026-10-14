import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'group_service.dart';
import 'privacy_service.dart';
import 'location_service.dart';

/// Máy trạng thái cảnh báo pin yếu: báo một lần mỗi chu kỳ xả pin.
class LowBatteryTracker {
  LowBatteryTracker({this.alerted = false});

  static const lowLevel = 15;
  static const resetLevel = 25;

  /// Đã báo trong chu kỳ xả hiện tại.
  bool alerted;

  /// Trả về `true` nếu cần gửi cảnh báo ngay bây giờ.
  bool update(int level, {required bool charging}) {
    if (charging || level > resetLevel) {
      alerted = false;
      return false;
    }
    if (level <= lowLevel && !alerted) {
      alerted = true;
      return true;
    }
    return false;
  }
}

/// Khi đang chia sẻ vị trí mà pin ≤ 15% và không sạc, gửi sự kiện `low_battery` vào mọi nhóm.
class BatteryAlertService {
  BatteryAlertService._();
  static final instance = BatteryAlertService._();

  static const _prefKey = 'low_battery_alerted';

  final _battery = Battery();
  final _tracker = LowBatteryTracker();
  Timer? _timer;
  StreamSubscription<BatteryState>? _stateSub;
  bool _loaded = false;

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 3), (_) => check());
    _stateSub ??= _battery.onBatteryStateChanged.listen((_) => check(), onError: (Object _) {});
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _stateSub?.cancel();
    _stateSub = null;
  }

  /// Gọi định kỳ và mỗi khi có vị trí mới.
  Future<void> check({int? level}) async {
    final loc = LocationService.instance;
    if (!loc.sharing.value || loc.groups.isEmpty) return;
    final int lvl;
    final BatteryState state;
    try {
      lvl = level ?? await _battery.batteryLevel;
      state = await _battery.batteryState;
    } catch (_) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!_loaded) {
      // Nhớ qua lần mở app để không báo lặp lại.
      _tracker.alerted = prefs.getBool(_prefKey) ?? false;
      _loaded = true;
    }
    final charging = state == BatteryState.charging || state == BatteryState.full;
    final before = _tracker.alerted;
    final fire = _tracker.update(lvl, charging: charging);
    if (_tracker.alerted != before) await prefs.setBool(_prefKey, _tracker.alerted);
    if (!fire) return;

    // Ghi riêng từng nhóm: một nhóm lỗi không chặn nhóm khác.
    // Không gửi cho nhóm đang tạm ẩn vị trí.
    await Future.wait(loc.groups.where((g) => !PrivacyService.instance.isPaused(g.id)).map((g) async {
      try {
        await GroupService.instance.addEvent(g.id, type: 'low_battery', battery: lvl);
      } catch (e) {
        debugPrint('Low battery event ${g.id}: $e');
      }
    }));
  }
}
