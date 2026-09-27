import 'staff_payroll_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll Repository
///
/// Persistence for attendance, advances, daily salary amounts and the
/// owner-entered MANUAL monthly salary. The monthly salary is CALCULATED as
/// the SUM of the daily salary amounts the owner enters per day; the owner
/// can always override the month with a manual monthly salary that wins.
/// Salary is never derived from an hourly rate and final payable is
/// effective salary − advances.
///
/// Dates cross the boundary as UTC-midnight business-day cookies
/// ([DateTime.utc(year, month, day)]), months as UTC first-of-month cookies,
/// so ranges are simple half-open comparisons regardless of device timezone.
/// [shopIds] scopes reads to businesses (Cafe/Food Truck isolation); writes
/// resolve the owning shop internally. Implementations must reject invalid
/// amounts with the typed [StaffPayrollFailure] values.
///
/// Cloud is authoritative: implementations backed by Supabase read
/// cloud-first when online (mirroring into the local cache) and fall back to
/// the local cache offline. The local cache alone is never the source of
/// truth for these owner records.
/// ---------------------------------------------------------------------------

abstract interface class StaffPayrollRepository {
  /// The single open shift for [staffUserId]; null when none is in progress.
  Future<StaffAttendanceRecord?> openShiftFor(String staffUserId);

  /// Opens a new shift at [inAt] (UTC instant) for [staffUserId]. The shift's
  /// business day is derived from [inAt]'s local calendar day. Throws
  /// [StaffPayrollShiftAlreadyOpenFailure] when a shift is already open.
  Future<void> clockIn({required String staffUserId, required DateTime inAt});

  /// Closes the open shift at [outAt] (UTC instant) and fixes its worked
  /// minutes. Throws [StaffPayrollNoOpenShiftFailure] /
  /// [StaffPayrollClockOutBeforeClockInFailure].
  Future<void> clockOut({required String staffUserId, required DateTime outAt});

  /// Attendance rows dated in [startDate]..[endExclusiveDate), oldest first.
  /// [shopIds] restricts the read to those businesses; null reads the
  /// resolved scope.
  Future<List<StaffAttendanceRecord>> attendanceFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  });

  /// Owner-only removal of one attendance shift, by its row id. This is a real
  /// hard delete, never a deactivate: the shift stops counting toward the
  /// month's working days, hours, salary and final payable.
  ///
  /// Cloud-first, matching [setDailySalary]'s clear path: the cloud row is
  /// dropped before the local mirror, and a cloud refusal leaves the local row
  /// untouched (typed [StaffPayrollFailure] surfaces) so both mirrors keep
  /// agreeing. Because attendance reads are cloud-authoritative, dropping the
  /// cloud row is also what removes the shift on every other device.
  Future<void> deleteAttendance(String staffUserId, String shiftId);

  /// Advances dated in [startDate]..[endExclusiveDate), oldest first.
  Future<List<StaffAdvanceEntry>> advancesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  });

  /// The owner-entered manual salary in paise for [staffUserId] and [month]
  /// (UTC first-of-month cookie); null when the owner has not set one yet.
  Future<int?> salaryForMonth(String staffUserId, DateTime month);

  /// Sets (or with a null argument clears) the manual monthly salary in
  /// paise. Throws [StaffPayrollNegativeSalaryFailure] for negative values.
  Future<void> setMonthlySalary(
    String staffUserId,
    DateTime month,
    int? salaryPaise,
  );

  /// Daily salary rows dated in [startDate]..[endExclusiveDate), day
  /// ascending.
  Future<List<StaffDailySalary>> dailySalariesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  });

  /// Sets (or with a null argument clears) the daily salary amount in paise
  /// for [attendanceDate] (UTC-midnight business-day cookie). Device-local:
  /// daily amounts feed the calculated monthly sum on this device, while the
  /// manual monthly salary remains the cloud-synced cross-device value.
  /// Throws [StaffPayrollNegativeSalaryFailure] for negative values.
  Future<void> setDailySalary(
    String staffUserId,
    DateTime attendanceDate,
    int? salaryPaise,
  );

  /// Records an advance. Throws [StaffPayrollNegativeAdvanceFailure] for
  /// negative amounts.
  Future<void> addAdvance({
    required String staffUserId,
    required int amountPaise,
    required DateTime advanceDate,
    String? note,
  });
}
