import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Nút "Dừng chia sẻ" trên thông báo cố định (dịch vụ nền) của Android khi đang chia sẻ vị trí.
///
/// geolocator không cho thêm nút vào thông báo của nó, nên phía Android (MainActivity) tìm thông báo
/// đó và đăng lại kèm nút. Bấm nút → mở app với action `com.iping.app.STOP_SHARING` → gọi [onStop].
class SharingNotification {
  SharingNotification._();
  static final instance = SharingNotification._();

  static const channel = MethodChannel('iping/sharing');

  Future<void> Function()? _onStop;
  bool _handlerSet = false;

  /// Đăng ký hành động khi người dùng bấm "Dừng chia sẻ". Trả về `true` nếu đã có yêu cầu dừng
  /// đang chờ (bấm nút khi app chưa chạy) — khi đó người gọi KHÔNG được tự bật lại chia sẻ.
  Future<bool> init(Future<void> Function() onStop) async {
    _onStop = onStop;
    if (!_isAndroid) return false;
    if (!_handlerSet) {
      _handlerSet = true;
      channel.setMethodCallHandler(_handle);
    }
    try {
      return await channel.invokeMethod<bool>('takePendingStop') ?? false;
    } catch (e) {
      debugPrint('Sharing notification init: $e');
      return false;
    }
  }

  /// Gắn nút "Dừng chia sẻ" vào thông báo dịch vụ nền (gọi sau khi luồng vị trí đã bắt đầu).
  Future<void> attachStopAction() async {
    if (!_isAndroid) return;
    try {
      await channel.invokeMethod<bool>('attachStopAction', {
        'title': 'Dừng chia sẻ',
      });
    } catch (e) {
      debugPrint('Attach stop action: $e');
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'stopSharing') return null;
    final onStop = _onStop;
    if (onStop == null) return false;
    await onStop();
    return true;
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
}

/// Hiện thông báo ngắn ở bất kỳ màn hình nào (dùng [ScaffoldMessenger] toàn cục).
void showGlobalMessage(GlobalKey<ScaffoldMessengerState> key, String text) {
  key.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
