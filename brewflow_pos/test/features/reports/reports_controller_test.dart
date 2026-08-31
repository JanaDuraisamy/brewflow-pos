import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/domain/reports_models.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';

/// One sale line bounded by the repository's snapshot semantics.
OrderItem _item(
  String name, {
  int price = 1500,
  int quantity = 1,
  String? productId,
}) => OrderItem(
  productName: name,
  unitPricePaise: price,
  quantity: quantity,
  lineTotalPaise: price * quantity,
  productId: productId,
);

/// Container with the three repositories reports composes, all faked.
ProviderContainer _container({
  FakeOrdersRepository? orders,
  FakeExpensesRepository? expenses,
  FakeInventoryRepository? inventory,
}) {
  final container = ProviderContainer(
    // Riverpod retries failing builds with exponential backoff by default;
    // failure-mapping tests want the error to surface immediately instead.
    retry: (count, error) => null,
    overrides: [
      ordersRepositoryProvider.overrideWithValue(
        orders ?? FakeOrdersRepository(),
      ),
      expensesRepositoryProvider.overrideWithValue(
        expenses ?? FakeExpensesRepository(),
      ),
      inventoryRepositoryProvider.overrideWithValue(
        inventory ?? FakeInventoryRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ReportsSnapshot> _load(ProviderContainer container) =>
    container.read(reportsControllerProvider.future);

void main() {
  group('reports range', () {
    test('defaults to a bounded last-30-days window', () async {
      final container = _container();
      final range = container.read(reportsRangeProvider);
      expect(range.datePreset, OrdersDatePreset.last30);
      expect(range.fromUtc, isNotNull);
      expect(range.toUtc, isNotNull);

      final snapshot = await _load(container);
      expect(snapshot.sales.dailySalesPaise.length, 30);
      expect(snapshot.sales.orderCount, 0);
    });

    test('today preset bounds the window to the current day', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 30000,
        items: [_item('Chai', price: 30000)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 20000,
        items: [_item('Cookie', price: 20000)],
      );
      final container = _container(orders: orders);
      container
          .read(reportsRangeProvider.notifier)
          .setPreset(OrdersDatePreset.today);

      final snapshot = await _load(container);
      expect(snapshot.range.datePreset, OrdersDatePreset.today);
      expect(snapshot.sales.dailySalesPaise.length, 1);
      expect(snapshot.sales.orderCount, 1);
      expect(snapshot.sales.totalPaise, 30000);
    });

    test('last7 preset keeps only the trailing week', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 30000,
        items: [_item('Chai', price: 30000)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 5)),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 10000,
        items: [_item('Cookie', price: 10000)],
      );
      orders.add(
        receiptNumber: 'R-3',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 20)),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 40000,
        items: [_item('Latte', price: 40000)],
      );
      final container = _container(orders: orders);
      container
          .read(reportsRangeProvider.notifier)
          .setPreset(OrdersDatePreset.last7);

      final snapshot = await _load(container);
      expect(snapshot.range.datePreset, OrdersDatePreset.last7);
      expect(snapshot.sales.dailySalesPaise.length, 7);
      expect(snapshot.sales.orderCount, 2);
      expect(snapshot.sales.totalPaise, 40000);
    });

    test('last30 preset includes month-old sales', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 30000,
        items: [_item('Chai', price: 30000)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 25)),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 10000,
        items: [_item('Cookie', price: 10000)],
      );
      orders.add(
        receiptNumber: 'R-3',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 40)),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 40000,
        items: [_item('Latte', price: 40000)],
      );
      final container = _container(orders: orders);

      final snapshot = await _load(container);
      expect(snapshot.range.datePreset, OrdersDatePreset.last30);
      expect(snapshot.sales.orderCount, 2);
      expect(snapshot.sales.totalPaise, 40000);
    });

    test('last90 preset includes quarter-old sales', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 80)),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 30000,
        items: [_item('Chai', price: 30000)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 100)),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 20000,
        items: [_item('Cookie', price: 20000)],
      );
      final container = _container(orders: orders);
      container
          .read(reportsRangeProvider.notifier)
          .setPreset(OrdersDatePreset.last90);

      final snapshot = await _load(container);
      expect(snapshot.range.datePreset, OrdersDatePreset.last90);
      expect(snapshot.sales.dailySalesPaise.length, 90);
      expect(snapshot.sales.orderCount, 1);
      expect(snapshot.sales.totalPaise, 30000);
    });

    test('custom range keeps only picked local dates', () async {
      final now = DateTime.now();
      final from = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 9));
      final to = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 5));

      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-in',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 7)),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 25000,
        items: [_item('Chai', price: 25000)],
      );
      orders.add(
        receiptNumber: 'R-out',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 40000,
        items: [_item('Latte', price: 40000)],
      );
      final container = _container(orders: orders);
      container.read(reportsRangeProvider.notifier).setCustomRange(from, to);

      final snapshot = await _load(container);
      expect(snapshot.range.isCustom, isTrue);
      expect(snapshot.sales.dailySalesPaise.length, 5);
      expect(snapshot.sales.orderCount, 1);
      expect(snapshot.sales.totalPaise, 25000);
    });
  });

  group('sales summary', () {
    test('totals sales, orders and items across the window', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [_item('Chai', price: 1500, quantity: 2)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 2000,
        items: [_item('Cookie', price: 2000)],
      );

      final snapshot = await _load(_container(orders: orders));
      expect(snapshot.sales.totalPaise, 5000);
      expect(snapshot.sales.orderCount, 2);
      expect(snapshot.sales.itemCount, 3);
      expect(snapshot.sales.dailySalesPaise.length, 30);
    });

    test('average sale is total over orders; null without sales', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 20000,
        items: [_item('Chai', price: 20000)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 40000,
        items: [_item('Latte', price: 40000)],
      );

      final snapshot = await _load(_container(orders: orders));
      expect(snapshot.sales.averageSalePaise, 30000);

      final empty = await _load(_container());
      expect(empty.sales.averageSalePaise, isNull);
    });

    test('payment split and whole-percent shares', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 45000,
        items: [_item('Chai', price: 45000)],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 15000,
        items: [_item('Cookie', price: 15000)],
      );

      final snapshot = await _load(_container(orders: orders));
      expect(snapshot.payments.paiseOf(PaymentMethod.cash), 45000);
      expect(snapshot.payments.paiseOf(PaymentMethod.upi), 15000);
      expect(snapshot.payments.paiseOf(PaymentMethod.bank), 0);
      expect(snapshot.payments.shareOf(PaymentMethod.cash), 75);
      expect(snapshot.payments.shareOf(PaymentMethod.upi), 25);
      expect(snapshot.payments.totalPaise, 60000);
    });

    test(
      'credit sales count in revenue but stay out of the payment split',
      () async {
        final orders = FakeOrdersRepository();
        orders.add(
          receiptNumber: 'R-1',
          createdAt: DateTime.now().toUtc(),
          paymentMethod: PaymentMethod.cash,
          totalPaise: 45000,
          items: [_item('Chai', price: 45000)],
        );
        orders.add(
          receiptNumber: 'R-2',
          createdAt: DateTime.now().toUtc(),
          paymentStatus: PaymentStatus.notPaid,
          totalPaise: 30000,
          items: [_item('Cookie', price: 30000)],
        );

        final snapshot = await _load(_container(orders: orders));
        expect(snapshot.sales.totalPaise, 75000);
        expect(snapshot.sales.orderCount, 2);
        expect(snapshot.sales.itemCount, 2);
        expect(snapshot.payments.paiseOf(PaymentMethod.cash), 45000);
        expect(snapshot.payments.paiseOf(PaymentMethod.upi), 0);
        expect(snapshot.payments.paiseOf(PaymentMethod.bank), 0);
        // Shares still derive from the full window revenue.
        expect(snapshot.payments.totalPaise, 75000);
        expect(snapshot.payments.shareOf(PaymentMethod.cash), 60);
        expect(snapshot.profitLoss.salesPaise, 75000);
      },
    );
  });

  group('expense summary', () {
    Future<FakeExpensesRepository> buildExpenses() async {
      final expenses = FakeExpensesRepository();
      expenses.seed(
        name: 'Shop Rent',
        amountPaise: 50000,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.bank,
        expenseDate: DateTime.now().toUtc(),
      );
      final utilities = expenses.seed(
        name: 'Utilities Bill',
        amountPaise: 10000,
        category: ExpenseCategory.utilities,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.now().toUtc(),
      );
      expenses.seed(
        name: 'Old Write-off',
        amountPaise: 99999,
        category: ExpenseCategory.misc,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.now().toUtc().subtract(const Duration(days: 40)),
      );
      await expenses.setExpenseActive(utilities.id, false);
      return expenses;
    }

    test('sums only active in-window expenses', () async {
      final snapshot = await _load(_container(expenses: await buildExpenses()));
      expect(snapshot.expenses.totalPaise, 50000);
      expect(snapshot.expenses.count, 1);
      expect(snapshot.expenses.byCategoryPaise[ExpenseCategory.rent], 50000);
      expect(
        snapshot.expenses.byCategoryPaise.containsKey(
          ExpenseCategory.utilities,
        ),
        isFalse,
      );
      expect(
        snapshot.expenses.byCategoryPaise.containsKey(ExpenseCategory.misc),
        isFalse,
      );
    });

    test(
      'NOT_PAID expenses count in totals while staying separately payable',
      () async {
        final expenses = FakeExpensesRepository();
        expenses.seed(
          name: 'Shop Rent',
          amountPaise: 50000,
          category: ExpenseCategory.rent,
          paymentMethod: PaymentMethod.bank,
          expenseDate: DateTime.now().toUtc(),
        );
        expenses.seed(
          name: 'Unpaid supply',
          amountPaise: 20000,
          category: ExpenseCategory.supplies,
          paymentMethod: PaymentMethod.cash,
          expenseDate: DateTime.now().toUtc(),
          paymentStatus: ExpensePaymentStatus.notPaid,
        );

        final snapshot = await _load(_container(expenses: expenses));

        // NOT_PAID is still a real expense: it is part of the window total and
        // the P&L, never treated as income.
        expect(snapshot.expenses.totalPaise, 70000);
        expect(snapshot.expenses.count, 2);
        expect(snapshot.profitLoss.expensesPaise, 70000);

        // The payable metric is the shop's outstanding liability, separate from
        // the expense totals above.
        expect(await expenses.payablePaise(), 20000);
      },
    );

    test('groups by fixed category and payment method', () async {
      final expenses = FakeExpensesRepository();
      expenses.seed(
        name: 'Shop Rent',
        amountPaise: 50000,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.bank,
        expenseDate: DateTime.now().toUtc(),
      );
      expenses.seed(
        name: 'Payroll',
        amountPaise: 30000,
        category: ExpenseCategory.salaries,
        paymentMethod: PaymentMethod.bank,
        expenseDate: DateTime.now().toUtc(),
      );
      expenses.seed(
        name: 'Transport',
        amountPaise: 20000,
        category: ExpenseCategory.transport,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.now().toUtc(),
      );

      final snapshot = await _load(_container(expenses: expenses));
      expect(snapshot.expenses.totalPaise, 100000);
      expect(snapshot.expenses.count, 3);
      expect(snapshot.expenses.byCategoryPaise[ExpenseCategory.rent], 50000);
      expect(
        snapshot.expenses.byCategoryPaise[ExpenseCategory.salaries],
        30000,
      );
      expect(
        snapshot.expenses.byCategoryPaise[ExpenseCategory.transport],
        20000,
      );
      expect(snapshot.expenses.byPaymentPaise[PaymentMethod.bank], 80000);
      expect(snapshot.expenses.byPaymentPaise[PaymentMethod.cash], 20000);
    });
  });

  group('profit & loss', () {
    Future<FakeInventoryRepository> buildInventory({
      int? chaiCost,
      int? latteCost,
    }) async {
      final inventory = FakeInventoryRepository();
      final category = await inventory.createCategory('Beverages');
      await inventory.createProduct(
        categoryId: category.id,
        name: 'Chai',
        sellingPricePaise: 1500,
        costPricePaise: chaiCost,
        stockQuantity: 10,
        isActive: true,
      );
      await inventory.createProduct(
        categoryId: category.id,
        name: 'Cafe Latte',
        sellingPricePaise: 40000,
        costPricePaise: latteCost,
        stockQuantity: 10,
        isActive: true,
      );
      return inventory;
    }

    test('net profit with fully resolved costs', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [
          _item('Chai', price: 1500, quantity: 2, productId: 'product-1'),
        ],
      );
      final expenses = FakeExpensesRepository();
      expenses.seed(
        name: 'Shop Rent',
        amountPaise: 500,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.now().toUtc(),
      );
      final inventory = await buildInventory(chaiCost: 1000);

      final snapshot = await _load(
        _container(orders: orders, expenses: expenses, inventory: inventory),
      );
      expect(snapshot.profitLoss.salesPaise, 3000);
      expect(snapshot.profitLoss.cogsPaise, 2000);
      expect(snapshot.profitLoss.expensesPaise, 500);
      expect(snapshot.profitLoss.netProfitPaise, 500);
      expect(snapshot.profitLoss.partialCosts, isFalse);
    });

    test('profit is null when no sold line resolves a cost', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [
          _item('Chai', price: 1500, quantity: 2, productId: 'product-1'),
        ],
      );
      final inventory = await buildInventory();

      final snapshot = await _load(
        _container(orders: orders, inventory: inventory),
      );
      expect(snapshot.profitLoss.cogsPaise, isNull);
      expect(snapshot.profitLoss.netProfitPaise, isNull);
      expect(snapshot.profitLoss.partialCosts, isFalse);
    });

    test('partial costs resolve only purchased lines', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [
          _item('Chai', price: 1500, quantity: 2, productId: 'product-1'),
        ],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 2000,
        items: [_item('Cafe Latte', price: 2000, productId: 'product-2')],
      );
      final inventory = await buildInventory(chaiCost: 1000);

      final snapshot = await _load(
        _container(orders: orders, inventory: inventory),
      );
      expect(snapshot.profitLoss.salesPaise, 5000);
      expect(snapshot.profitLoss.cogsPaise, 2000);
      expect(snapshot.profitLoss.netProfitPaise, 3000);
      expect(snapshot.profitLoss.partialCosts, isTrue);
    });

    test('zero activity yields a zero, not unknown, profit', () async {
      final snapshot = await _load(_container());
      expect(snapshot.profitLoss.hasSales, isFalse);
      expect(snapshot.profitLoss.cogsPaise, 0);
      expect(snapshot.profitLoss.netProfitPaise, 0);
      expect(snapshot.profitLoss.partialCosts, isFalse);
    });
  });

  group('product and category performance', () {
    test(
      'ranks top products by revenue from name snapshots, capped at 5',
      () async {
        final orders = FakeOrdersRepository();
        for (var i = 1; i <= 6; i++) {
          orders.add(
            receiptNumber: 'R-$i',
            createdAt: DateTime.now().toUtc(),
            paymentMethod: PaymentMethod.cash,
            totalPaise: i * 1000,
            items: [
              _item(
                'Snapshot Name $i',
                price: i * 1000,
                productId: 'product-$i',
              ),
            ],
          );
        }
        final inventory = FakeInventoryRepository();
        final category = await inventory.createCategory('Beverages');
        for (var i = 1; i <= 6; i++) {
          await inventory.createProduct(
            categoryId: category.id,
            name: 'Current Name $i',
            sellingPricePaise: i * 1000,
            stockQuantity: 5,
            isActive: true,
          );
        }

        final snapshot = await _load(
          _container(orders: orders, inventory: inventory),
        );
        expect(snapshot.topProducts.length, 5);
        expect(snapshot.topProducts.first.productName, 'Snapshot Name 6');
        expect(snapshot.topProducts.first.revenuePaise, 6000);
        expect(snapshot.topProducts.last.revenuePaise, 2000);
        expect(snapshot.topProducts.first.unitsSold, 1);
      },
    );

    test('groups revenue by the product current category', () async {
      final inventory = FakeInventoryRepository();
      final beverages = await inventory.createCategory('Beverages');
      final snacks = await inventory.createCategory('Snacks');
      await inventory.createProduct(
        categoryId: beverages.id,
        name: 'Chai',
        sellingPricePaise: 1500,
        costPricePaise: 1000,
        stockQuantity: 10,
        isActive: true,
      );
      await inventory.createProduct(
        categoryId: snacks.id,
        name: 'Cookie',
        sellingPricePaise: 2000,
        stockQuantity: 10,
        isActive: true,
      );

      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'R-1',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [
          _item('Chai', price: 1500, quantity: 2, productId: 'product-1'),
          _item('Cookie', price: 2000, productId: 'product-2'),
        ],
      );
      orders.add(
        receiptNumber: 'R-2',
        createdAt: DateTime.now().toUtc(),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 1000,
        items: [_item('Ancient Line', price: 1000, productId: 'product-9')],
      );

      final snapshot = await _load(
        _container(orders: orders, inventory: inventory),
      );
      expect(snapshot.categoryPerformance.length, 2);
      expect(snapshot.categoryPerformance[0].categoryName, 'Beverages');
      expect(snapshot.categoryPerformance[0].revenuePaise, 3000);
      expect(snapshot.categoryPerformance[1].categoryName, 'Snacks');
      expect(snapshot.categoryPerformance[1].revenuePaise, 2000);
    });
  });

  group('failure mapping', () {
    test('unexpected list failure becomes UnexpectedReportsFailure', () async {
      final orders = FakeOrdersRepository()..ordersError = Exception('boom');
      final container = _container(orders: orders);

      await expectLater(
        _load(container),
        throwsA(isA<UnexpectedReportsFailure>()),
      );
    });

    test('unexpected expenses failure is wrapped', () async {
      final expenses = FakeExpensesRepository()..loadError = Exception('boom');
      final container = _container(expenses: expenses);

      await expectLater(
        _load(container),
        throwsA(isA<UnexpectedReportsFailure>()),
      );
    });

    test('unexpected inventory failure is wrapped', () async {
      final inventory = FakeInventoryRepository()
        ..loadError = Exception('boom');
      final container = _container(inventory: inventory);

      await expectLater(
        _load(container),
        throwsA(isA<UnexpectedReportsFailure>()),
      );
    });

    test('typed order failures pass through with display text', () async {
      final orders = FakeOrdersRepository()
        ..detailError = const MissingOrderFailure();
      final order = OrderSummary(
        id: 'order-1',
        receiptNumber: 'R-1',
        itemCount: 1,
        totalPaise: 1000,
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime.now().toUtc(),
      );
      orders.storedSummaries.add(order);
      final container = _container(orders: orders);

      await expectLater(_load(container), throwsA(isA<MissingOrderFailure>()));
    });

    test('error messages fall back safely', () {
      expect(reportsErrorMessage(Exception('secret')), contains('try again'));
      expect(
        reportsErrorMessage(const MissingOrderFailure()),
        'Order not found.',
      );
      expect(
        reportsErrorMessage(const UnexpectedReportsFailure()),
        'Something went wrong. Please try again.',
      );
    });
  });

  test('changing the preset rebuilds the snapshot', () async {
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'R-1',
      createdAt: DateTime.now().toUtc(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 30000,
      items: [_item('Chai', price: 30000)],
    );
    orders.add(
      receiptNumber: 'R-2',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
      paymentMethod: PaymentMethod.upi,
      totalPaise: 20000,
      items: [_item('Cookie', price: 20000)],
    );
    final container = _container(orders: orders);

    var snapshot = await _load(container);
    expect(snapshot.sales.orderCount, 2);
    expect(snapshot.sales.totalPaise, 50000);

    container
        .read(reportsRangeProvider.notifier)
        .setPreset(OrdersDatePreset.last7);
    snapshot = await _load(container);
    expect(snapshot.sales.orderCount, 1);
    expect(snapshot.sales.totalPaise, 30000);
  });
}
