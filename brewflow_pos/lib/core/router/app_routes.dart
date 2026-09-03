/// ---------------------------------------------------------------------------
/// BrewFlow POS — Centralized Route Constants
///
/// Single source of truth for every application path. Widgets and the router
/// always reference these constants; route strings are never scattered
/// through widgets.
/// ---------------------------------------------------------------------------
library;

abstract final class AppRoutes {
  AppRoutes._();

  // Public routes
  static const String splash = '/splash';
  static const String auth = '/auth';

  /// Shown when an authenticated account lacks the permission for a route it
  /// tried to open directly.
  static const String noAccess = '/no-access';

  /// Owner-only staff management (pushed page, not a shell branch).
  static const String staff = '/staff';

  /// Owner-only storage monitoring + monthly cleanup (pushed page).
  static const String storageCleanup = '/storage';
  static const String storageCleanupReview = '/storage/review';

  // Application shell destinations
  static const String dashboard = '/dashboard';
  static const String inventory = '/inventory';
  static const String billing = '/billing';
  static const String orders = '/orders';
  static const String customers = '/customers';
  static const String suppliers = '/suppliers';
  static const String purchases = '/purchases';
  static const String expenses = '/expenses';
  static const String reports = '/reports';
  static const String offers = '/offers';
  static const String settings = '/settings';

  // Inventory module sub-routes (pushed on top of the inventory branch)
  static const String inventoryCategories = '/inventory/categories';
  static const String productNew = '/inventory/products/new';
  static const String productEdit = '/inventory/products/edit';
  static const String productStockHistory = '/inventory/products/history';

  // Orders module sub-routes (pushed on top of the orders branch)
  static const String orderDetail = '/orders/detail';

  // Customers module sub-routes (pushed on top of the customers branch)
  static const String customerNew = '/customers/new';
  static const String customerEdit = '/customers/edit';
  static const String customerDetail = '/customers/detail';

  // Suppliers module sub-routes (pushed on top of the suppliers branch)
  static const String supplierNew = '/suppliers/new';
  static const String supplierEdit = '/suppliers/edit';

  // Purchases module sub-routes (pushed on top of the purchases branch)
  static const String purchaseNew = '/purchases/new';
  static const String purchaseDetail = '/purchases/detail';

  // Expenses module sub-routes (pushed on top of the expenses branch)
  static const String expenseNew = '/expenses/new';
  static const String expenseEdit = '/expenses/edit';

  /// Every authenticated destination hosted by the application shell, in
  /// navigation order (branch index == list index).
  static const List<String> destinations = [
    dashboard,
    inventory,
    billing,
    orders,
    customers,
    suppliers,
    purchases,
    expenses,
    reports,
    offers,
    settings,
  ];

  /// Whether [location] is one of the authenticated shell destinations.
  static bool isDestination(String location) => destinations.contains(location);

  /// Whether [location] (and its module sub-routes) requires authentication.
  static bool isProtected(String location) => destinations.any(
    (destination) =>
        location == destination || location.startsWith('$destination/'),
  );
}
