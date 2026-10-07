import 'package:brewflow_pos/core/database/app_database.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Storage Cleanup Domain
///
/// Data shapes for owner-only storage monitoring and monthly orphan-image
/// cleanup. The client never lists Storage buckets or deletes objects directly
/// (that requires service-role privileges); everything crosses the
/// `storage-cleanup` Edge Function, which authorizes the owner server-side and
/// returns these shapes.
/// ---------------------------------------------------------------------------

/// Truthful status of the storage usage scan for one shop.
///
/// A scan that never succeeded or currently failed must never be rendered as
/// real zero values — the UI shows "Not scanned" / "Unavailable" instead.
enum StorageScanStatus {
  /// No scan has succeeded yet on this device.
  notScanned,

  /// A scan is running right now.
  scanning,

  /// The latest scan succeeded; [StorageCleanupState.report] holds its values.
  succeeded,

  /// The latest scan failed. A previous successful report may still be shown
  /// (labelled as stale), but never a fabricated zero.
  failed,
}

/// Aggregate result of a storage scan for one shop.
class StorageUsageReport {
  const StorageUsageReport({
    required this.usedBytes,
    required this.imageCount,
    required this.orphanCount,
    required this.reclaimableBytes,
    required this.orphanPaths,
    required this.lastScanAt,
    this.storageLimitBytes,
  });

  /// Total bytes used by all product-image objects for this shop.
  final int usedBytes;

  /// Total number of product-image objects for this shop.
  final int imageCount;

  /// Number of unreferenced (orphan) product-image objects.
  final int orphanCount;

  /// Sum of bytes across the orphan objects (reclaimable if deleted).
  final int reclaimableBytes;

  /// The exact Storage object paths classified as orphans.
  final List<String> orphanPaths;

  /// Configured storage limit (bytes) for the shop, or null when unlimited.
  final int? storageLimitBytes;

  /// UTC time the scan snapshot was produced server-side.
  final DateTime lastScanAt;

  /// Storage usage as a 0..1 fraction when a limit is configured, else null.
  double? get usageFraction {
    final limit = storageLimitBytes;
    if (limit == null || limit <= 0) return null;
    return (usedBytes / limit).clamp(0.0, 1.0);
  }
}

/// One individual orphan candidate offered for review before deletion.
class OrphanImage {
  const OrphanImage({required this.cloudPath, required this.sizeBytes});

  final String cloudPath;
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is OrphanImage && other.cloudPath == cloudPath;

  @override
  int get hashCode => cloudPath.hashCode;
}

/// Result of an owner-confirmed permanent deletion of orphan objects.
class CleanupDeleteResult {
  const CleanupDeleteResult({
    required this.deletedPaths,
    required this.deletedCount,
  });

  final List<String> deletedPaths;
  final int deletedCount;
}

/// Physical database metrics for one shop.
///
/// [dbBytesTotal] and per-table [tables] bytes are DATABASE-wide physical
/// figures (shared tables cannot attribute bytes to one shop). They are
/// shown labeled as such, paired with the shop's own logical counts.
class DatabaseMetrics {
  const DatabaseMetrics({
    required this.dbBytesTotal,
    required this.tables,
    this.storageLimitBytes,
    required this.measuredAt,
  });

  /// `pg_database_size(current_database())` at measure time.
  final int dbBytesTotal;

  /// Per-table physical size + total row count, DB-wide.
  final List<DatabaseTableMetrics> tables;

  /// Configured limit for the shop, or null when unlimited.
  final int? storageLimitBytes;

  final DateTime measuredAt;

  double? get usageFraction {
    final limit = storageLimitBytes;
    if (limit == null || limit <= 0) return null;
    return (dbBytesTotal / limit).clamp(0.0, 1.0);
  }
}

class DatabaseTableMetrics {
  const DatabaseTableMetrics({
    required this.table,
    required this.bytes,
    required this.rows,
  });

  final String table;
  final int bytes;
  final int rows;
}

