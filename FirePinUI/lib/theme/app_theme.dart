import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tokens inspected from the supplied Figma frames, at 390 × 844.
abstract final class AppColors {
  static const primary = Color(0xFF0D514B);
  static const primaryContainer = Color(0xFFE7F1EF);
  static const background = Color(0xFFF6F8F7);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF173431);
  static const textSecondary = Color(0xFF61736F);
  static const outline = Color(0xFFDAE5E1);
  static const warning = Color(0xFFA86E14);
  static const warningSurface = Color(0xFFFDF2D1);
  static const emergency = Color(0xFFB93C2C);
}

abstract final class AppType {
  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
  }) => TextStyle(
    fontFamily: 'Cairo',
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: (height ?? size * 1.75) / size,
  );
  static final title = text(28, weight: FontWeight.w700, height: 40);
  static final section = text(18, weight: FontWeight.w700, height: 30);
  static final body = text(16, height: 28);
  static final muted = text(16, color: AppColors.textSecondary, height: 28);
  static final button = text(17, weight: FontWeight.w700, height: 28);
  static final caption = text(14, color: AppColors.textSecondary, height: 24);
}

abstract final class AppTheme {
  static const systemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outline,
      // Onboarding validation is amber. Red belongs to emergency actions.
      error: AppColors.warning,
      onError: Colors.white,
      errorContainer: AppColors.warningSurface,
    ),
    textTheme: TextTheme(
      headlineMedium: AppType.title,
      titleLarge: AppType.section,
      bodyLarge: AppType.body,
      bodyMedium: AppType.body,
      bodySmall: AppType.caption,
      labelLarge: AppType.button,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: AppType.text(15, color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: AppType.text(14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
