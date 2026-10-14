import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Phát còi SOS khi app đang mở (push lúc app nền / tắt dùng âm thanh của kênh "sos" / file .caf).
class SosAlarmService {
  SosAlarmService._();
  static final instance = SosAlarmService._();

  /// Còi tự tắt sau khoảng này nếu không ai bấm tắt.
  static const maxDuration = Duration(seconds: 30);

  final ringing = ValueNotifier<bool>(false);
  AudioPlayer? _player;
  Timer? _stopTimer;

  Future<void> play() async {
    if (ringing.value) return;
    ringing.value = true;
    try {
      final player = _player ??= AudioPlayer();
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(usageType: AndroidUsageType.alarm, audioFocus: AndroidAudioFocus.gainTransient),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/sos_siren.wav'), volume: 1);
      _stopTimer?.cancel();
      _stopTimer = Timer(maxDuration, stop);
    } catch (e) {
      debugPrint('SOS alarm: $e');
      ringing.value = false;
    }
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    ringing.value = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
