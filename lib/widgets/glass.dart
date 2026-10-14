import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Liquid Glass theo kiểu iOS 26.
///
/// Khác với "kính mờ" cũ (blur mạnh + phủ trắng đục), Liquid Glass:
/// - trong hơn: lớp tint mỏng, nội dung phía sau vẫn đọc được màu sắc;
/// - tăng độ bão hoà và độ sáng của nền (vibrancy) để chữ vẫn nổi;
/// - viền phản quang (specular rim) sáng ở góc trên-trái và dưới-phải như
///   ánh sáng chiếu nghiêng vào một khối thuỷ tinh dày;
/// - quầng sáng mép bên trong, giả lập hiện tượng khúc xạ ở rìa thấu kính;
/// - góc bo liên tục (squircle) thay vì bo tròn thường;
/// - phản hồi khi chạm: co nhẹ và loé sáng (xem [GlassPressable]).

/// Hình dạng chung của các bề mặt kính.
ShapeBorder glassShape({double radius = 28, bool circle = false, bool capsule = false}) {
  if (circle) return const CircleBorder();
  if (capsule) return const StadiumBorder();
  return RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
}

/// Ma trận màu cho nền phía sau kính: tăng bão hoà [s], nén tương phản [contrast]
/// quanh màu xám giữa rồi cộng [lift] (thang 0–255).
///
/// iOS 26 (chế độ sáng) giữ kính sáng và trong trên mọi nền, kể cả ảnh vệ tinh tối:
/// nền được nén tương phản và nâng sáng (giống "luminosity" của vật liệu Apple), chỉ tăng
/// bão hoà nhẹ. Tăng bão hoà mạnh trên nền tối sẽ ra màu xám đục.
List<double> _vibrancyMatrix(double s, double contrast, double lift) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final a = 1 - s;
  final c = contrast;
  // Giữ màu xám giữa (128) cố định khi nén tương phản, rồi nâng sáng.
  final offset = 128 * (1 - c) + lift;
  return [
    c * (lr * a + s), c * lg * a, c * lb * a, 0, offset,
    c * lr * a, c * (lg * a + s), c * lb * a, 0, offset,
    c * lr * a, c * lg * a, c * (lb * a + s), 0, offset,
    0, 0, 0, 1, 0,
  ];
}

ui.ImageFilter glassFilter({required double blur, required bool dark}) => ui.ImageFilter.compose(
      outer: ColorFilter.matrix(dark ? _vibrancyMatrix(1.4, 0.85, -14) : _vibrancyMatrix(1.35, 0.7, 34)),
      inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror),
    );

/// Đánh dấu vùng có nền tĩnh, đã mờ sẵn (xem [GlassBackground]).
///
/// Kính nằm trên nền này không cần BackdropFilter: làm mờ lại một nền vốn đã mờ cho kết quả
/// gần như y hệt, nhưng tốn một lượt blur toàn vùng ở mỗi khung hình khi cuộn.
class GlassStaticBackdrop extends InheritedWidget {
  const GlassStaticBackdrop({super.key, required super.child});

  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<GlassStaticBackdrop>() != null;

  @override
  bool updateShouldNotify(GlassStaticBackdrop oldWidget) => false;
}

