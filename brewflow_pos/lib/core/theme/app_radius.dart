import 'package:flutter/widgets.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Radius
///
/// Rules:
/// - Never use BorderRadius.circular(15)
/// - Always use AppRadius.*
/// ---------------------------------------------------------------------------

final class AppRadius {
  AppRadius._();

  static const double none = 0;

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  static const double pill = 999;
}

/// ---------------------------------------------------------------------------
/// Ready-to-use BorderRadius
/// ---------------------------------------------------------------------------

final class AppBorderRadius {
  AppBorderRadius._();

  static const BorderRadius none = BorderRadius.all(
    Radius.circular(AppRadius.none),
  );

  static const BorderRadius xs = BorderRadius.all(
    Radius.circular(AppRadius.xs),
  );

  static const BorderRadius sm = BorderRadius.all(
    Radius.circular(AppRadius.sm),
  );

  static const BorderRadius md = BorderRadius.all(
    Radius.circular(AppRadius.md),
  );

  static const BorderRadius lg = BorderRadius.all(
    Radius.circular(AppRadius.lg),
  );

  static const BorderRadius xl = BorderRadius.all(
    Radius.circular(AppRadius.xl),
  );

  static const BorderRadius xxl = BorderRadius.all(
    Radius.circular(AppRadius.xxl),
  );

  static const BorderRadius pill = BorderRadius.all(
    Radius.circular(AppRadius.pill),
  );
}
