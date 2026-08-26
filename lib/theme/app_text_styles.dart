import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale. One family, a small set of sizes/weights — consistent
/// hierarchy over decorative variety, per the design system spec.
class AppTextStyles {
  const AppTextStyles._();

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle displayLarge = _base(size: 32, weight: FontWeight.w700, height: 1.2);
  static TextStyle displayMedium = _base(size: 28, weight: FontWeight.w700, height: 1.2);
  static TextStyle headline = _base(size: 22, weight: FontWeight.w600, height: 1.3);
  static TextStyle title = _base(size: 18, weight: FontWeight.w600, height: 1.3);
  static TextStyle subtitle = _base(size: 15, weight: FontWeight.w600, height: 1.4);
  static TextStyle body = _base(size: 14, weight: FontWeight.w400, height: 1.5);
  static TextStyle bodyStrong = _base(size: 14, weight: FontWeight.w600, height: 1.5);
  static TextStyle caption = _base(size: 12, weight: FontWeight.w400, height: 1.4);
  static TextStyle captionStrong = _base(size: 12, weight: FontWeight.w600, height: 1.4, letterSpacing: 0.2);
  static TextStyle button = _base(size: 14, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.1);
  static TextStyle numeric = _base(size: 20, weight: FontWeight.w700, height: 1.2);
}
