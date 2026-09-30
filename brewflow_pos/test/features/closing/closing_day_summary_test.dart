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
/// BrewFlow POS — Daily Closing Day Summary Card
///
/// Locks the summary contract: before a closing is saved the card is an
/// Auto-calculated preview of that day's totals (Cash / UPI / Sales /
/// Expenses), and once a closing is saved it switches to the Saved values
/// (adding Cash in box / Cash taken out). The preview is strictly read-only:
/// it must never add TextFields on top of the 9-field form.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftDailyClosingRepository closings;
  late FakeOrdersRepository orders;
  late FakeExpensesRepository expenses;

  const cafeShop = 'shop-cafe';

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
          closingShopScopeProvider.overrideWithValue(
            const AsyncValue.data(null),
          ),
        ],
        child: const MaterialApp(home: DailyClosingPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The summary card is the AppCard that owns the 'Day summary' heading; its
  // nearest Padding ancestor scopes out the Saved-closings list below it.
  Finder daySummaryScope() => find
      .ancestor(of: find.text('Day summary'), matching: find.byType(Padding))
      .first;

  Finder inSummary(String text) =>
      find.descendant(of: daySummaryScope(), matching: find.text(text));

  testWidgets('before any save the card previews the auto totals', (
    tester,
  ) async {
    seedDayTotals();
    await pumpPage(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('Day summary'), findsOneWidget);
    expect(find.text('Auto-calculated'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);

    expect(inSummary('₹8,000.00'), findsOneWidget); // Cash
    expect(inSummary('₹12,000.00'), findsOneWidget); // UPI
    expect(inSummary('₹20,000.00'), findsOneWidget); // Sales
    expect(inSummary('₹1,000.00'), findsOneWidget); // Expenses

    // The unsaved card never shows the saved-only rows.
    expect(inSummary('Cash in box'), findsNothing);
    expect(inSummary('Cash taken out'), findsNothing);

    // Read-only preview: the form below keeps exactly its own fields — six
    // amounts plus Tallied by and Note. "Taken out by" is a fixed-owner
    // dropdown, not a text field.
    expect(find.byType(TextField), findsNWidgets(8));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('a saved closing switches the card to the stored values', (
    tester,
  ) async {
    seedDayTotals();
    await closings.recordDailyClosing(
      businessDate: businessDate(),
      totalCashPaise: 111100,
      totalUpiPaise: 222200,
      totalSalesPaise: 333300,
      totalExpensePaise: 44400,
      cashLeftInBoxPaise: 55500,
      cashTakenOutPaise: 77700,
    );

    await pumpPage(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('Day summary'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Auto-calculated'), findsNothing);

    expect(inSummary('₹1,111.00'), findsOneWidget);
    expect(inSummary('₹2,222.00'), findsOneWidget);
    expect(inSummary('₹3,333.00'), findsOneWidget);
    expect(inSummary('₹444.00'), findsOneWidget);
    expect(inSummary('₹555.00'), findsOneWidget); // Cash in box
    expect(inSummary('₹777.00'), findsOneWidget); // Cash taken out
    expect(inSummary('Cash in box'), findsOneWidget);
    expect(inSummary('Cash taken out'), findsOneWidget);

    // Still read-only: nothing but the form's own fields on screen.
    expect(find.byType(TextField), findsNWidgets(8));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });
}