/// Bề mặt Liquid Glass.
///
/// Các kính cùng nằm dưới một [BackdropGroup] (ví dụ lớp điều khiển trên bản đồ) dùng chung
/// một lần đọc nền, nên thêm nút kính không làm tăng chi phí theo cấp số.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
    this.blur = 14,
    this.opacity = 0.55,
    this.circle = false,
    this.capsule = false,
    this.shadow = true,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// Độ mờ của nền phía sau. Liquid Glass dùng blur vừa phải (~12–16).
  final double blur;

  /// Độ đậm của lớp tint (0–1). Giá trị cao hơn = dễ đọc chữ hơn, ít trong hơn.
  /// Thang cũ (0.55–0.85) được giữ nguyên ý nghĩa nhưng kính tổng thể trong hơn.
  final double opacity;
  final bool circle;
  final bool capsule;
  final bool shadow;

  /// Màu tint (ví dụ đỏ cho SOS). Kính có tint màu sẽ đậm hơn một chút.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = glassShape(radius: radius, circle: circle, capsule: capsule);
    final base = tint ?? (dark ? const Color(0xFF16181D) : Colors.white);
    // Kính iOS 26 trong hơn hẳn: chỉ giữ khoảng một nửa độ đục của thang cũ.
    // Nền tĩnh: bỏ BackdropFilter, tint đậm hơn chút để bù phần vibrancy.
    final staticBackdrop = GlassStaticBackdrop.of(context);
    final alpha = (tint != null
            ? (0.35 + opacity * 0.45).clamp(0.0, 0.95)
            : (dark ? 0.18 + opacity * 0.38 : 0.14 + opacity * 0.40).clamp(0.0, 0.9)) +
        (staticBackdrop ? 0.08 : 0.0);

    final body = CustomPaint(
      painter: _GlassBodyPainter(shape: shape, base: base, alpha: alpha, dark: dark, tinted: tint != null),
      foregroundPainter: _GlassRimPainter(shape: shape, dark: dark, tinted: tint != null),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        // Một bóng tản vừa phải: kính "lơ lửng" trên nội dung. (Hai bóng blur lớn trên mỗi
        // nút kính tốn GPU đáng kể khi bản đồ vẽ lại liên tục.)
        shadows: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.38 : 0.11),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: staticBackdrop ? body : BackdropFilter.grouped(filter: glassFilter(blur: blur, dark: dark), child: body),
      ),
    );
  }
}

/// Lớp thân kính: tint mỏng + vệt phản chiếu phía trên + đáy hơi tối.
class _GlassBodyPainter extends CustomPainter {
  _GlassBodyPainter({
    required this.shape,
    required this.base,
    required this.alpha,
    required this.dark,
    required this.tinted,
  });

  final ShapeBorder shape;
  final Color base;
  final double alpha;
  final bool dark;
  final bool tinted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);

    // Tint chính, đậm hơn chút ở phía dưới để chữ dễ đọc.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base.withValues(alpha: (alpha - 0.04).clamp(0.0, 1.0)),
            base.withValues(alpha: (alpha + 0.06).clamp(0.0, 1.0)),
          ],
        ).createShader(rect),
    );

    // Vệt sáng mềm ở nửa trên (ánh sáng môi trường phản chiếu lên mặt kính).
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.1),
          colors: [
            Colors.white.withValues(alpha: dark ? 0.07 : (tinted ? 0.22 : 0.28)),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Quầng sáng mép bên trong: giả lập khúc xạ ở rìa khối kính. Vẽ bằng vài nét viền
    // nhạt dần thay cho MaskFilter.blur (blur trên path phải tính lại ở mỗi khung hình).
    final edgeAlpha = dark ? 0.05 : 0.16;
    for (var i = 0; i < 3; i++) {
      canvas.drawPath(
        shape.getOuterPath(rect.deflate(1.0 + i * 1.6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: edgeAlpha * (1 - i / 3)),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassBodyPainter old) =>
      old.shape != shape || old.base != base || old.alpha != alpha || old.dark != dark || old.tinted != tinted;
}

/// Viền phản quang: sáng ở góc trên-trái, mờ dần ở hai cạnh, sáng lại ở dưới-phải.
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter({required this.shape, required this.dark, required this.tinted});

  final ShapeBorder shape;
  final bool dark;
  final bool tinted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect.deflate(0.5));
    final hi = dark ? 0.45 : 0.95;
    final lo = dark ? 0.06 : (tinted ? 0.15 : 0.25);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: hi),
            Colors.white.withValues(alpha: lo),
            Colors.white.withValues(alpha: lo * 0.6),
            Colors.white.withValues(alpha: hi * 0.6),
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );

    // Đường tối rất mảnh ở mép dưới tạo độ dày cho kính.
    if (!dark) {
      canvas.drawPath(
        shape.getOuterPath(rect.deflate(0.25)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.08)],
            stops: const [0.6, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) => old.shape != shape || old.dark != dark || old.tinted != tinted;
}

