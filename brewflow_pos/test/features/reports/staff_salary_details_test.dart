import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_repository.dart';
import 'package:brewflow_pos/features/reports/data/management_report_pdf.dart';
import 'package:brewflow_pos/features/reports/domain/management_report_models.dart';
import 'package:brewflow_pos/features/reports/presentation/management_report_loader.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

/// Focused salary-PDF tests: attendance-derived days, salary sums and the
/// Final Payable = Total Salary − Advance rule. No database, no Supabase.
void main() {
  late FakeOrdersRepository orders;
  late FakeExpensesRepository expenses;
  late FakeStaffRepository staff;
  late _FakePayroll payroll;
  late _FakeClosings closings;
  late FakeSettingsRepository settings;
  late FakeCustomerLedgerRepository ledger;

  ManagementReportLoader makeLoader() => ManagementReportLoader(
    orders: orders,
    expenses: expenses,
    staff: staff,
    payroll: payroll,
    closings: closings,
    settings: settings,
    ledger: ledger,
    readShopIds: () async => const ['shop-1'],
    businessLabel: 'Cafe',
  );

  setUp(() {
    orders = FakeOrdersRepository();
    expenses = FakeExpensesRepository();
    staff = FakeStaffRepository();
    payroll = _FakePayroll();
    closings = _FakeClosings();
    settings = FakeSettingsRepository();
    ledger = FakeCustomerLedgerRepository();
    settings.stored = const ShopSettings(shopName: 'My Cafe');
  });

  test(
    'present/leave days derive from attendance; payable = salary-advance',
    () async {
      final ravi = await staff.createStaffProfile(
        identity: const AuthUser(id: 'ravi-auth', email: 'ravi@cafe.in'),
        shopId: 'shop-1',
        displayName: 'Ravi',
      );
      // Two worked shifts on the same day + one on another day = 2 present
      // days; one Leave row = 1 leave day. Leave never accrues minutes.
      payroll.seedAttendance(
        ravi.id,
        shifts: [
          (DateTime.utc(2026, 2, 3), 60, false),
          (DateTime.utc(2026, 2, 3), 120, false),
          (DateTime.utc(2026, 2, 10), 180, false),
        ],
      );
      payroll.seedLeave(ravi.id, days: [DateTime.utc(2026, 2, 12)]);
      payroll.seedDailySalary(
        ravi.id,
        days: [
          (DateTime.utc(2026, 2, 3), 40000),
          (DateTime.utc(2026, 2, 10), 40000),
        ],
      );
      payroll.seedAdvance(
        ravi.id,
        advances: [(DateTime.utc(2026, 2, 5), 20000)],
      );

      final data = await makeLoader().load(
        fromLocal: DateTime(2026, 2, 1),
        toLocal: DateTime(2026, 2, 28),
      );

      expect(data.staffRows, hasLength(1));
      final row = data.staffRows.single;
      expect(row.name, 'Ravi');
      expect(row.totalMinutes, 360);
      expect(row.presentDays, 2);
      expect(row.leaveDays, 1);
      expect(row.salaryPaise, 80000);
      expect(row.advancePaise, 20000);
      expect(row.payablePaise, 60000);
    },
  );

  test(
    'leave-only member still appears with zero salary math intact',
    () async {
      final meena = await staff.createStaffProfile(
        identity: const AuthUser(id: 'meena-auth', email: 'meena@cafe.in'),
        shopId: 'shop-1',
        displayName: 'Meena',
      );
      payroll.seedLeave(meena.id, days: [DateTime.utc(2026, 2, 8)]);

      final data = await makeLoader().load(
        fromLocal: DateTime(2026, 2, 1),
        toLocal: DateTime(2026, 2, 28),
      );

      expect(data.staffRows, hasLength(1));
      final row = data.staffRows.single;
      expect(row.presentDays, 0);
      expect(row.leaveDays, 1);
      expect(row.totalMinutes, 0);
      expect(row.salaryPaise, 0);
      expect(row.advancePaise, 0);
      expect(row.payablePaise, 0);
    },
  );

  test('payable is negative when advances exceed salary', () async {
    const row = ManagementStaffRow(
      name: 'Ravi',
      totalMinutes: 480,
      presentDays: 2,
      leaveDays: 0,
      salaryPaise: 50000,
      advancePaise: 80000,
    );
    expect(row.payablePaise, -30000);
  });

  test('staff PDF builds with the new salary columns', () async {
    final ravi = await staff.createStaffProfile(
      identity: const AuthUser(id: 'ravi-auth', email: 'ravi@cafe.in'),
      shopId: 'shop-1',
      displayName: 'Ravi',
    );
    payroll.seedAttendance(
      ravi.id,
      shifts: [(DateTime.utc(2026, 2, 3), 480, false)],
    );
    payroll.seedDailySalary(ravi.id, days: [(DateTime.utc(2026, 2, 3), 50000)]);
    payroll.seedAdvance(ravi.id, advances: [(DateTime.utc(2026, 2, 4), 10000)]);

    final data = await makeLoader().load(
      fromLocal: DateTime(2026, 2, 1),
      toLocal: DateTime(2026, 2, 28),
    );
    final bytes = await buildManagementReportPdf(data);

    expect(bytes, isNotEmpty);
    expect(data.staffRows.single.presentDays, 1);
    expect(data.staffRows.single.payablePaise, 40000);
  });

  test('empty range yields empty staff rows safely', () async {
    final data = await makeLoader().load(
      fromLocal: DateTime(2026, 2, 1),
      toLocal: DateTime(2026, 2, 28),
    );
    expect(data.staffRows, isEmpty);
    final bytes = await buildManagementReportPdf(data);
    expect(bytes, isNotEmpty);
  });
}

