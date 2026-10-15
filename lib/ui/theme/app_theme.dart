import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  /// The original fixed light theme (kept for tests and bare pumps).
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        // Explicitly light: see MpesaTrackerApp's `themeMode`.
        brightness: Brightness.light,
        primary: AppColors.primary,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  /// 0.1.2 S9a (AP1): the Material theme for one palette side. `main.dart`
  /// gives the chosen palette's light side as `theme` and its dark side as
  /// `darkTheme`, so dialogs, pickers, snackbars and text fields follow the
  /// chosen Appearance and palette, not just the pages that call
  /// `AppPalette.of`.
  static ThemeData forPalette(AppPalette p) {
    final dark = p.brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: p.primary, brightness: p.brightness).copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.card,
      onSurface: p.ink,
      onSurfaceVariant: p.softInk,
      outline: p.mutedInk,
      outlineVariant: p.line,
      error: p.error,
      inverseSurface: dark ? p.ink : p.deep,
      onInverseSurface: dark ? p.background : p.card,
      surfaceTint: Colors.transparent,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.card,
      fontFamily: 'Roboto',
      dividerColor: p.line,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.ink,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
      textSelectionTheme: TextSelectionThemeData(cursorColor: p.primary),
    );
  }
}
