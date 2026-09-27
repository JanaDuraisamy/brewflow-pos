import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/daos/daily_closing_dao.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/closing/data/daily_closing_cloud_gateway.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/daily_closing_models.dart';
import '../domain/daily_closing_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Daily Closing Repository
///
/// Local Drift mirror + cloud-authoritative Supabase store. Reads pull the
/// cloud rows for the requested scope first (when a gateway is present) and
/// then serve from the mirror, so a second owner device sees the same
/// closings after login. Any cloud failure falls back to the local mirror
/// (offline-safe); the mirror alone is never treated as the source of truth
/// while online. Amount validation happens here at the repository boundary.
///
/// Writes (record + delete) are cloud-authoritative when a gateway is
/// present: the cloud commit happens first and a failure surfaces a typed
/// [DailyClosingFailure] instead of silently keeping a locally-visible
/// record that other devices never see. Rows keep their local uuid, so an
/// edit or delete of the SAME record reflects across devices. When no
/// gateway is present (signed-out/offline-first/tests) writes are local-only.
/// ---------------------------------------------------------------------------

final class DriftDailyClosingRepository implements DailyClosingRepository {
  DriftDailyClosingRepository(
    AppDatabase db, {
    DailyClosingCloudGateway? cloudGateway,
    ConnectivityService? connectivityService,
  }) : _db = db,
       _dao = DailyClosingDao(db),
       _cloud = cloudGateway,
       _connectivity = connectivityService;

  static const String tag = 'DailyClosing';

  final AppDatabase _db;
  final DailyClosingDao _dao;
  final DailyClosingCloudGateway? _cloud;
  final ConnectivityService? _connectivity;

  /// Throws [DailyClosingCloudUnavailableFailure] when the device is offline
  /// and the write must reach the cloud. No-op when no connectivity service
  /// is wired (offline-first, tests).
  Future<void> _requireOnline() async {
    final connectivity = _connectivity;
    if (connectivity == null) return;
    try {
      await OnlineGuard(connectivity).requireOnline();
    } on OfflineException {
      throw const DailyClosingCloudUnavailableFailure();
    }
  }

  @override
  Future<List<DailyClosingRecord>> closingsFor({
    DateTime? startDate,
    DateTime? endExclusiveDate,
    List<String>? shopIds,
  }) async {
    await _pullCloud(
      startDate: startDate,
      endExclusiveDate: endExclusiveDate,
      shopIds: shopIds,
    );
    final rows = await _dao.query(
      shopIds: shopIds,
      fromDate: startDate,
      toDate: endExclusiveDate,
    );
    return rows.map(_toRecord).toList(growable: false);
  }

