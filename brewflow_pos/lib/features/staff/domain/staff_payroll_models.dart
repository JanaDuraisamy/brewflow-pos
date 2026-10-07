/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll Models
///
/// Values used by the "Staff Attendance" month view. All money is integer
/// paise. The owner enters a Daily Salary Amount per day's attendance; the
/// month's Calculated Salary is the SUM of those daily amounts. The owner can
/// also set a Manual Monthly Salary that overrides the calculated sum.
/// Attendance working hours are still calculated and displayed, but final
/// payable is always effective salary − advances. Never derived from an
/// hourly rate.
///
/// Hours math is pure and deterministic; money uses integers only.
/// ---------------------------------------------------------------------------
library;

/// Compact "4h 15m" style label for a minute total.
String formatHoursMinutes(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0 ? '$hours h' : '$hours h $minutes m';
}

/// Worked minutes between clock-in [inAt] and clock-out [outAt] (UTC
/// instants), truncating partial minutes. Throws [ArgumentError] when
/// [outAt] is before [inAt].
int workedMinutesBetween(DateTime inAt, DateTime outAt) {
  if (outAt.isBefore(inAt)) {
    throw ArgumentError('Clock-out cannot be before clock-in.');
  }
  return outAt.difference(inAt).inMinutes;
}

/// A single attendance shift. Open while [outAt] is null; [workedMinutes] is
/// fixed the moment the shift closes so summaries never shift retroactively.
///
/// A Leave day is the same row shape with [isLeave] true: an explicit
/// day-level state, never a worked shift. It carries the business-day cookie
/// in [inAt]/[outAt] with 0 minutes (so the open-shift notion, `outAt == null`,
/// never mistakes it for an open shift) and an optional [leaveReason].
/// [isLeave] is the source of truth — never the timestamps.
final class StaffAttendanceRecord {
  const StaffAttendanceRecord({
    required this.id,
    required this.staffUserId,
    required this.inAt,
    required this.outAt,
    required this.attendanceDate,
    required this.workedMinutes,
    this.isLeave = false,
    this.leaveReason,
  });

  final String id;
  final String staffUserId;

  /// UTC instant of clock-in.
  final DateTime inAt;

  /// UTC instant of clock-out; null while the shift is open.
  final DateTime? outAt;

  /// Local business-day cookie (UTC midnight) this shift belongs to.
  final DateTime attendanceDate;

  /// Worked minutes fixed at clock-out; 0 while open.
  final int workedMinutes;

  /// Day-level Leave marker. Leave never counts as working time.
  final bool isLeave;

  /// Optional owner note recorded with a Leave day; null when absent.
  final String? leaveReason;

  bool get isOpen => outAt == null;
}

/// Owner-entered salary amount for ONE business day's attendance. Day-level
/// (not per shift), so split shifts on the same day still carry one salary;
/// the month's calculated salary is the SUM of these daily amounts. The
/// owner may always override the month with a manual monthly salary instead.
final class StaffDailySalary {
  const StaffDailySalary({
    required this.id,
    required this.staffUserId,
    required this.attendanceDate,
    required this.salaryPaise,
  });

  final String id;
  final String staffUserId;

  /// Local business-day cookie (UTC midnight) this salary covers.
  final DateTime attendanceDate;

  /// Owner-entered salary amount in integer paise (>= 0).
  final int salaryPaise;
}

/// An advance drawn against a staff member's salary.
final class StaffAdvanceEntry {
  const StaffAdvanceEntry({
    required this.id,
    required this.staffUserId,
    required this.amountPaise,
    required this.advanceDate,
    required this.note,
  });

  final String id;
  final String staffUserId;
  final int amountPaise;

  /// Local business-day cookie (UTC midnight) the advance was paid on.
  final DateTime advanceDate;

  final String? note;
}

/// Everything the payroll month view needs in one immutable value: the
/// month's shifts and advances, the owner-entered daily salary amounts and
/// the owner-entered manual monthly salary. When no salary is effective
/// [payablePaise] stays null so the UI can prompt the owner. Payable may
/// legitimately be negative when advances exceed salary.
final class MonthlyPayrollSummary {
  const MonthlyPayrollSummary({
    required this.shifts,
    required this.advances,
    required this.manualSalaryPaise,
    required this.openShift,
    this.dailySalaries = const [],
  });

  final List<StaffAttendanceRecord> shifts;
  final List<StaffAdvanceEntry> advances;

  /// Owner-entered manual salary in paise for the month; null while unset.
  /// When set it overrides the calculated daily sum.
  final int? manualSalaryPaise;

  /// Currently open shift for the month (null when none is in progress).
  final StaffAttendanceRecord? openShift;

  /// Daily salary amounts recorded for the month (one per business day).
  final List<StaffDailySalary> dailySalaries;

