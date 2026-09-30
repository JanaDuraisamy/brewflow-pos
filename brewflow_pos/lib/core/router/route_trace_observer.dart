import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:flutter/widgets.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Navigation Tracing
///
/// Records the route the user actually reached, not the route that was
/// requested. That distinction matters: this app redirects heavily (auth
/// guard, permission guard, no-access, shop-scoped recovery), so a log that
/// only captured `go('/inventory')` would hide the fact that the user landed on
/// `/no-access` or was bounced to `/auth` instead.
///
/// A [NavigatorObserver] is used rather than instrumenting `context.go()` call
/// sites, so coverage is complete by construction: every push, pop and shell
/// branch switch is seen, including the ones triggered from widgets nobody
/// thought to instrument. Rebuilds and animations produce no lines.
///
/// Observation-only: no navigation decision is read from or written to here.
/// ---------------------------------------------------------------------------

final class BrewFlowRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _trace('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // After a pop the interesting location is the one being revealed.
    _trace('pop', previousRoute, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _trace('replace', newRoute, oldRoute);
  }

  static void _trace(String kind, Route<dynamic>? to, Route<dynamic>? from) {
    final location = to?.settings.name;
    if (location == null) return;
    AppTrace.event('nav.$kind', {'to': location, 'from': from?.settings.name});
  }
}