/// One month's logical usage stats + server ledger position.
///
/// Counts are EXACT row counts in the UTC month window. [logicalBytesEst] is
/// an honest ESTIMATE (per-table average row width x month rows) — Postgres
/// cannot attribute shared-table physical bytes to a calendar month, so this
/// is always labeled logical/estimated, never exact physical usage.
class MonthlyUsageStats {
  const MonthlyUsageStats({
    required this.month,
    required this.counts,
    required this.logicalBytesEst,
    required this.dbBytesTotal,
    this.avgBytes = const {},
  });

  /// First-of-month UTC cookie.
  final DateTime month;

  /// Exact row counts by category key (sales, saleItems, purchases, ...).
  final Map<String, int> counts;

  /// Estimated logical bytes for the month (see class doc).
  final int logicalBytesEst;

  /// Physical DB size when the stats were computed (context, DB-wide).
  final int dbBytesTotal;

  /// Server-measured average physical row width per category key. Multiply by
  /// [counts] for an honest per-category logical estimate.
  final Map<String, int> avgBytes;

  int get totalRecords => counts.values.fold(0, (a, b) => a + b);

  /// Estimated logical bytes for one category (count x average row width),
  /// or null when the server reported no average for it.
  int? estimatedBytesFor(String key) {
    final avg = avgBytes[key];
    final count = counts[key];
    if (avg == null || count == null) return null;
    return avg * count;
  }
}

/// One server-ledger snapshot row (history survives per device).
class MonthlySnapshot {
  const MonthlySnapshot({
    required this.month,
    required this.counts,
    required this.logicalBytesEst,
    required this.dbBytesTotal,
    required this.createdAt,
  });

  final DateTime month;
  final Map<String, int> counts;
  final int logicalBytesEst;
  final int dbBytesTotal;
  final DateTime createdAt;
}

/// Read-only month-cleanup preview: exactly what the atomic cleanup deletes.
class MonthCleanupPreview {
  const MonthCleanupPreview({
    required this.month,
    required this.counts,
    required this.monthOrphans,
    required this.reportConfirmed,
    required this.alreadyCleaned,
    this.openBillCount = 0,
  });

  final DateTime month;

  /// Exact deletable row counts by category (same SQL the cleanup runs).
  final Map<String, int> counts;

  /// Orphan files created that month (path + size) slated with the cleanup.
  final List<OrphanImage> monthOrphans;

  /// A report confirmation exists for this month.
  final bool reportConfirmed;

  /// A cleanup marker already exists for this month.
  final bool alreadyCleaned;

  /// In-month unpaid/partially-paid customer bills. While > 0 the cleanup
  /// must not delete sales: doing so would erase customer outstanding.
  final int openBillCount;

  int get totalRecords => counts.values.fold(0, (a, b) => a + b);

  int get orphanBytes => monthOrphans.fold(0, (a, o) => a + o.sizeBytes);
}

/// Result of an owner-confirmed month cleanup: ACTUAL cloud-deleted counts.
class MonthCleanupResult {
  const MonthCleanupResult({
    required this.month,
    required this.deleted,
    required this.alreadyCleaned,
    required this.markerId,
  });

  final DateTime month;

  /// Actual affected-row counts returned by the atomic RPC.
  final Map<String, int> deleted;

  /// True when a marker already existed: nothing was deleted again.
  final bool alreadyCleaned;

  final String markerId;

  int get totalDeleted => deleted.values.fold(0, (a, b) => a + b);
}

/// One month-scoped transactional category offered as a cleanup checkbox.
///
/// Groups the raw preview-count keys into owner-friendly units and records
/// exactly which tables the selection cascades to, so the owner sees what a
/// selection deletes before anything is destroyed.
class CleanupCategory {
  const CleanupCategory({
    required this.key,
    required this.label,
    required this.description,
    required this.deletes,
    required this.count,
    required this.estimatedBytes,
  });

  /// Stable selection key sent to the server when chosen.
  final String key;

  /// Owner-friendly name, e.g. 'Bills / Sales'.
  final String label;

  /// One-line plain description of what the category holds.
  final String description;

  /// Human-readable list of the tables/records this selection deletes.
  final List<String> deletes;

