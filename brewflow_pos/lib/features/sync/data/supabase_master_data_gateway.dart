import 'package:brewflow_pos/features/sync/domain/device_registration.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_gateway.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Supabase Master-Data Gateway
///
/// Maps the typed sync contract onto the cloud mirror tables created by
/// supabase/migrations/0003_master_data_sync.sql.
///
/// Trust boundary stays server-side: this gateway only speaks for the signed-in
/// session and never sends credentials or service keys; shop isolation is
/// enforced by RLS against user_profiles regardless of what a compromised
/// client claims.
///
/// Timestamp semantics: pushes carry each row's creation instant as
/// `client_created_at`; conflict ordering uses ONLY the server's
/// trigger-managed `updated_at` (arrival order), so skewed device clocks can
/// never corrupt incremental pulls.
/// ---------------------------------------------------------------------------

final class SupabaseMasterDataGateway implements RemoteMasterDataGateway {
  SupabaseMasterDataGateway(this._client);

  final SupabaseClient _client;

  // ---- Device registration ------------------------------------------------

  @override
  Future<void> registerDevice(DeviceRegistration registration) async {
    await _client.from('devices').upsert(<String, dynamic>{
      'id': registration.deviceId,
      'shop_id': registration.shopId,
      'user_id': registration.userId,
      if (registration.deviceName != null)
        'device_name': registration.deviceName,
      if (registration.platform != null) 'platform': registration.platform,
      'is_active': registration.isActive,
      if (registration.lastSeenAt != null)
        'last_seen_at': registration.lastSeenAt!.toIso8601String(),
    }, onConflict: 'id');
  }

  // ---- Categories -----------------------------------------------------------

  @override
  Future<void> upsertCategories(List<SyncCategory> rows) =>
      _upsert('categories', [for (final row in rows) _categoryToServer(row)]);

