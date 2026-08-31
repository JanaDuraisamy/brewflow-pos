import 'dart:async';

import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_page.dart';
import 'package:flutter/material.dart';
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

/// A shop with two past-week sales (cash 43000 + upi 10000 = 53000) and one
/// active rent expense (5000). [withCosts] controls whether every sold line
/// resolves to a product cost price.
Future<(FakeOrdersRepository, FakeInventoryRepository, FakeExpensesRepository)>
_seededWorld({bool withCosts = true}) async {
  final inventory = FakeInventoryRepository();
  final category = await inventory.createCategory('Beverages');
  await inventory.createProduct(
    categoryId: category.id,
    name: 'Chai',
    sellingPricePaise: 1500,
    costPricePaise: withCosts ? 1000 : null,
    stockQuantity: 10,
    isActive: true,
  );
  await inventory.createProduct(
    categoryId: category.id,
    name: 'Cafe Latte',
    sellingPricePaise: 40000,
    costPricePaise: withCosts ? 30000 : null,
    stockQuantity: 10,
    isActive: true,
  );
  await inventory.createProduct(
    categoryId: category.id,
    name: 'Cookie',
    sellingPricePaise: 2000,
    costPricePaise: withCosts ? 1500 : null,
    stockQuantity: 10,
    isActive: true,
  );

  final now = DateTime.now();
  final orders = FakeOrdersRepository();
  orders.add(
    receiptNumber: 'R-001',
    createdAt: now.toUtc(),
    paymentMethod: PaymentMethod.cash,
    totalPaise: 43000,
    items: [
      _item('Chai', price: 1500, quantity: 2, productId: 'product-1'),
      _item('Cafe Latte', price: 40000, quantity: 1, productId: 'product-2'),
    ],
  );
  orders.add(
    receiptNumber: 'R-002',
    createdAt: now.subtract(const Duration(days: 1)).toUtc(),
    paymentMethod: PaymentMethod.upi,
    totalPaise: 10000,
    items: [_item('Cookie', price: 2000, quantity: 5, productId: 'product-3')],
  );

  final expenses = FakeExpensesRepository();
  expenses.seed(
    name: 'Shop Rent',
    amountPaise: 5000,
    category: ExpenseCategory.rent,
    paymentMethod: PaymentMethod.bank,
    expenseDate: now.toUtc(),
  );

  return (orders, inventory, expenses);
}