  /// Exact in-month record count (same SQL the cleanup runs).
  final int count;

  /// Estimated logical bytes (count x server-measured average row width).
  final int estimatedBytes;
}

/// Static metadata for the month-cleanup checkbox categories. The controller
/// combines this with the exact preview counts and the server-measured average
/// row widths to build the selectable [CleanupCategory] list.
class CleanupCategoryMeta {
  const CleanupCategoryMeta({
    required this.key,
    required this.label,
    required this.description,
    required this.deletes,
    required this.countKeys,
  });

  /// Stable selection key sent to the server when chosen.
  final String key;

  /// Owner-friendly name, e.g. 'Bills / Sales'.
  final String label;

  /// One-line plain description of what the category holds.
  final String description;

  /// Human-readable list of the tables/records this selection deletes.
  final List<String> deletes;

  /// Preview-count keys whose rows this category aggregates.
  final List<String> countKeys;
}

/// The month-scoped transactional categories offered as cleanup checkboxes.
const List<CleanupCategoryMeta> kCleanupCategoryMeta = [
  CleanupCategoryMeta(
    key: 'sales',
    label: 'Bills / Sales',
    description: 'Counter and credit bills with their line items and payments.',
    deletes: [
      'sales',
      'sale_items',
      'sale_payments',
      'linked customer_payments',
    ],
    countKeys: ['sales', 'saleItems', 'salePayments', 'customerPayments'],
  ),
  CleanupCategoryMeta(
    key: 'purchases',
    label: 'Purchases',
    description: 'Stock receiving transactions and their line items.',
    deletes: ['purchases', 'purchase_items'],
    countKeys: ['purchases', 'purchaseItems'],
  ),
  CleanupCategoryMeta(
    key: 'expenses',
    label: 'Expenses',
    description: 'Business expenses. Payee-keyed expense payments are kept.',
    deletes: ['expenses'],
    countKeys: ['expenses'],
  ),
  CleanupCategoryMeta(
    key: 'stockMovements',
    label: 'Stock Movements',
    description: 'Stock in / adjustment / out events.',
    deletes: ['stock_movements'],
    countKeys: ['stockMovements'],
  ),
  CleanupCategoryMeta(
    key: 'staffAttendance',
    label: 'Staff Attendance',
    description: 'Clock-in/out and leave records.',
    deletes: ['staff_attendance'],
    countKeys: ['staffAttendance'],
  ),
  CleanupCategoryMeta(
    key: 'staffAdvances',
    label: 'Staff Advances',
    description: 'Salary advances given to staff.',
    deletes: ['staff_advances'],
    countKeys: ['staffAdvances'],
  ),
  CleanupCategoryMeta(
    key: 'staffDailySalaries',
    label: 'Daily Salaries',
    description: 'Daily wage accruals per attendance day.',
    deletes: ['staff_daily_salaries'],
    countKeys: ['staffDailySalaries'],
  ),
  CleanupCategoryMeta(
    key: 'staffMonthlySalaries',
    label: 'Monthly Salaries',
    description: 'Monthly salary records.',
    deletes: ['staff_monthly_salaries'],
    countKeys: ['staffMonthlySalaries'],
  ),
  CleanupCategoryMeta(
    key: 'dailyClosings',
    label: 'Daily Closings',
    description: 'End-of-day closing summaries.',
    deletes: ['daily_closings'],
    countKeys: ['dailyClosings'],
  ),
];

/// Owner-friendly reference data for one database table shown in the cloud
/// database detail view. Purely descriptive — the measured figures come from
/// the `storage_db_metrics` RPC.
class DatabaseTableInfo {
  const DatabaseTableInfo({
    required this.friendlyName,
    required this.description,
    required this.feature,
    required this.cleanupEligible,
    this.deletes,
    this.safetyNote,
    this.categoryKey,
  });

  /// Owner-friendly name, e.g. 'Sales / Bills'.
  final String friendlyName;

  /// What the table is, in one line.
  final String description;

  /// Which app feature writes/reads it.
  final String feature;

  /// Whether monthly cleanup can ever remove its records.
  final bool cleanupEligible;

