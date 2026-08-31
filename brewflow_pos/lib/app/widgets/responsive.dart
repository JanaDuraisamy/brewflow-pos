import 'package:brewflow_pos/core/theme/app_breakpoints.dart';
import 'package:flutter/widgets.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Responsive Helpers
///
/// [ResponsiveBuilder] exposes the current [AppBreakpoint] without repeating
/// LayoutBuilder plumbing in every page.
/// ---------------------------------------------------------------------------

final class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppBreakpoint breakpoint) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          builder(context, AppBreakpoints.fromWidth(constraints.maxWidth)),
    );
  }
}
