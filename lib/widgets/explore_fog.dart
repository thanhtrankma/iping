import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/area_service.dart';
import '../services/hex_grid.dart';
import '../theme.dart';

/// Ô láng giềng nằm bên kia cạnh thứ i của một ô (cạnh nối đỉnh i và i+1 trong
/// [HexGrid.cornerOffsets]: đỉnh 0 ở trên cùng, đi theo chiều kim đồng hồ).
const hexEdgeNeighbour = [(0, 1), (1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1)];

// ---------------------------------------------------------------------------
// Hiệu ứng "nổ" ô lục giác
// ---------------------------------------------------------------------------

class _Pop {
  _Pop(this.cell, this.start, this.duration, this.particles);
  final HexCell cell;
  final Duration start;
  final Duration duration;
  final int particles;
}

class _Burst {
  _Burst(this.cell, this.count, this.start);
  final HexCell cell;
  final int count;
  final Duration start;
  TextPainter? label;
}

/// Điều khiển hiệu ứng mở ô kiểu Bump: mỗi ô mới bật lên, loé sáng, toả sóng và bắn mảnh vụn;
/// một loạt ô mở cùng lúc chạy thành làn sóng từ vị trí của mình ra ngoài.
class HexRevealController extends ChangeNotifier {
  HexRevealController({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration _now = Duration.zero;
  final Map<HexCell, _Pop> _pops = {};
  final List<_Burst> _bursts = [];
  final Set<HexCell> _changed = {};
  Duration _lastHaptic = Duration.zero;
  bool _introDone = false;

  /// Ô mở tạm chỉ để xem thử hiệu ứng (bản debug), không ghi vào dữ liệu khám phá.
  final Set<HexCell> demo = {};

  static const popDuration = Duration(milliseconds: 720);
  static const burstDuration = Duration(milliseconds: 1100);

  /// Các ô đang (hoặc sắp) nổ: lớp sương tĩnh coi như chưa mở để hiệu ứng tự vẽ chúng.
  Iterable<HexCell> get hidden => _pops.keys;
  bool isHidden(HexCell c) => _pops.containsKey(c);
  bool get introDone => _introDone;

  /// Các ô vừa đổi trạng thái ẩn/hiện từ lần gọi trước (để làm mới cache theo bucket).
  Set<HexCell> takeChanged() {
    final out = Set<HexCell>.of(_changed);
    _changed.clear();
    return out;
  }

  Duration get now => _now;

  /// Cho [cells] nổ lần lượt theo khoảng cách tới [origin]: mỗi vòng trễ [stagger].
  void pop(
    Iterable<HexCell> cells, {
    HexCell? origin,
    Duration stagger = const Duration(milliseconds: 45),
    Duration maxDelay = const Duration(milliseconds: 900),
    int particles = 7,
    Duration? duration,
    bool burst = true,
    bool demoOnly = false,
  }) {
    if (demoOnly) demo.addAll(cells);
    final list = cells.where((c) => !_pops.containsKey(c)).toList();
    if (list.isEmpty) return;
    final o = origin ?? list.first;
    list.sort((a, b) => HexGrid.distance(o, a).compareTo(HexGrid.distance(o, b)));
    final base = HexGrid.distance(o, list.first);
    for (final c in list) {
      final ring = HexGrid.distance(o, c) - base;
      final delay = stagger * ring;
      _pops[c] = _Pop(c, _now + (delay > maxDelay ? maxDelay : delay), duration ?? popDuration, particles);
      _changed.add(c);
    }
    if (burst) {
      // Ô mở liên tiếp khi đang đi: cộng dồn vào nhãn "+N" gần nhất thay vì chồng nhiều nhãn.
      final recent = _bursts.where((b) => _now - b.start < const Duration(milliseconds: 650)).toList();
      if (recent.isNotEmpty) {
        final b = recent.last;
        _bursts.remove(b);
        _bursts.add(_Burst(list.first, b.count + list.length, b.start));
      } else {
        _bursts.add(_Burst(list.first, list.length, _now));
      }
    }
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  /// Làn sóng mở màn: các ô đang thấy bung ra lần lượt từ vị trí của mình.
  void intro(List<HexCell> visible, HexCell origin) {
    if (_introDone) return;
    _introDone = true;
    if (visible.isEmpty) return;
    pop(
      visible,
      origin: origin,
      stagger: const Duration(milliseconds: 28),
      maxDelay: const Duration(milliseconds: 1300),
      particles: 4,
      duration: const Duration(milliseconds: 620),
      burst: false,
    );
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    var hapticDue = false;
    _pops.removeWhere((c, p) {
      final started = _now >= p.start;
      if (started && _now - p.start < const Duration(milliseconds: 20)) hapticDue = true;
      final done = _now >= p.start + p.duration;
      if (done) _changed.add(c);
      return done;
    });
    _bursts.removeWhere((b) => _now >= b.start + burstDuration);
    if (hapticDue && _now - _lastHaptic > const Duration(milliseconds: 90)) {
      _lastHaptic = _now;
      HapticFeedback.selectionClick();
    }
    if (_pops.isEmpty && _bursts.isEmpty) _ticker.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Cache đường viền / vùng đã mở theo bucket 64 x 64 ô
// ---------------------------------------------------------------------------

class _Bucket {
  _Bucket(this.anchorX, this.anchorY, this.fill, this.edges);
  final double anchorX;
  final double anchorY;

  /// Mọi ô đã mở (đơn vị mét Mercator, gốc tại [anchorX], [anchorY], trục y hướng lên).
  final Path fill;

  /// Chỉ các cạnh giáp ô chưa mở: đường viền liền của cả vùng, giống Bump.
  final Path edges;
}

class _HexCache {
  final Map<(int, int), _Bucket?> _buckets = {};
  int _lastLen = -1;

  static (int, int) bucketKey(HexCell c) => (c.q >> HexGrid.bucketBits, c.r >> HexGrid.bucketBits);

  void clear() => _buckets.clear();

  /// Đồng bộ với tập ô hiện tại. [changed] là các ô vừa đổi trạng thái ẩn (đang nổ / nổ xong).
  void sync(Set<HexCell> cells, Set<HexCell> changed) {
    final newlyAdded = changed.where(cells.contains).length;
    if (_lastLen < 0 || cells.length < _lastLen || cells.length - _lastLen > newlyAdded) {
      // Dữ liệu tải lại / đồng bộ / đổi tài khoản: dựng lại khi cần.
      _buckets.clear();
    } else {
      for (final c in changed) {
        _buckets.remove(bucketKey(c));
        for (final (dq, dr) in hexEdgeNeighbour) {
          _buckets.remove(bucketKey(HexCell(c.q + dq, c.r + dr)));
        }
      }
    }
    _lastLen = cells.length;
  }

  _Bucket? bucket((int, int) key, Set<HexCell> cells, bool Function(HexCell) hidden) {
    if (_buckets.containsKey(key)) return _buckets[key];
    final (bq, br) = key;
    final q0 = bq << HexGrid.bucketBits, r0 = br << HexGrid.bucketBits;
    const n = 1 << HexGrid.bucketBits;
    final (ax, ay) = HexGrid.centerXY(HexCell(q0, r0));
    final fill = Path();
    final edges = Path();
    var any = false;
    bool open(HexCell c) => cells.contains(c) && !hidden(c);
    final corners = HexGrid.cornerOffsets;
    for (var r = r0; r < r0 + n; r++) {
      for (var q = q0; q < q0 + n; q++) {
        final c = HexCell(q, r);
        if (!open(c)) continue;
        any = true;
        final (x, y) = HexGrid.centerXY(c);
        final cx = x - ax, cy = y - ay;
        fill.addPolygon([for (final (dx, dy) in corners) Offset(cx + dx, cy + dy)], true);
        for (var i = 0; i < 6; i++) {
          final (dq, dr) = hexEdgeNeighbour[i];
          if (open(HexCell(q + dq, r + dr))) continue;
          final (x1, y1) = corners[i];
          final (x2, y2) = corners[(i + 1) % 6];
          edges
            ..moveTo(cx + x1, cy + y1)
            ..lineTo(cx + x2, cy + y2);
        }
      }
    }
    final b = any ? _Bucket(ax, ay, fill, edges) : null;
    _buckets[key] = b;
    return b;
  }
}

// ---------------------------------------------------------------------------
// Lớp sương mù
// ---------------------------------------------------------------------------

/// Lớp "sương mù" của màn Khám phá theo phong cách Bump: phủ kín bản đồ, vùng đã đi qua
/// sáng lên thành một khối liền có viền lượn theo cạnh lục giác; ô mới mở thì "nổ".
class ExploreFogLayer extends StatefulWidget {
  const ExploreFogLayer({
    super.key,
    required this.cells,
    required this.revision,
    this.area,
    this.reveal,
    this.origin,
  });

  final Set<HexCell> cells;

  /// Đổi giá trị để buộc vẽ lại khi [cells] thay đổi tại chỗ.
  final int revision;
  final ExploreArea? area;

  /// Hiệu ứng nổ ô (tuỳ chọn).
  final HexRevealController? reveal;

  /// Ô đang đứng, làm tâm làn sóng mở màn.
  final HexCell? origin;

  @override
  State<ExploreFogLayer> createState() => _ExploreFogLayerState();
}

class _ExploreFogLayerState extends State<ExploreFogLayer> {
  final _cache = _HexCache();

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final reveal = widget.reveal;
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget paint() {
      _cache.sync(widget.cells, reveal?.takeChanged() ?? const {});
      return CustomPaint(
        size: Size.infinite,
        painter: _FogPainter(
          camera: camera,
          cells: widget.cells,
          cache: _cache,
          area: widget.area,
          reveal: reveal,
          dark: dark,
          revision: widget.revision,
          frame: reveal?.now ?? Duration.zero,
        ),
      );
    }

    if (reveal != null && !reveal.introDone && widget.origin != null && widget.cells.isNotEmpty) {
      final origin = widget.origin!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        reveal.intro(_visibleCells(camera, widget.cells, limit: 360, origin: origin), origin);
      });
    }

    return MobileLayerTransformer(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: reveal == null ? paint() : ListenableBuilder(listenable: reveal, builder: (_, __) => paint()),
        ),
      ),
    );
  }