  /// Worked minutes across WORKED shifts only. Leave rows carry 0 by
  /// construction and are excluded explicitly, so Leave can never accrue
  /// working time even if a row is ever written inconsistently.
  int get totalMinutes => shifts
      .where((shift) => !shift.isLeave)
      .fold(0, (sum, shift) => sum + shift.workedMinutes);

  /// Number of distinct business days with a recorded WORKED shift this
  /// month. Leave days never count as working days; multiple shifts on the
  /// same day still count as one working day.
  int get totalWorkingDays => shifts
      .where((shift) => !shift.isLeave)
      .map((shift) => shift.attendanceDate)
      .toSet()
      .length;

  /// Number of distinct business days marked Leave this month.
  int get totalLeaveDays => shifts
      .where((shift) => shift.isLeave)
      .map((shift) => shift.attendanceDate)
      .toSet()
      .length;

  int get advancePaise =>
      advances.fold(0, (sum, advance) => sum + advance.amountPaise);

  /// Calculated salary = SUM of the month's daily salary amounts. Zero until
  /// any daily salary is recorded; never reads the legacy hourly rate.
  int get calculatedSalaryPaise =>
      dailySalaries.fold(0, (sum, day) => sum + day.salaryPaise);

  /// Effective monthly salary: the owner's manual override wins when set,
  /// otherwise the calculated daily sum once any daily salary exists. Null
  /// while neither is set so [payablePaise] stays unset and the UI can
  /// prompt the owner.
  int? get effectiveSalaryPaise {
    final manual = manualSalaryPaise;
    if (manual != null) return manual;
    return dailySalaries.isEmpty ? null : calculatedSalaryPaise;
  }

  /// Final payable = effective salary minus advances. Null when no salary is
  /// entered; may legitimately be negative when advances exceed salary.
  int? get payablePaise {
    final salary = effectiveSalaryPaise;
    return salary == null ? null : salary - advancePaise;
  }
}

/// Recoverable, user-safe payroll failures.
sealed class StaffPayrollFailure implements Exception {
  const StaffPayrollFailure();

  String get message;
}

/// Clocking in while another shift is still open.
final class StaffPayrollShiftAlreadyOpenFailure extends StaffPayrollFailure {
  const StaffPayrollShiftAlreadyOpenFailure();

  @override
  String get message =>
      'This staff member already has an open shift. Close it first.';
}

/// Clocking out with no open shift.
final class StaffPayrollNoOpenShiftFailure extends StaffPayrollFailure {
  const StaffPayrollNoOpenShiftFailure();

  @override
  String get message => 'There is no open shift to close.';
}

/// Marking Leave on a day that already has a worked (checked-in) shift.
/// Leave is a day-level state for days with no worked attendance; the worked
/// shift stays untouched.
final class StaffPayrollLeaveConflictFailure extends StaffPayrollFailure {
  const StaffPayrollLeaveConflictFailure();

  @override
  String get message =>
      'This day already has worked attendance and cannot be marked Leave.';
}

/// Clocking in on a day already marked Leave. Clear the Leave day first.
final class StaffPayrollAlreadyOnLeaveFailure extends StaffPayrollFailure {
  const StaffPayrollAlreadyOnLeaveFailure();

  @override
  String get message => 'This day is marked Leave. Clear Leave to clock in.';
}

/// Clock-out time earlier than the shift's clock-in time.
final class StaffPayrollClockOutBeforeClockInFailure
    extends StaffPayrollFailure {
  const StaffPayrollClockOutBeforeClockInFailure();

  @override
  String get message => 'Clock-out cannot be before clock-in.';
}

/// Negative advance amounts are not permitted.
final class StaffPayrollNegativeAdvanceFailure extends StaffPayrollFailure {
  const StaffPayrollNegativeAdvanceFailure();

  @override
  String get message => 'Advance amount cannot be negative.';
}

/// Negative salary amounts are not permitted.
final class StaffPayrollNegativeSalaryFailure extends StaffPayrollFailure {
  const StaffPayrollNegativeSalaryFailure();

  @override
  String get message => 'Salary amount cannot be negative.';
}

/// A cloud-backed write requires internet but the device is offline. The
/// record would not be committed everywhere, so the mutation is rejected
/// rather than silently kept device-local.
final class StaffPayrollCloudUnavailableFailure extends StaffPayrollFailure {
  const StaffPayrollCloudUnavailableFailure();

  @override
  String get message =>
      'Internet connection required. Please check your connection and try again.';
}

/// A cloud-backed write failed for a non-offline reason.
final class StaffPayrollCloudWriteFailure extends StaffPayrollFailure {
  const StaffPayrollCloudWriteFailure();

  @override
  String get message => 'Could not sync with the cloud. Please try again.';
}