/// Phản hồi chạm kiểu Liquid Glass: co nhẹ, loé sáng tại điểm chạm, rung nhẹ.
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.shape,
    this.scale = 0.94,
    this.haptic = true,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ShapeBorder? shape;
  final double scale;
  final bool haptic;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 380),
  );
  Offset? _point;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(TapDownDetails d) {
    setState(() => _point = d.localPosition);
    _c.forward();
  }

  void _up([_]) => _c.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _down : null,
      onTapUp: enabled ? _up : null,
      onTapCancel: enabled ? _up : null,
      onLongPress: widget.onLongPress,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap?.call();
            }
          : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Đường cong "lò xo": vào nhanh, ra có chút nảy.
          final t = Curves.easeOut.transform(_c.value);
          return Transform.scale(
            scale: 1 - (1 - widget.scale) * t,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child!,
                if (_c.value > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipPath(
                        clipper: ShapeBorderClipper(shape: widget.shape ?? glassShape()),
                        child: CustomPaint(painter: _GlowPainter(_point, t)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.point, this.t);
  final Offset? point;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = point ?? size.center(Offset.zero);
    final r = size.longestSide * 0.9;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.35 * t), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.point != point || old.t != t;
}

/// Nút tròn bằng kính, dùng trên bản đồ.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    this.icon,
    this.child,
    required this.onTap,
    this.size = 50,
    this.color,
    this.tooltip,
    this.tint,
  });

  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final String? tooltip;

  /// Kính có màu (ví dụ nút chính). Khi có tint, biểu tượng mặc định màu trắng.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? (tint != null ? Colors.white : Theme.of(context).colorScheme.onSurface);
    final btn = GlassPressable(
      onTap: onTap,
      shape: const CircleBorder(),
      scale: 0.9,
      child: SizedBox(
        width: size,
        height: size,
        child: Glass(
          circle: true,
          tint: tint,
          opacity: 0.6,
          child: Center(child: child ?? Icon(icon, size: size * 0.44, color: fg)),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Viên thuốc bằng kính có chữ (ví dụ "❤️ Yêu nhé!").
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child, required this.onTap, this.padding, this.tint});
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return GlassPressable(
      onTap: onTap,
      shape: const StadiumBorder(),
      child: Glass(
        capsule: true,
        tint: tint,
        opacity: 0.6,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: child,
      ),
    );
  }
}

/// Ô hành động trong thẻ kính (Lịch sử, Lái xe, ...).
/// Là một lớp kính lồng bên trong kính: nền hơi đậm hơn, góc bo đồng tâm.
class GlassTile extends StatelessWidget {
  const GlassTile({super.key, required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Màu biểu tượng; mặc định là màu thương hiệu.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = glassShape(radius: 20);
    final accent = color ?? (dark ? Colors.white : AppColors.brand);
    return GlassPressable(
      onTap: onTap,
      shape: shape,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.45),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 25, color: accent),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nền cho các màn hình không có bản đồ: các đốm màu lớn đã làm mờ,
/// để kính có thứ gì đó phía sau mà "khúc xạ" (kính trên nền phẳng trông như giấy).
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blobs = dark
        ? const [Color(0xFF2B3A8F), Color(0xFF5B2E8A), Color(0xFF0F5C5A)]
        : const [Color(0xFFB9C8FF), Color(0xFFE4CCFF), Color(0xFFBFEBDD)];
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: dark ? const Color(0xFF0B0D12) : const Color(0xFFF2F4FA)),
        // Đốm màu vẽ bằng RadialGradient tự mờ dần, không cần ImageFiltered blur toàn màn hình
        // (Impeller không có raster cache nên blur đó bị tính lại ở mỗi khung hình khi cuộn).
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _BlobPainter(blobs, dark))),
          ),
        ),
        GlassStaticBackdrop(child: child),
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.colors, this.dark);
  final List<Color> colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = dark ? 0.55 : 0.85;
    void blob(Color c, double x, double y, double r) {
      final center = Offset(size.width * x, size.height * y);
      // Bán kính lớn hơn vòng tròn gốc để phần mờ dần giống blur sigma 60 trước đây.
      final radius = size.shortestSide * r + 90;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: a), c.withValues(alpha: a * 0.85), c.withValues(alpha: 0)],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    blob(colors[0], 0.05, 0.08, 0.75);
    blob(colors[1], 0.95, 0.38, 0.6);
    blob(colors[2], 0.2, 0.9, 0.7);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.dark != dark || old.colors != colors;
}

