import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF3B5BFD);
  static const brandDeep = Color(0xFF2236C4);
  static const sos = Color(0xFFFF3B30);
  static const online = Color(0xFF34C759);
  static const warning = Color(0xFFFF9F0A);

  /// Bảng màu phụ theo màu hệ thống iOS, dùng cho icon badge, biểu đồ...
  static const indigo = Color(0xFF5856D6);
  static const purple = Color(0xFFAF52DE);
  static const pink = Color(0xFFFF2D55);
  static const teal = Color(0xFF30B0C7);
  static const mint = Color(0xFF00C7BE);
  static const orange = Color(0xFFFF9500);
  static const gray = Color(0xFF8E8E93);

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF5B7CFF), Color(0xFF2E3FD1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    primary: light ? AppColors.brand : const Color(0xFF7C93FF),
    error: AppColors.sos,
  );
  final fieldRadius = BorderRadius.circular(16);
  final bg = light ? const Color(0xFFF2F4FA) : const Color(0xFF0B0D12);

  // Chữ kiểu SF: đậm hơn, khoảng cách chữ hơi âm ở cỡ lớn.
  final base = ThemeData(brightness: brightness, useMaterial3: true).textTheme;
  final text = base.copyWith(
    displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    bodyLarge: base.bodyLarge?.copyWith(letterSpacing: -0.2),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: scheme.onSurface.withValues(alpha: 0.06),
    dividerTheme: DividerThemeData(color: scheme.onSurface.withValues(alpha: 0.1), thickness: 0.5, space: 0.5),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: light ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.06),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: scheme.onSurface),
      subtitleTextStyle: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.55)),
      iconColor: scheme.onSurface.withValues(alpha: 0.7),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.black.withValues(alpha: 0.045) : Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.8), width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.15)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: const StadiumBorder(),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: light ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.08),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: const StadiumBorder()),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.online : scheme.onSurface.withValues(alpha: 0.12),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: light ? const Color(0xFFF7F8FC).withValues(alpha: 0.96) : const Color(0xFF1E2129).withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(34)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: light ? const Color(0xFFF7F8FC) : const Color(0xFF16181F),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(38))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: light ? Colors.white.withValues(alpha: 0.96) : const Color(0xFF1E2129),
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: light ? const Color(0xEE1C1C1E) : const Color(0xEEF2F2F7),
      contentTextStyle: TextStyle(color: light ? Colors.white : Colors.black, fontWeight: FontWeight.w500),
      shape: const StadiumBorder(),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
