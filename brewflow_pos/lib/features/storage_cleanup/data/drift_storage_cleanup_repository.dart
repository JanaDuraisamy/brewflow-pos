import 'dart:convert';

import 'package:brewflow_pos/core/database/app_database.dart'
    hide MonthCleanupMarker, MonthlyReportConfirmation, StorageMonthlySnapshot;
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Local Storage Cleanup Bookkeeping
///
/// Device-local storage for the owner notification and per-shop cleanup state.
/// Nothing here is privileged: rows hold counts, byte sizes and timestamps —
/// never Storage object bytes and never service-role credentials.
///
/// Plus the monthly ledger mirrors: cached server snapshots (derived data,
/// refreshed from the Edge Function, never synced) and report confirmations
/// (owner-authored: local insert + durable outbox UPSERT through the existing
/// engine so every owner device agrees a month is report-backed).
/// ---------------------------------------------------------------------------

class DriftStorageCleanupRepository {
  DriftStorageCleanupRepository(this._db, {this._outbox});

  final AppDatabase _db;

  /// Durable confirmation queue. Null in unit tests and legacy call sites:
  /// confirmations still commit locally and gate cleanup on this device.
  final SyncOutboxCoordinator? _outbox;

  /// Creates an unread owner notification for [shopId] unless an identical
  /// notification for the same shop+kind is still open (undismissed). Returns
  /// true when a new notification was inserted.
  Future<bool> postNotification({
    required String shopId,
    required int orphanCount,
    required int reclaimableBytes,
  }) async {
    final existing = await _activeFor(
      shopId,
      StorageCleanupNotificationKind.cleanupAvailable,
    );
    if (existing != null) return false;
    await _db
        .into(_db.storageCleanupNotification)
        .insert(
          StorageCleanupNotificationCompanion.insert(
            id: Value(Uuid().v4()),
            shopId: shopId,
            kind: StorageCleanupNotificationKind.cleanupAvailable.storageValue,
            orphanCount: Value(orphanCount),
            reclaimableBytes: Value(reclaimableBytes),
          ),
        );
    return true;
  }

  /// Latest open (undismissed) owner notification for [shopId] + [kind].
  Future<StorageCleanupNotificationRecord?> activeNotification({
    required String shopId,
    StorageCleanupNotificationKind kind =
        StorageCleanupNotificationKind.cleanupAvailable,
  }) => _activeFor(shopId, kind);