  static List<HexCell> _visibleCells(MapCamera camera, Set<HexCell> cells, {required int limit, required HexCell origin}) {
    final ppm = 256 * math.pow(2, camera.zoom) / (2 * math.pi * HexGrid.earthRadius);
    final (cx, cy) = HexGrid.project(camera.center.latitude, camera.center.longitude);
    final mx = camera.size.x / 2 / ppm, my = camera.size.y / 2 / ppm;
    final out = <HexCell>[];
    for (final c in cells) {
      final (x, y) = HexGrid.centerXY(c);
      if ((x - cx).abs() <= mx && (y - cy).abs() <= my) out.add(c);
    }
    if (out.length > limit) {
      out.sort((a, b) => HexGrid.distance(origin, a).compareTo(HexGrid.distance(origin, b)));
      out.length = limit;
    }
    return out;
  }
}

class _FogPainter extends CustomPainter {
  _FogPainter({
    required this.camera,
    required this.cells,
    required this.cache,
    required this.area,
    required this.reveal,
    required this.dark,
    required this.revision,
    required this.frame,
  });

  final MapCamera camera;
  final Set<HexCell> cells;
  final _HexCache cache;
  final ExploreArea? area;
  final HexRevealController? reveal;
  final bool dark;
  final int revision;
  final Duration frame;

