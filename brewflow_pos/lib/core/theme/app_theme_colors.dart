import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Theme-Aware Colors
///
/// The static [AppColors] brand/status palette never changes between themes.
/// These *theme-dependent* tokens (page/card/text/divider tints) do, so they
/// are resolved from the active [ThemeData] through [BuildContext.appColors].
/// Values mirror the equivalent light values in [AppColors] so call sites keep
/// the same semantics in light mode.
/// ---------------------------------------------------------------------------

final class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.charcoal,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.divider,
    required this.outline,
    required this.softGreen,
    required this.lightGray,
  });

  /// Near-black heading text in light mode, near-white in dark mode.
  final Color charcoal;

  /// Page background behind cards.
  final Color background;

  /// Primary content surface (cards, panels).
  final Color surface;

  /// Neutral elevated/inset surfaces (fills, table stripes).
  final Color surfaceVariant;

  /// Primary body text.
  final Color textPrimary;

  /// Secondary/helper text.
  final Color textSecondary;

  /// Disabled text.
  final Color textDisabled;

  /// Hairline dividers and borders.
  final Color divider;

  /// Interactive outlines (inputs, unfilled controls).
  final Color outline;

  /// Soft green highlight fills (selected chips, icon circles).
  final Color softGreen;

  /// Neutral soft fills (search fields, chips).
  final Color lightGray;

  static const AppThemeColors light = AppThemeColors(
    charcoal: Color(0xFF212121),
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F5F9),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    textDisabled: Color(0xFF94A3B8),
    divider: Color(0xFFE2E8F0),
    outline: Color(0xFFCBD5E1),
    softGreen: Color(0xFFE8F5E9),
    lightGray: Color(0xFFF4F6F8),
  );

  static const AppThemeColors dark = AppThemeColors(
    charcoal: Color(0xFFE2E8F0),
    background: Color(0xFF0B1220),
    surface: Color(0xFF111827),
    surfaceVariant: Color(0xFF1F2937),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textDisabled: Color(0xFF64748B),
    divider: Color(0xFF334155),
    outline: Color(0xFF475569),
    softGreen: Color(0xFF1B3321),
    lightGray: Color(0xFF1F2937),
  );

  @override
  AppThemeColors copyWith({
    Color? charcoal,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? divider,
    Color? outline,
    Color? softGreen,
    Color? lightGray,
  }) {
    return AppThemeColors(
      charcoal: charcoal ?? this.charcoal,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      divider: divider ?? this.divider,
      outline: outline ?? this.outline,
      softGreen: softGreen ?? this.softGreen,
      lightGray: lightGray ?? this.lightGray,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) {
      return this;
    }
    return AppThemeColors(
      charcoal: Color.lerp(charcoal, other.charcoal, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      softGreen: Color.lerp(softGreen, other.softGreen, t)!,
      lightGray: Color.lerp(lightGray, other.lightGray, t)!,
    );
  }
}

/// Convenience accessor for the active theme's [AppThemeColors].
extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.light;
}
