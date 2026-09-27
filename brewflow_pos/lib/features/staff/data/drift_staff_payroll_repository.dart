import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/daos/staff_payroll_dao.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/staff/data/staff_payroll_cloud_gateway.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/staff_payroll_models.dart';
import '../domain/staff_payroll_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Staff Payroll Repository
///
/// Local Drift mirror + cloud-authoritative Supabase store. Reads pull the
/// cloud rows for the requested scope first (when a gateway is present) and
/// then serve from the mirror, so a second owner device sees the same
/// attendance, salary and advances after login. Any cloud failure falls back
/// to the local mirror (offline-safe); the mirror alone is never treated as
/// the source of truth while online.
///
/// Writes resolve the staff profile's own shop ([Users.shopId]) so Cafe and
/// Food Truck data stay strictly isolated even from the "All businesses"
/// view. Legacy rows with a null shop are backfilled to the profile's shop
/// on the next write so history is preserved under the right scope.
///
/// Monthly salary is CALCULATED as the SUM of the daily salary amounts the
/// owner enters per day, overridden by a manual monthly salary when set —
/// never derived from an hourly rate. Daily salary amounts AND attendance
/// are cloud-authoritative when a gateway is present: the cloud write
/// happens first and commits the row everywhere, then the local mirror is
/// updated with the same id — a cloud failure surfaces a typed
/// [StaffPayrollFailure] instead of silently diverging. The manual monthly
/// salary and advances keep their cloud-persistent best-effort push.
/// ---------------------------------------------------------------------------

final class DriftStaffPayrollRepository implements StaffPayrollRepository {
  DriftStaffPayrollRepository(
    AppDatabase db, {
    StaffPayrollCloudGateway? cloudGateway,
    ConnectivityService? connectivityService,
  }) : _db = db,
       _dao = StaffPayrollDao(db),
       _cloud = cloudGateway,
       _connectivity = connectivityService;

  static const String tag = 'StaffPayroll';

  final AppDatabase _db;
  final StaffPayrollDao _dao;
  final StaffPayrollCloudGateway? _cloud;
  final ConnectivityService? _connectivity;

  /// The owning shop of [staffUserId]'s profile; null for unknown profiles.
  Future<String?> _profileShopId(String staffUserId) async {
    final query = _db.select(_db.users)
      ..where((t) => t.id.equals(staffUserId))
      ..limit(1);
    return (await query.getSingleOrNull())?.shopId;
  }

  /// The cross-device identity of [staffUserId]'s profile, or null when the
  /// profile has never been linked to an auth account.
  ///
  /// This is the key every cloud payroll read and write is filtered or stamped
  /// with. The local [staffUserId] is a per-device uuid and must never reach
  /// the cloud as a lookup key: a second device mints a different one, so
  /// filtering by it returned nothing. A profile with no auth id simply has no
  /// cloud identity, and its payroll stays local-only until it is linked.
  Future<String?> _authUserIdFor(String staffUserId) async {
    final query = _db.select(_db.users)
      ..where((t) => t.id.equals(staffUserId))
      ..limit(1);
    return (await query.getSingleOrNull())?.authUserId;
  }

