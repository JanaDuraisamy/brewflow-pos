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

  /// Minimum **available content width** — never the window width — at which a
  /// wide multi-column data table is shown instead of the card layout.
  ///
  /// A window is always wider than the content the shell hands a page: the
  /// navigation rail gutter and [AppInsets.screen] both come out of it. A
  /// branch keyed off the window therefore promotes a table onto a page that
  /// cannot fit it, which is exactly the overflow this threshold exists to
  /// prevent. Measure the content box and compare against this.
  static const double denseTable = 800;

  /// Minimum available content width for a NARROW data table — five plain text
  /// columns, no thumbnail and no per-row action buttons (the purchase items
  /// table).
  ///
  /// Deliberately lower than [denseTable]: the seven-column product table
  /// carries a thumbnail and three action buttons per row and genuinely needs
  /// the extra room, while this one fits comfortably well before it. Both are
  /// content widths, and both are compared against the box the shell hands the
  /// page rather than the window.
  static const double compactTable = 640;

  /// Available content **height** below which a page's fixed chrome is
  /// compacted, measured on the box the shell hands the page — never the
  /// window.
  ///
  /// A short phone (or a phone in landscape, or one with large system insets)
  /// can hand a page less height than its page header, header actions and
  /// filter row need. The flexible part is the list, so those fixed rows win
  /// the space and the list is squeezed to nothing — the overflow and the
  /// invisible content both come from the chrome being stacked one control per
  /// line. Below this height those rows sit side by side instead, which keeps
  /// every control reachable and leaves the list real room.
  ///
  /// Roughly "the page cannot fit its chrome plus a usable list": the tallest
  /// two-row chrome in the app is about 248dp, and a list worth looking at
  /// needs ~100dp more.
  static const double shortContent = 340;

  static AppBreakpoint fromWidth(double width) {
    if (width < compact) return AppBreakpoint.compact;
    if (width < expanded) return AppBreakpoint.medium;
    return AppBreakpoint.expanded;
  }
}
