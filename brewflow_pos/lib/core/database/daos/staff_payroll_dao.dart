import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll DAO
///
/// All Drift access for attendance, advances, daily salary amounts and the
/// owner-entered manual monthly salary lives here. Queries are SQL-side
/// (never in-memory). Worked minutes are persisted when a shift closes so
/// month summaries never change retroactively. Every read accepts an optional
/// shop scope so Cafe and Food Truck data stay strictly isolated.
/// ---------------------------------------------------------------------------

final class StaffPayrollDao {
  StaffPayrollDao(this._db);

  final AppDatabase _db;

  /// The single open (not yet closed) shift for [staffUserId], newest first.
  Future<StaffAttendanceData?> openShiftFor(String staffUserId) {
    final query = _db.select(_db.staffAttendance)
      ..where((t) => t.staffUserId.equals(staffUserId) & t.outAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.inAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// Attendance rows for [staffUserId] with an [attendanceDate] in
  /// [fromDate]..[toDate) (half-open range of UTC-midnight day cookies),
  /// ordered by clock-in time ascending — the month history ordering.
  /// [shopIds] restricts rows to those businesses; null reads every scope.
  Future<List<StaffAttendanceData>> shiftsFor(
    String staffUserId, {
    required DateTime fromDate,
    required DateTime toDate,
    List<String>? shopIds,
  }) {
    final query = _db.select(_db.staffAttendance)
      ..where(
        (t) =>
            t.staffUserId.equals(staffUserId) &
            t.attendanceDate.isBiggerOrEqualValue(fromDate) &
            t.attendanceDate.isSmallerThanValue(toDate),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.inAt)]);
    if (shopIds != null) {
      query.where((t) => t.shopId.isIn(shopIds));
    }
    return query.get();
  }

  Future<StaffAttendanceData> insertShift(StaffAttendanceCompanion shift) =>
      _db.into(_db.staffAttendance).insertReturning(shift);

