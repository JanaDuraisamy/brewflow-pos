import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
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

/// Controllers assembly for the date-range management report loader.
///
/// The loader is a plain class, so every repository is a fake injected
/// directly and the business context is fixed to Cafe + shop 'shop-1'. No
/// ProviderContainer, database or Supabase is involved.
void main() {
  late FakeOrdersRepository orders;
  late FakeExpensesRepository expenses;
  late FakeStaffRepository staff;
  late _FakeStaffPayrollRepository payroll;
  late _FakeDailyClosingRepository closings;
  late FakeSettingsRepository settings;
  late FakeCustomerLedgerRepository ledger;

  ManagementReportLoader makeLoader({List<String>? scope}) =>
      ManagementReportLoader(
        orders: orders,
        expenses: expenses,
        staff: staff,
        payroll: payroll,
        closings: closings,
        settings: settings,
        ledger: ledger,
        readShopIds: () async => scope ?? const ['shop-1'],
        businessLabel: 'Cafe',
      );

  Future<ManagementReportData> load({DateTime? from, DateTime? to}) =>
      makeLoader().load(
        fromLocal: from ?? DateTime(2026, 2, 1),
        toLocal: to ?? DateTime(2026, 2, 28),
      );

  /// A paid sale of [totalPaise] belonging to [shopId].
  void seedSale({
    required String receiptNumber,
    required int totalPaise,
    required String shopId,
  }) => orders.add(
    receiptNumber: receiptNumber,
    createdAt: DateTime.utc(2026, 2, 5, 9),
    paymentStatus: PaymentStatus.paid,
    paymentMethod: PaymentMethod.cash,
    totalPaise: totalPaise,
    items: [
      OrderItem(
        productName: 'Tea',
        unitPricePaise: totalPaise,
        quantity: 1,
        lineTotalPaise: totalPaise,
      ),
    ],
    shopId: shopId,
  );

  setUp(() {
    orders = FakeOrdersRepository();
    expenses = FakeExpensesRepository();
    staff = FakeStaffRepository();
    payroll = _FakeStaffPayrollRepository();
    closings = _FakeDailyClosingRepository();
    settings = FakeSettingsRepository();
    ledger = FakeCustomerLedgerRepository();
    settings.stored = const ShopSettings(shopName: 'My Cafe');
  });

  group('resolved scope is a hard scope', () {
    // `readShopIds` is the switcher's answer. An EMPTY list means the session
    // resolved no business of its own and must fail closed. Collapsing it to
    // null — the repositories' "every business" value — published the whole
    // company's takings to a session that was entitled to none of it.

    test('an empty scope reports zeros instead of every business', () async {
      seedSale(receiptNumber: 'BF-CAFE', totalPaise: 10000, shopId: 'shop-1');
      seedSale(receiptNumber: 'BF-FT', totalPaise: 7000, shopId: 'shop-2');

      final data = await makeLoader(
        scope: const [],
      ).load(fromLocal: DateTime(2026, 2, 1), toLocal: DateTime(2026, 2, 28));

      expect(data.salesTotalPaise, 0);
      expect(data.salesCashPaise, 0);
      expect(data.staffRows, isEmpty);
    });

    test('a partial scope totals only the resolved businesses', () async {
      seedSale(receiptNumber: 'BF-CAFE', totalPaise: 10000, shopId: 'shop-1');
      seedSale(receiptNumber: 'BF-FT', totalPaise: 7000, shopId: 'shop-2');

      final data = await makeLoader(
        scope: const ['shop-2'],
      ).load(fromLocal: DateTime(2026, 2, 1), toLocal: DateTime(2026, 2, 28));

      expect(data.salesTotalPaise, 7000);
      expect(data.salesCashPaise, 7000);
    });

    test('a multi-shop scope totals every resolved business', () async {
      seedSale(receiptNumber: 'BF-CAFE', totalPaise: 10000, shopId: 'shop-1');
      seedSale(receiptNumber: 'BF-FT', totalPaise: 7000, shopId: 'shop-2');

      final data = await makeLoader(
        scope: const ['shop-1', 'shop-2'],
      ).load(fromLocal: DateTime(2026, 2, 1), toLocal: DateTime(2026, 2, 28));

      expect(data.salesTotalPaise, 17000);
    });
  });

  test('aggregates a full range across every section', () async {
    orders.add(
      receiptNumber: 'BF-0001',
      createdAt: DateTime.utc(2026, 2, 5, 9),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 10000,
      items: const [
        OrderItem(
          productName: 'Tea',
          unitPricePaise: 10000,
          quantity: 1,
          lineTotalPaise: 10000,
        ),
      ],
      shopId: 'shop-1',
    );
    orders.add(
      receiptNumber: 'BF-0002',
      createdAt: DateTime.utc(2026, 2, 10, 12),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.upi,
      totalPaise: 5000,
      items: const [
        OrderItem(
          productName: 'Coffee',
          unitPricePaise: 5000,
          quantity: 1,
          lineTotalPaise: 5000,
        ),
      ],
      shopId: 'shop-1',
    );
    orders.add(
      receiptNumber: 'BF-0003',
      createdAt: DateTime.utc(2026, 2, 12, 14),
      paymentStatus: PaymentStatus.notPaid,
      totalPaise: 3000,
      items: const [
        OrderItem(
          productName: 'Snacks',
          unitPricePaise: 3000,
          quantity: 1,
          lineTotalPaise: 3000,
        ),
      ],
      shopId: 'shop-1',
    );
    // Voided sales are reverted and must never count toward totals.
    orders.add(
      receiptNumber: 'BF-0004',
      createdAt: DateTime.utc(2026, 2, 15, 10),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 999999,
      items: const [
        OrderItem(
          productName: 'Mistake',
          unitPricePaise: 999999,
          quantity: 1,
          lineTotalPaise: 999999,
        ),
      ],
      shopId: 'shop-1',
      isVoided: true,
      voidedAt: DateTime.utc(2026, 2, 15, 11),
    );
    // Outside the range.
    orders.add(
      receiptNumber: 'BF-0099',
      createdAt: DateTime.utc(2026, 1, 20, 9),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 70000,
      items: const [
        OrderItem(
          productName: 'Old',
          unitPricePaise: 70000,
          quantity: 1,
          lineTotalPaise: 70000,
        ),
      ],
      shopId: 'shop-1',
    );

    expenses.seed(
      name: 'Rent',
      amountPaise: 20000,
      category: ExpenseCategory.rent,
      paymentMethod: PaymentMethod.cash,
      expenseDate: DateTime.utc(2026, 2, 1),
      paymentStatus: ExpensePaymentStatus.paid,
    );
    expenses.seed(
      name: 'Power bill',
      amountPaise: 8000,
      category: ExpenseCategory.utilities,
      paymentMethod: PaymentMethod.upi,
      expenseDate: DateTime.utc(2026, 2, 7),
      paymentStatus: ExpensePaymentStatus.paid,
    );
    expenses.seed(
      name: 'Papad stock',
      amountPaise: 1500,
      category: ExpenseCategory.supplies,
      paymentMethod: PaymentMethod.cash,
      expenseDate: DateTime.utc(2026, 2, 12),
      paymentStatus: ExpensePaymentStatus.notPaid,
    );
    expenses.seed(
      name: 'Bank transfer',
      amountPaise: 4000,
      category: ExpenseCategory.misc,
      paymentMethod: PaymentMethod.bank,
      expenseDate: DateTime.utc(2026, 2, 20),
      paymentStatus: ExpensePaymentStatus.paid,
    );
    // Outside the range.
    expenses.seed(
      name: 'Old bill',
      amountPaise: 50000,
      category: ExpenseCategory.utilities,
      paymentMethod: PaymentMethod.cash,
      expenseDate: DateTime.utc(2026, 1, 25),
      paymentStatus: ExpensePaymentStatus.paid,
    );

    final ravi = await staff.createStaffProfile(
      identity: const AuthUser(id: 'ravi-auth', email: 'ravi@cafe.in'),
      shopId: 'shop-1',
      displayName: 'Ravi',
    );
    // Meena has no attendance/payroll rows in the range and must be omitted.
    await staff.createStaffProfile(
      identity: const AuthUser(id: 'meena-auth', email: 'meena@cafe.in'),
      shopId: 'shop-1',
      displayName: 'Meena',
    );
    payroll.seedAttendance(
      ravi.id,
      shifts: [
        (DateTime.utc(2026, 2, 3), 60),
        (DateTime.utc(2026, 2, 10), 120),
      ],
    );
    payroll.seedDailySalary(
      ravi.id,
      days: [
        (DateTime.utc(2026, 2, 3), 40000),
        (DateTime.utc(2026, 2, 10), 40000),
      ],
    );
    payroll.seedAdvance(ravi.id, advances: [(DateTime.utc(2026, 2, 5), 20000)]);

    closings.seed(
      'c1',
      businessDate: DateTime.utc(2026, 2, 14),
      totalCashPaise: 150000,
      totalUpiPaise: 200000,
      totalSalesPaise: 350000,
      totalExpensePaise: 30000,
      cashLeftInBoxPaise: 120000,
      cashTakenOutPaise: 30000,
      takenOutBy: 'Ravi',
    );
    closings.seed(
      'c2',
      businessDate: DateTime.utc(2026, 2, 20),
      totalCashPaise: 100000,
      totalUpiPaise: 250000,
      totalSalesPaise: 350000,
      totalExpensePaise: 0,
      cashLeftInBoxPaise: 90000,
      cashTakenOutPaise: 10000,
      takenOutBy: 'Ravi',
    );
    closings.seed(
      'c3',
      businessDate: DateTime.utc(2026, 2, 25),
      totalCashPaise: 80000,
      totalUpiPaise: 100000,
      totalSalesPaise: 180000,
      totalExpensePaise: 5000,
      cashLeftInBoxPaise: 75000,
      cashTakenOutPaise: 5000,
      takenOutBy: null,
    );
    // Outside the range.
    closings.seed(
      'c4',
      businessDate: DateTime.utc(2026, 1, 30),
      totalCashPaise: 99990000,
      totalUpiPaise: 0,
      totalSalesPaise: 99990000,
      totalExpensePaise: 0,
      cashLeftInBoxPaise: 0,
      cashTakenOutPaise: 0,
      takenOutBy: null,
    );

    final data = await load();

    expect(data.shopName, 'My Cafe');
    expect(data.businessLabel, 'Cafe');
    expect(data.anyRecords, isTrue);

    // Sales: cash + UPI + credit; voided and out-of-range excluded.
    expect(data.salesTotalPaise, 18000);
    expect(data.salesCashPaise, 10000);
    expect(data.salesUpiPaise, 5000);

    // Expenses: full ledger (paid cash/UPI/bank + not-paid), oldest first.
    expect(data.expenseTotalPaise, 33500);
    expect(data.expenseCashPaise, 20000);
    expect(data.expenseUpiPaise, 8000);
    expect(data.expenseBankPaise, 4000);
    expect(data.expenseNotPaidPaise, 1500);
    expect(
      [for (final row in data.expenseRows) row.name],
      ['Rent', 'Power bill', 'Papad stock', 'Bank transfer'],
    );
    expect(data.expenseRows.last.paymentLabel, 'Bank');

    // Staff: only staff with in-range records; totals summed per member.
    expect(data.staffRows, hasLength(1));
    expect(data.staffRows.single.name, 'Ravi');
    expect(data.staffRows.single.totalMinutes, 180);
    expect(data.staffRows.single.salaryPaise, 80000);
    expect(data.staffRows.single.advancePaise, 20000);

    // Closings: in-range only, oldest business day first.
    expect([for (final c in data.closings) c.id], ['c1', 'c2', 'c3']);

    // Taken-by: only closings with money taken; unknown grouped + alphabetical.
    expect(data.takenByRows, hasLength(2));
    expect(data.takenByRows.first.name, 'Not recorded');
    expect(data.takenByRows.first.daysTaken, 1);
    expect(data.takenByRows.first.totalPaise, 5000);
    expect(data.takenByRows.last.name, 'Ravi');
    expect(data.takenByRows.last.daysTaken, 2);
    expect(data.takenByRows.last.totalPaise, 40000);

    // Customer outstanding: no ledger bills seeded => no rows, zero total.
    expect(data.customerOutstandingRows, isEmpty);
    expect(data.customerOutstandingTotalPaise, 0);
  });

  test('empty range yields empty sections and zeros', () async {
    final data = await load();

    expect(data.salesTotalPaise, 0);
    expect(data.salesCashPaise, 0);
    expect(data.salesUpiPaise, 0);
    expect(data.expenseRows, isEmpty);
    expect(data.expenseTotalPaise, 0);
    expect(data.customerOutstandingRows, isEmpty);
    expect(data.customerOutstandingTotalPaise, 0);
    expect(data.staffRows, isEmpty);
    expect(data.closings, isEmpty);
    expect(data.takenByRows, isEmpty);
    expect(data.anyRecords, isFalse);
  });

  test('rejects a backwards range', () async {
    await expectLater(
      load(from: DateTime(2026, 2, 10), to: DateTime(2026, 2, 5)),
      throwsA(isA<InvalidManagementReportRangeFailure>()),
    );
  });

  test('wraps unexpected failures into the report failure', () async {
    orders.ordersError = StateError('boom');
    await expectLater(
      load(),
      throwsA(isA<UnexpectedManagementReportFailure>()),
    );
  });

  test('rethrows typed repository failures', () async {
    expenses.loadError = const UnexpectedExpensesFailure();
    await expectLater(load(), throwsA(isA<ExpensesFailure>()));
  });

  test(
    'customer outstanding balances are snapshotted as of the To Date',
    () async {
      void seedBill({
        required String id,
        required String customerId,
        required DateTime createdAt,
        required int totalPaise,
        String customerName = '',
        String shopId = 'shop-1',
      }) {
        ledger.bills.add(
          FakeLedgerBill(
            id: id,
            customerId: customerId,
            customerName: customerName,
            phone: customerId == 'kumar' ? '9998887776' : null,
            receiptNumber: 'BF-$id',
            createdAt: createdAt,
            totalPaise: totalPaise,
            shopId: shopId,
          ),
        );
      }

      void seedPayment({
        required String id,
        required String customerId,
        required String saleId,
        required int amountPaise,
        required DateTime paidAt,
      }) {
        ledger.storedPayments.add(
          CustomerPayment(
            id: id,
            customerId: customerId,
            saleId: saleId,
            amountPaise: amountPaise,
            paymentMethod: PaymentMethod.cash,
            paidAt: paidAt,
            reversed: false,
            reversedAt: null,
            createdAt: paidAt,
            updatedAt: paidAt,
          ),
        );
      }

      // Ravi: one bill partially paid before the To Date; a later bill created
      // AFTER the To Date must never count toward the snapshot.
      seedBill(
        id: 'r1',
        customerId: 'ravi',
        customerName: 'Ravi',
        createdAt: DateTime.utc(2026, 2, 10),
        totalPaise: 30000,
      );
      seedPayment(
        id: 'p1',
        customerId: 'ravi',
        saleId: 'r1',
        amountPaise: 10000,
        paidAt: DateTime.utc(2026, 2, 15),
      );
      seedBill(
        id: 'r2',
        customerId: 'ravi',
        createdAt: DateTime.utc(2026, 3, 5),
        totalPaise: 90000,
      );
      // Meena: an unpaid bill plus a bill whose payment landed AFTER the To
      // Date (that payment must not be subtracted from the snapshot).
      seedBill(
        id: 'm1',
        customerId: 'meena',
        customerName: 'Meena',
        createdAt: DateTime.utc(2026, 2, 20),
        totalPaise: 5000,
      );
      seedBill(
        id: 'm2',
        customerId: 'meena',
        createdAt: DateTime.utc(2026, 2, 15),
        totalPaise: 10000,
      );
      seedPayment(
        id: 'p2',
        customerId: 'meena',
        saleId: 'm2',
        amountPaise: 4000,
        paidAt: DateTime.utc(2026, 3, 1),
      );
      // Kumar: an unpaid bill BEFORE the range still counts (this is not a
      // range sum); a bill fully settled before the To Date drops to zero.
      seedBill(
        id: 'k1',
        customerId: 'kumar',
        customerName: 'Kumar',
        createdAt: DateTime.utc(2026, 1, 20),
        totalPaise: 8000,
      );
      seedBill(
        id: 'k2',
        customerId: 'kumar',
        createdAt: DateTime.utc(2026, 1, 25),
        totalPaise: 7000,
      );
      seedPayment(
        id: 'p3',
        customerId: 'kumar',
        saleId: 'k2',
        amountPaise: 7000,
        paidAt: DateTime.utc(2026, 2, 5),
      );
      // Vimal belongs to another shop and must be excluded by the shop scope.
      seedBill(
        id: 'v1',
        customerId: 'vimal',
        customerName: 'Vimal',
        createdAt: DateTime.utc(2026, 2, 5),
        totalPaise: 40000,
        shopId: 'shop-2',
      );

      final data = await load();

      expect(
        [for (final row in data.customerOutstandingRows) row.name],
        ['Kumar', 'Meena', 'Ravi'],
      );
      expect(data.customerOutstandingRows[0].phone, '9998887776');
      expect(data.customerOutstandingRows[0].outstandingPaise, 8000);
      expect(data.customerOutstandingRows[1].outstandingPaise, 15000);
      expect(data.customerOutstandingRows[2].outstandingPaise, 20000);
      expect(data.customerOutstandingTotalPaise, 43000);
      expect(data.anyRecords, isTrue);
    },
  );

  test('rethrows customer ledger failures', () async {
    ledger.outstandingAsOfError = const UnexpectedLedgerFailure();
    await expectLater(load(), throwsA(isA<CustomerLedgerFailure>()));
  });
}

