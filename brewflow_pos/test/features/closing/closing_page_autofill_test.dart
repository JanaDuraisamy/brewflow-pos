import 'package:brewflow_pos/core/database/app_database.dart' hide Expense;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/closing/presentation/daily_closing_page.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_orders_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Page Autofill Regression
///
/// Locks the form contract: opening a date auto-fills Total Cash / Total UPI
/// from that day's paid sales and Total Expenses from that day's expenses,
/// Total Sales auto-calculates as Cash + UPI, a manually typed Total Sales
/// is never clobbered afterwards, and reopening a date with a saved closing
/// loads the saved values instead of the auto totals.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftDailyClosingRepository closings;
  late FakeOrdersRepository orders;
  late FakeExpensesRepository expenses;

  const cafeShop = 'shop-cafe';

  // The page derives the date from the LOCAL calendar day as a UTC cookie.
  DateTime businessDate() {
    final local = DateTime.now();
    return DateTime.utc(local.year, local.month, local.day);
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    closings = DriftDailyClosingRepository(database);
    orders = FakeOrdersRepository();
    expenses = FakeExpensesRepository();
  });

  tearDown(() async {
    await database.close();
  });

  OrderItem item(int total) => OrderItem(
    productName: 'Chai',
    unitPricePaise: total,
    quantity: 1,
    lineTotalPaise: total,
  );

  void seedDayTotals() {
    final day = businessDate();
    orders.add(
      receiptNumber: 'BF-1',
      createdAt: day.add(const Duration(hours: 5)),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 800000, // ₹8,000
      items: [item(800000)],
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-2',
      createdAt: day.add(const Duration(hours: 10)),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.upi,
      totalPaise: 1200000, // ₹12,000
      items: [item(1200000)],
      shopId: cafeShop,
    );
    final at = day;
    expenses.storedExpenses.add(
      Expense(
        id: 'e1',
        name: 'Milk',
        amountPaise: 100000,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: ExpensePaymentStatus.paid,
        expenseDate: at,
        isActive: true,
        createdAt: at,
        updatedAt: at,
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyClosingRepositoryProvider.overrideWithValue(closings),
          ordersRepositoryProvider.overrideWithValue(orders),
          expensesRepositoryProvider.overrideWithValue(expenses),
          // Unscoped read-all (the fallback path); shop isolation itself
          // is locked in daily_closing_cloud_test.
          closingShopScopeProvider.overrideWithValue(
            const AsyncValue.data(null),
          ),
        ],
        child: const MaterialApp(home: DailyClosingPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Amount fields render in form order: cash, UPI, sales, expenses, box,
  // taken-out.
  String fieldText(WidgetTester tester, int index) =>
      tester
          .widget<TextField>(find.byType(TextField).at(index))
          .controller
          ?.text ??
      '';

  testWidgets('opening a date auto-fills cash, UPI, expenses and total sales', (
    tester,
  ) async {
    seedDayTotals();
    await pumpPage(tester);
    expect(tester.takeException(), isNull);

    expect(fieldText(tester, 0), '8000.00');
    expect(fieldText(tester, 1), '12000.00');
    expect(fieldText(tester, 2), '20000.00'); // 8000 + 12000
    expect(fieldText(tester, 3), '1000.00');
  });

  testWidgets('a manually typed Total Sales is never clobbered', (
    tester,
  ) async {
    seedDayTotals();
    await pumpPage(tester);
    expect(fieldText(tester, 2), '20000.00');

    await tester.enterText(find.byType(TextField).at(2), '25000.00');
    await tester.pumpAndSettle();

    expect(fieldText(tester, 0), '8000.00');
    expect(fieldText(tester, 2), '25000.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening a saved date loads the saved values', (tester) async {
    seedDayTotals();
    // A saved revision for the same date wins over the auto totals.
    await closings.recordDailyClosing(
      businessDate: businessDate(),
      totalCashPaise: 111100,
      totalUpiPaise: 222200,
      totalSalesPaise: 333300,
      totalExpensePaise: 44400,
      cashLeftInBoxPaise: 0,
      cashTakenOutPaise: 0,
    );

    await pumpPage(tester);

    // Saved values load (7-field form order: cash, UPI, sales, expenses…).
    expect(fieldText(tester, 0), '1111.00');
    expect(fieldText(tester, 1), '2222.00');
    expect(fieldText(tester, 2), '3333.00');
    expect(fieldText(tester, 3), '444.00');
    expect(tester.takeException(), isNull);
  });
}
