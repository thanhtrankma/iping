import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_service.dart';
import 'pause_schedule.dart';

/// Tạm dừng chia sẻ vị trí với từng nhóm (chế độ ẩn theo nhóm).
/// Lưu cục bộ để giữ qua lần mở app sau, và tự bật lại khi hết hạn.
class PrivacyService {
  PrivacyService._();
  static final instance = PrivacyService._();

  static const _prefKey = 'paused_groups';

  final paused = ValueNotifier<PauseSchedule>(const PauseSchedule());

  Timer? _timer;
  bool _loaded = false;
  /// Nhóm đã được đánh dấu `sharing: false` trong phiên này (chỉ ghi một lần).
  final Set<String> _marked = {};

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = (await SharedPreferences.getInstance()).getString(_prefKey);
    if (raw != null) {
      try {
        paused.value = PauseSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>).prune(DateTime.now());
      } catch (e) {
        debugPrint('Paused groups: $e');
      }
    }
    _schedule();
  }

  bool isPaused(String gid) => paused.value.isPaused(gid, DateTime.now());

  /// Tạm dừng chia sẻ với nhóm [gid] đến [until] (null = cho đến khi bật lại).
  Future<void> pause(String gid, DateTime? until) async {
    paused.value = paused.value.pause(gid, until);
    await _save();
    _schedule();
    _marked.remove(gid);
    await markPaused(gid);
  }

  /// Chia sẻ lại với nhóm [gid] ngay.
  Future<void> resume(String gid) async {
    paused.value = paused.value.resume(gid);
    _marked.remove(gid);
    await _save();
    _schedule();
    await _clearMark(gid);
    await LocationService.instance.refresh();
  }

  /// Ghi `sharing: false` (kèm hạn) vào vị trí của mình trong nhóm, chỉ một lần mỗi phiên.
  /// Dùng `update` để không tạo doc rỗng khi chưa từng chia sẻ (khi đó vốn không có gì để ẩn).
  Future<void> markPaused(String gid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !_marked.add(gid)) return;
    final until = paused.value.untilOf(gid);
    try {
      await FirebaseFirestore.instance.doc('groups/$gid/locations/$uid').update({
        'sharing': false,
        'pausedUntil': until == null ? null : Timestamp.fromDate(until),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Mark paused $gid: $e');
    }
  }

  Future<void> _clearMark(String gid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .doc('groups/$gid/locations/$uid')
          .update({'pausedUntil': FieldValue.delete()});
    } catch (e) {
      debugPrint('Clear paused $gid: $e');
    }
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setString(_prefKey, jsonEncode(paused.value.toJson()));

  /// Hẹn giờ tới hạn gần nhất để tự bật lại.
  void _schedule() {
    _timer?.cancel();
    final next = paused.value.nextExpiry(DateTime.now());
    if (next == null) return;
    _timer = Timer(next.difference(DateTime.now()) + const Duration(seconds: 1), _expire);
  }

  Future<void> _expire() async {
    final now = DateTime.now();
    final expired = paused.value.expired(now);
    if (expired.isEmpty) return _schedule();
    paused.value = paused.value.prune(now);
    _marked.removeAll(expired);
    await _save();
    _schedule();
    for (final gid in expired) {
      await _clearMark(gid);
    }
    await LocationService.instance.refresh();
  }
}