/// In-memory minimal [StaffPayrollRepository] for the loader test: stores the
/// three in-range read families per member and filters by half-open day-cookie
/// range like the Drift implementation.
final class _FakeStaffPayrollRepository implements StaffPayrollRepository {
  Object? loadError;
  final Map<String, List<StaffAttendanceRecord>> _attendance = {};
  final Map<String, List<StaffDailySalary>> _dailySalaries = {};
  final Map<String, List<StaffAdvanceEntry>> _advances = {};

  @override
  Future<List<StaffAttendanceRecord>> attendanceFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    _throwIfLoadError();
    return [
      for (final shift
          in _attendance[staffUserId] ?? const <StaffAttendanceRecord>[])
        if (_inRange(shift.attendanceDate, startDate, endExclusiveDate)) shift,
    ];
  }

  @override
  Future<void> deleteAttendance(String staffUserId, String shiftId) async {
    _throwIfLoadError();
    final remaining =
        _attendance[staffUserId]?.where((s) => s.id != shiftId).toList() ??
        const <StaffAttendanceRecord>[];
    _attendance[staffUserId] = remaining;
  }

  @override
  Future<List<StaffDailySalary>> dailySalariesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    _throwIfLoadError();
    return [
      for (final day
          in _dailySalaries[staffUserId] ?? const <StaffDailySalary>[])
        if (_inRange(day.attendanceDate, startDate, endExclusiveDate)) day,
    ];
  }

  @override
  Future<List<StaffAdvanceEntry>> advancesFor({
    required String staffUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
    List<String>? shopIds,
  }) async {
    _throwIfLoadError();
    return [
      for (final advance
          in _advances[staffUserId] ?? const <StaffAdvanceEntry>[])
        if (_inRange(advance.advanceDate, startDate, endExclusiveDate)) advance,
    ];
  }

  void seedAttendance(
    String staffUserId, {
    required List<(DateTime day, int minutes)> shifts,
  }) {
    for (final (day, minutes) in shifts) {
      _attendance
          .putIfAbsent(staffUserId, () => <StaffAttendanceRecord>[])
          .add(
            StaffAttendanceRecord(
              id: 'att-${_attendance[staffUserId]!.length}',
              staffUserId: staffUserId,
              inAt: day,
              outAt: day.add(const Duration(hours: 8)),
              attendanceDate: day,
              workedMinutes: minutes,
            ),
          );
    }
  }

  void seedDailySalary(
    String staffUserId, {
    required List<(DateTime day, int salaryPaise)> days,
  }) {
    for (final (day, salaryPaise) in days) {
      _dailySalaries
          .putIfAbsent(staffUserId, () => <StaffDailySalary>[])
          .add(
            StaffDailySalary(
              id: 'sal-${_dailySalaries[staffUserId]!.length}',
              staffUserId: staffUserId,
              attendanceDate: day,
              salaryPaise: salaryPaise,
            ),
          );
    }
  }

  void seedAdvance(
    String staffUserId, {
    required List<(DateTime day, int amountPaise)> advances,
  }) {
    for (final (day, amountPaise) in advances) {
      _advances
          .putIfAbsent(staffUserId, () => <StaffAdvanceEntry>[])
          .add(
            StaffAdvanceEntry(
              id: 'adv-${_advances[staffUserId]!.length}',
              staffUserId: staffUserId,
              advanceDate: day,
              amountPaise: amountPaise,
              note: null,
            ),
          );
    }
  }

  bool _inRange(
    DateTime cookie,
    DateTime startDate,
    DateTime endExclusiveDate,
  ) => !cookie.isBefore(startDate) && cookie.isBefore(endExclusiveDate);

  void _throwIfLoadError() {
    final error = loadError;
    if (error != null) throw error;
  }

  @override
  Future<StaffAttendanceRecord?> openShiftFor(String staffUserId) async => null;

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
  Future<int?> salaryForMonth(String staffUserId, DateTime month) async => null;

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

