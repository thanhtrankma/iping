import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/crash_countdown_screen.dart';
import 'crash_detector.dart';
import 'location_service.dart';
import 'push_router.dart';

/// Phát hiện va chạm (BETA): chỉ chạy khi người dùng bật và đang chia sẻ vị trí, lúc app còn hoạt động.
/// Nghi va chạm → mở màn đếm ngược để người dùng huỷ trước khi gửi SOS.
class CrashService {
  CrashService._();
  static final instance = CrashService._();

  static const _prefKey = 'crash_detection';

  final enabled = ValueNotifier<bool>(false);
  final _detector = CrashDetector();
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  bool _showing = false;

  Future<void> init() async {
    enabled.value = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? false;
    // Đăng nhập lại sẽ gọi init lần nữa: gỡ listener cũ trước.
    dispose();
    LocationService.instance.sharing.addListener(_sync);
    LocationService.instance.lastPosition.addListener(_onPosition);
    _sync();
  }

  Future<void> setEnabled(bool on) async {
    enabled.value = on;
    (await SharedPreferences.getInstance()).setBool(_prefKey, on);
    _sync();
  }

  void dispose() {
    LocationService.instance.sharing.removeListener(_sync);
    LocationService.instance.lastPosition.removeListener(_onPosition);
    _accelSub?.cancel();
    _accelSub = null;
  }

  void _onPosition() {
    final p = LocationService.instance.lastPosition.value;
    if (p != null && p.speed >= 0) _detector.onSpeed(p.speed * 3.6, DateTime.now());
  }

  void _sync() {
    final run = enabled.value && LocationService.instance.sharing.value;
    if (run && _accelSub == null) {
      _accelSub = userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (e) {
          if (_detector.onAcceleration(e.x, e.y, e.z, DateTime.now())) _trigger();
        },
        onError: (Object e) => debugPrint('Crash sensor: $e'),
      );
    } else if (!run) {
      _accelSub?.cancel();
      _accelSub = null;
    }
  }

  void _trigger() {
    final nav = navigatorKey.currentState;
    if (_showing || nav == null) return;
    _showing = true;
    nav
        .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CrashCountdownScreen()))
        .whenComplete(() => _showing = false);
  }
}
