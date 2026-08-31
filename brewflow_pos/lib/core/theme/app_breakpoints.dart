/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Breakpoints
///
/// Single source of truth for responsive modes, matching the shell's
/// navigation behavior:
/// - compact  (phone):   < 600
/// - medium   (tablet):  >= 600
/// - expanded (desktop): >= 1000
/// ---------------------------------------------------------------------------
library;

enum AppBreakpoint {
  compact,
  medium,
  expanded;

  bool get isCompact => this == AppBreakpoint.compact;

  bool get isMedium => this == AppBreakpoint.medium;

  bool get isExpanded => this == AppBreakpoint.expanded;
}

final class AppBreakpoints {
  AppBreakpoints._();

  /// Boundary between compact (phone) and medium (tablet) layouts.
  static const double compact = 600;

  /// Boundary between medium (tablet) and expanded (desktop) layouts.
  static const double expanded = 1000;

  static AppBreakpoint fromWidth(double width) {
    if (width < compact) return AppBreakpoint.compact;
    if (width < expanded) return AppBreakpoint.medium;
    return AppBreakpoint.expanded;
  }
}