  Future<void> closeShift(
    String shiftId,
    DateTime outAt,
    int workedMinutes,
  ) async {
    await (_db.update(
      _db.staffAttendance,
    )..where((t) => t.id.equals(shiftId))).write(
      StaffAttendanceCompanion(
        outAt: Value(outAt),
        workedMinutes: Value(workedMinutes),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Hard-deletes one shift row by its id. A real delete (never a
  /// deactivate): the shift is gone from working days and hours immediately.
  /// Returns the number of rows removed (0 when the id is already gone, so
  /// a repeated cross-device delete stays idempotent).
  Future<int> deleteShift(String shiftId) {
    return (_db.delete(
      _db.staffAttendance,
    )..where((t) => t.id.equals(shiftId))).go();
  }

  /// Hard-deletes every shift in [staffUserId]'s [fromDate]..[toDate) window
  /// for [shopId] whose id is not in [keepIds]. This is how a delete that
  /// happened on another device leaves the local mirror: the cloud stays
  /// authoritative for the window it was fetched for, and rows it no longer
  /// lists were removed there.
  ///
  /// An empty [keepIds] is treated as "the cloud confirmed nothing" and is
  /// deliberately a no-op. Wiping a whole window on an empty list would turn
  /// any silent mismatch (wrong member key, revoked membership, a gateway
  /// that returns nothing instead of throwing) into unrecoverable loss of
  /// attendance the device recorded itself.
  Future<int> pruneShiftsAbsentFromCloud({
    required String staffUserId,
    required String shopId,
    required DateTime fromDate,
    required DateTime toDate,
    required Set<String> keepIds,
  }) {
    if (keepIds.isEmpty) return Future.value(0);
    final query = _db.delete(_db.staffAttendance)
      ..where(
        (t) =>
            t.staffUserId.equals(staffUserId) &
            t.shopId.equals(shopId) &
            t.attendanceDate.isBiggerOrEqualValue(fromDate) &
            t.attendanceDate.isSmallerThanValue(toDate),
      )
      ..where((t) => t.id.isNotIn(keepIds));
    return query.go();
  }

  /// Advances for [staffUserId] dated in [fromDate]..[toDate), oldest first.
  /// [shopIds] restricts rows to those businesses; null reads every scope.
  Future<List<StaffAdvance>> advancesFor(
    String staffUserId, {
    required DateTime fromDate,
    required DateTime toDate,
    List<String>? shopIds,
  }) {
    final query = _db.select(_db.staffAdvances)
      ..where(
        (t) =>
            t.staffUserId.equals(staffUserId) &
            t.advanceDate.isBiggerOrEqualValue(fromDate) &
            t.advanceDate.isSmallerThanValue(toDate),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.advanceDate),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (shopIds != null) {
      query.where((t) => t.shopId.isIn(shopIds));
    }
    return query.get();
  }

  Future<StaffAdvance> insertAdvance(StaffAdvancesCompanion advance) =>
      _db.into(_db.staffAdvances).insertReturning(advance);

  /// Daily salary rows for [staffUserId] with an [attendanceDate] in
  /// [fromDate]..[toDate) (half-open range of UTC-midnight day cookies),
  /// ordered by day ascending — the month ordering.
  /// [shopIds] restricts rows to those businesses; null reads every scope.
  Future<List<StaffDailySalaryData>> dailySalariesFor(
    String staffUserId, {
    required DateTime fromDate,
    required DateTime toDate,
    List<String>? shopIds,
  }) {
    final query = _db.select(_db.staffDailySalary)
      ..where(
        (t) =>
            t.staffUserId.equals(staffUserId) &
            t.attendanceDate.isBiggerOrEqualValue(fromDate) &
            t.attendanceDate.isSmallerThanValue(toDate),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.attendanceDate)]);
    if (shopIds != null) {
      query.where((t) => t.shopId.isIn(shopIds));
    }
    return query.get();
  }

  /// Inserts or replaces the daily salary row for (staff, day). A null
  /// [salaryPaise] clears the row (delete) so "unset" and "zero salary" stay
  /// distinct.
  Future<void> setDailySalary({
    required String? shopId,
    required String staffUserId,
    required DateTime attendanceDate,
    required int? salaryPaise,
  }) async {
    await (_db.delete(_db.staffDailySalary)..where(
          (t) =>
              t.staffUserId.equals(staffUserId) &
              t.attendanceDate.equals(attendanceDate),
        ))
        .go();
    if (salaryPaise == null) return;
    await _db
        .into(_db.staffDailySalary)
        .insert(
          StaffDailySalaryCompanion(
            shopId: Value(shopId),
            staffUserId: Value(staffUserId),
            attendanceDate: Value(attendanceDate),
            salaryPaise: Value(salaryPaise),
          ),
        );
  }

  /// The owner-entered manual salary in paise for [staffUserId] and
  /// [monthDate] (UTC first-of-month cookie); null when unset.
  Future<int?> monthlySalaryFor(
    String staffUserId,
    DateTime monthDate, {
    List<String>? shopIds,
  }) async {
    final query = _db.select(_db.staffMonthlySalaries)
      ..where(
        (t) =>
            t.staffUserId.equals(staffUserId) & t.monthDate.equals(monthDate),
      )
      ..limit(1);
    if (shopIds != null) {
      query.where((t) => t.shopId.isIn(shopIds));
    }
    final row = await query.getSingleOrNull();
    return row?.salaryPaise;
  }

  /// Inserts or replaces the manual monthly salary row. A null [salaryPaise]
  /// clears the row (delete) so "unset" and "zero salary" stay distinct.
  Future<void> setMonthlySalary({
    required String? shopId,
    required String staffUserId,
    required DateTime monthDate,
    required int? salaryPaise,
  }) async {
    await (_db.delete(_db.staffMonthlySalaries)..where(
          (t) =>
              t.staffUserId.equals(staffUserId) &
              t.monthDate.equals(monthDate) &
              (shopId == null ? t.shopId.isNull() : t.shopId.equals(shopId)),
        ))
        .go();
    if (salaryPaise == null) return;
    await _db
        .into(_db.staffMonthlySalaries)
        .insert(
          StaffMonthlySalariesCompanion(
            shopId: Value(shopId),
            staffUserId: Value(staffUserId),
            monthDate: Value(monthDate),
            salaryPaise: Value(salaryPaise),
          ),
        );
  }
}
