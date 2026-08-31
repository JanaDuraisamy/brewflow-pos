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

  // ---- Deletions -------------------------------------------------------------

  /// Records that an entity row was hard-deleted on this device, so other
  /// devices can learn about it through their next pull.
  Future<void> recordDeletion(SyncDeletion deletion);

  Future<PullPage<SyncDeletion>> pullDeletions({
    required DateTime since,
    required int limit,
  });
}
