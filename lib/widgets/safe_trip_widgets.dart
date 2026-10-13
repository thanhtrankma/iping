import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/location_service.dart';
import '../services/safe_trip_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'common.dart';
import 'glass.dart';

/// Thành phần giao diện dùng chung cho "Về an toàn": đếm ngược, thanh tiến độ,
/// nút điều khiển chuyến của mình, lớp bản đồ (cờ điểm đến + đường nét đứt).

/// Một chuyến kèm nhóm của nó (ở chế độ "Tất cả bạn bè" có thể nhiều nhóm).
typedef GroupSafeTrip = ({String gid, SafeTrip trip});

String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes phút';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

/// "còn 12 phút" / "quá giờ 5 phút".
String safeTripCountdown(SafeTrip t, DateTime now) {
  final secs = t.remaining(now).inSeconds;
  if (t.isLate(now)) {
    final m = (-secs / 60).floor();
    return m <= 0 ? 'vừa quá giờ' : 'quá giờ ${_durationLabel(m)}';
  }
  final m = (secs / 60).ceil();
  return m <= 0 ? 'sắp tới giờ' : 'còn ${_durationLabel(m)}';
}

/// Màu trạng thái: xanh khi đang đi, đỏ khi quá giờ.
Color safeTripColor(SafeTrip t, DateTime now) => t.isLate(now) ? AppColors.sos : AppColors.online;

/// Dựng lại định kỳ để đếm ngược luôn đúng.
class SafeTripTicker extends StatefulWidget {
  const SafeTripTicker({super.key, required this.builder, this.interval = const Duration(seconds: 30)});
  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration interval;

  @override
  State<SafeTripTicker> createState() => _SafeTripTickerState();
}

class _SafeTripTickerState extends State<SafeTripTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

/// Thao tác trên chuyến của chính mình (có xác nhận / báo lỗi).
class SafeTripActions {
  static Future<void> arrive(BuildContext context, String gid) async {
    try {
      await SafeTripService.instance.arrive(gid);
      if (context.mounted) showMessage(context, 'Đã báo nhóm bạn về tới nơi an toàn ✅');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không gửi được: $e');
    }
  }

  static Future<void> extend(BuildContext context, String gid, SafeTrip trip) async {
    try {
      await SafeTripService.instance.extend(gid, trip);
      final now = DateTime.now();
      final due = (trip.dueAt.isAfter(now) ? trip.dueAt : now).add(SafeTripService.extendStep);
      if (context.mounted) showMessage(context, 'Đã gia hạn tới ${clock(due)}');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không gia hạn được: $e');
    }
  }

  /// Kết thúc chuyến; khi đang quá giờ là "Tôi ổn" (nhóm nhận tin đã an toàn).
  static Future<void> end(BuildContext context, String gid, SafeTrip trip) async {
    final late = trip.isLate(DateTime.now());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(late ? Icons.verified_user_rounded : Icons.shield_outlined, color: AppColors.online, size: 36),
        title: Text(late ? 'Báo bạn vẫn an toàn?' : 'Kết thúc chuyến về ${trip.destName}?'),
        content: Text(late
            ? 'Nhóm sẽ nhận thông báo bạn đã an toàn và chuyến về ${trip.destName} sẽ kết thúc.'
            : 'Nhóm sẽ không còn theo dõi chuyến này và bạn sẽ không được cảnh báo nếu chưa tới.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(late ? 'Huỷ' : 'Tiếp tục đi')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: late ? AppColors.online : AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(late ? 'Tôi ổn' : 'Kết thúc'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SafeTripService.instance.end(gid, trip);
    } catch (e) {
      if (context.mounted) showMessage(context, 'Không gửi được: $e');
    }
  }
}

/// Nút viên thuốc bên trong kính: nền trong mờ (không lồng thêm kính).
class SafeTripPillButton extends StatelessWidget {
  const SafeTripPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.filled = false,
    this.icon,
  });
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = color ?? scheme.onSurface;
    final fg = filled ? Colors.white : accent;
    final bg = filled
        ? accent
        : (color != null ? accent.withValues(alpha: dark ? 0.22 : 0.13) : scheme.onSurface.withValues(alpha: 0.08));
    return GlassPressable(
      onTap: onTap,
      shape: const StadiumBorder(),
      scale: 0.92,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: const StadiumBorder(), color: bg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ba nút điều khiển chuyến của mình: Đã tới · +15' · Kết thúc / Tôi ổn.
class SafeTripControls extends StatelessWidget {
  const SafeTripControls({super.key, required this.gid, required this.trip, required this.now});
  final String gid;
  final SafeTrip trip;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final late = trip.isLate(now);
    return Row(
      children: [
        Expanded(
          child: SafeTripPillButton(
            label: 'Đã tới',
            icon: Icons.check_rounded,
            color: AppColors.online,
            filled: true,
            onTap: () => SafeTripActions.arrive(context, gid),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SafeTripPillButton(
            label: "+${SafeTripService.extendStep.inMinutes}'",
            onTap: () => SafeTripActions.extend(context, gid, trip),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SafeTripPillButton(
            label: late ? 'Tôi ổn' : 'Kết thúc',
            color: late ? AppColors.online : null,
            onTap: () => SafeTripActions.end(context, gid, trip),
          ),
        ),
      ],
    );
  }
}

/// Thanh tiến độ mảnh dạng viên thuốc.
class SafeTripProgressBar extends StatelessWidget {
  const SafeTripProgressBar({super.key, required this.value, required this.color, this.height = 6});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1);
    return Container(
      height: height,
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: track),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.04, 1.0),
        child: DecoratedBox(decoration: ShapeDecoration(shape: const StadiumBorder(), color: color)),
      ),
    );
  }
}

