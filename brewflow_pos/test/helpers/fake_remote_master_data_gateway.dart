import 'package:brewflow_pos/features/sync/domain/device_registration.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_gateway.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';

/// ---------------------------------------------------------------------------
/// Test double — in-memory cloud mirror standing in for Supabase.
///
/// [FakeRemoteStore] is the shared "server": one instance represents the
/// cloud for a whole test scenario. Each device gets its OWN
/// [FakeRemoteMasterDataGateway] bound to the store and to its shop id,
/// which models RLS honestly:
///
///   - pushes with a foreign shop_id are REJECTED (WITH CHECK violation),
///   - pulls only ever return the viewer's own shop rows.
///
/// Server timestamps come from a deterministic monotonic clock (every write
/// advances by exactly 1 ms), so cursor behavior is fully reproducible.
/// ---------------------------------------------------------------------------

final class StoredRow<T> {
  StoredRow(this.row, this.shopId, this.updatedAt);
  T row;
  final String shopId;
  DateTime updatedAt;
}

/// Shared "server" state: one instance per test scenario, visible to every
/// device's gateway. Public because two gateways must share it.
final class FakeRemoteStore {
  DateTime clock = DateTime.utc(2026, 1, 1);

  final Map<String, DeviceRegistration> devices = {};
  final Map<String, StoredRow<SyncCategory>> categories = {};
  final Map<String, StoredRow<SyncProduct>> products = {};
  final Map<String, StoredRow<SyncProductVariant>> productVariants = {};
  final Map<String, StoredRow<SyncSupplier>> suppliers = {};
  final Map<String, StoredRow<SyncCustomer>> customers = {};
  final Map<String, StoredRow<SyncSale>> sales = {};
  final Map<String, StoredRow<SyncSaleItem>> saleItems = {};
  final Map<String, StoredRow<SyncExpense>> expenses = {};
  final Map<String, StoredRow<SyncCustomerPayment>> customerPayments = {};
  final Map<String, StoredRow<SyncDeletion>> deletions = {};

  DateTime _tick() {
    clock = clock.add(const Duration(milliseconds: 1));
    return clock;
  }
}

/// Per-device gateway view over the shared store.
final class FakeRemoteMasterDataGateway implements RemoteMasterDataGateway {
  FakeRemoteMasterDataGateway(this._store, {required this.viewerShopId});

  /// When true, every push throws (offline simulation). Pulls keep working
  /// only when [pullsFail] is set as well — offline blocks both directions.
  bool pushesFail = false;
  bool pullsFail = false;

  /// Counters asserted by retry/idempotency tests.
  int pushAttempts = 0;

  final FakeRemoteStore _store;
  final String viewerShopId;

  void _rejectForeign(String shopId) {
    if (shopId != viewerShopId) {
      throw StateError('RLS: row $shopId violates viewer check $viewerShopId');
    }
  }

  void _ensureOnline() {
    if (pushesFail || pullsFail) {
      throw Exception('network unavailable');
    }
  }

  // ---- Devices -------------------------------------------------------------

  @override
  Future<void> registerDevice(DeviceRegistration registration) async {
    if (pushesFail) {
      _ensureOnline();
    }
    _rejectForeign(registration.shopId);
    _store.devices[registration.deviceId] = registration;
  }

  // ---- Categories ------------------------------------------------------------

