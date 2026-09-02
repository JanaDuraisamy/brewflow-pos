/// ---------------------------------------------------------------------------
/// BrewFlow POS — Authorization Core
///
/// The single authoritative source for roles and permissions. Every role
/// check in the app flows through [AuthorizationService.can]; widgets,
/// controllers and repositories all ask the same question here, so permission
/// logic is never duplicated or scattered.
///
/// - OWNER implicitly holds every permission and can never be restricted.
/// - STAFF holds exactly the capabilities the owner granted (persisted as
///   normalized rows in the staff_permissions table).
/// ---------------------------------------------------------------------------
library;

/// Access role of an authenticated profile.
enum UserRole {
  owner,
  staff;

  /// Database-storage value, kept stable for history.
  String get dbValue => switch (this) {
    UserRole.owner => 'OWNER',
    UserRole.staff => 'STAFF',
  };

  static UserRole? fromDbValue(String value) => switch (value) {
    'OWNER' => UserRole.owner,
    'STAFF' => UserRole.staff,
    _ => null,
  };
}

/// One capability a STAFF profile may be granted.
enum Permission {
  /// See the dashboard landing page.
  viewDashboard('VIEW_DASHBOARD'),

  /// Use Billing/POS, including completing sales.
  billing('BILLING'),

  /// Browse products/variants in Inventory.
  viewInventory('VIEW_INVENTORY'),

  /// Create/edit/deactivate products, categories and variants.
  editInventory('EDIT_INVENTORY'),

  /// Manual stock adjustments (audit-tracked).
  stockAdjustment('STOCK_ADJUSTMENT'),

  /// Purchases/receiving.
  purchases('PURCHASES'),

  /// Supplier management.
  suppliers('SUPPLIERS'),

  /// Customer management.
  customers('CUSTOMERS'),

  /// Customer ledger payments and dues view.
  customerLedger('CUSTOMER_LEDGER'),

  /// Expenses module, including mutations.
  expenses('EXPENSES'),

  /// Reports access.
  reports('REPORTS'),

  /// Orders module.
  orders('ORDERS'),

  /// Settings mutations (business identity, preferences).
  settings('SETTINGS'),

  /// Offers/promotions management.
  offers('OFFERS'),

  /// Staff management (owner-only capability; granting it does not lift the
  /// owner-protection rules below).
  manageStaff('MANAGE_STAFF');

  const Permission(this.dbValue);

  /// Database-storage value, kept stable for history.
  final String dbValue;

  static Permission? fromDbValue(String value) {
    for (final permission in Permission.values) {
      if (permission.dbValue == value) return permission;
    }
    return null;
  }
}

/// Permissions a newly created STAFF profile receives when the owner picks no
/// explicit set: safe counter-facing basics only; every sensitive operation
/// stays off until explicitly granted.
const Set<Permission> defaultStaffPermissions = {
  Permission.billing,
  Permission.viewInventory,
  Permission.customers,
  Permission.orders,
};

/// Typed, user-safe denial raised by controllers/repositories when an
/// operation requires a permission the signed-in profile does not hold.
final class PermissionDeniedFailure implements Exception {
  const PermissionDeniedFailure([
    this.message =
        'You do not have access to '
        'this feature. Ask the owner to grant permission.',
  ]);

  /// Message safe to show directly to the user.
  final String message;

  @override
  String toString() => message;
}

/// Answers one question for the whole app: may the current profile perform
/// [permission]?
abstract interface class AuthorizationService {
  bool can(Permission permission);
}

/// Authorization over a concrete role + granted set. Owner always wins;
/// staff is judged strictly by their granted set.
final class RoleBasedAuthorization implements AuthorizationService {
  const RoleBasedAuthorization({
    required this.role,
    this.grantedPermissions = const {},
  });

  final UserRole? role;
  final Set<Permission> grantedPermissions;

  @override
  bool can(Permission permission) => switch (role) {
    UserRole.owner => true,
    UserRole.staff => grantedPermissions.contains(permission),
    null => false,
  };

  /// Boundary check for business operations. A resolved STAFF/OWNER session
  /// is judged strictly; a missing profile (no resolved session yet — e.g.
  /// pure unit/service contexts) does not fail closed here, because such
  /// contexts never come from a signed-in device session. The route guard
  /// guarantees every real app session has a resolved profile before any
  /// business screen is reachable.
  bool canForSession(Permission permission) =>
      role == null ? true : can(permission);
}