/// Vị trí hiện tại của mình (để tính tiến độ).
LatLng? mySafeTripPosition() {
  final p = LocationService.instance.lastPosition.value;
  return p == null ? null : LatLng(p.latitude, p.longitude);
}

/// Thẻ trạng thái chuyến (đặt bên trong một bề mặt kính: chỉ dùng nền trong mờ).
/// [name] null = chuyến của chính mình.
class SafeTripStatusCard extends StatelessWidget {
  const SafeTripStatusCard({
    super.key,
    required this.gid,
    required this.trip,
    this.name,
    this.current,
    this.controls = false,
  });
  final String gid;
  final SafeTrip trip;
  final String? name;
  final LatLng? current;
  final bool controls;

  @override
  Widget build(BuildContext context) {
    return SafeTripTicker(builder: (context, now) {
      final scheme = Theme.of(context).colorScheme;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final late = trip.isLate(now);
      final color = safeTripColor(trip, now);
      final secondary = scheme.onSurface.withValues(alpha: 0.55);
      final pos = current;
      final progress = pos == null || trip.start == null ? null : trip.progress(pos);
      final who = name == null ? 'Đang về' : '$name đang về';
      final title = late
          ? (name == null ? 'Bạn đã quá giờ về ${trip.destName}' : '$name quá giờ, chưa tới ${trip.destName}')
          : '$who ${trip.destName}';

      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: ShapeDecoration(
          shape: glassShape(radius: 22),
          color: late
              ? AppColors.sos.withValues(alpha: dark ? 0.2 : 0.1)
              : (dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GlassIconBadge(icon: late ? Icons.warning_rounded : Icons.shield_rounded, color: color, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: late ? AppColors.sos : scheme.onSurface)),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Dự kiến ${clock(trip.dueAt)} · '),
                          TextSpan(
                            text: safeTripCountdown(trip, now),
                            style: TextStyle(
                                color: late ? AppColors.sos : secondary,
                                fontWeight: late ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ]),
                        style: TextStyle(fontSize: 14, color: secondary, letterSpacing: -0.1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              SafeTripProgressBar(value: progress, color: color),
            ],
            if (controls) ...[
              const SizedBox(height: 12),
              SafeTripControls(gid: gid, trip: trip, now: now),
            ],
          ],
        ),
      );
    });
  }
}

/// Sheet kính điều khiển chuyến của mình; tự đóng khi chuyến kết thúc.
Future<void> showMySafeTripSheet(BuildContext context, String gid) {
  return showGlassSheet<void>(
    context,
    builder: (ctx) => _MySafeTripSheet(gid: gid),
  );
}

class _MySafeTripSheet extends StatefulWidget {
  const _MySafeTripSheet({required this.gid});
  final String gid;

  @override
  State<_MySafeTripSheet> createState() => _MySafeTripSheetState();
}

class _MySafeTripSheetState extends State<_MySafeTripSheet> {
  late final Stream<SafeTrip?> _trip = SafeTripService.instance.mine(widget.gid);
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SafeTrip?>(
      stream: _trip,
      builder: (context, snap) {
        final trip = snap.data;
        if (trip == null) {
          if (snap.connectionState == ConnectionState.active && !_closing) {
            _closing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).maybePop();
            });
          }
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator.adaptive()));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetTitle('Về an toàn',
                  subtitle: 'Nhóm sẽ được báo khi bạn tới nơi, hoặc nếu quá giờ mà chưa tới.'),
              ValueListenableBuilder(
                valueListenable: LocationService.instance.lastPosition,
                builder: (context, _, __) => SafeTripStatusCard(
                  gid: widget.gid,
                  trip: trip,
                  current: mySafeTripPosition(),
                  controls: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lớp bản đồ cho các chuyến đang mở: vùng điểm đến, đường nét đứt từ vị trí hiện tại
/// tới điểm đến (đỏ nếu quá giờ) và cờ ở điểm đến.
List<Widget> safeTripLayers(
  List<GroupSafeTrip> trips, {
  required Map<String, LatLng> current,
  required DateTime now,
  void Function(GroupSafeTrip t)? onTap,
}) {
  if (trips.isEmpty) return const [];
  return [
    CircleLayer(circles: [
      for (final t in trips)
        CircleMarker(
          point: t.trip.dest,
          radius: t.trip.radius,
          useRadiusInMeter: true,
          color: safeTripColor(t.trip, now).withValues(alpha: 0.12),
          borderColor: safeTripColor(t.trip, now).withValues(alpha: 0.6),
          borderStrokeWidth: 1.5,
        ),
    ]),
    PolylineLayer(polylines: [
      for (final t in trips)
        if (current[t.trip.uid] != null)
          Polyline(
            points: [current[t.trip.uid]!, t.trip.dest],
            strokeWidth: 4,
            color: safeTripColor(t.trip, now).withValues(alpha: 0.85),
            borderColor: Colors.white.withValues(alpha: 0.9),
            borderStrokeWidth: 1.5,
            pattern: StrokePattern.dashed(segments: const [10, 8]),
          ),
    ]),
    MarkerLayer(markers: [
      for (final t in trips)
        Marker(
          point: t.trip.dest,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap(t),
            child: _SafeTripFlag(color: safeTripColor(t.trip, now)),
          ),
        ),
    ]),
  ];
}

class _SafeTripFlag extends StatelessWidget {
  const _SafeTripFlag({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 3))],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(color, Colors.white, 0.18)!, color],
          ),
        ),
        child: const Center(child: Icon(Icons.flag_rounded, size: 19, color: Colors.white)),
      ),
    );
  }
}