  /// Re-claims this device's own pre-re-key cloud rows so history recorded
  /// before the cloud was keyed on auth_user_id becomes visible everywhere.
  ///
  /// Best effort and never fatal: it is a repair, not a correctness
  /// requirement, and the predicate can only match rows this device wrote.
  Future<void> _claimLegacyCloudRows(
    String staffUserId,
    String authUserId,
    String shopId,
  ) async {
    final cloud = _cloud;
    if (cloud == null) return;
    for (final table in StaffPayrollTable.values) {
      try {
        await cloud.claimLegacyRows(
          table: table,
          shopId: shopId,
          localStaffUserId: staffUserId,
          authUserId: authUserId,
        );
      } on Object catch (error, stackTrace) {
        AppLog.warning(
          'legacy payroll row claim failed; history may stay device-local',
          tag: tag,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Backfills legacy null-shop rows for [staffUserId] to [shopId] so
  /// pre-cloud history stays visible under the right business scope.
  Future<void> _backfillNullShop(String staffUserId, String shopId) async {
    await (_db.update(_db.staffAttendance)
          ..where((t) => t.staffUserId.equals(staffUserId) & t.shopId.isNull()))
        .write(
          StaffAttendanceCompanion(
            shopId: Value(shopId),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
    await (_db.update(_db.staffAdvances)
          ..where((t) => t.staffUserId.equals(staffUserId) & t.shopId.isNull()))
        .write(
          StaffAdvancesCompanion(
            shopId: Value(shopId),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
    await (_db.update(_db.staffDailySalary)
          ..where((t) => t.staffUserId.equals(staffUserId) & t.shopId.isNull()))
        .write(
          StaffDailySalaryCompanion(
            shopId: Value(shopId),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
    await (_db.update(_db.staffMonthlySalaries)
          ..where((t) => t.staffUserId.equals(staffUserId) & t.shopId.isNull()))
        .write(
          StaffMonthlySalariesCompanion(
            shopId: Value(shopId),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> _pushToCloud({
    required String? shopId,
    required String? authUserId,
    required Future<void> Function(String shopId, String authUserId) push,
  }) async {
    final cloud = _cloud;
    if (cloud == null || shopId == null || authUserId == null) return;
    try {
      await push(shopId, authUserId);
    } on Object catch (error, stackTrace) {
      // Offline or cloud hiccup: the local mirror keeps the counter usable;
      // the next online read/write re-syncs. Never fail the owner action.
      AppLog.warning(
        'payroll cloud push failed; kept local mirror',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Throws [StaffPayrollCloudUnavailableFailure] when the device is offline
  /// and the write must reach the cloud. No-op when no connectivity service
  /// is wired (offline-first, tests).
  Future<void> _requireOnline() async {
    final connectivity = _connectivity;
    if (connectivity == null) return;
    try {
      await OnlineGuard(connectivity).requireOnline();
    } on OfflineException {
      throw const StaffPayrollCloudUnavailableFailure();
    }
  }

  /// Runs a cloud-authoritative write: the cloud commit happens first and any
  /// failure surfaces typed [StaffPayrollFailure] values instead of silently
  /// keeping a locally-visible but never-committed row. In offline-first
  /// deployments (no gateway, or a profile without a resolved shop or auth
  /// identity) there is nothing to commit and the write proceeds locally.
  Future<void> _writeCloud({
    required String? shopId,
    required String? authUserId,
    required Future<void> Function(String shopId, String authUserId) push,
  }) async {
    final cloud = _cloud;
    if (cloud == null || shopId == null || authUserId == null) return;
    await _requireOnline();
    try {
      await push(shopId, authUserId);
    } on StaffPayrollFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLog.error(
        'payroll cloud write failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const StaffPayrollCloudWriteFailure();
    }
  }

  @override
  Future<StaffAttendanceRecord?> openShiftFor(String staffUserId) async {
    // Pull a live window first. An open shift is live state, not history, and
    // a device that had never pulled would otherwise report "no open shift"
    // and let the same person clock in a second time on another device. The
    // pull is best-effort (offline keeps the local mirror).
    //
    // The window is keyed on LOCAL calendar days turned into UTC-midnight
    // cookies, exactly like clockIn's business day, plus the previous day so a
    // forgotten clock-out that is still open overnight is found.
    final shopId = await _profileShopId(staffUserId);
    if (shopId != null) {
      final local = DateTime.now().toLocal();
      final todayCookie = DateTime.utc(local.year, local.month, local.day);
      await _pullCloud(
        staffUserId: staffUserId,
        startDate: todayCookie.subtract(const Duration(days: 1)),
        endExclusiveDate: todayCookie.add(const Duration(days: 1)),
        shopIds: [shopId],
      );
    }
    final row = await _dao.openShiftFor(staffUserId);
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<void> clockIn({
    required String staffUserId,
    required DateTime inAt,
  }) async {
    final open = await _dao.openShiftFor(staffUserId);
    if (open != null) {
      throw const StaffPayrollShiftAlreadyOpenFailure();
    }
    final shopId = await _profileShopId(staffUserId);
    if (shopId != null) {
      await _backfillNullShop(staffUserId, shopId);
    }
    final local = inAt.toLocal();
    final businessDay = DateTime.utc(local.year, local.month, local.day);
    // Pre-mint the shift id so the cloud row and the local mirror are the
    // SAME row (upsert by id across devices).
    final record = StaffAttendanceRecord(
      id: const Uuid().v4(),
      staffUserId: staffUserId,
      inAt: inAt.toUtc(),
      outAt: null,
      attendanceDate: businessDay,
      workedMinutes: 0,
    );
    final authUserId = await _authUserIdFor(staffUserId);
    await _writeCloud(
      shopId: shopId,
      authUserId: authUserId,
      push: (shop, auth) => _cloud!.upsertAttendance(
        shopId: shop,
        authUserId: auth,
        record: record,
      ),
    );
    await _dao.insertShift(
      StaffAttendanceCompanion(
        id: Value(record.id),
        shopId: Value(shopId),
        staffUserId: Value(staffUserId),
        inAt: Value(record.inAt),
        attendanceDate: Value(businessDay),
        workedMinutes: const Value(0),
      ),
    );
  }

  @override
  Future<void> clockOut({
    required String staffUserId,
    required DateTime outAt,
  }) async {
    final open = await _dao.openShiftFor(staffUserId);
    if (open == null) {
      throw const StaffPayrollNoOpenShiftFailure();
    }
    if (outAt.isBefore(open.inAt)) {
      throw const StaffPayrollClockOutBeforeClockInFailure();
    }
    final minutes = outAt.difference(open.inAt).inMinutes;
    final shopId = open.shopId ?? await _profileShopId(staffUserId);
    final authUserId = await _authUserIdFor(staffUserId);
    await _writeCloud(
      shopId: shopId,
      authUserId: authUserId,
      push: (shop, auth) => _cloud!.upsertAttendance(
        shopId: shop,
        authUserId: auth,
        record: _toRecord(
          open.copyWith(outAt: Value(outAt.toUtc()), workedMinutes: minutes),
        ),
      ),
    );
    await _dao.closeShift(open.id, outAt.toUtc(), minutes);
  }

  @override
  Future<List<StaffAttendanceRecord>> attendanceFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    await _pullCloud(
      staffUserId: staffUserId,
      startDate: startDate,
      endExclusiveDate: endExclusiveDate,
      shopIds: shopIds,
    );
    final rows = await _dao.shiftsFor(
      staffUserId,
      fromDate: startDate,
      toDate: endExclusiveDate,
      shopIds: shopIds,
    );
    return rows.map(_toRecord).toList(growable: false);
  }

  @override
  Future<List<StaffAdvanceEntry>> advancesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    await _pullCloud(
      staffUserId: staffUserId,
      startDate: startDate,
      endExclusiveDate: endExclusiveDate,
      shopIds: shopIds,
    );
    final rows = await _dao.advancesFor(
      staffUserId,
      fromDate: startDate,
      toDate: endExclusiveDate,
      shopIds: shopIds,
    );
    return rows
        .map(
          (row) => StaffAdvanceEntry(
            id: row.id,
            staffUserId: row.staffUserId,
            amountPaise: row.amountPaise,
            advanceDate: row.advanceDate,
            note: row.note,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> deleteAttendance(String staffUserId, String shiftId) async {
    // Resolve the owning shop from the row itself so a legacy row without a
    // backfilled shop still deletes against the member's shop.
    final local = await (_db.select(
      _db.staffAttendance,
    )..where((t) => t.id.equals(shiftId))).getSingleOrNull();
    if (local == null) {
      // Already gone (a repeated or already-synced delete). Nothing to undo
      // in the cloud, so the local mirror is already correct.
      return;
    }
    if (local.staffUserId != staffUserId) return;
    final shopId = local.shopId ?? await _profileShopId(staffUserId);
    final authUserId = await _authUserIdFor(staffUserId);
    if (shopId != null) {
      await _backfillNullShop(staffUserId, shopId);
    }
    final cloud = _cloud;
    if (cloud != null && shopId != null && authUserId != null) {
      // Cloud first, and a refusal aborts before the local delete so the two
      // mirrors never disagree about a row that still exists upstream.
      await _writeCloud(
        shopId: shopId,
        authUserId: authUserId,
        push: (shop, auth) => _cloud!.deleteAttendance(
          shopId: shop,
          authUserId: auth,
          shiftId: shiftId,
        ),
      );
    }
    await _dao.deleteShift(shiftId);
  }

  @override
  Future<int?> salaryForMonth(String staffUserId, DateTime month) async {
    final monthCookie = DateTime.utc(month.year, month.month);
    await _pullSalary(staffUserId: staffUserId, month: monthCookie);
    return _dao.monthlySalaryFor(staffUserId, monthCookie);
  }

  @override
  Future<void> setMonthlySalary(
    String staffUserId,
    DateTime month,
    int? salaryPaise,
  ) async {
    if (salaryPaise != null && salaryPaise < 0) {
      throw const StaffPayrollNegativeSalaryFailure();
    }
    final monthCookie = DateTime.utc(month.year, month.month);
    final shopId = await _profileShopId(staffUserId);
    final authUserId = await _authUserIdFor(staffUserId);
    if (shopId != null) {
      await _backfillNullShop(staffUserId, shopId);
    }
    final cloud = _cloud;
    if (salaryPaise == null) {
      // Clearing is a real delete, and it follows the cloud-first pattern: the
      // cloud row goes FIRST so no other device can re-pull it, and only then
      // does the local mirror drop the month. A failed cloud delete leaves the
      // local mirror intact instead of showing "no salary" for a month the
      // cloud still holds.
      if (cloud != null && shopId != null && authUserId != null) {
        await _requireOnline();
        try {
          await cloud.deleteSalary(
            shopId: shopId,
            authUserId: authUserId,
            monthDate: monthCookie,
          );
        } on Object catch (error, stackTrace) {
          AppLog.error(
            'payroll salary cloud delete failed',
            tag: tag,
            error: error,
            stackTrace: stackTrace,
          );
          throw const StaffPayrollCloudWriteFailure();
        }
      }
      await _dao.setMonthlySalary(
        shopId: shopId,
        staffUserId: staffUserId,
        monthDate: monthCookie,
        salaryPaise: null,
      );
      return;
    }
    await _dao.setMonthlySalary(
      shopId: shopId,
      staffUserId: staffUserId,
      monthDate: monthCookie,
      salaryPaise: salaryPaise,
    );
    if (cloud == null || shopId == null || authUserId == null) return;
    try {
      await cloud.upsertSalary(
        authUserId: authUserId,
        salary: CloudMonthlySalary(
          id: const Uuid().v4(),
          shopId: shopId,
          staffUserId: staffUserId,
          monthDate: monthCookie,
          salaryPaise: salaryPaise,
        ),
      );
    } on Object catch (error, stackTrace) {
      AppLog.warning(
        'payroll salary cloud push failed; kept local mirror',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<StaffDailySalary>> dailySalariesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    await _pullDailySalaries(
      staffUserId: staffUserId,
      startDate: startDate,
      endExclusiveDate: endExclusiveDate,
      shopIds: shopIds,
    );
    final rows = await _dao.dailySalariesFor(
      staffUserId,
      fromDate: startDate,
      toDate: endExclusiveDate,
      shopIds: shopIds,
    );
    return rows
        .map(
          (row) => StaffDailySalary(
            id: row.id,
            staffUserId: row.staffUserId,
            attendanceDate: row.attendanceDate,
            salaryPaise: row.salaryPaise,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setDailySalary(
    String staffUserId,
    DateTime attendanceDate,
    int? salaryPaise,
  ) async {
    if (salaryPaise != null && salaryPaise < 0) {
      throw const StaffPayrollNegativeSalaryFailure();
    }
    final dayCookie = DateTime.utc(
      attendanceDate.year,
      attendanceDate.month,
      attendanceDate.day,
    );
    final shopId = await _profileShopId(staffUserId);
    final authUserId = await _authUserIdFor(staffUserId);
    if (shopId != null) {
      await _backfillNullShop(staffUserId, shopId);
    }
    final cloud = _cloud;
    if (cloud != null && shopId != null && authUserId != null) {
      await _requireOnline();
      try {
        if (salaryPaise == null) {
          // Clearing removes the day everywhere so every owner device reads
          // the day back as unset.
          await cloud.deleteDailySalary(
            shopId: shopId,
            authUserId: authUserId,
            attendanceDate: dayCookie,
          );
        } else {
          await cloud.upsertDailySalary(
            shopId: shopId,
            authUserId: authUserId,
            salary: CloudDailySalary(
              id: const Uuid().v4(),
              shopId: shopId,
              staffUserId: staffUserId,
              attendanceDate: dayCookie,
              salaryPaise: salaryPaise,
            ),
          );
        }
      } on StaffPayrollFailure {
        rethrow;
      } on Object catch (error, stackTrace) {
        AppLog.error(
          'payroll daily salary cloud write failed',
          tag: tag,
          error: error,
          stackTrace: stackTrace,
        );
        throw const StaffPayrollCloudWriteFailure();
      }
    }
    await _dao.setDailySalary(
      shopId: shopId,
      staffUserId: staffUserId,
      attendanceDate: dayCookie,
      salaryPaise: salaryPaise,
    );
  }

  @override
  Future<void> addAdvance({
    required String staffUserId,
    required int amountPaise,
    required DateTime advanceDate,
    String? note,
  }) async {
    if (amountPaise < 0) {
      throw const StaffPayrollNegativeAdvanceFailure();
    }
    final shopId = await _profileShopId(staffUserId);
    final authUserId = await _authUserIdFor(staffUserId);
    if (shopId != null) {
      await _backfillNullShop(staffUserId, shopId);
    }
    final inserted = await _dao.insertAdvance(
      StaffAdvancesCompanion(
        shopId: Value(shopId),
        staffUserId: Value(staffUserId),
        amountPaise: Value(amountPaise),
        advanceDate: Value(advanceDate),
        note: Value(note),
      ),
    );
    await _pushToCloud(
      shopId: shopId,
      authUserId: authUserId,
      push: (shop, auth) => _cloud!.insertAdvance(
        shopId: shop,
        authUserId: auth,
        entry: StaffAdvanceEntry(
          id: inserted.id,
          staffUserId: staffUserId,
          amountPaise: amountPaise,
          advanceDate: advanceDate,
          note: note,
        ),
      ),
    );
  }

  /// Pulls cloud rows for the requested scope into the local mirror and
  /// reconciles deletions: local rows inside the pulled window that the cloud
  /// no longer lists are hard-deleted, so a delete made on another device
  /// disappears here on the next read. Best-effort: any failure keeps the
  /// local mirror (offline-safe). Scoped pulls only.
  Future<void> _pullCloud({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    final cloud = _cloud;
    if (cloud == null) return;
    // Without an explicit scope there is nothing safe to pull: an unscoped
    // pull could mix businesses. Scoped callers (the payroll controllers)
    // always pass the member's shop; unscoped callers keep local behavior.
    if (shopIds == null || shopIds.isEmpty) return;
    // No auth id means the profile has no cloud identity, so the cloud cannot
    // be enumerated for it. Serve the local mirror and, critically, do NOT
    // prune: treating "no identity" as "cloud says nothing" is what would wipe
    // this device's own attendance.
    final authUserId = await _authUserIdFor(staffUserId);
    if (authUserId == null) return;
    try {
      for (final shopId in shopIds) {
        // Repair pass first: attach the auth id to this device's own
        // pre-re-key rows so the fetch below can actually see them.
        await _claimLegacyCloudRows(staffUserId, authUserId, shopId);
        final shifts = await cloud.fetchAttendance(
          shopId: shopId,
          staffUserId: staffUserId,
          authUserId: authUserId,
          startDate: startDate,
          endExclusiveDate: endExclusiveDate,
        );
        for (final shift in shifts) {
          await _upsertLocalShift(shopId, shift);
        }
        // Cloud-authoritative window: a shift the cloud no longer lists for
        // this (shop, member, month) window was deleted on another device, so
        // it is hard-deleted here too. Attendance rows commit to the cloud
        // before the local insert, so a row missing from the fetched list is a
        // genuine delete rather than an unsynced write.
        //
        // Safety: an empty `shifts` list is passed through as a no-op by the
        // DAO, so a key mismatch or a gateway that answers empty can never
        // erase a window of attendance this device recorded itself.
        await _dao.pruneShiftsAbsentFromCloud(
          staffUserId: staffUserId,
          shopId: shopId,
          fromDate: startDate,
          toDate: endExclusiveDate,
          keepIds: {for (final shift in shifts) shift.id},
        );
        final advances = await cloud.fetchAdvances(
          shopId: shopId,
          staffUserId: staffUserId,
          authUserId: authUserId,
          startDate: startDate,
          endExclusiveDate: endExclusiveDate,
        );
        for (final advance in advances) {
          await _upsertLocalAdvance(shopId, advance);
        }
      }
    } on Object catch (error, stackTrace) {
      AppLog.warning(
        'payroll cloud pull failed; serving local mirror',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _pullSalary({
    required String staffUserId,
    required DateTime month,
  }) async {
    final cloud = _cloud;
    if (cloud == null) return;
    final shopId = await _profileShopId(staffUserId);
    if (shopId == null) return;
    final authUserId = await _authUserIdFor(staffUserId);
    if (authUserId == null) return;
    try {
      await _claimLegacyCloudRows(staffUserId, authUserId, shopId);
      final remote = await cloud.fetchSalary(
        shopId: shopId,
        staffUserId: staffUserId,
        authUserId: authUserId,
        monthDate: month,
      );
      if (remote == null) return;
      await _dao.setMonthlySalary(
        shopId: shopId,
        staffUserId: staffUserId,
        monthDate: month,
        salaryPaise: remote.salaryPaise,
      );
    } on Object catch (error, stackTrace) {
      AppLog.warning(
        'payroll salary cloud pull failed; serving local mirror',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Pulls the scoped daily salary rows into the local mirror. Best-effort:
  /// any failure keeps the local mirror (offline-safe). Scoped pulls only.
  Future<void> _pullDailySalaries({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    final cloud = _cloud;
    if (cloud == null || shopIds == null || shopIds.isEmpty) return;
    final authUserId = await _authUserIdFor(staffUserId);
    if (authUserId == null) return;
    try {
      for (final shopId in shopIds) {
        await _claimLegacyCloudRows(staffUserId, authUserId, shopId);
        final remote = await cloud.fetchDailySalaries(
          shopId: shopId,
          staffUserId: staffUserId,
          authUserId: authUserId,
          startDate: startDate,
          endExclusiveDate: endExclusiveDate,
        );
        for (final salary in remote) {
          await _upsertLocalDailySalary(shopId, salary);
        }
      }
    } on Object catch (error, stackTrace) {
      AppLog.warning(
        'payroll daily salary cloud pull failed; serving local mirror',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Mirrors a pulled daily salary row. The business key is (shop, staff,
  /// day): the cloud table's UNIQUE constraint guarantees one row per day, so
  /// the local mirror replaces any stale same-day row (delete + insert) to
  /// keep the calculated monthly SUM exact — a pulled cross-device edit must
  /// never double-count a day.
  Future<void> _upsertLocalDailySalary(
    String shopId,
    CloudDailySalary salary,
  ) async {
    await (_db.delete(_db.staffDailySalary)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.staffUserId.equals(salary.staffUserId) &
              t.attendanceDate.equals(salary.attendanceDate),
        ))
        .go();
    await _db
        .into(_db.staffDailySalary)
        .insert(
          StaffDailySalaryCompanion(
            id: Value(salary.id),
            shopId: Value(shopId),
            staffUserId: Value(salary.staffUserId),
            attendanceDate: Value(salary.attendanceDate),
            salaryPaise: Value(salary.salaryPaise),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> _upsertLocalShift(
    String shopId,
    StaffAttendanceRecord shift,
  ) async {
    final existing = await (_db.select(
      _db.staffAttendance,
    )..where((t) => t.id.equals(shift.id))).getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.staffAttendance)
          .insert(
            StaffAttendanceCompanion(
              id: Value(shift.id),
              shopId: Value(shopId),
              staffUserId: Value(shift.staffUserId),
              inAt: Value(shift.inAt),
              outAt: Value(shift.outAt),
              attendanceDate: Value(shift.attendanceDate),
              workedMinutes: Value(shift.workedMinutes),
            ),
          );
      return;
    }
    // Cloud wins on conflicts (authoritative): refresh mutable columns.
    await (_db.update(
      _db.staffAttendance,
    )..where((t) => t.id.equals(shift.id))).write(
      StaffAttendanceCompanion(
        outAt: Value(shift.outAt),
        workedMinutes: Value(shift.workedMinutes),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> _upsertLocalAdvance(
    String shopId,
    StaffAdvanceEntry advance,
  ) async {
    final existing = await (_db.select(
      _db.staffAdvances,
    )..where((t) => t.id.equals(advance.id))).getSingleOrNull();
    if (existing != null) return;
    await _db
        .into(_db.staffAdvances)
        .insert(
          StaffAdvancesCompanion(
            id: Value(advance.id),
            shopId: Value(shopId),
            staffUserId: Value(advance.staffUserId),
            amountPaise: Value(advance.amountPaise),
            advanceDate: Value(advance.advanceDate),
            note: Value(advance.note),
          ),
        );
  }

  static StaffAttendanceRecord _toRecord(StaffAttendanceData row) =>
      StaffAttendanceRecord(
        id: row.id,
        staffUserId: row.staffUserId,
        inAt: row.inAt,
        outAt: row.outAt,
        attendanceDate: row.attendanceDate,
        workedMinutes: row.workedMinutes,
      );
}
