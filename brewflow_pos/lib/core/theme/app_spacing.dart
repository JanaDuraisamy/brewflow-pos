import 'package:flutter/widgets.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Spacing
///
/// 8pt Grid System
///
/// Never use:
/// EdgeInsets.all(13)
///
/// Always use:
/// EdgeInsets.all(AppSpacing.lg)
/// ---------------------------------------------------------------------------

final class AppSpacing {
  AppSpacing._();

  // Base Scale

  static const double none = 0;

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  static const double xxxl = 32;

  static const double huge = 40;

  static const double massive = 48;

  static const double giant = 56;

  static const double ultra = 64;

  static const double mega = 72;

  static const double max = 80;

  static const double screenPadding = 24;

  static const double cardPadding = 16;

  static const double dialogPadding = 24;

  static const double listItemSpacing = 12;

  static const double sectionSpacing = 32;
}

/// ---------------------------------------------------------------------------
/// Ready-to-use EdgeInsets
/// ---------------------------------------------------------------------------

final class AppInsets {
  AppInsets._();

  static const EdgeInsets zero = EdgeInsets.zero;

  static const EdgeInsets xs = EdgeInsets.all(AppSpacing.xs);

  static const EdgeInsets sm = EdgeInsets.all(AppSpacing.sm);

  static const EdgeInsets md = EdgeInsets.all(AppSpacing.md);

  static const EdgeInsets lg = EdgeInsets.all(AppSpacing.lg);

  static const EdgeInsets xl = EdgeInsets.all(AppSpacing.xl);

  static const EdgeInsets xxl = EdgeInsets.all(AppSpacing.xxl);

  static const EdgeInsets screen = EdgeInsets.all(AppSpacing.screenPadding);

  static const EdgeInsets card = EdgeInsets.all(AppSpacing.cardPadding);

  static const EdgeInsets dialog = EdgeInsets.all(AppSpacing.dialogPadding);

  static const EdgeInsets horizontal = EdgeInsets.symmetric(
    horizontal: AppSpacing.screenPadding,
  );

  static const EdgeInsets vertical = EdgeInsets.symmetric(
    vertical: AppSpacing.screenPadding,
  );
}
