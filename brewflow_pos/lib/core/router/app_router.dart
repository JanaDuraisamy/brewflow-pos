import 'dart:async';

import 'package:brewflow_pos/app/shells/access_denied_shell.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/shells/splash_shell.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_page.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_detail_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_form_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_page.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expense_form_page.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_page.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/category_management_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_history_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_form_page.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/order_detail_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_page.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_detail_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_form_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchases_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/supplier_form_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_page.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_page.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_page.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_page.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/owner_storage_usage_page.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

export 'package:brewflow_pos/core/router/app_routes.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Centralized Router Configuration
///
/// Single source of truth for application navigation:
/// - public routes: /splash and /auth
/// - the application shell ([AppShell]) via a [StatefulShellRoute] with one
///   branch per destination, so destination pages stay alive across switches
///   and direct navigation to any named destination works.
///
/// Authentication guard: [appRouterProvider] wires the router to the auth
/// state through the [redirect] + [refreshListenable] extension points — the
/// router itself is never recreated while auth changes.
/// ---------------------------------------------------------------------------

/// Builds the application router.
///
/// [redirect] and [refreshListenable] are the extension points for guards:
/// pass an authorization redirect here and nothing else in the route table
/// needs to change.
GoRouter buildAppRouter({
  FutureOr<String?> Function(BuildContext context, GoRouterState state)?
  redirect,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashShell(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: 'auth',
        builder: (context, state) => const AuthShell(),
      ),
      GoRoute(
        path: AppRoutes.noAccess,
        name: 'no_access',
        builder: (context, state) => const AccessDeniedShell(),
      ),
      GoRoute(
        path: AppRoutes.staff,
        name: 'staff',
        builder: (context, state) => const StaffPage(),
      ),
      GoRoute(
        path: AppRoutes.storageCleanup,
        name: 'storage_cleanup',
        builder: (context, state) => const OwnerStorageUsagePage(),
      ),
      GoRoute(
        path: AppRoutes.storageCleanupReview,
        name: 'storage_cleanup_review',
        builder: (context, state) => StorageCleanupReviewPage(
          report: state.extra is StorageUsageReport
              ? state.extra! as StorageUsageReport
              : null,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          _branch(
            GoRoute(
              path: AppRoutes.dashboard,
              name: 'dashboard',
              builder: (context, state) => const DashboardPage(),
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.inventory,
              name: 'inventory',
              builder: (context, state) => const InventoryPage(),
              routes: [
                GoRoute(
                  path: 'categories',
                  name: 'inventory_categories',
                  builder: (context, state) => const CategoryManagementPage(),
                ),
                GoRoute(
                  path: 'products/new',
                  name: 'inventory_product_new',
                  builder: (context, state) => const ProductFormPage(),
                ),
                GoRoute(
                  path: 'products/edit',
                  name: 'inventory_product_edit',
                  builder: (context, state) => ProductFormPage(
                    product: state.extra is Product
                        ? state.extra! as Product
                        : null,
                  ),
                ),
                GoRoute(
                  path: 'products/history',
                  name: 'inventory_product_stock_history',
                  builder: (context, state) => StockMovementHistoryPage(
                    args: state.extra is StockHistoryArgs
                        ? state.extra! as StockHistoryArgs
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.billing,
              name: 'billing',
              builder: (context, state) => const PosPage(),
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.orders,
              name: 'orders',
              builder: (context, state) => const OrdersPage(),
              routes: [
                GoRoute(
                  path: 'detail',
                  name: 'orders_detail',
                  builder: (context, state) => OrderDetailPage(
                    order: state.extra is OrderSummary
                        ? state.extra! as OrderSummary
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.customers,
              name: 'customers',
              builder: (context, state) => const CustomersPage(),
              routes: [
                GoRoute(
                  path: 'new',
                  name: 'customers_new',
                  builder: (context, state) => const CustomerFormPage(),
                ),
                GoRoute(
                  path: 'edit',
                  name: 'customers_edit',
                  builder: (context, state) => CustomerFormPage(
                    customer: state.extra is Customer
                        ? state.extra! as Customer
                        : null,
                  ),
                ),
                GoRoute(
                  path: 'detail',
                  name: 'customers_detail',
                  builder: (context, state) => CustomerDetailPage(
                    customer: state.extra is Customer
                        ? state.extra! as Customer
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.suppliers,
              name: 'suppliers',
              builder: (context, state) => const SuppliersPage(),
              routes: [
                GoRoute(
                  path: 'new',
                  name: 'suppliers_new',
                  builder: (context, state) => const SupplierFormPage(),
                ),
                GoRoute(
                  path: 'edit',
                  name: 'suppliers_edit',
                  builder: (context, state) => SupplierFormPage(
                    supplier: state.extra is Supplier
                        ? state.extra! as Supplier
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.purchases,
              name: 'purchases',
              builder: (context, state) => const PurchasesPage(),
              routes: [
                GoRoute(
                  path: 'new',
                  name: 'purchases_new',
                  builder: (context, state) => const PurchaseFormPage(),
                ),
                GoRoute(
                  path: 'detail',
                  name: 'purchases_detail',
                  builder: (context, state) => PurchaseDetailPage(
                    purchase: state.extra is Purchase
                        ? state.extra! as Purchase
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.expenses,
              name: 'expenses',
              builder: (context, state) => const ExpensesPage(),
              routes: [
                GoRoute(
                  path: 'new',
                  name: 'expenses_new',
                  builder: (context, state) => const ExpenseFormPage(),
                ),
                GoRoute(
                  path: 'edit',
                  name: 'expenses_edit',
                  builder: (context, state) => ExpenseFormPage(
                    expense: state.extra is Expense
                        ? state.extra! as Expense
                        : null,
                  ),
                ),
              ],
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.reports,
              name: 'reports',
              builder: (context, state) => const ReportsPage(),
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.offers,
              name: 'offers',
              builder: (context, state) => const OffersPage(),
            ),
          ),
          _branch(
            GoRoute(
              path: AppRoutes.settings,
              name: 'settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ),
        ],
      ),
    ],
    redirect: redirect,
    refreshListenable: refreshListenable,
  );
}

/// A shell branch hosting a single destination route.
StatefulShellBranch _branch(GoRoute route) =>
    StatefulShellBranch(routes: [route]);

/// The single stable router instance for the application scope.
///
/// Watches auth state without recreating the router: a [ValueNotifier] bridge
/// notifies GoRouter to re-evaluate redirects on every auth state change.
/// The router is disposed with the scope.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ValueNotifier<AuthState>(
    ref.read(authControllerProvider),
  );
  ref.listen(authControllerProvider, (previous, next) {
    authNotifier.value = next;
  });
  ref.onDispose(authNotifier.dispose);

  // Role/permission changes (login resolution, staff edits, sign-out) must
  // also re-evaluate redirects.
  final profileNotifier = ValueNotifier<int>(0);
  ref.listen(userProfileProvider, (previous, next) {
    profileNotifier.value++;
  });
  ref.onDispose(profileNotifier.dispose);

  final router = buildAppRouter(
    refreshListenable: Listenable.merge([authNotifier, profileNotifier]),
    redirect: (context, state) =>
        _authorizationRedirect(context, state, authNotifier.value),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Authorization guard.
///
/// - While auth is [AuthStatus.initializing] no redirects run: the splash
///   stays visible until the session resolves (no artificial delays).
/// - Authenticated users land on the dashboard shell; every shell destination
///   stays reachable for the OWNER, while STAFF routes are judged against
///   their granted permissions — direct navigation included. While the
///   profile is still resolving, navigation proceeds (the shell re-renders
///   once permissions land); a resolved "no access" state sends protected
///   locations to /no-access.
/// - Unauthenticated users are forced to /auth and cannot reach any shell
///   destination.
/// - Every redirect target is a redirect-worthy location, so no loops occur.
FutureOr<String?> _authorizationRedirect(
  BuildContext context,
  GoRouterState state,
  AuthState auth,
) {
  if (auth.status == AuthStatus.initializing) {
    return null;
  }

  final location = state.matchedLocation;

  if (auth.status == AuthStatus.authenticated) {
    if (location == AppRoutes.noAccess) {
      return null;
    }
    // /staff lives outside the shell branch list but is still a guarded,
    // owner-only destination. /storage is the same kind: a pushed, owner-only
    // screen (storage monitoring + monthly cleanup).
    final isStorage = location.startsWith(AppRoutes.storageCleanup);
    if (!AppRoutes.isProtected(location) &&
        location != AppRoutes.staff &&
        !isStorage) {
      return AppRoutes.dashboard;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final profileAsync = container.read(userProfileProvider);
    // Deny only on a RESOLVED profile that lacks the permission (staff
    // restrictions, direct deep-links included). Unresolved/errored states
    // degrade to legacy access inside the controller instead of locking the
    // operator out of the device.
    if (!profileAsync.hasValue || profileAsync.value == null) {
      // Inactive/unprovisioned profiles surface as typed errors: deny hard.
      final error = profileAsync.error;
      if (error is ProfileNotProvisionedFailure) {
        return AppRoutes.noAccess;
      }
      return null;
    }
    final profile = profileAsync.value!;
    // Storage monitoring/cleanup is strictly owner-only: staff are always
    // denied regardless of any permission, since the operation requires an
    // OWNER at the server boundary too.
    if (location.startsWith(AppRoutes.storageCleanup) && !profile.isOwner) {
      return AppRoutes.noAccess;
    }
    final authorization = RoleBasedAuthorization(
      role: profile.role,
      grantedPermissions: profile.permissions,
    );
    final required = _requiredPermissionFor(location);
    if (required == null || authorization.can(required)) {
      return null;
    }
    return AppRoutes.noAccess;
  }

  // Unauthenticated or auth error (error keeps the user on the login screen
  // so the failure message stays visible and can be retried).
  if (location != AppRoutes.auth) {
    return AppRoutes.auth;
  }
  return null;
}

/// The permission a protected location requires. Sub-routes inherit their
/// module's permission; /staff is owner-gated via [Permission.manageStaff].
Permission? _requiredPermissionFor(String location) {
  if (location == AppRoutes.dashboard) return Permission.viewDashboard;
  if (location.startsWith(AppRoutes.inventory)) {
    return Permission.viewInventory;
  }
  if (location == AppRoutes.billing) return Permission.billing;
  if (location.startsWith(AppRoutes.orders)) return Permission.orders;
  if (location.startsWith(AppRoutes.customers)) return Permission.customers;
  if (location.startsWith(AppRoutes.suppliers)) return Permission.suppliers;
  if (location.startsWith(AppRoutes.purchases)) return Permission.purchases;
  if (location.startsWith(AppRoutes.expenses)) return Permission.expenses;
  if (location == AppRoutes.reports) return Permission.reports;
  if (location == AppRoutes.offers) return Permission.offers;
  if (location == AppRoutes.settings) return Permission.settings;
  if (location == AppRoutes.staff) return Permission.manageStaff;
  if (location.startsWith(AppRoutes.storageCleanup)) {
    return Permission.manageStaff;
  }
  return null;
}