  /// When cleanup-eligible: the human-readable cascade of what is deleted.
  final List<String>? deletes;

  /// Safety note where the table must never be deleted.
  final String? safetyNote;

  /// The month-cleanup category this table belongs to (null when the table is
  /// never cleaned up). Used to scope a per-table month delete.
  final String? categoryKey;
}

/// Returns the cleanup category metadata for [table], or null when the table
/// is not month-cleanup-eligible.
CleanupCategoryMeta? cleanupCategoryForTable(String table) {
  final info = kDatabaseTableInfo[table];
  if (info == null || !info.cleanupEligible) return null;
  final key = info.categoryKey;
  if (key == null) return null;
  for (final meta in kCleanupCategoryMeta) {
    if (meta.key == key) return meta;
  }
  return null;
}

/// The month-stats count key for [table] (snake_case → camelCase), matching
/// the keys the `month_size_estimate` RPC returns. Only meaningful for
/// month-scoped tables.
String tableCountKey(String table) {
  final parts = table.split('_');
  if (parts.length == 1) return table;
  return parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}')
          .join();
}

/// Static reference data for every table the metrics RPC can report.
/// Keyed by the physical table name.
const Map<String, DatabaseTableInfo> kDatabaseTableInfo = {
  'sales': DatabaseTableInfo(
    friendlyName: 'Sales / Bills',
    description: 'One row per completed bill, counter or credit.',
    feature: 'Billing, receipts, customer dues, reports',
    cleanupEligible: true,
    deletes: [
      'sales',
      'sale_items',
      'sale_payments',
      'linked customer_payments',
    ],
    categoryKey: 'sales',
  ),
  'sale_items': DatabaseTableInfo(
    friendlyName: 'Sale Items',
    description: 'The line items on each bill (product, qty, price).',
    feature: 'Billing, receipts, stock deduction',
    cleanupEligible: true,
    deletes: ['sale_items'],
    categoryKey: 'sales',
  ),
  'sale_payments': DatabaseTableInfo(
    friendlyName: 'Sale Payments',
    description: 'Counter payments captured at checkout (cash/UPI/bank).',
    feature: 'Billing, counter settlement',
    cleanupEligible: true,
    deletes: ['sale_payments'],
    categoryKey: 'sales',
  ),
  'customer_payments': DatabaseTableInfo(
    friendlyName: 'Customer Payments',
    description: 'Amounts collected against credit bills, per bill.',
    feature: 'Customer ledger, dues collection',
    cleanupEligible: true,
    deletes: ['customer_payments linked to in-month bills'],
    categoryKey: 'sales',
  ),
  'expenses': DatabaseTableInfo(
    friendlyName: 'Expenses',
    description: 'Business expenses recorded against a business date.',
    feature: 'Expenses, profit & loss reports',
    cleanupEligible: true,
    deletes: ['expenses'],
    categoryKey: 'expenses',
  ),
  'expense_payments': DatabaseTableInfo(
    friendlyName: 'Expense Payments',
    description: 'Payee-keyed payments made against expenses.',
    feature: 'Shop payables, supplier/payee settlement',
    cleanupEligible: false,
    safetyNote:
        'Payee-keyed, not month-scoped — never deleted by month cleanup.',
  ),
  'purchases': DatabaseTableInfo(
    friendlyName: 'Purchases',
    description: 'Stock receiving transactions from suppliers.',
    feature: 'Purchases, stock in, supplier accounts',
    cleanupEligible: true,
    deletes: ['purchases', 'purchase_items'],
    categoryKey: 'purchases',
  ),
  'purchase_items': DatabaseTableInfo(
    friendlyName: 'Purchase Items',
    description: 'The line items on each purchase (product, qty, cost).',
    feature: 'Purchases, stock in',
    cleanupEligible: true,
    deletes: ['purchase_items'],
    categoryKey: 'purchases',
  ),
  'stock_movements': DatabaseTableInfo(
    friendlyName: 'Stock Movements',
    description: 'Every stock in/adjustment/out event with its reason.',
    feature: 'Inventory, stock history',
    cleanupEligible: true,
    deletes: ['stock_movements'],
    categoryKey: 'stockMovements',
  ),
  'staff_attendance': DatabaseTableInfo(
    friendlyName: 'Staff Attendance',
    description: 'Clock-in/out and leave records per staff member.',
    feature: 'Staff attendance, payroll',
    cleanupEligible: true,
    deletes: ['staff_attendance'],
    categoryKey: 'staffAttendance',
  ),
  'staff_advances': DatabaseTableInfo(
    friendlyName: 'Staff Advances',
    description: 'Salary advances given to staff, per date.',
    feature: 'Staff payroll, advances',
    cleanupEligible: true,
    deletes: ['staff_advances'],
    categoryKey: 'staffAdvances',
  ),
  'staff_daily_salaries': DatabaseTableInfo(
    friendlyName: 'Daily Salaries',
    description: 'Daily wage accruals per staff attendance day.',
    feature: 'Staff payroll (daily wages)',
    cleanupEligible: true,
    deletes: ['staff_daily_salaries'],
    categoryKey: 'staffDailySalaries',
  ),
  'staff_monthly_salaries': DatabaseTableInfo(
    friendlyName: 'Monthly Salaries',
    description: 'Monthly salary records per staff member.',
    feature: 'Staff payroll (monthly salaries)',
    cleanupEligible: true,
    deletes: ['staff_monthly_salaries'],
    categoryKey: 'staffMonthlySalaries',
  ),
  'daily_closings': DatabaseTableInfo(
    friendlyName: 'Daily Closings',
    description: 'End-of-day closing summaries per business date.',
    feature: 'Daily closing, reports',
    cleanupEligible: true,
    deletes: ['daily_closings'],
    categoryKey: 'dailyClosings',
  ),
  'products': DatabaseTableInfo(
    friendlyName: 'Products',
    description: 'The product catalogue (master data).',
    feature: 'Inventory, billing, POS shelf',
    cleanupEligible: false,
    safetyNote: 'Master data — never deleted by month cleanup.',
  ),
  'product_variants': DatabaseTableInfo(
    friendlyName: 'Product Variants',
    description: 'Size/price variants of each product (master data).',
    feature: 'Inventory, billing',
    cleanupEligible: false,
    safetyNote: 'Master data — never deleted by month cleanup.',
  ),
  'customers': DatabaseTableInfo(
    friendlyName: 'Customers',
    description: 'Customer profiles and contact details (master data).',
    feature: 'Customer ledger, dues',
    cleanupEligible: false,
    safetyNote: 'Master data — never deleted by month cleanup.',
  ),
  'suppliers': DatabaseTableInfo(
    friendlyName: 'Suppliers',
    description: 'Supplier profiles (master data).',
    feature: 'Purchases, payables',
    cleanupEligible: false,
    safetyNote: 'Master data — never deleted by month cleanup.',
  ),
  'offers': DatabaseTableInfo(
    friendlyName: 'Offers',
    description: 'Discount/offer configuration (master data).',
    feature: 'Billing offers',
    cleanupEligible: false,
    safetyNote: 'Master data — never deleted by month cleanup.',
  ),
  'product_recipes': DatabaseTableInfo(
    friendlyName: 'Product Recipes',
    description: 'Ingredient recipes for products (master data).',
    feature: 'Inventory recipes',
    cleanupEligible: false,
    safetyNote: 'Master data — never deleted by month cleanup.',
  ),
  'sync_outbox': DatabaseTableInfo(
    friendlyName: 'Sync Queue',
    description: 'Durable outbound sync queue for cloud replication.',
    feature: 'Cloud sync engine',
    cleanupEligible: false,
    safetyNote:
        'Durable queue — only the sync engine drains it; never deleted.',
  ),
  'master_deletions': DatabaseTableInfo(
    friendlyName: 'Master Deletions',
    description: 'Tombstone ledger for hard-deleted master rows.',
    feature: 'Cloud sync engine',
    cleanupEligible: false,
    safetyNote: 'Bookkeeping ledger — never deleted.',
  ),
};