  @override
  Future<void> upsertCategories(List<SyncCategory> rows) async {
    pushAttempts++;
    if (pushesFail) {
      _ensureOnline();
    }
    for (final row in rows) {
      _rejectForeign(row.shopId);
      // Enforce cloud unique (shop_id, name) like real Supabase.
      for (final stored in _store.categories.values) {
        if (stored.shopId == row.shopId &&
            stored.row.name == row.name &&
            stored.row.id != row.id) {
          throw Exception(
            'PostgrestException(message: duplicate key value violates unique constraint "ux_categories_shop_name", code: 23505, details: Key (shop_id, name)=(${row.shopId}, ${row.name}) already exists., hint: null)',
          );
        }
      }
      final existing = _store.categories[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.categories[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncCategory>> pullCategories({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) {
      _ensureOnline();
    }
    return _page(_store.categories, since, limit, (r) => r.row);
  }

  // ---- Products -----------------------------------------------------------------

  @override
  Future<void> upsertProducts(List<SyncProduct> rows) async {
    pushAttempts++;
    if (pushesFail) {
      _ensureOnline();
    }
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.products[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.products[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncProduct>> pullProducts({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) {
      _ensureOnline();
    }
    return _page(_store.products, since, limit, (r) => r.row);
  }

  // ---- Variants -------------------------------------------------------------------

  @override
  Future<void> upsertProductVariants(List<SyncProductVariant> rows) async {
    pushAttempts++;
    if (pushesFail) {
      _ensureOnline();
    }
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.productVariants[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.productVariants[row.id] = StoredRow(
          row,
          row.shopId,
          _store._tick(),
        );
      }
    }
  }

  @override
  Future<PullPage<SyncProductVariant>> pullProductVariants({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) {
      _ensureOnline();
    }
    return _page(_store.productVariants, since, limit, (r) => r.row);
  }

  // ---- Suppliers ---------------------------------------------------------------------

  @override
  Future<void> upsertSuppliers(List<SyncSupplier> rows) async {
    pushAttempts++;
    if (pushesFail) {
      _ensureOnline();
    }
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.suppliers[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.suppliers[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncSupplier>> pullSuppliers({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) {
      _ensureOnline();
    }
    return _page(_store.suppliers, since, limit, (r) => r.row);
  }

  // ---- Customers ------------------------------------------------------------------------

  @override
  Future<void> upsertCustomers(List<SyncCustomer> rows) async {
    pushAttempts++;
    if (pushesFail) {
      _ensureOnline();
    }
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.customers[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.customers[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncCustomer>> pullCustomers({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) {
      _ensureOnline();
    }
    return _page(_store.customers, since, limit, (r) => r.row);
  }

  // ---- Sales ---------------------------------------------------------------------------

  @override
  Future<void> upsertSales(List<SyncSale> rows) async {
    pushAttempts++;
    if (pushesFail) _ensureOnline();
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.sales[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.sales[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncSale>> pullSales({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) _ensureOnline();
    return _page(_store.sales, since, limit, (r) => r.row);
  }

  // ---- Sale Items ----------------------------------------------------------------------

  @override
  Future<void> upsertSaleItems(List<SyncSaleItem> rows) async {
    pushAttempts++;
    if (pushesFail) _ensureOnline();
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.saleItems[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.saleItems[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncSaleItem>> pullSaleItems({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) _ensureOnline();
    return _page(_store.saleItems, since, limit, (r) => r.row);
  }

  // ---- Expenses ------------------------------------------------------------------------

  @override
  Future<void> upsertExpenses(List<SyncExpense> rows) async {
    pushAttempts++;
    if (pushesFail) _ensureOnline();
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.expenses[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.expenses[row.id] = StoredRow(row, row.shopId, _store._tick());
      }
    }
  }

  @override
  Future<PullPage<SyncExpense>> pullExpenses({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) _ensureOnline();
    return _page(_store.expenses, since, limit, (r) => r.row);
  }

  // ---- Customer Payments ----------------------------------------------------------------

  @override
  Future<void> upsertCustomerPayments(List<SyncCustomerPayment> rows) async {
    pushAttempts++;
    if (pushesFail) _ensureOnline();
    for (final row in rows) {
      _rejectForeign(row.shopId);
      final existing = _store.customerPayments[row.id];
      if (existing != null) {
        existing
          ..row = row
          ..updatedAt = _store._tick();
      } else {
        _store.customerPayments[row.id] = StoredRow(
          row,
          row.shopId,
          _store._tick(),
        );
      }
    }
  }

  @override
  Future<PullPage<SyncCustomerPayment>> pullCustomerPayments({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) _ensureOnline();
    return _page(_store.customerPayments, since, limit, (r) => r.row);
  }

  // ---- Deletions ----------------------------------------------------------------------------

  @override
  Future<void> recordDeletion(SyncDeletion deletion) async {
    pushAttempts++;
    if (pushesFail) {
      _ensureOnline();
    }
    _rejectForeign(deletion.shopId);
    _store.deletions['${deletion.entity.wire}:${deletion.id}'] = StoredRow(
      deletion,
      deletion.shopId,
      _store._tick(),
    );
  }

  @override
  Future<PullPage<SyncDeletion>> pullDeletions({
    required DateTime since,
    required int limit,
  }) async {
    if (pullsFail) {
      _ensureOnline();
    }
    return _page(_store.deletions, since, limit, (r) => r.row);
  }

  // ---- Shared page assembly ------------------------------------------------------------------

  PullPage<T> _page<T>(
    Map<String, StoredRow<T>> table,
    DateTime since,
    int limit,
    T Function(StoredRow<T>) extract,
  ) {
    final visible =
        table.values
            .where((stored) => stored.shopId == viewerShopId)
            .where((stored) => stored.updatedAt.isAfter(since))
            .toList()
          ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final pageRows = visible.take(limit).toList();
    final newCursor = pageRows.isEmpty ? since : pageRows.last.updatedAt;
    return PullPage(
      rows: [for (final stored in pageRows) extract(stored)],
      newCursor: newCursor,
    );
  }
}
