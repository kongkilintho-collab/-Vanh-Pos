import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(brightness: Brightness.light);
  static ThemeData dark() => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryDark,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: isDark ? AppColors.surfaceDarkTone : AppColors.surface,
      onSurface: isDark ? AppColors.inkDark : AppColors.ink,
    );

    final background = isDark ? AppColors.backgroundDark : AppColors.background;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    final muted = isDark ? AppColors.mutedDark : AppColors.muted;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: AppTextStyles.body.fontFamily,
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge.copyWith(color: colorScheme.onSurface),
        displayMedium: AppTextStyles.displayMedium.copyWith(color: colorScheme.onSurface),
        headlineMedium: AppTextStyles.headline.copyWith(color: colorScheme.onSurface),
        titleLarge: AppTextStyles.title.copyWith(color: colorScheme.onSurface),
        titleMedium: AppTextStyles.subtitle.copyWith(color: colorScheme.onSurface),
        bodyLarge: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
        bodyMedium: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
        bodySmall: AppTextStyles.caption.copyWith(color: muted),
        labelLarge: AppTextStyles.button,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.surfaceDarkTone : AppColors.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTextStyles.title.copyWith(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surfaceAltDark : AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceAltDark : AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        labelStyle: AppTextStyles.body.copyWith(color: muted),
        hintStyle: AppTextStyles.body.copyWith(color: muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          minimumSize: const Size(0, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: border),
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          minimumSize: const Size(0, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: AppTextStyles.button,
          minimumSize: const Size(0, 40),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surfaceAltDark : AppColors.surfaceAlt,
        labelStyle: AppTextStyles.caption.copyWith(color: colorScheme.onSurface),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: AppTextStyles.captionStrong.copyWith(color: muted),
        dataTextStyle: AppTextStyles.body.copyWith(color: colorScheme.onSurface),
        dividerThickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.inkDark : AppColors.ink,
        contentTextStyle: AppTextStyles.body.copyWith(color: isDark ? AppColors.ink : Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
      ),
    );
  }
}