  // Bảng màu kiểu Bump: sương tím xám, vùng đã đi màu kem, viền xanh oải hương.
  Color get _fog => dark ? const Color(0xE0121828) : const Color(0xCCD8DDEE);
  Color get _explored => dark ? const Color(0x24FFF1D0) : const Color(0x99FFF8E7);
  Color get _edge => dark ? const Color(0xFF93A6FF) : const Color(0xFF7D93F2);
  static const _areaShade = Color(0x1F3B5BFD);
  static const _sparks = [Color(0xFF5B7CFF), Color(0xFFFFC94D), Color(0xFFFF7AB6), Color(0xFF58E0C0), Color(0xFFB18CFF)];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Mét Mercator -> điểm ảnh màn hình (bản đồ không xoay nên chỉ là tịnh tiến + co giãn).
    final ppm = 256 * math.pow(2, camera.zoom) / (2 * math.pi * HexGrid.earthRadius);
    final c = camera.center;
    final (cx, cy) = HexGrid.project(c.latitude, c.longitude);
    final o = camera.latLngToScreenPoint(c);
    Offset px(double x, double y) => Offset(o.x + (x - cx) * ppm, o.y - (y - cy) * ppm);
    final cellPx = HexGrid.size * ppm;

    // Bucket nằm trong khung hình (thêm lề 1 bucket).
    final hx = size.width / 2 / ppm + HexGrid.size * 2, hy = size.height / 2 / ppm + HexGrid.size * 2;
    final corners = [
      HexGrid.cellAtXY(cx - hx, cy - hy),
      HexGrid.cellAtXY(cx + hx, cy - hy),
      HexGrid.cellAtXY(cx - hx, cy + hy),
      HexGrid.cellAtXY(cx + hx, cy + hy),
    ];
    final bq0 = corners.map((e) => e.q).reduce(math.min) >> HexGrid.bucketBits;
    final bq1 = corners.map((e) => e.q).reduce(math.max) >> HexGrid.bucketBits;
    final br0 = corners.map((e) => e.r).reduce(math.min) >> HexGrid.bucketBits;
    final br1 = corners.map((e) => e.r).reduce(math.max) >> HexGrid.bucketBits;
    final hidden = reveal?.isHidden ?? (_) => false;
    final buckets = <_Bucket>[
      for (var bq = bq0 - 1; bq <= bq1 + 1; bq++)
        for (var br = br0 - 1; br <= br1 + 1; br++)
          if (cache.bucket((bq, br), cells, hidden) case final b?) b,
    ];