/// Nhóm danh sách kiểu "inset grouped" của iOS, làm bằng kính.
/// Các con được ngăn bằng đường kẻ mảnh, thụt vào theo [dividerIndent].
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.dividerIndent = 56,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 20),
  });

  final List<Widget> children;
  final String? header;
  final String? footer;
  final double dividerIndent;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Divider(
      height: 0.5,
      thickness: 0.5,
      indent: dividerIndent,
      color: scheme.onSurface.withValues(alpha: 0.12),
    );
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12.5,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          Glass(
            radius: 26,
            opacity: 0.7,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) divider,
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: Text(
                footer!,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurface.withValues(alpha: 0.5)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ô biểu tượng màu bo squircle, dùng làm leading cho dòng cài đặt (như iOS Settings).
class GlassIconBadge extends StatelessWidget {
  const GlassIconBadge({super.key, required this.icon, required this.color, this.size = 30});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: glassShape(radius: size * 0.27),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.18)!, color],
        ),
      ),
      child: Icon(icon, size: size * 0.62, color: Colors.white),
    );
  }
}

/// Thanh tab nổi dạng viên thuốc kính, có "thấu kính" trượt theo tab đang chọn.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<({IconData icon, String label})> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Glass(
      capsule: true,
      opacity: 0.65,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return SizedBox(
          height: 56,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: dark ? Colors.white.withValues(alpha: 0.14) : scheme.primary.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(i);
                        },
                        child: _TabItem(item: items[i], selected: i == index),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.item, required this.selected});
  final ({IconData icon, String label}) item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.75);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: selected ? 1.08 : 1,
          duration: const Duration(milliseconds: 250),
          child: Icon(item.icon, size: 24, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
        ),
      ],
    );
  }
}

/// Khoảng cách từ đáy màn hình tới các bảng kính nổi (sheet, thanh dưới).
///
/// - iOS: vạch home được phép nằm đè nhẹ lên kính (như iOS 26) nên chỉ chừa ~40%.
/// - Android: thanh điều hướng (3 nút hoặc vạch cử chỉ) vẽ đè lên app khi edge-to-edge,
///   nên phải chừa đủ chiều cao của nó, nếu không các nút sẽ đè lên nội dung.
double floatingBottomGap(BuildContext context, {double min = 8}) {
  final bottom = MediaQuery.viewPaddingOf(context).bottom;
  if (bottom <= 0) return min;
  if (Theme.of(context).platform == TargetPlatform.iOS) return bottom * 0.4 + 4;
  return bottom + 6;
}

/// Mở bottom sheet dạng kính nổi (cách mép màn hình, bo góc lớn) như sheet iOS 26.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, floatingBottomGap(ctx)),
        child: Glass(
          radius: 38,
          opacity: 0.85,
          blur: 24,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 36,
                    height: 5,
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.22),
                    ),
                  ),
                ),
                Flexible(child: builder(ctx)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// AppBar trong suốt dùng trên [GlassBackground]: tiêu đề lớn kiểu iOS,
/// nút quay lại là nút kính tròn.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.title, this.actions, this.leading});
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      toolbarHeight: 60,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      leadingWidth: 64,
      leading: leading ??
          (canPop
              ? Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Center(
                    child: GlassButton(
                      size: 42,
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Quay lại',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                )
              : null),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      actions: actions == null ? null : [...actions!, const SizedBox(width: 10)],
    );
  }
}
