import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../services/geocode_service.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/safe_trip_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/map_view.dart';
import 'history_screen.dart' show durationText;

/// "Về an toàn": chọn điểm đến + giờ dự kiến tới, nhóm sẽ được báo khi tới nơi
/// hoặc khi quá giờ mà chưa tới (giống Check In của iOS 17 / Safe Arrival của Life360).
class SafeTripScreen extends StatefulWidget {
  const SafeTripScreen({super.key, required this.group});
  final Group group;

  @override
  State<SafeTripScreen> createState() => _SafeTripScreenState();
}

/// Điểm đến đang chọn: địa điểm đã lưu, điểm hẹn, hoặc điểm chạm trên bản đồ.
class _Dest {
  const _Dest({required this.key, required this.point, required this.icon, required this.color, this.name});
  final String key;
  final LatLng point;
  final IconData icon;
  final Color color;

  /// `null` khi đang tra địa chỉ cho điểm chạm trên bản đồ.
  final String? name;

  static const customKey = 'custom';
  static const customFallback = 'Vị trí đã chọn';

  bool get isCustom => key == customKey;
  String get label => name ?? customFallback;

  _Dest withName(String name) => _Dest(key: key, point: point, icon: icon, color: color, name: name);
}

const _minLead = Duration(minutes: 5);

class _SafeTripScreenState extends State<SafeTripScreen> {
  final _map = MapController();
  final _panelKey = GlobalKey();
  late final Stream<List<Place>> _places = GroupService.instance.places(widget.group.id);
  late final Stream<List<Meetup>> _meetups = GroupService.instance.activeMeetups(widget.group.id);

  Position? _pos;
  _Dest? _dest;
  late DateTime _due = _roundUp(DateTime.now().add(const Duration(minutes: 30)));

  /// Người dùng đã tự chỉnh giờ: không tự tính lại khi đổi điểm đến.
  bool _manual = false;
  bool _starting = false;
  int _geocodeToken = 0;
  Timer? _ticker;

