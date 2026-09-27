import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll Math Regression
///
/// Locks the pure, deterministic money rules that payroll_controller depends
/// on. The month's Calculated Salary is the SUM of the daily salary amounts
/// the owner enters per day; a Manual Monthly Salary overrides the sum when
/// set (never derived from an hourly rate). Payable = effective salary −
/// advances (may legitimately be negative). Attendance hours are
/// display-only. Money uses integers only — no doubles ever touch money.
/// These exact values are asserted so a future refactor cannot silently
/// change a rupee amount.
/// ---------------------------------------------------------------------------

void main() {
  final july = DateTime.utc(2025, 7);

  StaffAttendanceRecord shift({
    int minutes = 0,
    DateTime? inAt,
    DateTime? outAt,
    String id = 'shift-1',
    String staffUserId = 'staff-1',
    DateTime? attendanceDate,
  }) => StaffAttendanceRecord(
    id: id,
    staffUserId: staffUserId,
    inAt: inAt ?? july,
    outAt: outAt,
    attendanceDate: attendanceDate ?? july,
    workedMinutes: minutes,
  );

  StaffAdvanceEntry advance({
    int amountPaise = 10000,
    String id = 'adv-1',
    String staffUserId = 'staff-1',
  }) => StaffAdvanceEntry(
    id: id,
    staffUserId: staffUserId,
    amountPaise: amountPaise,
    advanceDate: july,
    note: null,
  );

  StaffDailySalary daily({
    int salaryPaise = 30000,
    String id = 'daily-1',
    String staffUserId = 'staff-1',
    DateTime? attendanceDate,
  }) => StaffDailySalary(
    id: id,
    staffUserId: staffUserId,
    attendanceDate: attendanceDate ?? july,
    salaryPaise: salaryPaise,
  );

  MonthlyPayrollSummary summary({
    List<StaffAttendanceRecord>? shifts,
    List<StaffAdvanceEntry>? advances,
    List<StaffDailySalary>? dailySalaries,
    int? manualSalaryPaise,
    StaffAttendanceRecord? openShift,
  }) => MonthlyPayrollSummary(
    shifts: shifts ?? const [],
    advances: advances ?? const [],
    manualSalaryPaise: manualSalaryPaise,
    openShift: openShift,
    dailySalaries: dailySalaries ?? const [],
  );

  group('workedMinutesBetween', () {
    test('a full 8h day is 480 minutes', () {
      expect(
        workedMinutesBetween(
          DateTime.utc(2025, 7, 3, 3, 30), // 09:00 IST
          DateTime.utc(2025, 7, 3, 11, 30), // 17:00 IST
        ),
        480,
      );
    });

    test('partial minutes truncate toward zero', () {
      expect(
        workedMinutesBetween(
          DateTime.utc(2025, 7, 3, 3, 30, 45),
          DateTime.utc(2025, 7, 3, 4, 31, 44),
        ),
        60,
      );
    });

    test('clock-out before clock-in throws', () {
      expect(
        () => workedMinutesBetween(
          DateTime.utc(2025, 7, 3, 4),
          DateTime.utc(2025, 7, 3, 3),
        ),
        throwsArgumentError,
      );
    });
  });

  group('formatHoursMinutes', () {
    test('exact hours show hours only', () {
      expect(formatHoursMinutes(240), '4 h');
    });

    test('hours and minutes show a compact label', () {
      expect(formatHoursMinutes(255), '4 h 15 m');
    });

    test('zero shows zero hours', () {
      expect(formatHoursMinutes(0), '0 h');
    });

    test('minutes-only totals show minutes', () {
      expect(formatHoursMinutes(45), '0 h 45 m');
    });
  });

  group('MonthlyPayrollSummary', () {
    test('totals sum every shift and advance exactly once', () {
      final s = summary(
        shifts: [
          shift(minutes: 120),
          shift(minutes: 60, id: 's2'),
          shift(minutes: 380, id: 's3'),
        ],
        advances: [
          advance(),
          advance(id: 'a2', amountPaise: 2000),
        ],
        manualSalaryPaise: 1200000, // ₹12,000 entered by the owner
      );

      expect(s.totalMinutes, 560);
      expect(s.advancePaise, 12000);
    });

    test('total hours accumulate across split shifts in a month', () {
      final s = summary(
        shifts: [
          shift(minutes: 480),
          shift(minutes: 240, id: 's2'),
        ],
        manualSalaryPaise: 1200000,
      );
      expect(s.totalMinutes, 720);
      expect(formatHoursMinutes(s.totalMinutes), '12 h');
    });

    test('working days count distinct business days, not shifts', () {
      final day1 = DateTime.utc(2025, 7, 3);
      final s = summary(
        shifts: [
          shift(minutes: 120, attendanceDate: day1),
          shift(id: 's2', minutes: 60, inAt: day1, attendanceDate: day1),
          shift(
            id: 's3',
            minutes: 300,
            inAt: DateTime.utc(2025, 7, 5, 3),
            attendanceDate: DateTime.utc(2025, 7, 5),
          ),
          shift(
            id: 's4',
            minutes: 420,
            inAt: DateTime.utc(2025, 7, 6, 3),
            attendanceDate: DateTime.utc(2025, 7, 6),
          ),
        ],
      );
      // Two shifts on 3 Jul still count as ONE working day.
      expect(s.totalWorkingDays, 3);
    });

    test('working days are empty until the first shift', () {
      expect(summary().totalWorkingDays, 0);
    });

    test('payable is null while salary is unset; UI must prompt the owner', () {
      expect(summary(shifts: [shift(minutes: 560)]).payablePaise, isNull);
    });

    test('payable = manual salary − advances (never silently clamped)', () {
      final s = summary(
        shifts: [shift(minutes: 300)],
        advances: [
          advance(amountPaise: 200000), // ₹2,000 advance on ₹12,000 salary
        ],
        manualSalaryPaise: 1200000,
      );
      expect(s.payablePaise, 1000000);
    });

    test('payable is legitimately negative when advances exceed salary', () {
      final s = summary(
        shifts: [shift(minutes: 300)],
        advances: [advance(amountPaise: 1300000)],
        manualSalaryPaise: 1200000,
      );
      expect(s.payablePaise, -100000);
    });

    test('open shift is surfaced but never counts toward its minutes', () {
      final s = summary(
        shifts: [shift(minutes: 60)],
        openShift: shift(
          id: 'open-1',
          minutes: 999, // workedMinutes is fixed only at close
          outAt: null,
        ),
        manualSalaryPaise: 1200000,
      );
      expect(s.openShift?.isOpen, isTrue);
      expect(s.totalMinutes, 60); // open shift contributes 0
    });
  });

  group('daily salaries drive the calculated monthly salary', () {
    test('calculated salary is the SUM of every daily entry', () {
      final s = summary(
        dailySalaries: [
          daily(
            id: 'd1',
            salaryPaise: 30000,
            attendanceDate: DateTime.utc(2025, 7, 1),
          ),
          daily(
            id: 'd2',
            salaryPaise: 30000,
            attendanceDate: DateTime.utc(2025, 7, 2),
          ),
          daily(
            id: 'd3',
            salaryPaise: 45000,
            attendanceDate: DateTime.utc(2025, 7, 3),
          ),
        ],
      );
      expect(s.calculatedSalaryPaise, 105000);
      expect(s.effectiveSalaryPaise, 105000);
    });

    test('day-level rows mean split shifts never double-count salary', () {
      // Daily salaries are keyed by business day, so two shifts on the same
      // day still map to ONE daily salary row in the month data.
      final s = summary(
        shifts: [
          shift(minutes: 240, attendanceDate: DateTime.utc(2025, 7, 3)),
          shift(
            id: 's2',
            minutes: 240,
            attendanceDate: DateTime.utc(2025, 7, 3),
          ),
        ],
        dailySalaries: [daily(attendanceDate: DateTime.utc(2025, 7, 3))],
      );
      expect(s.totalWorkingDays, 1);
      expect(s.calculatedSalaryPaise, 30000);
      expect(s.effectiveSalaryPaise, 30000);
    });

    test('manual monthly salary overrides the calculated sum', () {
      final s = summary(
        dailySalaries: [daily(salaryPaise: 300000)],
        manualSalaryPaise: 1200000,
      );
      expect(s.calculatedSalaryPaise, 300000);
      expect(s.effectiveSalaryPaise, 1200000);
    });

    test('updating a daily entry updates the calculated salary', () {
      var s = summary(
        dailySalaries: [
          daily(id: 'd1', salaryPaise: 30000),
          daily(id: 'd2', salaryPaise: 40000),
        ],
      );
      expect(s.calculatedSalaryPaise, 70000);
      // The day was corrected; the month recalculates from the new amount.
      s = summary(
        dailySalaries: [
          daily(id: 'd1', salaryPaise: 35000),
          daily(id: 'd2', salaryPaise: 40000),
        ],
      );
      expect(s.calculatedSalaryPaise, 75000);
      expect(s.effectiveSalaryPaise, 75000);
    });

    test('payable = calculated salary − advances', () {
      final s = summary(
        advances: [advance(amountPaise: 40000)],
        dailySalaries: [
          daily(id: 'd1', salaryPaise: 50000),
          daily(id: 'd2', salaryPaise: 50000),
        ],
      );
      expect(s.calculatedSalaryPaise, 100000);
      expect(s.effectiveSalaryPaise, 100000);
      expect(s.payablePaise, 60000);
    });

    test('payable uses the manual override when one is set', () {
      final s = summary(
        advances: [advance(amountPaise: 200000)], // ₹2,000 advance
        dailySalaries: [daily(salaryPaise: 30000)],
        manualSalaryPaise: 1200000, // ₹12,000 override
      );
      expect(s.payablePaise, 1000000);
    });

    test('payable stays null while neither daily nor manual salary exists', () {
      final s = summary(shifts: [shift(minutes: 560)]);
      expect(s.effectiveSalaryPaise, isNull);
      expect(s.payablePaise, isNull);
    });
  });
}