/// In-memory minimal [DailyClosingRepository] for the loader test.
final class _FakeDailyClosingRepository implements DailyClosingRepository {
  final List<DailyClosingRecord> _stored = [];

  void seed(
    String id, {
    required DateTime businessDate,
    required int totalCashPaise,
    required int totalUpiPaise,
    required int totalSalesPaise,
    required int totalExpensePaise,
    required int cashLeftInBoxPaise,
    required int cashTakenOutPaise,
    String? takenOutBy,
  }) {
    _stored.add(
      DailyClosingRecord(
        id: id,
        businessDate: businessDate,
        totalCashPaise: totalCashPaise,
        totalUpiPaise: totalUpiPaise,
        totalSalesPaise: totalSalesPaise,
        totalExpensePaise: totalExpensePaise,
        cashLeftInBoxPaise: cashLeftInBoxPaise,
        cashTakenOutPaise: cashTakenOutPaise,
        takenOutBy: takenOutBy,
        talliedBy: null,
        note: null,
        createdAt: businessDate.add(const Duration(hours: 19)),
      ),
    );
  }

  @override
  Future<List<DailyClosingRecord>> closingsFor({
    DateTime? startDate,
    DateTime? endExclusiveDate,
    List<String>? shopIds,
  }) async {
    return [
      for (final record in _stored)
        if ((startDate == null || !record.businessDate.isBefore(startDate)) &&
            (endExclusiveDate == null ||
                record.businessDate.isBefore(endExclusiveDate)))
          record,
    ];
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
  }) => throw UnimplementedError();

  @override
  Future<void> deleteDailyClosing(String id) async {}
}
