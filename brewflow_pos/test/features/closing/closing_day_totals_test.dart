import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_orders_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Closing Day Totals Regression
///
/// Locks the date-specific auto-population contract used by the Daily Closing
/// page: Total Cash / Total UPI come from completed paid sales for that exact
/// business day, Total Expenses from the expense data for the same day, and
/// Total Sales = Total Cash + Total UPI. Voided, credit (not-paid) and bank
/// sales never contribute; other days never leak in; reads stay shop-scoped.
/// ---------------------------------------------------------------------------

void main() {
  late FakeOrdersRepository orders;
  late FakeExpensesRepository expenses;

  const cafeShop = 'shop-cafe';
  final day = DateTime.utc(2025, 7, 31);

  OrderItem item(int total) => OrderItem(
    productName: 'Chai',
    unitPricePaise: total,
    quantity: 1,
    lineTotalPaise: total,
  );

  Expense expense({
    required String id,
    required int amountPaise,
    required DateTime date,
  }) => Expense(
    id: id,
    name: 'Milk',
    amountPaise: amountPaise,
    category: ExpenseCategory.supplies,
    paymentMethod: PaymentMethod.cash,
    paymentStatus: ExpensePaymentStatus.paid,
    expenseDate: date,
    isActive: true,
    createdAt: date,
    updatedAt: date,
  );

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(orders),
        expensesRepositoryProvider.overrideWithValue(expenses),
        closingShopScopeProvider.overrideWithValue(
          const AsyncValue.data([cafeShop]),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    orders = FakeOrdersRepository();
    expenses = FakeExpensesRepository();
  });

  test('cash + UPI auto-populate and total sales = cash + UPI', () async {
    orders.add(
      receiptNumber: 'BF-1',
      createdAt: DateTime.utc(2025, 7, 31, 5),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 800000, // ₹8,000
      items: [item(800000)],
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-2',
      createdAt: DateTime.utc(2025, 7, 31, 10),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.upi,
      totalPaise: 1200000, // ₹12,000
      items: [item(1200000)],
      shopId: cafeShop,
    );
    expenses.storedExpenses.add(
      expense(id: 'e1', amountPaise: 100000, date: DateTime.utc(2025, 7, 31)),
    );

    final totals = await container().read(closingDayTotalsProvider(day).future);
    expect(totals.totalCashPaise, 800000);
    expect(totals.totalUpiPaise, 1200000);
    expect(totals.totalSalesPaise, 2000000); // 8000 + 12000
    expect(totals.totalExpensePaise, 100000);
  });

  test('voided, not-paid and bank sales never contribute', () async {
    orders.add(
      receiptNumber: 'BF-1',
      createdAt: DateTime.utc(2025, 7, 31, 5),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 800000,
      items: [item(800000)],
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-2',
      createdAt: DateTime.utc(2025, 7, 31, 6),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 50000,
      items: [item(50000)],
      isVoided: true,
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-3',
      createdAt: DateTime.utc(2025, 7, 31, 7),
      paymentStatus: PaymentStatus.notPaid,
      totalPaise: 90000,
      items: [item(90000)],
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-4',
      createdAt: DateTime.utc(2025, 7, 31, 8),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.bank,
      totalPaise: 70000,
      items: [item(70000)],
      shopId: cafeShop,
    );

    final totals = await container().read(closingDayTotalsProvider(day).future);
    expect(totals.totalCashPaise, 800000);
    expect(totals.totalUpiPaise, 0);
    expect(totals.totalSalesPaise, 800000);
  });

  test('other days never leak into the selected date', () async {
    orders.add(
      receiptNumber: 'BF-1',
      createdAt: DateTime.utc(2025, 7, 31, 5),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 800000,
      items: [item(800000)],
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-0',
      createdAt: DateTime.utc(2025, 7, 30, 5),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 999000,
      items: [item(999000)],
      shopId: cafeShop,
    );
    expenses.storedExpenses.add(
      expense(id: 'e0', amountPaise: 111000, date: DateTime.utc(2025, 7, 30)),
    );

    final totals = await container().read(closingDayTotalsProvider(day).future);
    expect(totals.totalCashPaise, 800000);
    expect(totals.totalExpensePaise, 0);
  });

  test('reads stay scoped to the requested shops', () async {
    orders.add(
      receiptNumber: 'BF-1',
      createdAt: DateTime.utc(2025, 7, 31, 5),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 800000,
      items: [item(800000)],
      shopId: cafeShop,
    );
    orders.add(
      receiptNumber: 'BF-9',
      createdAt: DateTime.utc(2025, 7, 31, 6),
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      totalPaise: 555000,
      items: [item(555000)],
      shopId: 'shop-truck',
    );

    final totals = await container().read(closingDayTotalsProvider(day).future);
    expect(totals.totalCashPaise, 800000);
  });
}
