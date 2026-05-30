import 'package:flutter/material.dart';

import 'app_colors.dart';

ThemeData buildGestiaTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFF0D7B0),
        onPrimaryContainer: const Color(0xFF31200A),
        secondary: AppColors.chartTeal,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFD6EADF),
        onSecondaryContainer: const Color(0xFF0F2D24),
        tertiary: AppColors.chartOrange,
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFF4DDCE),
        onTertiaryContainer: const Color(0xFF3A1D0B),
        surface: const Color(0xFFFFFFFF),
        surfaceContainerHighest: const Color(0xFFEAF1FA),
        onSurface: const Color(0xFF111827),
        onSurfaceVariant: const Color(0xFF667085),
        outline: const Color(0xFFD7DFEA),
        outlineVariant: const Color(0xFFE8EEF6),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFF5F8FC),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
      }),
    ),
  );
}

ThemeData buildGestiaDarkTheme() {
  const surface = Color(0xFF101826);
  const scaffold = Color(0xFF08111F);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF6EA8FF),
        onPrimary: const Color(0xFF031B44),
        primaryContainer: const Color(0xFF0B3A86),
        onPrimaryContainer: const Color(0xFFEAF2FF),
        secondary: const Color(0xFF7FD0AE),
        onSecondary: const Color(0xFF0E261D),
        secondaryContainer: const Color(0xFF204437),
        onSecondaryContainer: const Color(0xFFD6F1E3),
        tertiary: const Color(0xFFE4A06F),
        onTertiary: const Color(0xFF341606),
        tertiaryContainer: const Color(0xFF5A2B12),
        onTertiaryContainer: const Color(0xFFFFDDC9),
        surface: surface,
        surfaceContainerHighest: const Color(0xFF27312C),
        onSurface: const Color(0xFFF2E9DC),
        onSurfaceVariant: const Color(0xFFBBB2A4),
        outline: const Color(0xFF5F5A51),
        outlineVariant: const Color(0xFF393E39),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffold,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: colorScheme.primary.withValues(alpha: 0.28),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
      }),
    ),
  );
}
