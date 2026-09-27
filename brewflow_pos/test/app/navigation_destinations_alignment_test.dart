import 'package:brewflow_pos/app/navigation/navigation_config.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('navigation destination alignment', () {
    test('registry is exactly the router destination list, in order', () {
      expect(canonicalNavRoutes, AppRoutes.destinations);
    });

    test('every destination is a real branch with the matching index', () {
      for (var i = 0; i < navDestinations.length; i++) {
        expect(
          AppRoutes.branchIndexOf(navDestinations[i].route),
          i,
          reason: '${navDestinations[i].route} must map to branch $i',
        );
      }
    });

    test('pushed routes are not shell branches', () {
      // Payroll and closing stay pushed, so they must not collide with a
      // branch index — that collision is what mis-routed taps before.
      expect(AppRoutes.branchIndexOf(AppRoutes.staffPayroll), -1);
      expect(AppRoutes.branchIndexOf(AppRoutes.closing), -1);
      expect(
        AppRoutes.isDestination(AppRoutes.staffPayroll),
        isFalse,
        reason: 'payroll is reached from inside Staff Management',
      );
    });

    test('routes and labels are unique and non-empty', () {
      final routes = navDestinations.map((d) => d.route).toList();
      final labels = navDestinations.map((d) => d.label).toList();
      expect(routes.toSet().length, routes.length);
      expect(labels.toSet().length, labels.length);
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
    });

    test('Staff Management is a real branch with its canonical name', () {
      expect(AppRoutes.destinations, contains(AppRoutes.staff));
      final staff = NavArrangement.destinationFor(AppRoutes.staff);
      expect(staff, isNotNull);
      expect(staff!.label, 'Staff Management');
      expect(staff.permission, Permission.manageStaff);
      // The regression: Staff used to sit outside the shell, so tapping it
      // opened Inventory.
      expect(AppRoutes.branchIndexOf(AppRoutes.staff), 1);
      expect(
        AppRoutes.branchIndexOf(AppRoutes.staff),
        isNot(AppRoutes.branchIndexOf(AppRoutes.inventory)),
      );
    });

    test('every destination declares a permission, unknown routes do not', () {
      for (final destination in navDestinations) {
        expect(
          NavArrangement.permissionOfRoute(destination.route),
          destination.permission,
        );
      }
      expect(NavArrangement.permissionOfRoute('/nope'), isNull);
    });
  });

  group('NavArrangement defaults', () {
    test('default order is the canonical order', () {
      expect(NavArrangement.defaults.order, AppRoutes.destinations);
    });

    test('default main bar is the documented three', () {
      expect(NavArrangement.defaults.primary, defaultPrimaryRoutes);
      expect(defaultPrimaryRoutes.length, lessThanOrEqualTo(maxPrimaryRoutes));
      expect(NavArrangement.defaults.primary, contains(AppRoutes.staff));
    });

    test('null settings fall back to defaults', () {
      final arrangement = NavArrangement.fromSettings(null);
      expect(arrangement.order, NavArrangement.defaults.order);
      expect(arrangement.primary, NavArrangement.defaults.primary);
    });

    test('unconfigured settings fall back to defaults', () {
      final arrangement = NavArrangement.fromSettings(
        const ShopSettings(shopName: 'JiggarTea'),
      );
      expect(arrangement.order, AppRoutes.destinations);
      expect(arrangement.primary, defaultPrimaryRoutes);
    });
  });

  group('NavArrangement cannot hide a feature', () {
    test('a persisted order that lists only one route keeps all twelve', () {
      final arrangement = NavArrangement.resolve(order: [AppRoutes.settings]);
      expect(arrangement.order.length, AppRoutes.destinations.length);
      expect(arrangement.order.toSet(), AppRoutes.destinations.toSet());
    });

    test('unknown routes are dropped', () {
      final arrangement = NavArrangement.resolve(
        order: ['/ghost', AppRoutes.billing],
      );
      expect(arrangement.order, isNot(contains('/ghost')));
      expect(arrangement.order.length, AppRoutes.destinations.length);
    });

    test('duplicates are collapsed', () {
      final arrangement = NavArrangement.resolve(
        order: [
          AppRoutes.orders,
          AppRoutes.orders,
          AppRoutes.orders,
          AppRoutes.billing,
        ],
      );
      expect(arrangement.order.where((r) => r == AppRoutes.orders).length, 1);
      expect(arrangement.order.length, AppRoutes.destinations.length);
    });

    test('a fully corrupt preference still yields every destination', () {
      final arrangement = NavArrangement.resolve(
        order: ['/a', '/b', '/c'],
        primary: ['/a'],
      );
      expect(arrangement.order, AppRoutes.destinations);
      expect(arrangement.primary, defaultPrimaryRoutes);
    });

    test('reordering keeps the full set and is reversible', () {
      final moved = NavArrangement.defaults.moveUp(AppRoutes.expenses);
      expect(moved.order.length, AppRoutes.destinations.length);
      expect(moved.order.toSet(), AppRoutes.destinations.toSet());
      expect(
        moved.order.indexOf(AppRoutes.expenses),
        NavArrangement.defaults.order.indexOf(AppRoutes.expenses) - 1,
      );
      expect(
        moved.moveDown(AppRoutes.expenses).order,
        NavArrangement.defaults.order,
      );
    });

    test('moving the first or last slot is a no-op', () {
      final first = AppRoutes.destinations.first;
      final last = AppRoutes.destinations.last;
      expect(
        NavArrangement.defaults.moveUp(first).order,
        NavArrangement.defaults.order,
      );
      expect(
        NavArrangement.defaults.moveDown(last).order,
        NavArrangement.defaults.order,
      );
    });

    test('moving an unknown route is a no-op', () {
      expect(
        NavArrangement.defaults.moveUp('/ghost').order,
        NavArrangement.defaults.order,
      );
    });
  });

  group('NavArrangement main/More partitioning', () {
    test('demoting a primary keeps it reachable under More', () {
      final arrangement = NavArrangement.defaults.setPrimary(
        AppRoutes.staff,
        isPrimary: false,
      );
      expect(arrangement.isPrimary(AppRoutes.staff), isFalse);
      expect(
        arrangement.contains(AppRoutes.staff),
        isTrue,
        reason: 'demoted means More, never hidden',
      );
      expect(arrangement.order.length, AppRoutes.destinations.length);
    });

    test('promoting fills the bar up to the cap', () {
      var arrangement = NavArrangement.defaults;
      for (final route in [AppRoutes.orders, AppRoutes.reports]) {
        arrangement = arrangement.setPrimary(route, isPrimary: true);
      }
      expect(arrangement.primary.length, maxPrimaryRoutes);
    });

    test('promoting past the cap is refused, not silently dropped', () {
      var arrangement = NavArrangement.defaults;
      for (final route in [
        AppRoutes.orders,
        AppRoutes.reports,
        AppRoutes.offers,
      ]) {
        arrangement = arrangement.setPrimary(route, isPrimary: true);
      }
      expect(arrangement.primary.length, maxPrimaryRoutes);
      expect(arrangement.isPrimary(AppRoutes.offers), isFalse);
      expect(
        arrangement.contains(AppRoutes.offers),
        isTrue,
        reason: 'a refused promotion must not hide the destination',
      );
    });

    test('a persisted over-cap primary list is trimmed, nothing lost', () {
      final arrangement = NavArrangement.resolve(
        primary: [
          AppRoutes.dashboard,
          AppRoutes.staff,
          AppRoutes.inventory,
          AppRoutes.billing,
          AppRoutes.orders,
          AppRoutes.customers,
        ],
      );
      expect(arrangement.primary.length, maxPrimaryRoutes);
      expect(arrangement.order.length, AppRoutes.destinations.length);
    });

    test('an empty persisted primary list falls back to the defaults', () {
      final arrangement = NavArrangement.resolve(
        order: [AppRoutes.orders, AppRoutes.dashboard],
        primary: const [],
      );
      expect(arrangement.primary, defaultPrimaryRoutes);
    });

    test('cannot demote every destination out of the main bar', () {
      var arrangement = NavArrangement.defaults;
      for (final route in List<String>.of(defaultPrimaryRoutes)) {
        arrangement = arrangement.setPrimary(route, isPrimary: false);
      }
      expect(
        arrangement.primary,
        defaultPrimaryRoutes,
        reason: 'a single-More bar is not a usable arrangement',
      );
    });

    test('primary is always a subset of order', () {
      final arrangement = NavArrangement.resolve(
        order: [AppRoutes.billing, AppRoutes.dashboard],
        primary: [AppRoutes.expenses, AppRoutes.dashboard],
      );
      expect(
        arrangement.order.toSet().containsAll(arrangement.primary),
        isTrue,
      );
    });
  });

  group('canonical labels', () {
    test('labels are never shortened to fit the phone bar', () {
      expect(
        NavArrangement.defaults.labelFor(AppRoutes.dashboard),
        'Dashboard',
      );
      expect(
        NavArrangement.defaults.labelFor(AppRoutes.staff),
        'Staff Management',
      );
      expect(
        NavArrangement.defaults.labelFor(AppRoutes.inventory),
        'Inventory',
      );
      expect(
        NavArrangement.defaults.labelFor('/ghost', fallback: 'Unknown'),
        'Unknown',
      );
    });

    test('an unknown route has no descriptor', () {
      expect(NavArrangement.destinationFor('/ghost'), isNull);
    });
  });
}
