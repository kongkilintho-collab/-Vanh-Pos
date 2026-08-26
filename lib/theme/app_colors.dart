import 'package:flutter/material.dart';

/// Brand and semantic colors for the Beauty Clinic POS design system.
///
/// Kept intentionally small and flat — premium/minimal per spec, not a
/// large ad-hoc palette. Every screen should draw from these tokens rather
/// than inlining new colors.
class AppColors {
  const AppColors._();

  // Brand
  static const primary = Color(0xFF9C6B4F); // warm clay — beauty/spa feel
  static const primaryDark = Color(0xFF7A5038);
  static const primaryLight = Color(0xFFEFE1D6);

  // Neutrals
  static const ink = Color(0xFF1F1B18);
  static const body = Color(0xFF4A433D);
  static const muted = Color(0xFF8A8078);
  static const border = Color(0xFFE6DED6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFFAF6F2);
  static const background = Color(0xFFF6F1EC);

  // Semantic
  static const success = Color(0xFF2E7D53);
  static const successBg = Color(0xFFE5F3EA);
  static const warning = Color(0xFFB2790C);
  static const warningBg = Color(0xFFFBF0DC);
  static const danger = Color(0xFFC13B3B);
  static const dangerBg = Color(0xFFFBE8E8);
  static const info = Color(0xFF2D6FB2);
  static const infoBg = Color(0xFFE6F0FA);

  // Dark mode
  static const inkDark = Color(0xFFF2ECE6);
  static const bodyDark = Color(0xFFD4CBC2);
  static const mutedDark = Color(0xFF9A8F84);
  static const borderDark = Color(0xFF3A332C);
  static const surfaceDarkTone = Color(0xFF241F1A);
  static const surfaceAltDark = Color(0xFF2C2620);
  static const backgroundDark = Color(0xFF1A1613);
}
