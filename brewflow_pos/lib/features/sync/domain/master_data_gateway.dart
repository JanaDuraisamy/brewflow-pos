/// ---------------------------------------------------------------------------
/// BrewFlow POS — Remote Master-Data Gateway (domain contract)
///
/// The ONLY boundary through which the sync engine touches the cloud mirror.
/// UI/controllers never issue Supabase calls themselves. Implementations:
///
/// - [SupabaseMasterDataGateway] — production (RLS-scoped by the caller's
///   session; the server never trusts client shop claims).
/// - in-memory fakes — tests drive two "devices" against one shared fake to
///   prove real A→cloud→B propagation.
///
/// Contract rules:
/// - Push methods are idempotent UPSERTS keyed by the entity UUID.
/// - Pull methods return rows with server `updated_at` strictly greater than
///   [since], ordered ascending, at most [limit] rows — so advancing a cursor
///   to the last returned timestamp is always safe.
/// - Failures THROW; the engine owns retry bookkeeping (never silent loss).
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/sync/domain/device_registration.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';

/// Cursor-based incremental pull page for one entity type.
final class PullPage<T> {
  const PullPage({required this.rows, required this.newCursor});

  /// Rows with updated_at > previous cursor, ascending by it.
  final List<T> rows;

  /// The cursor callers must persist for the next pull: the greatest
  /// server `updated_at` seen (unchanged when [rows] is empty).
  final DateTime newCursor;
}

abstract interface class RemoteMasterDataGateway
    implements RemoteDeviceGateway {
  // ---- Shops -----------------------------------------------------------

  Future<void> upsertShops(List<SyncShop> rows);

  Future<PullPage<SyncShop>> pullShops({
    required DateTime since,
    required int limit,
  });

  // ---- Categories ---------------------------------------------------------

  Future<void> upsertCategories(List<SyncCategory> rows);

  Future<PullPage<SyncCategory>> pullCategories({
    required DateTime since,
    required int limit,
  });

  // ---- Products + variants ------------------------------------------------

  Future<void> upsertProducts(List<SyncProduct> rows);

  Future<PullPage<SyncProduct>> pullProducts({
    required DateTime since,
    required int limit,
  });

  Future<void> upsertProductVariants(List<SyncProductVariant> rows);

  Future<PullPage<SyncProductVariant>> pullProductVariants({
    required DateTime since,
    required int limit,
  });

  // ---- Suppliers ----------------------------------------------------------

  Future<void> upsertSuppliers(List<SyncSupplier> rows);

  Future<PullPage<SyncSupplier>> pullSuppliers({
    required DateTime since,
    required int limit,
  });

  // ---- Customers ----------------------------------------------------------

  Future<void> upsertCustomers(List<SyncCustomer> rows);

  Future<PullPage<SyncCustomer>> pullCustomers({
    required DateTime since,
    required int limit,
  });

  // ---- Sales --------------------------------------------------------------

  Future<void> upsertSales(List<SyncSale> rows);

  Future<PullPage<SyncSale>> pullSales({
    required DateTime since,
    required int limit,
  });

  // ---- Sale Items ---------------------------------------------------------

  Future<void> upsertSaleItems(List<SyncSaleItem> rows);

  Future<PullPage<SyncSaleItem>> pullSaleItems({
    required DateTime since,
    required int limit,
  });

  // ---- Expenses -----------------------------------------------------------

  Future<void> upsertExpenses(List<SyncExpense> rows);

  Future<PullPage<SyncExpense>> pullExpenses({
    required DateTime since,
    required int limit,
  });

  // ---- Customer Payments --------------------------------------------------

  Future<void> upsertCustomerPayments(List<SyncCustomerPayment> rows);

  Future<PullPage<SyncCustomerPayment>> pullCustomerPayments({
    required DateTime since,
    required int limit,
  });

  // ---- Expense payments ------------------------------------------------------

  /// Pushes payments made against shop payables. Whole rows only: a balance is
  /// derived by every device from the payments it holds, so nothing here
  /// carries a running total that two devices could disagree about.
  Future<void> upsertExpensePayments(List<SyncExpensePayment> rows);

  Future<PullPage<SyncExpensePayment>> pullExpensePayments({
    required DateTime since,
    required int limit,
  });

  // ---- Offers ---------------------------------------------------------------

  Future<void> upsertOffers(List<SyncOffer> rows);

  Future<PullPage<SyncOffer>> pullOffers({
    required DateTime since,
    required int limit,
  });

  // ---- Staff attendance -----------------------------------------------------

  /// Pushes attendance shifts. Idempotent UPSERTS keyed by the shift UUID:
  /// retrying the same operation (clock-in, then clock-out of the same shift)
  /// converges on one row, never duplicates.
  ///
  /// [authUserId] is the cross-device identity the row is stamped with;
  /// [SyncStaffAttendance.staffUserId] is the authoring device's local profile
  /// id, carried for attribution only.
  Future<void> upsertStaffAttendance(List<SyncStaffAttendance> rows);

  Future<PullPage<SyncStaffAttendance>> pullStaffAttendance({
    required DateTime since,
    required int limit,
  });

  /// Hard-deletes one attendance shift in the cloud, scoped to the shop and
  /// the cross-device staff identity. Owner-only by RLS (0027), exactly like
  /// the direct payroll gateway's delete.
  Future<void> deleteStaffAttendance({
    required String shopId,
    required String authUserId,
    required String shiftId,
  });

  // ---- Deletions -------------------------------------------------------------

  /// Hard-deletes the `customers` row in the cloud.
  ///
  /// The CUSTOMER tombstone is what actually makes deletion correct on other
  /// devices: `_drainDeletions` runs last in every pull cycle, so a device that
  /// re-pulls a still-present row in the same cycle has it removed again by the
  /// tombstone. This is the belt to that braces, removing the other half of the
  /// problem: without it the deleted row stays in `customers` forever, so every
  /// freshly provisioned device pulls and deletes it again on every first sync,
  /// and deleted customers accumulate in the cloud table invisibly.
  Future<void> deleteCustomer(String id);

  /// Hard-deletes the `products` row in the cloud.
  ///
  /// Same reasoning as [deleteCustomer], and needed for the same reason. The
  /// PRODUCT tombstone alone makes peers converge — `_drainDeletions` runs last
  /// in the pull — but the row would otherwise linger in `products` and be
  /// re-pulled by every freshly provisioned device on every first sync.
  ///
  /// Safe unconditionally as of schema v31 / cloud migration 0037: the six
  /// historical `sale_items` / `purchase_items` / `stock_movements` foreign keys
  /// are already gone (so history cannot block it), and
  /// `product_variants.product_id` is `ON DELETE CASCADE`, so the variants leave
  /// with the product instead of raising a foreign-key violation. `master_
  /// deletions` is never FK-referenced, so the tombstone insert is unaffected.
  Future<void> deleteProduct(String id);

  /// Records that an entity row was hard-deleted on this device, so other
  /// devices can learn about it through their next pull.
  Future<void> recordDeletion(SyncDeletion deletion);

  Future<PullPage<SyncDeletion>> pullDeletions({
    required DateTime since,
    required int limit,
  });
}
