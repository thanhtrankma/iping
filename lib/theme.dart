import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF3B5BFD);
  static const brandDeep = Color(0xFF2236C4);
  static const sos = Color(0xFFE53935);
  static const online = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);

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
    primary: light ? AppColors.brand : null,
  );
  final radius14 = BorderRadius.circular(14);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF4F6FB) : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: light ? const Color(0xFFF4F6FB) : scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: light ? Colors.white : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? const Color(0xFFF0F2F8) : scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius14,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: light ? Colors.white : scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