/// Owner-recorded "report generated/saved for this month" marker. Synced
/// across owner devices through the existing engine like any master row.
class MonthlyReportConfirmation {
  const MonthlyReportConfirmation({
    required this.id,
    required this.shopId,
    required this.month,
    required this.confirmedAt,
    this.confirmedBy,
    this.source = 'management-report',
  });

  final String id;
  final String shopId;

  /// First-of-month UTC cookie.
  final DateTime month;
  final DateTime confirmedAt;
  final String? confirmedBy;
  final String source;
}

/// Owner-notification kinds surfaced on-device.
enum StorageCleanupNotificationKind {
  /// A monthly scan found reclaimable (unreferenced) images.
  cleanupAvailable;

  String get storageValue => switch (this) {
    StorageCleanupNotificationKind.cleanupAvailable => 'CLEANUP_AVAILABLE',
  };

  static StorageCleanupNotificationKind? fromStorage(String value) =>
      switch (value) {
        'CLEANUP_AVAILABLE' => StorageCleanupNotificationKind.cleanupAvailable,
        _ => null,
      };
}

/// A local, owner-only notification record (mirrors the Drift table).
class StorageCleanupNotificationRecord {
  const StorageCleanupNotificationRecord({
    required this.id,
    required this.shopId,
    required this.kind,
    required this.orphanCount,
    required this.reclaimableBytes,
    required this.createdAt,
    this.isRead = false,
    this.dismissed = false,
  });