/// Pumps the Reports page with faked repositories. State settles only when
/// the caller asks for it (loading-state tests control the pump manually).
Future<ProviderContainer> _pumpReports(
  WidgetTester tester, {
  FakeOrdersRepository? orders,
  FakeInventoryRepository? inventory,
  FakeExpensesRepository? expenses,
}) async {
  final container = ProviderContainer(
    // Riverpod retries failing builds by default; tests want deterministic
    // error surfacing without background backoff timers.
    retry: (count, error) => null,
    overrides: [
      ordersRepositoryProvider.overrideWithValue(
        orders ?? FakeOrdersRepository(),
      ),
      inventoryRepositoryProvider.overrideWithValue(
        inventory ?? FakeInventoryRepository(),
      ),
      expensesRepositoryProvider.overrideWithValue(
        expenses ?? FakeExpensesRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReportsPage()),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders the page header', (tester) async {
    await _pumpReports(tester);
    await tester.pumpAndSettle();

    expect(find.text('Reports'), findsOneWidget);
    expect(
      find.text('Sales, expenses and profit for a date range.'),
      findsOneWidget,
    );
  });

  testWidgets('renders the range selector presets', (tester) async {
    await _pumpReports(tester);
    await tester.pumpAndSettle();

    // 'Last 30 days' also appears as the Sales Overview subtitle; the chip
    // row is the only horizontal scroll, so scope the labels to it.
    final chips = find.byType(SingleChildScrollView);
    expect(
      find.descendant(of: chips, matching: find.text('Today')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chips, matching: find.text('Last 7 days')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chips, matching: find.text('Last 30 days')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chips, matching: find.text('Last 90 days')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chips, matching: find.text('Custom')),
      findsOneWidget,
    );
  });

  testWidgets('shows seeded sales KPIs by default (last 30 days)', (
    tester,
  ) async {
    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    await tester.pumpAndSettle();

    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('₹530.00'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Avg. Sale'), findsOneWidget);
    expect(find.text('₹265.00'), findsOneWidget);
    expect(find.text('Sales Overview'), findsOneWidget);
  });

  testWidgets('payment methods show amounts and shares', (tester) async {
    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Payment Methods'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('₹430.00'), findsOneWidget);
    expect(find.text('81%'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('18%'), findsOneWidget);
    // 'Bank' also appears in the expenses 'By payment method' rows, so
    // scope the assertion to the payment card.
    final paymentCard = find.widgetWithText(SectionCard, 'Payment Methods');
    expect(
      find.descendant(of: paymentCard, matching: find.text('Bank')),
      findsOneWidget,
    );
    expect(find.text('0%'), findsWidgets);
  });

  testWidgets('expenses section shows total, count and breakdown rows', (
    tester,
  ) async {
    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Expenses Summary'), findsOneWidget);
    expect(find.text('Total Expenses'), findsOneWidget);
    expect(find.text('1 expense'), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('By payment method'), findsOneWidget);
    // Total + category row + payment row; the P&L card shows its own
    // ₹50.00 'Expenses' line, so scope to this card.
    final expensesCard = find.widgetWithText(SectionCard, 'Expenses Summary');
    expect(
      find.descendant(of: expensesCard, matching: find.text('₹50.00')),
      findsNWidgets(3),
    );
  });

  testWidgets('profit and loss shows resolved figures and the cost caveat', (
    tester,
  ) async {
    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Profit & Loss'), findsOneWidget);
    expect(find.text('Cost of Goods'), findsOneWidget);
    // Chai 2×₹10 + Cafe Latte ₹300 + Cookie 5×₹15 = ₹395.00 COGS.
    expect(find.text('₹395.00'), findsOneWidget);
    expect(find.text('Net Profit'), findsOneWidget);
    // ₹530.00 sales − ₹395.00 COGS − ₹50.00 expenses = ₹85.00.
    expect(find.text('₹85.00'), findsOneWidget);
    expect(
      find.text(
        'Profit uses current product cost prices; historical sale-time '
        'cost is not stored.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add cost prices to see profit'), findsNothing);
  });

  testWidgets(
    'missing product costs show guidance instead of invented profit',
    (tester) async {
      final world = await _seededWorld(withCosts: false);
      await _pumpReports(
        tester,
        orders: world.$1,
        inventory: world.$2,
        expenses: world.$3,
      );
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();

      expect(find.text('Add cost prices to see profit'), findsOneWidget);
      // The payment card legitimately shows ₹0.00 for methods with no sales;
      // the P&L card must never invent a profit figure.
      final pnlCard = find.widgetWithText(SectionCard, 'Profit & Loss');
      expect(
        find.descendant(of: pnlCard, matching: find.text('₹0.00')),
        findsNothing,
      );
      expect(find.text('₹160.00'), findsNothing);
    },
  );

  testWidgets('partial costs keep profit but say it covers only resolved '
      'lines', (tester) async {
    final inventory = FakeInventoryRepository();
    final category = await inventory.createCategory('Beverages');
    await inventory.createProduct(
      categoryId: category.id,
      name: 'Chai',
      sellingPricePaise: 1500,
      costPricePaise: 1000,
      stockQuantity: 10,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: category.id,
      name: 'Cafe Latte',
      sellingPricePaise: 40000,
      stockQuantity: 10,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: category.id,
      name: 'Cookie',
      sellingPricePaise: 2000,
      stockQuantity: 10,
      isActive: true,
    );
    final now = DateTime.now();
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'R-001',
      createdAt: now.toUtc(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 43000,
      items: [
        _item('Chai', price: 1500, quantity: 2, productId: 'product-1'),
        _item('Cafe Latte', price: 40000, productId: 'product-2'),
      ],
    );
    orders.add(
      receiptNumber: 'R-002',
      createdAt: now.subtract(const Duration(days: 1)).toUtc(),
      paymentMethod: PaymentMethod.upi,
      totalPaise: 10000,
      items: [
        _item('Cookie', price: 2000, quantity: 5, productId: 'product-3'),
      ],
    );
    final expenses = FakeExpensesRepository();
    expenses.seed(
      name: 'Shop Rent',
      amountPaise: 5000,
      category: ExpenseCategory.rent,
      paymentMethod: PaymentMethod.bank,
      expenseDate: now.toUtc(),
    );

    await _pumpReports(
      tester,
      orders: orders,
      inventory: inventory,
      expenses: expenses,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(
      find.text('Profit uses only lines with current cost prices'),
      findsOneWidget,
    );
    expect(find.text('₹460.00'), findsOneWidget);
    expect(find.text('Add cost prices to see profit'), findsNothing);
  });

  testWidgets('top products use sale name snapshots with units and revenue', (
    tester,
  ) async {
    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Top Products'), findsOneWidget);
    expect(find.text('Cafe Latte'), findsOneWidget);
    expect(find.text('1 pcs'), findsOneWidget);
    expect(find.text('₹400.00'), findsOneWidget);
    expect(find.text('Cookie'), findsOneWidget);
    expect(find.text('5 pcs'), findsOneWidget);
    expect(find.text('Chai'), findsOneWidget);
    expect(find.text('2 pcs'), findsOneWidget);
  });

  testWidgets('category performance joins the product current category', (
    tester,
  ) async {
    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Category Performance'), findsOneWidget);
    expect(
      find.text("Category performance uses the product's current category."),
      findsOneWidget,
    );
    expect(find.text('Beverages'), findsOneWidget);
    // ₹530.00 also appears on the KPI, payment total and P&L sales rows;
    // scope the count to the category card.
    final categoryCard = find.widgetWithText(
      SectionCard,
      'Category Performance',
    );
    expect(
      find.descendant(of: categoryCard, matching: find.text('₹530.00')),
      findsOneWidget,
    );
  });

  testWidgets('empty data renders honest empty states with no invented '
      'figures', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpReports(tester);
    await tester.pumpAndSettle();

    expect(find.text('No sales recorded in this window'), findsOneWidget);
    expect(find.text('No expenses recorded in this range'), findsOneWidget);
    expect(find.text('No products sold in this range'), findsOneWidget);
    // The category card shows its own honest empty state.
    expect(find.text('No sales recorded in this range'), findsOneWidget);

    final amounts = RegExp(r'\d[\d,]*\.\d{2}');
    final currencies = RegExp(r'[₹$€£]');
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ReportsPage),
        matching: find.byType(Text),
      ),
    );
    for (final text in texts) {
      expect(
        text.data,
        isNot(matches(amounts)),
        reason: 'no fake amounts: ${text.data}',
      );
      expect(
        text.data,
        isNot(matches(currencies)),
        reason: 'no fake currency: ${text.data}',
      );
    }
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('shows the branded loading state while data is in flight', (
    tester,
  ) async {
    final orders = FakeOrdersRepository()..ordersGate = Completer<void>();
    final container = await _pumpReports(tester, orders: orders);
    await tester.pump();

    expect(find.text('Crunching your numbers…'), findsOneWidget);

    orders.ordersGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sales Overview'), findsOneWidget);
    expect(container.read(reportsControllerProvider).value, isNotNull);
  });

  testWidgets('errors surface a safe message and retry recovers', (
    tester,
  ) async {
    final orders = FakeOrdersRepository()..ordersError = Exception('boom');
    await _pumpReports(tester, orders: orders);
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    orders.ordersError = null;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsNothing);
    expect(find.text('Sales Overview'), findsOneWidget);
  });

  testWidgets('switching the range preset recomputes every section', (
    tester,
  ) async {
    final world = await _seededWorld();
    final orders = world.$1;
    orders.add(
      receiptNumber: 'R-003',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 40000,
      items: [_item('Old Chai', price: 40000, productId: 'product-1')],
    );
    await _pumpReports(
      tester,
      orders: orders,
      inventory: world.$2,
      expenses: world.$3,
    );
    await tester.pumpAndSettle();

    expect(find.text('₹930.00'), findsOneWidget);

    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();

    expect(find.text('₹930.00'), findsNothing);
    expect(find.text('₹530.00'), findsOneWidget);
  });

  testWidgets('a custom range applied through the controller filters the '
      'page', (tester) async {
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'R-in',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 12)),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 25000,
      items: [_item('Chai', price: 25000)],
    );
    orders.add(
      receiptNumber: 'R-out',
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 40000,
      items: [_item('Latte', price: 40000)],
    );
    final container = await _pumpReports(tester, orders: orders);
    await tester.pumpAndSettle();

    expect(find.text('₹650.00'), findsOneWidget);

    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 13));
    final to = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 11));
    container.read(reportsRangeProvider.notifier).setCustomRange(from, to);
    await tester.pumpAndSettle();

    expect(find.text('₹650.00'), findsNothing);
    expect(find.text('₹250.00'), findsNWidgets(2));
  });

  testWidgets('fully resolved zero profit shows an honest ₹0.00', (
    tester,
  ) async {
    final inventory = FakeInventoryRepository();
    final category = await inventory.createCategory('Beverages');
    await inventory.createProduct(
      categoryId: category.id,
      name: 'Chai',
      sellingPricePaise: 3000,
      costPricePaise: 3000,
      stockQuantity: 10,
      isActive: true,
    );
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'R-001',
      createdAt: DateTime.now().toUtc(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 3000,
      items: [_item('Chai', price: 3000, productId: 'product-1')],
    );

    await _pumpReports(tester, orders: orders, inventory: inventory);
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('₹0.00'), findsNWidgets(3));
    expect(find.text('Add cost prices to see profit'), findsNothing);
  });

  testWidgets('a lossy range renders a signed net profit', (tester) async {
    final inventory = FakeInventoryRepository();
    final category = await inventory.createCategory('Beverages');
    await inventory.createProduct(
      categoryId: category.id,
      name: 'Chai',
      sellingPricePaise: 3000,
      costPricePaise: 1000,
      stockQuantity: 10,
      isActive: true,
    );
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'R-001',
      createdAt: DateTime.now().toUtc(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 3000,
      items: [_item('Chai', price: 3000, productId: 'product-1')],
    );
    final expenses = FakeExpensesRepository();
    expenses.seed(
      name: 'Shop Rent',
      amountPaise: 5000,
      category: ExpenseCategory.rent,
      paymentMethod: PaymentMethod.bank,
      expenseDate: DateTime.now().toUtc(),
    );

    await _pumpReports(
      tester,
      orders: orders,
      inventory: inventory,
      expenses: expenses,
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('-₹30.00'), findsOneWidget);
  });

  testWidgets('lays out without overflow at 360px', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -2200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow on a wide desktop viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final world = await _seededWorld();
    await _pumpReports(
      tester,
      orders: world.$1,
      inventory: world.$2,
      expenses: world.$3,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sales Overview'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