  LatLng? get _me => _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);

  double? get _distance {
    final me = _me, d = _dest;
    if (me == null || d == null) return null;
    return Geolocator.distanceBetween(me.latitude, me.longitude, d.point.latitude, d.point.longitude);
  }

  @override
  void initState() {
    super.initState();
    final loc = LocationService.instance;
    _pos = loc.lastPosition.value;
    loc.lastPosition.addListener(_onPosition);
    if (_pos == null) {
      loc.currentPosition().then((p) {
        if (!mounted || p == null || _pos != null) return;
        setState(() => _pos = p);
        if (_dest == null) {
          _map.move(LatLng(p.latitude, p.longitude), 15);
        } else {
          _suggest();
          _fit();
        }
      });
    }
    // Giữ "~25 phút" luôn đúng và giờ dự kiến không lùi quá sát hiện tại.
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {
        final min = _minDue();
        if (_due.isBefore(min)) _due = _roundUp(min);
      });
    });
  }

  @override
  void dispose() {
    LocationService.instance.lastPosition.removeListener(_onPosition);
    _ticker?.cancel();
    super.dispose();
  }

  void _onPosition() {
    final p = LocationService.instance.lastPosition.value;
    if (!mounted || p == null) return;
    final first = _pos == null;
    setState(() {
      _pos = p;
      if (first) _suggest();
    });
  }

  // ---- Thời gian ----

  static DateTime _roundUp(DateTime t) {
    final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    return base.isBefore(t) ? base.add(const Duration(minutes: 1)) : base;
  }

  DateTime _minDue() => DateTime.now().add(_minLead);

  DateTime _clampDue(DateTime t) {
    final min = _minDue();
    return t.isBefore(min) ? _roundUp(min) : t;
  }

  /// Tính lại giờ dự kiến theo quãng đường và tốc độ hiện tại (trừ khi người dùng đã tự chọn).
  void _suggest() {
    if (_manual || _dest == null) return;
    final speed = _pos?.speed;
    final d = suggestSafeTripDuration(_distance ?? 0, speed: speed != null && speed >= 0 ? speed : null);
    _due = _clampDue(_roundUp(DateTime.now().add(d)));
  }

  void _adjust(int minutes) {
    setState(() {
      _manual = true;
      _due = _clampDue(_due.add(Duration(minutes: minutes)));
    });
  }

  Future<void> _pickTime() async {
    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
      helpText: 'Dự kiến tới lúc',
      cancelText: 'Huỷ',
      confirmText: 'Xong',
    );
    if (tod == null || !mounted) return;
    final now = DateTime.now();
    var t = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    // Giờ đã qua trong hôm nay → hiểu là ngày mai.
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    setState(() {
      _manual = true;
      _due = _clampDue(t);
    });
  }

  // ---- Điểm đến ----

  void _select(_Dest d) {
    setState(() {
      _dest = d;
      _suggest();
    });
    _fit();
  }

  Future<void> _tapMap(LatLng p) async {
    HapticFeedback.selectionClick();
    final token = ++_geocodeToken;
    setState(() {
      _dest = _Dest(key: _Dest.customKey, point: p, icon: Icons.push_pin_rounded, color: AppColors.online);
      _suggest();
    });
    String name = _Dest.customFallback;
    try {
      final addr = await GeocodeService.instance.address(p.latitude, p.longitude);
      final first = addr.split(',').first.trim();
      // Không tra được địa chỉ thì service trả về toạ độ "lat, lng".
      final isCoords = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(first);
      if (first.isNotEmpty && !isCoords) name = first;
    } catch (_) {}
    if (!mounted || token != _geocodeToken || _dest?.isCustom != true) return;
    setState(() => _dest = _dest!.withName(name));
  }

  /// Đưa cả vị trí hiện tại và điểm đến vào khung nhìn, chừa chỗ cho thanh trên và bảng dưới.
  void _fit() {
    final d = _dest;
    if (d == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final media = MediaQuery.of(context);
      final panel = _panelKey.currentContext?.size?.height ?? 380;
      final pts = [d.point, if (_me != null) _me!];
      try {
        _map.fitCamera(CameraFit.coordinates(
          coordinates: pts,
          maxZoom: 16,
          padding: EdgeInsets.fromLTRB(48, media.padding.top + 90, 48, panel + media.padding.bottom + 40),
        ));
      } catch (_) {
        // Bản đồ chưa sẵn sàng.
      }
    });
  }

  // ---- Bắt đầu ----

  Future<void> _start() async {
    final d = _dest;
    if (d == null || _starting) return;
    final due = _clampDue(_due);
    setState(() => _starting = true);
    String? err;
    try {
      err = await SafeTripService.instance.start(
        widget.group.id,
        destName: d.label,
        destLat: d.point.latitude,
        destLng: d.point.longitude,
        dueAt: due,
        radius: SafeTripService.defaultRadius,
      );
    } catch (e) {
      err = 'Không bắt đầu được: $e';
    }
    if (!mounted) return;
    if (err != null) {
      setState(() => _starting = false);
      showMessage(context, err);
      return;
    }
    HapticFeedback.mediumImpact();
    showMessage(context, 'Đã báo cho ${widget.group.name}');
    Navigator.pop(context);
  }

  // ---- Giao diện ----

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final d = _dest;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IPingMap(
              controller: _map,
              center: me ?? defaultCenter,
              zoom: 15,
              onTap: (_, p) => _tapMap(p),
              layers: [
                if (d != null)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: d.point,
                      radius: SafeTripService.defaultRadius,
                      useRadiusInMeter: true,
                      color: d.color.withValues(alpha: 0.16),
                      borderColor: Colors.white.withValues(alpha: 0.95),
                      borderStrokeWidth: 2,
                    ),
                  ]),
                if (d != null && me != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: [me, d.point],
                      strokeWidth: 4,
                      color: AppColors.brand.withValues(alpha: 0.85),
                      borderColor: Colors.white.withValues(alpha: 0.9),
                      borderStrokeWidth: 1.5,
                      pattern: StrokePattern.dashed(segments: const [10, 8]),
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (me != null) Marker(point: me, width: 34, height: 34, child: const _MeDot()),
                  if (d != null)
                    Marker(
                      point: d.point,
                      width: 46,
                      height: 46,
                      child: _DestPin(icon: d.icon, color: d.color),
                    ),
                ]),
              ],
            ),
          ),
          // Thanh trên nổi: nút quay lại + gợi ý.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  GlassButton(
                    size: 46,
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Quay lại',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Glass(
                      capsule: true,
                      opacity: 0.65,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: AppColors.brand),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text('Chạm bản đồ để chọn điểm đến',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Glass(
                  key: _panelKey,
                  radius: 34,
                  opacity: 0.8,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  child: Material(
                    type: MaterialType.transparency,
                    child: _panel(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Về an toàn',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 3),
              Text(
                'Nhóm sẽ được báo khi bạn tới nơi, hoặc nếu bạn chưa tới đúng giờ.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: secondary, letterSpacing: -0.1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _destinationChips(),
        const SizedBox(height: 10),
        _destinationRow(context, secondary),
        const SizedBox(height: 14),
        _timeBlock(context, secondary),
        const SizedBox(height: 16),
        _StartButton(
          enabled: _dest != null,
          busy: _starting,
          onTap: _start,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.near_me_rounded, size: 13, color: secondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Chia sẻ vị trí sẽ được bật trong suốt chuyến đi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _destinationChips() {
    return StreamBuilder<List<Place>>(
      stream: _places,
      builder: (context, placeSnap) => StreamBuilder<List<Meetup>>(
        stream: _meetups,
        builder: (context, meetSnap) {
          final places = placeSnap.data ?? const <Place>[];
          final meetups = meetSnap.data ?? const <Meetup>[];
          final d = _dest;
          final chips = <Widget>[
            if (d != null && d.isCustom)
              _Chip(
                icon: d.icon,
                color: d.color,
                label: d.name ?? 'Đang tìm…',
                selected: true,
                onTap: _fit,
              ),
            for (final p in places)
              _Chip(
                icon: _placeIcon(p.name),
                color: _placeColor(p.name),
                label: p.name,
                selected: d?.key == 'p:${p.id}',
                onTap: () => _select(_Dest(
                  key: 'p:${p.id}',
                  point: p.point,
                  icon: _placeIcon(p.name),
                  color: _placeColor(p.name),
                  name: p.name,
                )),
              ),
            for (final m in meetups)
              _Chip(
                icon: Icons.flag_rounded,
                color: AppColors.sos,
                label: m.title.isEmpty ? 'Điểm hẹn' : m.title,
                selected: d?.key == 'm:${m.id}',
                onTap: () => _select(_Dest(
                  key: 'm:${m.id}',
                  point: m.point,
                  icon: Icons.flag_rounded,
                  color: AppColors.sos,
                  name: m.title.isEmpty ? 'Điểm hẹn' : m.title,
                )),
              ),
          ];
          if (chips.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => chips[i],
            ),
          );
        },
      ),
    );
  }

  Widget _destinationRow(BuildContext context, Color secondary) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final d = _dest;
    final dist = _distance;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: glassShape(radius: 20),
        color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            GlassIconBadge(
              icon: d?.icon ?? Icons.place_outlined,
              color: d?.color ?? AppColors.gray,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d == null ? 'Chưa chọn điểm đến' : (d.name ?? 'Đang tìm địa chỉ…'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    d == null
                        ? 'Chọn địa điểm phía trên hoặc chạm bản đồ'
                        : dist == null
                            ? 'Đang xác định vị trí của bạn…'
                            : 'Cách bạn ${distanceLabel(dist)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeBlock(BuildContext context, Color secondary) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final left = _due.difference(now);
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(_due.year, _due.month, _due.day);
    final dayDiff = dueDay.difference(today).inDays;
    final hhmm = '${_due.hour.toString().padLeft(2, '0')}:${_due.minute.toString().padLeft(2, '0')}';
    final canMinus = !_due.subtract(const Duration(minutes: 5)).isBefore(_minDue().subtract(const Duration(seconds: 59)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Dự kiến tới ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                TextSpan(
                  text: hhmm,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (dayDiff == 1)
                  TextSpan(
                    text: ' ngày mai',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                TextSpan(
                  text: '  (~${durationText(left.isNegative ? Duration.zero : left)})',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: secondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _AdjustButton(label: '−5', onTap: canMinus ? () => _adjust(-5) : null),
            const SizedBox(width: 8),
            _AdjustButton(label: '+5', onTap: () => _adjust(5)),
            const SizedBox(width: 8),
            _AdjustButton(label: '+15', onTap: () => _adjust(15)),
            const SizedBox(width: 8),
            Expanded(
              child: _AdjustButton(label: 'Chọn giờ', icon: Icons.schedule_rounded, onTap: _pickTime, accent: true),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- Thành phần nhỏ ----

/// Màu đệm bên trong bảng kính (không lồng kính trong kính).
Color _fill(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.09)
    : Colors.white.withValues(alpha: 0.55);

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPressable(
      onTap: onTap,
      shape: const StadiumBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: selected ? AppColors.brand : _fill(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? Colors.white : color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: selected ? Colors.white : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.label, required this.onTap, this.icon, this.accent = false});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final fg = !enabled
        ? scheme.onSurface.withValues(alpha: 0.3)
        : accent
            ? scheme.primary
            : scheme.onSurface;
    return GlassPressable(
      onTap: onTap,
      shape: const StadiumBorder(),
      child: Container(
        height: 38,
        constraints: const BoxConstraints(minWidth: 54),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: const StadiumBorder(), color: _fill(context)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.busy, required this.onTap});
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && !busy;
    return GlassPressable(
      onTap: active ? onTap : null,
      shape: const StadiumBorder(),
      scale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 54,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          gradient: enabled ? AppColors.brandGradient : null,
          color: enabled ? null : scheme.onSurface.withValues(alpha: 0.1),
          shadows: enabled
              ? [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded,
                      size: 20, color: enabled ? Colors.white : scheme.onSurface.withValues(alpha: 0.35)),
                  const SizedBox(width: 8),
                  Text(
                    'Bắt đầu',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: enabled ? Colors.white : scheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Chấm vị trí của chính mình kiểu Apple Maps.
class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.brand.withValues(alpha: 0.18)),
      alignment: Alignment.center,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brand,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
        ),
      ),
    );
  }
}

/// Ghim điểm đến: vòng trắng, nền màu, biểu tượng địa điểm.
class _DestPin extends StatelessWidget {
  const _DestPin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(color, Colors.white, 0.18)!, color],
          ),
        ),
        child: Icon(icon, size: 21, color: Colors.white),
      ),
    );
  }
}

// Giống places_tab: biểu tượng & màu theo tên địa điểm.
Color _placeColor(String name) {
  final n = name.toLowerCase();
  if (n.contains('nhà') || n.contains('home')) return AppColors.orange;
  if (n.contains('trường') || n.contains('học')) return AppColors.indigo;
  if (n.contains('công ty') || n.contains('văn phòng') || n.contains('làm')) return AppColors.teal;
  if (n.contains('gym') || n.contains('tập')) return AppColors.pink;
  return AppColors.brand;
}

IconData _placeIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('nhà') || n.contains('home')) return Icons.home_rounded;
  if (n.contains('trường') || n.contains('học')) return Icons.school_rounded;
  if (n.contains('công ty') || n.contains('văn phòng') || n.contains('làm')) return Icons.work_rounded;
  if (n.contains('gym') || n.contains('tập')) return Icons.fitness_center_rounded;
  return Icons.place_rounded;
}
