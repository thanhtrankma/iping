import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Bề mặt "liquid glass": làm mờ nền phía sau, phủ lớp trắng trong suốt,
/// viền sáng và vệt phản chiếu ở nửa trên.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
    this.blur = 22,
    this.opacity = 0.55,
    this.circle = false,
    this.shadow = true,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double opacity;
  final bool circle;
  final bool shadow;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ?? (dark ? const Color(0xFF1C1F26) : Colors.white);
    final ShapeBorder border =
        circle ? const CircleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    ShapeDecoration shape(Gradient g) => ShapeDecoration(shape: border, gradient: g);
    final clip = circle
        ? const ShapeBorderClipper(shape: CircleBorder())
        : ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)));
    final borderRadius = circle ? null : BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 8))]
            : null,
      ),
      child: ClipPath(
        clipper: clip,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Stack(
            children: [
              // Lớp kính chính.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: shape(
                    LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        base.withValues(alpha: (opacity + 0.15).clamp(0, 1)),
                        base.withValues(alpha: opacity),
                        base.withValues(alpha: (opacity - 0.1).clamp(0, 1)),
                      ],
                    ),
                  ),
                ),
              ),
              // Vệt phản chiếu ánh sáng ở phía trên.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: shape(
                      LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.white.withValues(alpha: dark ? 0.08 : 0.35),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
              // Viền sáng mảnh.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: circle
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.15 : 0.7), width: 1.2),
                          )
                        : BoxDecoration(
                            borderRadius: borderRadius,
                            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.15 : 0.7), width: 1.2),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút tròn bằng kính, dùng trên bản đồ.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    this.icon,
    this.child,
    required this.onTap,
    this.size = 54,
    this.color,
    this.tooltip,
  });

  final IconData? icon;
  final Widget? child;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: size,
      height: size,
      child: Glass(
        circle: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: child ??
                  Icon(icon, size: size * 0.46, color: color ?? Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Viên thuốc bằng kính có chữ (ví dụ "❤️ Yêu nhé!").
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child, required this.onTap, this.padding});
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 30,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Ô hành động vuông bo góc trong thẻ kính (Lịch sử, Lái xe, ...).
class GlassTile extends StatelessWidget {
  const GlassTile({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? Colors.white.withValues(alpha: 0.08) : AppColors.brand.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nền màn hình có gradient nhẹ để các thẻ kính nổi lên.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF10131A), Color(0xFF1A2033)]
              : const [Color(0xFFEAF0FF), Color(0xFFF6F3FF), Color(0xFFEFF7F4)],
        ),
      ),
      child: child,
    );
  }
}