  Future<StorageCleanupNotificationRecord?> _activeFor(
    String shopId,
    StorageCleanupNotificationKind kind,
  ) async {
    final row =
        await (_db.select(_db.storageCleanupNotification)
              ..where(
                (n) =>
                    n.shopId.equals(shopId) &
                    n.kind.equals(kind.storageValue) &
                    n.dismissed.equals(false),
              )
              ..orderBy([(n) => OrderingTerm.desc(n.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : StorageCleanupNotificationRecord.fromRow(row);
  }

  /// Marks the notification as read/seen (or applies [dismissed]).
  Future<void> markNotification({
    required String id,
    bool isRead = true,
    bool dismissed = false,
  }) async {
    await (_db.update(
      _db.storageCleanupNotification,
    )..where((n) => n.id.equals(id))).write(
      StorageCleanupNotificationCompanion(
        isRead: Value(isRead),
        dismissed: Value(dismissed),
      ),
    );
  }

  /// Timestamp of the last owner-confirmed cleanup for [shopId], or null.
  Future<DateTime?> lastCleanupAt(String shopId) async {
    final row = await _stateRow(shopId);
    return row?.lastCleanupAt;
  }

  /// Records that an owner-confirmed cleanup completed for [shopId].
  Future<void> recordCleanup({
    required String shopId,
    required int usedBytes,
    required int reclaimableBytes,
  }) async {
    await _db
        .into(_db.storageCleanupState)
        .insertOnConflictUpdate(
          StorageCleanupStateCompanion.insert(
            shopId: shopId,
            lastCleanupAt: Value(DateTime.now().toUtc()),
            lastScanAt: Value(DateTime.now().toUtc()),
            lastUsedBytes: Value(usedBytes),
            lastReclaimableBytes: Value(reclaimableBytes),
          ),
        );
  }

  /// Records that a usage scan completed for [shopId] (for offline display).
  Future<void> recordScan({
    required String shopId,
    required int usedBytes,
    required int reclaimableBytes,
  }) async {
    await _db
        .into(_db.storageCleanupState)
        .insertOnConflictUpdate(
          StorageCleanupStateCompanion.insert(
            shopId: shopId,
            lastScanAt: Value(DateTime.now().toUtc()),
            lastUsedBytes: Value(usedBytes),
            lastReclaimableBytes: Value(reclaimableBytes),
          ),
        );
  }

  Future<StorageCleanupStateData?> _stateRow(String shopId) => (_db.select(
    _db.storageCleanupState,
  )..where((s) => s.shopId.equals(shopId))).getSingleOrNull();

  // ---- Monthly ledger mirrors ------------------------------------------------

  /// Caches one server-computed month snapshot for offline history. Replaces
  /// any cached row for the same (shop, month); derived data is never synced.
  Future<void> cacheSnapshot({
    required String shopId,
    required MonthlyUsageStats stats,
  }) async {
    final month = DateTime.utc(stats.month.year, stats.month.month);
    await (_db.delete(
      _db.storageMonthlySnapshots,
    )..where((t) => t.shopId.equals(shopId) & t.month.equals(month))).go();
    await _db
        .into(_db.storageMonthlySnapshots)
        .insert(
          StorageMonthlySnapshotsCompanion.insert(
            shopId: Value(shopId),
            month: month,
            countsJson: const JsonEncoder().convert(stats.counts),
            logicalBytesEst: Value(stats.logicalBytesEst),
            dbBytesTotal: Value(stats.dbBytesTotal),
            snapshotAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// Distinct months (newest first) in which this shop has any month-scoped
  /// transactional activity in the local database.
  ///
  /// The server ledger only holds months someone refreshed, so history built
  /// from snapshots alone silently skips months the shop actually traded
  /// in. Discovery scans the same tables the month cleanup scopes (sales,
  /// purchases, expenses, stock movements, closings and staff rows), so every
  /// month the owner can review or clean is offered even before its snapshot
  /// is computed — opening such a month shows "No snapshot yet" and a
  /// refresh computes it on demand.
  Future<List<DateTime>> activeMonths(String shopId) async {
    const sources = [
      'SELECT strftime(\'%Y-%m\', created_at) AS month FROM sales WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', created_at) AS month FROM purchases WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', expense_date) AS month FROM expenses WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', created_at) AS month FROM stock_movements WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', business_date) AS month FROM daily_closings WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', attendance_date) AS month FROM staff_attendance WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', advance_date) AS month FROM staff_advances WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', attendance_date) AS month FROM staff_daily_salary WHERE shop_id = ?',
      'SELECT strftime(\'%Y-%m\', month_date) AS month FROM staff_monthly_salaries WHERE shop_id = ?',
    ];
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT month FROM (${sources.join(' UNION ')}) '
          'WHERE month IS NOT NULL ORDER BY month DESC',
          variables: [for (final _ in sources) Variable.withString(shopId)],
        )
        .get();
    return [
      for (final row in rows)
        DateTime.utc(
          int.parse(row.data['month'].substring(0, 4)),
          int.parse(row.data['month'].substring(5, 7)),
        ),
    ];
  }

  /// Cached snapshots for [shopId], newest month first.
  Future<List<MonthlySnapshot>> cachedSnapshots(String shopId) async {
    final rows =
        await (_db.select(_db.storageMonthlySnapshots)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.desc(t.month)]))
            .get();
    return [
      for (final row in rows)
        MonthlySnapshot(
          month: row.month,
          counts: _decodeCounts(row.countsJson),
          logicalBytesEst: row.logicalBytesEst,
          dbBytesTotal: row.dbBytesTotal ?? 0,
          createdAt: row.snapshotAt,
        ),
    ];
  }

