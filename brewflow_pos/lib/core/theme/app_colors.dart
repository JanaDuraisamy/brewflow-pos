import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Colors
///
/// Rules:
/// - Never use Colors.green directly.
/// - Never hardcode colors inside widgets.
/// - Always use AppColors.
/// ---------------------------------------------------------------------------

final class AppColors {
  AppColors._();

  // -------------------------------------------------------------------------
  // Brand
  // -------------------------------------------------------------------------

  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF1B5E20);

  static const Color secondary = Color(0xFF00897B);

  // -------------------------------------------------------------------------
  // Approved Brand Palette
  // -------------------------------------------------------------------------

  static const Color charcoal = Color(0xFF212121);

  static const Color gold = Color(0xFFFFB300);

  static const Color softGreen = Color(0xFFE8F5E9);

  static const Color lightGray = Color(0xFFF4F6F8);

  // -------------------------------------------------------------------------
  // Background
  // -------------------------------------------------------------------------

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);

  // -------------------------------------------------------------------------
  // Text
  // -------------------------------------------------------------------------

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF94A3B8);

  // -------------------------------------------------------------------------
  // Border / Divider
  // -------------------------------------------------------------------------

  static const Color divider = Color(0xFFE2E8F0);
  static const Color outline = Color(0xFFCBD5E1);

  // -------------------------------------------------------------------------
  // Status
  // -------------------------------------------------------------------------

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF0284C7);

  // -------------------------------------------------------------------------
  // POS Order Status
  // -------------------------------------------------------------------------

  static const Color orderPending = Color(0xFFF59E0B);
  static const Color orderPreparing = Color(0xFF0284C7);
  static const Color orderReady = Color(0xFF16A34A);
  static const Color orderCompleted = Color(0xFF15803D);
  static const Color orderCancelled = Color(0xFFDC2626);
  static const Color orderRefunded = Color(0xFF7C3AED);

  // -------------------------------------------------------------------------
  // Inventory
  // -------------------------------------------------------------------------

  static const Color inStock = Color(0xFF16A34A);
  static const Color lowStock = Color(0xFFF59E0B);
  static const Color outOfStock = Color(0xFFDC2626);

  // -------------------------------------------------------------------------
  // Payment
  // -------------------------------------------------------------------------

  static const Color cash = Color(0xFF16A34A);
  static const Color card = Color(0xFF2563EB);
  static const Color upi = Color(0xFF7C3AED);
  static const Color wallet = Color(0xFFF97316);

  // -------------------------------------------------------------------------
  // Material 3 Color Scheme
  // -------------------------------------------------------------------------

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,

    primary: primary,
    onPrimary: Colors.white,

    secondary: secondary,
    onSecondary: Colors.white,

    error: error,
    onError: Colors.white,

    surface: surface,
    onSurface: textPrimary,

    primaryContainer: softGreen,
    onPrimaryContainer: primaryDark,

    secondaryContainer: Color(0xFFB2DFDB),
    onSecondaryContainer: textPrimary,

    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: textPrimary,

    surfaceContainerHighest: surfaceVariant,

    outline: outline,
    outlineVariant: divider,

    shadow: Colors.black26,
    scrim: Colors.black54,

    inverseSurface: Color(0xFF1E293B),
    onInverseSurface: Colors.white,

    inversePrimary: primaryLight,

    surfaceTint: primary,
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,

    primary: Color(0xFF66BB6A),
    onPrimary: Colors.black,

    secondary: Color(0xFF4DB6AC),
    onSecondary: Colors.black,

    error: Color(0xFFFF6B6B),
    onError: Colors.black,

    surface: Color(0xFF111827),
    onSurface: Colors.white,

    primaryContainer: Color(0xFF2E7D32),
    onPrimaryContainer: Colors.white,

    secondaryContainer: Color(0xFF00695C),
    onSecondaryContainer: Colors.white,

    errorContainer: Color(0xFF8B0000),
    onErrorContainer: Colors.white,

    surfaceContainerHighest: Color(0xFF1F2937),

    outline: Color(0xFF475569),
    outlineVariant: Color(0xFF334155),

    shadow: Colors.black54,
    scrim: Colors.black,

    inverseSurface: Colors.white,
    onInverseSurface: Colors.black,

    inversePrimary: primary,

    surfaceTint: primary,
  );
}