  @override
  Future<PullPage<SyncCategory>> pullCategories({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'categories',
    since: since,
    limit: limit,
    fromRow: _categoryFromServer,
  );

  Map<String, dynamic> _categoryToServer(SyncCategory row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'name': row.name,
    'is_active': row.isActive,
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncCategory _categoryFromServer(Map<String, dynamic> json) => SyncCategory(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    name: json['name'] as String,
    isActive: json['is_active'] as bool,
    createdAt: _utc(json['client_created_at']),
  );

  // ---- Products -------------------------------------------------------------

  @override
  Future<void> upsertProducts(List<SyncProduct> rows) =>
      _upsert('products', [for (final row in rows) _productToServer(row)]);

  @override
  Future<PullPage<SyncProduct>> pullProducts({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'products',
    since: since,
    limit: limit,
    fromRow: _productFromServer,
  );

  Map<String, dynamic> _productToServer(SyncProduct row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'category_id': row.categoryId,
    'name': row.name,
    'sku': row.sku,
    'selling_price_paise': row.sellingPricePaise,
    'cost_price_paise': row.costPricePaise,
    'stock_quantity': row.stockQuantity,
    'stock_unit': row.stockUnit.wire,
    'low_stock_mode': row.lowStockMode.wire,
    'low_stock_threshold': row.lowStockThreshold,
    'membership_enabled': row.membershipEnabled,
    'member_price_paise': row.memberPricePaise,
    'is_active': row.isActive,
    'client_created_at': row.createdAt.toIso8601String(),
    // image_path intentionally never pushed: device-local asset paths are
    // meaningless on other devices (see master_data_models.dart).
  };

  SyncProduct _productFromServer(Map<String, dynamic> json) => SyncProduct(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    categoryId: json['category_id'] as String,
    name: json['name'] as String,
    sku: json['sku'] as String?,
    sellingPricePaise: json['selling_price_paise'] as int,
    costPricePaise: json['cost_price_paise'] as int?,
    stockQuantity: json['stock_quantity'] as int,
    stockUnit: SyncStockUnitWire.from(json['stock_unit'] as String),
    lowStockMode: SyncLowStockModeWire.from(json['low_stock_mode'] as String),
    lowStockThreshold: json['low_stock_threshold'] as int?,
    membershipEnabled: json['membership_enabled'] as bool,
    memberPricePaise: json['member_price_paise'] as int?,
    isActive: json['is_active'] as bool,
    createdAt: _utc(json['client_created_at']),
  );

  // ---- Product variants -----------------------------------------------------

  @override
  Future<void> upsertProductVariants(List<SyncProductVariant> rows) => _upsert(
    'product_variants',
    [for (final row in rows) _variantToServer(row)],
  );

  @override
  Future<PullPage<SyncProductVariant>> pullProductVariants({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'product_variants',
    since: since,
    limit: limit,
    fromRow: _variantFromServer,
  );

  Map<String, dynamic> _variantToServer(SyncProductVariant row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'product_id': row.productId,
    'name': row.name,
    'sku': row.sku,
    'selling_price_paise': row.sellingPricePaise,
    'cost_price_paise': row.costPricePaise,
    'stock_quantity': row.stockQuantity,
    'low_stock_mode': row.lowStockMode.wire,
    'low_stock_threshold': row.lowStockThreshold,
    'membership_enabled': row.membershipEnabled,
    'member_price_paise': row.memberPricePaise,
    'is_active': row.isActive,
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncProductVariant _variantFromServer(Map<String, dynamic> json) =>
      SyncProductVariant(
        id: json['id'] as String,
        shopId: json['shop_id'] as String,
        productId: json['product_id'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String?,
        sellingPricePaise: json['selling_price_paise'] as int,
        costPricePaise: json['cost_price_paise'] as int?,
        stockQuantity: json['stock_quantity'] as int,
        lowStockMode: SyncLowStockModeWire.from(
          json['low_stock_mode'] as String,
        ),
        lowStockThreshold: json['low_stock_threshold'] as int?,
        membershipEnabled: json['membership_enabled'] as bool,
        memberPricePaise: json['member_price_paise'] as int?,
        isActive: json['is_active'] as bool,
        createdAt: _utc(json['client_created_at']),
      );

  // ---- Suppliers --------------------------------------------------------------

  @override
  Future<void> upsertSuppliers(List<SyncSupplier> rows) =>
      _upsert('suppliers', [for (final row in rows) _supplierToServer(row)]);

  @override
  Future<PullPage<SyncSupplier>> pullSuppliers({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'suppliers',
    since: since,
    limit: limit,
    fromRow: _supplierFromServer,
  );

  Map<String, dynamic> _supplierToServer(SyncSupplier row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'name': row.name,
    'phone': row.phone,
    'email': row.email,
    'address': row.address,
    'notes': row.notes,
    'is_active': row.isActive,
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncSupplier _supplierFromServer(Map<String, dynamic> json) => SyncSupplier(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    address: json['address'] as String?,
    notes: json['notes'] as String?,
    isActive: json['is_active'] as bool,
    createdAt: _utc(json['client_created_at']),
  );

  // ---- Customers ----------------------------------------------------------------

  @override
  Future<void> upsertCustomers(List<SyncCustomer> rows) =>
      _upsert('customers', [for (final row in rows) _customerToServer(row)]);

  @override
  Future<PullPage<SyncCustomer>> pullCustomers({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'customers',
    since: since,
    limit: limit,
    fromRow: _customerFromServer,
  );

  Map<String, dynamic> _customerToServer(SyncCustomer row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'name': row.name,
    'phone': row.phone,
    'email': row.email,
    'address': row.address,
    'is_active': row.isActive,
    'membership_active': row.membershipActive,
    'membership_fee_paise': row.membershipFeePaise,
    'whatsapp_status': row.whatsappStatus,
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncCustomer _customerFromServer(Map<String, dynamic> json) => SyncCustomer(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    address: json['address'] as String?,
    isActive: json['is_active'] as bool,
    membershipActive: json['membership_active'] as bool,
    membershipFeePaise: json['membership_fee_paise'] as int?,
    whatsappStatus: json['whatsapp_status'] as String,
    createdAt: _utc(json['client_created_at']),
  );

  // ---- Sales -------------------------------------------------------------------

  @override
  Future<void> upsertSales(List<SyncSale> rows) =>
      _upsert('sales', [for (final row in rows) _saleToServer(row)]);

  @override
  Future<PullPage<SyncSale>> pullSales({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'sales',
    since: since,
    limit: limit,
    fromRow: _saleFromServer,
  );

  Map<String, dynamic> _saleToServer(SyncSale row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'customer_id': row.customerId,
    'receipt_number': row.receiptNumber,
    'subtotal_paise': row.subtotalPaise,
    'total_paise': row.totalPaise,
    'payment_method': row.paymentMethod,
    'payment_status': row.paymentStatus,
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncSale _saleFromServer(Map<String, dynamic> json) => SyncSale(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    customerId: json['customer_id'] as String?,
    receiptNumber: json['receipt_number'] as String,
    subtotalPaise: json['subtotal_paise'] as int,
    totalPaise: json['total_paise'] as int,
    paymentMethod: json['payment_method'] as String?,
    paymentStatus: json['payment_status'] as String,
    createdAt: _utc(json['client_created_at']),
  );

  // ---- Sale Items ------------------------------------------------------------

  @override
  Future<void> upsertSaleItems(List<SyncSaleItem> rows) =>
      _upsert('sale_items', [for (final row in rows) _saleItemToServer(row)]);

  @override
  Future<PullPage<SyncSaleItem>> pullSaleItems({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'sale_items',
    since: since,
    limit: limit,
    fromRow: _saleItemFromServer,
  );

  Map<String, dynamic> _saleItemToServer(SyncSaleItem row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'sale_id': row.saleId,
    'product_id': row.productId,
    'variant_id': row.variantId,
    'product_name': row.productName,
    'variant_name': row.variantName,
    'sku': row.sku,
    'unit_price_paise': row.unitPricePaise,
    'quantity': row.quantity,
    'line_total_paise': row.lineTotalPaise,
    'client_created_at': DateTime.now().toUtc().toIso8601String(),
  };

  SyncSaleItem _saleItemFromServer(Map<String, dynamic> json) => SyncSaleItem(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    saleId: json['sale_id'] as String,
    productId: json['product_id'] as String,
    variantId: json['variant_id'] as String?,
    productName: json['product_name'] as String,
    variantName: json['variant_name'] as String?,
    sku: json['sku'] as String?,
    unitPricePaise: json['unit_price_paise'] as int,
    quantity: json['quantity'] as int,
    lineTotalPaise: json['line_total_paise'] as int,
  );

  // ---- Expenses ---------------------------------------------------------------

  @override
  Future<void> upsertExpenses(List<SyncExpense> rows) =>
      _upsert('expenses', [for (final row in rows) _expenseToServer(row)]);

  @override
  Future<PullPage<SyncExpense>> pullExpenses({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'expenses',
    since: since,
    limit: limit,
    fromRow: _expenseFromServer,
  );

  Map<String, dynamic> _expenseToServer(SyncExpense row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'name': row.name,
    'amount_paise': row.amountPaise,
    'category': row.category,
    'payment_method': row.paymentMethod,
    'payment_status': row.paymentStatus,
    'expense_date': row.expenseDate.toIso8601String(),
    'note': row.note,
    'is_active': row.isActive,
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncExpense _expenseFromServer(Map<String, dynamic> json) => SyncExpense(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    name: json['name'] as String,
    amountPaise: json['amount_paise'] as int,
    category: json['category'] as String,
    paymentMethod: json['payment_method'] as String,
    paymentStatus: json['payment_status'] as String,
    expenseDate: _utc(json['expense_date']),
    note: json['note'] as String?,
    isActive: json['is_active'] as bool,
    createdAt: _utc(json['client_created_at']),
  );

  // ---- Customer Payments ------------------------------------------------------

  @override
  Future<void> upsertCustomerPayments(List<SyncCustomerPayment> rows) =>
      _upsert('customer_payments', [
        for (final row in rows) _customerPaymentToServer(row),
      ]);

  @override
  Future<PullPage<SyncCustomerPayment>> pullCustomerPayments({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'customer_payments',
    since: since,
    limit: limit,
    fromRow: _customerPaymentFromServer,
  );

  Map<String, dynamic> _customerPaymentToServer(SyncCustomerPayment row) => {
    'id': row.id,
    'shop_id': row.shopId,
    'customer_id': row.customerId,
    'sale_id': row.saleId,
    'amount_paise': row.amountPaise,
    'payment_method': row.paymentMethod,
    'note': row.note,
    'paid_at': row.paidAt.toIso8601String(),
    'reversed': row.reversed,
    'reversed_at': row.reversedAt?.toIso8601String(),
    'client_created_at': row.createdAt.toIso8601String(),
  };

  SyncCustomerPayment _customerPaymentFromServer(Map<String, dynamic> json) =>
      SyncCustomerPayment(
        id: json['id'] as String,
        shopId: json['shop_id'] as String,
        customerId: json['customer_id'] as String,
        saleId: json['sale_id'] as String?,
        amountPaise: json['amount_paise'] as int,
        paymentMethod: json['payment_method'] as String,
        note: json['note'] as String?,
        paidAt: _utc(json['paid_at']),
        reversed: json['reversed'] as bool,
        reversedAt: json['reversed_at'] != null
            ? _utc(json['reversed_at'])
            : null,
        createdAt: _utc(json['client_created_at']),
      );

  // ---- Deletions -------------------------------------------------------------------

  @override
  Future<void> recordDeletion(SyncDeletion deletion) async {
    await _client.from('master_deletions').upsert(<String, dynamic>{
      'entity': deletion.entity.wire,
      'id': deletion.id,
      'shop_id': deletion.shopId,
    }, onConflict: 'entity,id');
  }

  @override
  Future<PullPage<SyncDeletion>> pullDeletions({
    required DateTime since,
    required int limit,
  }) => _pull(
    table: 'master_deletions',
    since: since,
    limit: limit,
    cursorColumn: 'deleted_at',
    fromRow: (json) => SyncDeletion(
      entity: MasterEntity.fromWire(json['entity'] as String),
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
    ),
  );

  // ---- Shared plumbing ---------------------------------------------------------------

  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows, onConflict: 'id');
  }

  Future<PullPage<T>> _pull<T>({
    required String table,
    required DateTime since,
    required int limit,
    required T Function(Map<String, dynamic>) fromRow,
    String cursorColumn = 'updated_at',
  }) async {
    final data = await _client
        .from(table)
        .select()
        .gt(cursorColumn, since.toIso8601String())
        .order(cursorColumn, ascending: true)
        .limit(limit);
    final rows = [for (final json in data) fromRow(json)];
    final newCursor = rows.isEmpty ? since : _utc(data.last[cursorColumn]);
    return PullPage(rows: rows, newCursor: newCursor);
  }

  /// Postgres timestamptz arrives as an ISO string; normalize to UTC so
  /// cursor comparisons stay exact across devices.
  static DateTime _utc(Object? value) =>
      DateTime.parse(value as String).toUtc();
}