  /// Records the owner's "report generated/saved" confirmation for a month.
  /// Re-confirming refreshes the row (UNIQUE shop+month). With a coordinator,
  /// the UPSERT rides the durable outbox so every owner device agrees;
  /// without one the confirmation still gates cleanup on this device.
  Future<MonthlyReportConfirmation> confirmReport({
    required String shopId,
    required DateTime month,
    String? confirmedBy,
    String source = 'management-report',
  }) async {
    final cookie = DateTime.utc(month.year, month.month);
    final now = DateTime.now().toUtc();
    Future<MonthlyReportConfirmation> write() => _db.transaction(() async {
      final existing =
          await (_db.select(
                _db.monthlyReportConfirmations,
              )..where((t) => t.shopId.equals(shopId) & t.month.equals(cookie)))
              .getSingleOrNull();
      final id = existing?.id ?? const Uuid().v4();
      await (_db.delete(
        _db.monthlyReportConfirmations,
      )..where((t) => t.shopId.equals(shopId) & t.month.equals(cookie))).go();
      await _db
          .into(_db.monthlyReportConfirmations)
          .insert(
            MonthlyReportConfirmationsCompanion.insert(
              id: Value(id),
              shopId: Value(shopId),
              month: cookie,
              confirmedAt: now,
              confirmedBy: Value(confirmedBy),
              source: Value(source),
              createdAt: Value(existing?.createdAt ?? now),
              updatedAt: Value(now),
            ),
          );
      return MonthlyReportConfirmation(
        id: id,
        shopId: shopId,
        month: cookie,
        confirmedAt: now,
        confirmedBy: confirmedBy,
        source: source,
      );
    });
    final coordinator = _outbox;
    if (coordinator == null) return write();
    return coordinator.run<MonthlyReportConfirmation>(
      write: write,
      snapshots: (confirmation, context) async => [
        OutboxAppend(
          entity: MasterEntity.monthlyReportConfirmation,
          entityId: confirmation.id,
          payload: SyncMonthlyReportConfirmation(
            id: confirmation.id,
            shopId: shopId,
            month: cookie,
            confirmedAt: confirmation.confirmedAt,
            confirmedBy: confirmedBy,
            source: source,
            createdAt: confirmation.confirmedAt,
          ).toJson(),
        ),
      ],
    );
  }

  /// Local confirmation for (shop, month), or null.
  Future<MonthlyReportConfirmation?> confirmationFor(
    String shopId,
    DateTime month,
  ) async {
    final cookie = DateTime.utc(month.year, month.month);
    final row =
        await (_db.select(_db.monthlyReportConfirmations)
              ..where((t) => t.shopId.equals(shopId) & t.month.equals(cookie)))
            .getSingleOrNull();
    if (row == null) return null;
    return MonthlyReportConfirmation(
      id: row.id,
      shopId: row.shopId ?? shopId,
      month: row.month,
      confirmedAt: row.confirmedAt,
      confirmedBy: row.confirmedBy,
      source: row.source,
    );
  }

