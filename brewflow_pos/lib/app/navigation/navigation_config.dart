/// ---------------------------------------------------------------------------
/// BrewFlow POS — Navigation Destinations & Owner Arrangement
///
/// [navDestinations] is the canonical registry of shell destinations: route,
/// label, icons and the permission each one requires. It MUST stay aligned
/// with [AppRoutes.destinations] and the router's branch order — a silent
/// drift between the navigation list and the branch list is exactly what made
/// "Staff" open Stock. `navigation_destinations_alignment_test.dart` locks
/// that invariant.
///
/// [NavArrangement] is the owner's navigation-organization preference: the
/// order of destinations and which of them sit in the phone main bar versus
/// the "More" sheet. It is PRESENTATION ONLY —
/// - [NavDestination.label] is canonical and never user-editable;
/// - an arrangement never hides, disables, deletes or revokes a feature:
///   every destination stays in [NavArrangement.order] and therefore remains
///   reachable, either in the main bar or under "More";
/// - it never grants access. Staff visibility is still filtered by
///   [NavDestination.permission] and enforced by the router guard.
///
/// The arrangement is persisted as part of [ShopSettings] through the existing
/// preferences-backed settings repository, so it reuses the app's established
/// settings/preference persistence mechanism instead of a parallel store.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:flutter/material.dart';

/// One shell navigation destination.
final class NavDestination {
  const NavDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.permission,
  });

  /// Stable identity and persistence key. Route paths are already unique and
  /// stable, so an arrangement stores these and never a label or an index —
  /// an index would silently re-point a preference at a different feature
  /// whenever the destination list changes.
  final String route;

  /// CANONICAL feature name. Never user-editable and never shortened by the
  /// arrangement; the phone bar renders it as-is.
  final String label;

  final IconData icon;
  final IconData selectedIcon;

  /// Permission required to open this destination. Staff navigation is
  /// filtered by this value; the router guard remains the hard boundary.
  final Permission permission;
}

/// Canonical navigation order. Index here == router branch index ==
/// [AppRoutes.destinations] index.
const List<NavDestination> navDestinations = [
  NavDestination(
    route: AppRoutes.dashboard,
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    permission: Permission.viewDashboard,
  ),
  NavDestination(
    route: AppRoutes.staff,
    label: 'Staff Management',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    permission: Permission.manageStaff,
  ),
  NavDestination(
    route: AppRoutes.inventory,
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    permission: Permission.viewInventory,
  ),
  NavDestination(
    route: AppRoutes.billing,
    label: 'Billing',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
    permission: Permission.billing,
  ),
  NavDestination(
    route: AppRoutes.orders,
    label: 'Orders',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    permission: Permission.orders,
  ),
  NavDestination(
    route: AppRoutes.customers,
    label: 'Customers',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    permission: Permission.customers,
  ),
  NavDestination(
    route: AppRoutes.suppliers,
    label: 'Suppliers',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping,
    permission: Permission.suppliers,
  ),
  NavDestination(
    route: AppRoutes.purchases,
    label: 'Purchases',
    icon: Icons.shopping_basket_outlined,
    selectedIcon: Icons.shopping_basket,
    permission: Permission.purchases,
  ),
  NavDestination(
    route: AppRoutes.expenses,
    label: 'Expenses',
    icon: Icons.payments_outlined,
    selectedIcon: Icons.payments,
    permission: Permission.expenses,
  ),
  NavDestination(
    route: AppRoutes.reports,
    label: 'Reports',
    icon: Icons.insert_chart_outlined,
    selectedIcon: Icons.insert_chart,
    permission: Permission.reports,
  ),
  NavDestination(
    route: AppRoutes.offers,
    label: 'Offers',
    icon: Icons.local_offer_outlined,
    selectedIcon: Icons.local_offer,
    permission: Permission.offers,
  ),
  NavDestination(
    route: AppRoutes.settings,
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    permission: Permission.settings,
  ),
];

/// Canonical route order, derived from [navDestinations] so the two can never
/// disagree inside this layer.
List<String> get canonicalNavRoutes => [
  for (final destination in navDestinations) destination.route,
];

/// Destinations shown directly in the phone main bar until the owner
/// customizes the arrangement.
const List<String> defaultPrimaryRoutes = [
  AppRoutes.dashboard,
  AppRoutes.staff,
  AppRoutes.customers,
];

/// Upper bound on main-bar entries. The bar appends a trailing "More" entry,
/// so this keeps the bar at five slots on the narrowest phones.
const int maxPrimaryRoutes = 4;

/// The owner's navigation-organization preference.
///
/// [order] always contains every destination in [navDestinations] exactly
/// once, and [primary] is a subset of it — which is what makes the
/// customization incapable of hiding a feature.
final class NavArrangement {
  const NavArrangement({required this.order, required this.primary});

  /// Route paths in display order.
  final List<String> order;

  /// Routes shown directly in the phone main bar. Everything else remains
  /// reachable under "More".
  final List<String> primary;