  final String id;
  final String shopId;
  final StorageCleanupNotificationKind kind;
  final int orphanCount;
  final int reclaimableBytes;
  final DateTime createdAt;
  final bool isRead;
  final bool dismissed;

  StorageCleanupNotificationRecord copyWith({bool? isRead, bool? dismissed}) =>
      StorageCleanupNotificationRecord(
        id: id,
        shopId: shopId,
        kind: kind,
        orphanCount: orphanCount,
        reclaimableBytes: reclaimableBytes,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        dismissed: dismissed ?? this.dismissed,
      );

  factory StorageCleanupNotificationRecord.fromRow(
    StorageCleanupNotificationData row,
  ) => StorageCleanupNotificationRecord(
    id: row.id,
    shopId: row.shopId,
    kind:
        StorageCleanupNotificationKind.fromStorage(row.kind) ??
        StorageCleanupNotificationKind.cleanupAvailable,
    orphanCount: row.orphanCount,
    reclaimableBytes: row.reclaimableBytes,
    createdAt: row.createdAt,
    isRead: row.isRead,
    dismissed: row.dismissed,
  );
}

/// Base for all storage-cleanup failures; every subtype carries a user-safe
/// message.
sealed class StorageCleanupFailure implements Exception {
  const StorageCleanupFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The signed-in profile is not an active OWNER of this shop.
final class StorageCleanupForbiddenFailure extends StorageCleanupFailure {
  const StorageCleanupForbiddenFailure()
    : super('Only an active shop owner can review or clean up storage.');
}

/// The storage-cleanup service (Edge Function) is unreachable or errored.
final class StorageCleanupServiceFailure extends StorageCleanupFailure {
  const StorageCleanupServiceFailure([
    super.message = 'Storage information is unavailable right now.',
  ]);
}

/// The signed-in session expired.
final class StorageCleanupSessionFailure extends StorageCleanupFailure {
  const StorageCleanupSessionFailure()
    : super('Your session has expired. Please sign in again and retry.');
}

/// Destructive month cleanup attempted without a report confirmation, while
/// changes are still syncing, or while offline. The month is untouched.
final class MonthCleanupBlockedFailure extends StorageCleanupFailure {
  const MonthCleanupBlockedFailure([
    super.message = 'Monthly cleanup is blocked right now.',
  ]);
}

/// The month-cleanup service call failed after the owner confirmed.
final class MonthCleanupServiceFailure extends StorageCleanupFailure {
  const MonthCleanupServiceFailure([
    super.message =
        'Monthly cleanup could not be completed. Nothing was deleted.',
  ]);
}