  /// Applies a completed month cleanup locally: deletes this device's month
  /// mirrors in dependency order and records the marker, atomically. Called
  /// only after the atomic server cleanup succeeded (or returns
  /// already-cleaned) — cloud first, mirror second, like every other
  /// destructive path in the codebase.
  ///
  /// Deletion is scoped to [tables] — the cleanup's actual affected keys from
  /// [MonthCleanupResult.deleted] — so categories the owner did not select are
  /// preserved locally, exactly matching the server. When [tables] is empty
  /// (an already-cleaned race, or a legacy marker with no selection recorded)
  /// there is no selection to honor, so the full month scope is cleared as
  /// before.
  Future<void> applyLocalMonthCleanup({
    required String shopId,
    required DateTime month,
    required String markerId,
    required List<String> tables,
    required Map<String, int> deletedCounts,
  }) async {
    final cookie = DateTime.utc(month.year, month.month);
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await deleteShopMonth(
        _db,
        shopId,
        cookie,
        scope: tables.isEmpty ? null : tables.toSet(),
      );
      await _db
          .into(_db.monthCleanupMarkers)
          .insertOnConflictUpdate(
            MonthCleanupMarkersCompanion.insert(
              id: Value(markerId),
              shopId: Value(shopId),
              month: cookie,
              tablesJson: Value(const JsonEncoder().convert(tables)),
              deletedCountsJson: Value(
                const JsonEncoder().convert(deletedCounts),
              ),
              completedAt: now,
              createdAt: Value(now),
              updatedAt: Value(now),
              applied: const Value(true),
            ),
          );
    });
  }

  /// Whether this device already applied the cleanup [markerId].
  Future<bool> markerApplied(String markerId) async {
    final row =
        await (_db.select(_db.monthCleanupMarkers)
              ..where((t) => t.id.equals(markerId) & t.applied.equals(true)))
            .getSingleOrNull();
    return row != null;
  }

  /// Whether a cleanup marker exists for (shop, month) — i.e. the month was
  /// already cleaned (locally applied or synced from a peer device).
  Future<bool> monthCleaned(String shopId, DateTime month) async {
    final cookie = DateTime.utc(month.year, month.month);
    final row =
        await (_db.select(_db.monthCleanupMarkers)
              ..where(
                (t) =>
                    t.shopId.equals(shopId) &
                    t.month.equals(cookie) &
                    t.applied.equals(true),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  static Map<String, int> _decodeCounts(String raw) {
    try {
      final decoded = const JsonDecoder().convert(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }
}

/// Normalizes a cleanup selection to the domain category keys used by
/// [deleteShopMonth].
///
/// Callers pass the cleanup's actual affected keys — the server
/// `month_cleanup_atomic` `deleted` keys, and the marker `tables` keys derived
/// from them — which are the EXPANDED per-table keys (`salePayments`,
/// `saleItems`, `customerPayments`, `sales`, `purchases`, ...). Both a category
/// key and its count keys map to the same category, so the owner and the peer
/// device scope their deletions identically.
const Map<String, String> _cleanupKeyToCategory = {
  'sales': 'sales',
  'saleItems': 'sales',
  'salePayments': 'sales',
  'customerPayments': 'sales',
  'purchases': 'purchases',
  'purchaseItems': 'purchases',
  'expenses': 'expenses',
  'stockMovements': 'stockMovements',
  'dailyClosings': 'dailyClosings',
  'staffAttendance': 'staffAttendance',
  'staffAdvances': 'staffAdvances',
  'staffDailySalaries': 'staffDailySalaries',
  'staffMonthlySalaries': 'staffMonthlySalaries',
};

Set<String> _categoriesInScope(Set<String> scope) => {
  for (final key in scope) _cleanupKeyToCategory[key] ?? key,
};

/// Deletes one shop's transactional rows for a UTC month, children before
/// parents (RESTRICT FKs).
///
/// Scope mirrors the server-side `month_cleanup_atomic` exactly: sales (+sale
/// payments, items, linked customer payments), purchases (+items), expenses,
/// stock movements, daily closings and staff rows. Master data (products,
/// customers, suppliers, offers, recipes), payee-keyed expense payments, the
/// sync outbox and bookkeeping are NEVER touched. Runs inside the caller's
/// transaction.
///
/// [scope] selects which categories to delete, using the cleanup's affected
/// keys (see [_cleanupKeyToCategory]). When `null` the whole month scope is
/// deleted (the original full-cleanup behavior, kept for callers and tests
/// that do not pass a selection). When provided, only the categories it maps
/// to are touched, so unselected categories (e.g. stock movements when the
/// owner cleaned only Expenses) are preserved.
Future<void> deleteShopMonth(
  AppDatabase db,
  String shopId,
  DateTime month, {
  Set<String>? scope,
}) async {
  final start = DateTime.utc(month.year, month.month);
  final end = DateTime.utc(month.year, month.month + 1);

  final selected = scope == null ? null : _categoriesInScope(scope);
  bool inScope(String category) =>
      selected == null || selected.contains(category);

  Future<List<String>> saleIds() async {
    final rows =
        await (db.select(db.sales)..where(
              (s) =>
                  s.shopId.equals(shopId) &
                  s.createdAt.isBiggerOrEqualValue(start) &
                  s.createdAt.isSmallerThanValue(end),
            ))
            .get();
    return [for (final row in rows) row.id];
  }

  Future<List<String>> purchaseIds() async {
    final rows =
        await (db.select(db.purchases)..where(
              (p) =>
                  p.shopId.equals(shopId) &
                  p.createdAt.isBiggerOrEqualValue(start) &
                  p.createdAt.isSmallerThanValue(end),
            ))
            .get();
    return [for (final row in rows) row.id];
  }

  if (inScope('sales')) {
    final sales = await saleIds();
    if (sales.isNotEmpty) {
      await (db.delete(
        db.salePayments,
      )..where((t) => t.saleId.isIn(sales))).go();
      await (db.delete(db.saleItems)..where((t) => t.saleId.isIn(sales))).go();
      await (db.delete(
        db.customerPayments,
      )..where((t) => t.saleId.isIn(sales))).go();
    }
    await (db.delete(db.sales)..where(
          (s) =>
              s.shopId.equals(shopId) &
              s.createdAt.isBiggerOrEqualValue(start) &
              s.createdAt.isSmallerThanValue(end),
        ))
        .go();
  }

  if (inScope('purchases')) {
    final purchases = await purchaseIds();
    if (purchases.isNotEmpty) {
      await (db.delete(
        db.purchaseItems,
      )..where((t) => t.purchaseId.isIn(purchases))).go();
    }
    await (db.delete(db.purchases)..where(
          (p) =>
              p.shopId.equals(shopId) &
              p.createdAt.isBiggerOrEqualValue(start) &
              p.createdAt.isSmallerThanValue(end),
        ))
        .go();
  }

  if (inScope('expenses')) {
    await (db.delete(db.expenses)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.expenseDate.isBiggerOrEqualValue(start) &
              t.expenseDate.isSmallerThanValue(end),
        ))
        .go();
  }
  if (inScope('stockMovements')) {
    await (db.delete(db.stockMovements)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.createdAt.isBiggerOrEqualValue(start) &
              t.createdAt.isSmallerThanValue(end),
        ))
        .go();
  }
  if (inScope('dailyClosings')) {
    await (db.delete(db.dailyClosings)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.businessDate.isBiggerOrEqualValue(start) &
              t.businessDate.isSmallerThanValue(end),
        ))
        .go();
  }
  if (inScope('staffAttendance')) {
    await (db.delete(db.staffAttendance)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.attendanceDate.isBiggerOrEqualValue(start) &
              t.attendanceDate.isSmallerThanValue(end),
        ))
        .go();
  }
  if (inScope('staffAdvances')) {
    await (db.delete(db.staffAdvances)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.advanceDate.isBiggerOrEqualValue(start) &
              t.advanceDate.isSmallerThanValue(end),
        ))
        .go();
  }
  if (inScope('staffDailySalaries')) {
    await (db.delete(db.staffDailySalary)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.attendanceDate.isBiggerOrEqualValue(start) &
              t.attendanceDate.isSmallerThanValue(end),
        ))
        .go();
  }
  if (inScope('staffMonthlySalaries')) {
    await (db.delete(
      db.staffMonthlySalaries,
    )..where((t) => t.shopId.equals(shopId) & t.monthDate.equals(start))).go();
  }
}
