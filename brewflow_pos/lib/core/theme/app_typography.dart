import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// Typography
///
/// Font Family : Inter (bundled)
/// Material 3 Compatible
/// ---------------------------------------------------------------------------

final class AppTypography {
  AppTypography._();

  static TextTheme get textTheme => TextTheme(
    displayLarge: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 57,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
    ),
    displayMedium: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 45,
      fontWeight: FontWeight.w700,
    ),
    displaySmall: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 36,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 32,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 28,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 22,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
  );
}
