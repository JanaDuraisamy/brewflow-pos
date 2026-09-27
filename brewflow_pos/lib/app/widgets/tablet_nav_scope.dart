import 'package:flutter/widgets.dart';

/// Exposes the app shell's tablet navigation state to pages beneath it.
///
/// On widths >= 600 the rail auto-collapses after the first app-level
/// navigation so the opened page gets the full width (tablet compact and wide
/// desktop share one contract — no width-band thresholds). When collapsed the
/// shell reserves a left gutter for the floating menu toggle and sign-out,
/// and children can read [collapsed] to adapt their own layout (for example
/// the POS page keeping its wide two-pane layout even though the viewport now
/// falls below the usual wide threshold).
///
/// Phone shells do not insert this scope, so [TabletNavScope.isCollapsed]
/// safely returns false there.
final class TabletNavScope extends InheritedWidget {
  const TabletNavScope({
    super.key,
    required this.collapsed,
    required super.child,
  });

  /// Whether the tablet rail is currently auto-hidden.
  final bool collapsed;

  static TabletNavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabletNavScope>();

  /// True when the app shell has collapsed the tablet navigation rail.
  ///
  /// Returns false on phone and wide-desktop layouts where the scope is not
  /// present at all.
  static bool isCollapsed(BuildContext context) =>
      maybeOf(context)?.collapsed ?? false;

  @override
  bool updateShouldNotify(TabletNavScope oldWidget) =>
      collapsed != oldWidget.collapsed;
}