  /// The out-of-the-box arrangement: canonical order with the default main bar.
  static final NavArrangement defaults = NavArrangement.resolve();

  /// Folds a persisted arrangement onto the canonical destination list.
  ///
  /// Unknown routes are dropped, duplicates collapsed, and any destination
  /// missing from [order] is appended in canonical order. Partial or corrupt
  /// preferences therefore degrade to a valid arrangement that still shows
  /// every feature, never to a lost or duplicated navigation entry.
  factory NavArrangement.resolve({
    List<String> order = const [],
    List<String> primary = const [],
  }) {
    final canonical = canonicalNavRoutes;
    final known = canonical.toSet();
    final seen = <String>{};
    final resolvedOrder = <String>[
      for (final route in order)
        if (known.contains(route) && seen.add(route)) route,
      for (final route in canonical)
        if (seen.add(route)) route,
    ];
    final limit = resolvedOrder.length < maxPrimaryRoutes
        ? resolvedOrder.length
        : maxPrimaryRoutes;
    // An empty stored selection means "not customized yet", not "no main bar":
    // fall back to [defaultPrimaryRoutes]. A bar with no primary at all would
    // be a single "More" entry, which is not a usable arrangement.
    final requested = primary.isEmpty ? defaultPrimaryRoutes : primary;
    var wanted = <String>{
      for (final route in requested)
        if (resolvedOrder.contains(route)) route,
    };
    // A stored selection can also name only routes that no longer exist, which
    // matches nothing above. Degrade to the defaults rather than to a bar with
    // no primary at all.
    if (wanted.isEmpty) {
      wanted = {
        for (final route in defaultPrimaryRoutes)
          if (resolvedOrder.contains(route)) route,
      };
    }
    final capped = wanted.take(limit).toSet();
    return NavArrangement(
      order: resolvedOrder,
      primary: [
        for (final route in resolvedOrder)
          if (capped.contains(route)) route,
      ],
    );
  }

  /// Reads the arrangement off persisted settings, falling back to
  /// [defaults] while settings have not loaded (or are unavailable).
  factory NavArrangement.fromSettings(ShopSettings? settings) =>
      settings == null
      ? NavArrangement.defaults
      : NavArrangement.resolve(
          order: settings.navigationOrder,
          primary: settings.navigationPrimary,
        );

  bool isPrimary(String route) => primary.contains(route);

  bool contains(String route) => order.contains(route);

  /// Moves [route] one slot towards the start of [order].
  NavArrangement moveUp(String route) => _shift(route, -1);

  /// Moves [route] one slot towards the end of [order].
  NavArrangement moveDown(String route) => _shift(route, 1);

  NavArrangement _shift(String route, int delta) {
    final from = order.indexOf(route);
    if (from < 0) return this;
    final to = from + delta;
    if (to < 0 || to >= order.length) return this;
    final next = List<String>.of(order);
    next
      ..removeAt(from)
      ..insert(to, route);
    return NavArrangement.resolve(order: next, primary: primary);
  }

  /// Moves [route] into or out of the phone main bar.
  ///
  /// Turning a destination off the main bar never hides it — it moves to
  /// "More". Promoting past [maxPrimaryRoutes] is a no-op so the bar cannot
  /// grow past its slot budget, and the owner can always demote something
  /// else to make room.
  NavArrangement setPrimary(String route, {required bool isPrimary}) {
    if (!contains(route)) return this;
    if (isPrimary == this.isPrimary(route)) return this;
    if (isPrimary) {
      if (primary.length >= maxPrimaryRoutes) return this;
      return NavArrangement.resolve(order: order, primary: [...primary, route]);
    }
    return NavArrangement.resolve(
      order: order,
      primary: [...primary]..remove(route),
    );
  }

  /// Replaces the whole order (used by drag-reorder in the editor).
  NavArrangement withOrder(List<String> newOrder) =>
      NavArrangement.resolve(order: newOrder, primary: primary);

  NavDestination descriptorFor(String route) => navDestinations.firstWhere(
    (destination) => destination.route == route,
    orElse: () => navDestinations.first,
  );

  /// Canonical label for [route], or [fallback] for an unknown route.
  String labelFor(String route, {String fallback = ''}) {
    for (final destination in navDestinations) {
      if (destination.route == route) return destination.label;
    }
    return fallback;
  }

  /// Permission required by [route], or null when the route is unknown.
  Permission? permissionFor(String route) => permissionOfRoute(route);

  /// Permission required by [route] regardless of any arrangement, or null
  /// when the route is not a known destination.
  static Permission? permissionOfRoute(String route) {
    for (final destination in navDestinations) {
      if (destination.route == route) return destination.permission;
    }
    return null;
  }

  /// The registry entry for [route], or null when it is not a destination.
  static NavDestination? destinationFor(String route) {
    for (final destination in navDestinations) {
      if (destination.route == route) return destination;
    }
    return null;
  }
}