    void inBucket(_Bucket b, void Function() draw) {
      final p = px(b.anchorX, b.anchorY);
      canvas
        ..save()
        ..translate(p.dx, p.dy)
        ..scale(ppm, -ppm);
      draw();
      canvas.restore();
    }

    Path? areaPath;
    final a = area;
    if (a != null) {
      areaPath = Path()..fillType = PathFillType.evenOdd;
      for (final ring in a.ringsXY) {
        if (ring.length < 3) continue;
        areaPath.addPolygon([for (final (x, y) in ring) px(x, y)], true);
      }
    }

    // Ô đang nổ: tỉ lệ hiện tại của từng ô (0 = chưa bắt đầu).
    final popping = <(HexCell, double)>[];
    final r = reveal;
    if (r != null) {
      for (final h in r.hidden) {
        final p = r._pops[h]!;
        final t = (frame - p.start).inMicroseconds / p.duration.inMicroseconds;
        popping.add((h, t.clamp(0.0, 1.0)));
      }
    }

    List<Offset> hexAt(HexCell cell, double scale) {
      final (x, y) = HexGrid.centerXY(cell);
      final center = px(x, y);
      return [for (final (dx, dy) in HexGrid.cornerOffsets) center + Offset(dx * ppm * scale, -dy * ppm * scale)];
    }