final class _FakePayroll implements StaffPayrollRepository {
  final Map<String, List<StaffAttendanceRecord>> _attendance = {};
  final Map<String, List<StaffDailySalary>> _salaries = {};
  final Map<String, List<StaffAdvanceEntry>> _advances = {};

  void seedAttendance(
    String staffUserId, {
    required List<(DateTime, int, bool)> shifts,
  }) {
    for (final (day, minutes, isLeave) in shifts) {
      _attendance
          .putIfAbsent(staffUserId, () => [])
          .add(
            StaffAttendanceRecord(
              id: 'att-${_attendance[staffUserId]!.length}',
              staffUserId: staffUserId,
              inAt: day,
              outAt: day.add(const Duration(hours: 8)),
              attendanceDate: day,
              workedMinutes: isLeave ? 0 : minutes,
              isLeave: isLeave,
            ),
          );
    }
  }

  void seedLeave(String staffUserId, {required List<DateTime> days}) {
    for (final day in days) {
      _attendance
          .putIfAbsent(staffUserId, () => [])
          .add(
            StaffAttendanceRecord(
              id: 'leave-${_attendance[staffUserId]!.length}',
              staffUserId: staffUserId,
              inAt: day,
              outAt: day,
              attendanceDate: day,
              workedMinutes: 0,
              isLeave: true,
            ),
          );
    }
  }

  void seedDailySalary(
    String staffUserId, {
    required List<(DateTime, int)> days,
  }) {
    for (final (day, salary) in days) {
      _salaries
          .putIfAbsent(staffUserId, () => [])
          .add(
            StaffDailySalary(
              id: 'sal-${_salaries[staffUserId]!.length}',
              staffUserId: staffUserId,
              attendanceDate: day,
              salaryPaise: salary,
            ),
          );
    }
  }

  void seedAdvance(
    String staffUserId, {
    required List<(DateTime, int)> advances,
  }) {
    for (final (day, amount) in advances) {
      _advances
          .putIfAbsent(staffUserId, () => [])
          .add(
            StaffAdvanceEntry(
              id: 'adv-${_advances[staffUserId]!.length}',
              staffUserId: staffUserId,
              amountPaise: amount,
              advanceDate: day,
              note: null,
            ),
          );
    }
  }

  bool _inRange(DateTime cookie, DateTime start, DateTime end) =>
      !cookie.isBefore(start) && cookie.isBefore(end);

  @override
  Future<List<StaffAttendanceRecord>> attendanceFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
    bool localOnly = false,
  }) async => [
    for (final s in _attendance[staffUserId] ?? const [])
      if (_inRange(s.attendanceDate, startDate, endExclusiveDate)) s,
  ];

  @override
  Future<List<StaffDailySalary>> dailySalariesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
    bool localOnly = false,
  }) async => [
    for (final d in _salaries[staffUserId] ?? const [])
      if (_inRange(d.attendanceDate, startDate, endExclusiveDate)) d,
  ];

  @override
  Future<List<StaffAdvanceEntry>> advancesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
    bool localOnly = false,
  }) async => [
    for (final a in _advances[staffUserId] ?? const [])
      if (_inRange(a.advanceDate, startDate, endExclusiveDate)) a,
  ];

  @override
  Future<void> deleteAttendance(String staffUserId, String shiftId) async {}
  @override
  Future<StaffAttendanceRecord?> openShiftFor(
    String staffUserId, {
    bool localOnly = false,
  }) async => null;
  @override
  Future<void> clockIn({
    required String staffUserId,
    required DateTime inAt,
  }) async {}
  @override
  Future<void> clockOut({
    required String staffUserId,
    required DateTime outAt,
  }) async {}
  @override
  Future<void> markLeave({
    required String staffUserId,
    required DateTime attendanceDate,
    String? reason,
  }) async {}
  @override
  Future<void> clearLeave({
    required String staffUserId,
    required DateTime attendanceDate,
  }) async {}
  @override
  Future<int?> salaryForMonth(
    String staffUserId,
    DateTime month, {
    bool localOnly = false,
  }) async => null;
  @override
  Future<void> setMonthlySalary(
    String staffUserId,
    DateTime month,
    int? salaryPaise,
  ) async {}
  @override
  Future<void> setDailySalary(
    String staffUserId,
    DateTime attendanceDate,
    int? salaryPaise,
  ) async {}
  @override
  Future<void> addAdvance({
    required String staffUserId,
    required int amountPaise,
    required DateTime advanceDate,
    String? note,
  }) async {}
}

/// Minimal closings repo: no closings in range for these salary tests.
final class _FakeClosings implements DailyClosingRepository {
  @override
  Future<List<DailyClosingRecord>> closingsFor({
    DateTime? startDate,
    DateTime? endExclusiveDate,
    List<String>? shopIds,
  }) async => const [];

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
  }) => throw UnimplementedError();

  @override
  Future<void> deleteDailyClosing(String id) async {}
}