  @override
  Future<DailyClosingRecord> recordDailyClosing({
    required DateTime businessDate,
    required int totalCashPaise,
    required int totalUpiPaise,
    required int totalSalesPaise,
    required int totalExpensePaise,
    required int cashLeftInBoxPaise,
    required int cashTakenOutPaise,
    String? shopId,
    String? takenOutBy,
    String? talliedBy,
    String? note,
  }) async {
    if (totalCashPaise < 0 ||
        totalUpiPaise < 0 ||
        totalSalesPaise < 0 ||
        totalExpensePaise < 0 ||
        cashLeftInBoxPaise < 0 ||
        cashTakenOutPaise < 0) {
      throw const DailyClosingNegativeAmountFailure();
    }
    final resolvedShopId = shopId ?? await resolveWritableShopId(_db);
    // Pre-mint id + createdAt so the cloud row and the local mirror are the
    // SAME row (upsert by id across devices and identical timestamps).
    final now = DateTime.now().toUtc();
    final record = DailyClosingRecord(
      id: const Uuid().v4(),
      businessDate: businessDate,
      totalCashPaise: totalCashPaise,
      totalUpiPaise: totalUpiPaise,
      totalSalesPaise: totalSalesPaise,
      totalExpensePaise: totalExpensePaise,
      cashLeftInBoxPaise: cashLeftInBoxPaise,
      cashTakenOutPaise: cashTakenOutPaise,
      takenOutBy: takenOutBy,
      talliedBy: talliedBy,
      note: note,
      createdAt: now,
    );
    final cloud = _cloud;
    if (cloud != null) {
      await _requireOnline();
      try {
        await cloud.upsertClosing(shopId: resolvedShopId, record: record);
      } on DailyClosingFailure {
        rethrow;
      } on Object catch (error, stackTrace) {
        AppLog.error(
          'closing cloud write failed',
          tag: tag,
          error: error,
          stackTrace: stackTrace,
        );
        throw const DailyClosingCloudWriteFailure();
      }
    }
    await _dao.insert(
      DailyClosingsCompanion(
        id: Value(record.id),
        shopId: Value(resolvedShopId),
        businessDate: Value(businessDate),
        totalCashPaise: Value(totalCashPaise),
        totalUpiPaise: Value(totalUpiPaise),
        totalSalesPaise: Value(totalSalesPaise),
        totalExpensePaise: Value(totalExpensePaise),
        cashLeftInBoxPaise: Value(cashLeftInBoxPaise),
        cashTakenOutPaise: Value(cashTakenOutPaise),
        takenOutBy: Value(record.takenOutBy),
        talliedBy: Value(record.talliedBy),
        note: Value(record.note),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return record;
  }

  @override
  Future<void> deleteDailyClosing(String id) async {
    final cloud = _cloud;
    if (cloud != null) {
      await _requireOnline();
      try {
        await cloud.deleteClosing(id: id);
      } on DailyClosingFailure {
        rethrow;
      } on Object catch (error, stackTrace) {
        AppLog.error(
          'closing cloud delete failed',
          tag: tag,
          error: error,
          stackTrace: stackTrace,
        );
        throw const DailyClosingCloudWriteFailure();
      }
    }
    await _dao.deleteById(id);
  }

  /// Pulls cloud rows for the requested scope into the local mirror.
  /// Best-effort: any failure keeps the local mirror (offline-safe).
  /// Unscoped pulls are skipped — they could mix businesses.
  Future<void> _pullCloud({
    DateTime? startDate,
    DateTime? endExclusiveDate,
    List<String>? shopIds,
  }) async {
    final cloud = _cloud;
    if (cloud == null || shopIds == null || shopIds.isEmpty) return;
    try {
      for (final shopId in shopIds) {
        final remote = await cloud.fetchClosings(
          shopId: shopId,
          startDate: startDate,
          endExclusiveDate: endExclusiveDate,
        );
        for (final record in remote) {
          await _upsertLocal(shopId, record);
        }
      }
    } on Object catch (error, stackTrace) {
      AppLog.warning(
        'closing cloud pull failed; serving local mirror',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _upsertLocal(String shopId, DailyClosingRecord record) async {
    final existing = await (_db.select(
      _db.dailyClosings,
    )..where((t) => t.id.equals(record.id))).getSingleOrNull();
    final companion = DailyClosingsCompanion(
      id: Value(record.id),
      shopId: Value(shopId),
      businessDate: Value(record.businessDate),
      totalCashPaise: Value(record.totalCashPaise),
      totalUpiPaise: Value(record.totalUpiPaise),
      totalSalesPaise: Value(record.totalSalesPaise),
      totalExpensePaise: Value(record.totalExpensePaise),
      cashLeftInBoxPaise: Value(record.cashLeftInBoxPaise),
      cashTakenOutPaise: Value(record.cashTakenOutPaise),
      takenOutBy: Value(record.takenOutBy),
      talliedBy: Value(record.talliedBy),
      note: Value(record.note),
    );
    if (existing == null) {
      await _db.into(_db.dailyClosings).insert(companion);
      return;
    }
    // Cloud wins on conflicts (authoritative).
    await (_db.update(
      _db.dailyClosings,
    )..where((t) => t.id.equals(record.id))).write(
      companion.copyWith(
        createdAt: const Value.absent(),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  static DailyClosingRecord _toRecord(DailyClosing row) => DailyClosingRecord(
    id: row.id,
    businessDate: row.businessDate,
    totalCashPaise: row.totalCashPaise,
    totalUpiPaise: row.totalUpiPaise,
    totalSalesPaise: row.totalSalesPaise,
    totalExpensePaise: row.totalExpensePaise,
    cashLeftInBoxPaise: row.cashLeftInBoxPaise,
    cashTakenOutPaise: row.cashTakenOutPaise,
    takenOutBy: row.takenOutBy,
    talliedBy: row.talliedBy,
    note: row.note,
    createdAt: row.createdAt,
  );
}