    // 1. Sương + vùng đang xem, khoét vùng đã mở (và ô đang nổ theo độ bung).
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = _fog);
    if (areaPath != null) canvas.drawPath(areaPath, Paint()..color = _areaShade);
    final cut = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Colors.black;
    for (final b in buckets) {
      inBucket(b, () => canvas.drawPath(b.fill, cut));
    }
    for (final (cell, t) in popping) {
      if (t <= 0) continue;
      final s = _popScale(t);
      canvas.drawPath(Path()..addPolygon(hexAt(cell, s), true), cut);
    }
    final demo = Path();
    for (final d in r?.demo ?? const <HexCell>{}) {
      if (!hidden(d)) demo.addPolygon(hexAt(d, 1), true);
    }
    canvas.drawPath(demo, cut);
    canvas.restore();
    canvas.drawPath(demo, Paint()..color = _explored);

    // 2. Mặt kem của vùng đã đi.
    final cream = Paint()..color = _explored;
    for (final b in buckets) {
      inBucket(b, () => canvas.drawPath(b.fill, cream));
    }

    // 3. Đường viền liền của cả vùng (chỉ cạnh giáp sương).
    if (cellPx >= 2.5) {
      final w = (cellPx * 0.09).clamp(1.2, 3.0);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 3.2) / ppm
        ..strokeCap = StrokeCap.round
        ..color = _edge.withValues(alpha: 0.22);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w / ppm
        ..strokeCap = StrokeCap.round
        ..color = _edge;
      for (final b in buckets) {
        inBucket(b, () {
          canvas.drawPath(b.edges, glow);
          canvas.drawPath(b.edges, line);
        });
      }
    }

    // 4. Ranh giới khu vực hiện tại.
    if (areaPath != null) {
      for (final (width, alpha) in const [(14.0, 0.10), (8.0, 0.18)]) {
        canvas.drawPath(
          areaPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round
            ..color = AppColors.brand.withValues(alpha: alpha),
        );
      }
      canvas.drawPath(
        areaPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.brand,
      );
    }

    // 5. Hiệu ứng nổ.
    if (r != null && cellPx >= 2) {
      for (final (cell, t) in popping) {
        if (t <= 0) continue;
        _paintPop(canvas, cell, t, r._pops[cell]!.particles, hexAt, px, ppm);
      }
      for (final b in r._bursts) {
        _paintBurst(canvas, b, frame, px);
      }
    }
  }

  /// "Nổ": bung ra quá đà rồi nảy về như lò xo trong 60% đầu.
  static const _popCurve = ElasticOutCurve(0.55);
  static double _popScale(double t) => _popCurve.transform((t / 0.6).clamp(0.0, 1.0));

  void _paintPop(
    Canvas canvas,
    HexCell cell,
    double t,
    int particles,
    List<Offset> Function(HexCell, double) hexAt,
    Offset Function(double, double) px,
    double ppm,
  ) {
    final fade = 1 - t;
    final s = _popScale(t);

    // Mặt ô loé sáng rồi tắt dần.
    final face = Path()..addPolygon(hexAt(cell, s * 0.94), true);
    final (fx, fy) = HexGrid.centerXY(cell);
    final fc = px(fx, fy);
    final fr = HexGrid.size * ppm * s;
    canvas.drawPath(
      face,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.95 * fade),
            _edge.withValues(alpha: 0.55 * fade * fade),
          ],
        ).createShader(Rect.fromCircle(center: fc, radius: math.max(1, fr))),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = _edge.withValues(alpha: fade),
    );

    // Sóng xung kích hình lục giác loang ra.
    final wave = Curves.easeOut.transform(t);
    canvas.drawPath(
      Path()..addPolygon(hexAt(cell, 1 + wave * 0.9), true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * fade + 0.4
        ..strokeJoin = StrokeJoin.round
        ..color = _edge.withValues(alpha: 0.55 * fade),
    );

    // Mảnh vụn bắn ra theo hướng ngẫu nhiên (cố định theo ô).
    final (x, y) = HexGrid.centerXY(cell);
    final center = px(x, y);
    final rnd = math.Random(cell.hashCode);
    final reach = HexGrid.size * ppm;
    for (var i = 0; i < particles; i++) {
      final angle = (i / particles) * 2 * math.pi + rnd.nextDouble() * 0.8;
      final dist = reach * (0.35 + (1.2 + rnd.nextDouble()) * wave);
      final p = center + Offset(math.cos(angle), math.sin(angle)) * dist;
      final color = _sparks[(i + cell.q.abs()) % _sparks.length];
      final r = (2.2 + rnd.nextDouble() * 2.2) * (1 - t * 0.7);
      if (i.isEven) {
        canvas.drawCircle(p, r, Paint()..color = color.withValues(alpha: fade));
      } else {
        // Mảnh lục giác nhỏ xoay khi bay.
        final rot = angle + t * 4;
        canvas.drawPath(
          Path()
            ..addPolygon([
              for (var k = 0; k < 6; k++)
                p + Offset(math.cos(rot + k * math.pi / 3), math.sin(rot + k * math.pi / 3)) * r * 1.3,
            ], true),
          Paint()..color = color.withValues(alpha: fade),
        );
      }
    }
  }

  void _paintBurst(Canvas canvas, _Burst b, Duration now, Offset Function(double, double) px) {
    final t = ((now - b.start).inMicroseconds / HexRevealController.burstDuration.inMicroseconds).clamp(0.0, 1.0);
    final label = b.label ??= TextPainter(
      text: TextSpan(
        text: '+${b.count}',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -0.5,
          shadows: [Shadow(color: Color(0xAA2E3FD1), blurRadius: 8, offset: Offset(0, 2))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final (x, y) = HexGrid.centerXY(b.cell);
    final rise = Curves.easeOutCubic.transform(t) * 46;
    final scale = Curves.elasticOut.transform((t / 0.5).clamp(0.0, 1.0)) * (1 - math.max(0, t - 0.75) * 2);
    if (scale <= 0) return;
    final at = px(x, y) - Offset(0, 28 + rise);
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(scale);
    final w = label.width + 18, h = label.height + 6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h / 2)),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF6E8BFF), Color(0xFF3B5BFD)])
            .createShader(Rect.fromCenter(center: Offset.zero, width: w, height: h)),
    );
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FogPainter old) =>
      old.camera != camera ||
      old.revision != revision ||
      old.area != area ||
      old.cells != cells ||
      old.frame != frame ||
      old.dark != dark;
}
