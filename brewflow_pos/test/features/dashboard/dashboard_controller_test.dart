import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

void main() {
  DateTime localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime today() => localDay(DateTime.now());

  DateTime daysAgo(int days) =>
      localDay(today().subtract(Duration(days: days)));

  FakeOrdersRepository ordersWith(
    List<(int daysAgo, int totalPaise, PaymentMethod, List<OrderItem>)> seeds,
  ) {
    final orders = FakeOrdersRepository();
    for (var i = 0; i < seeds.length; i++) {
      final (age, total, method, items) = seeds[i];
      orders.add(
        receiptNumber: 'BF-${100 + i}',
        createdAt: daysAgo(age),
        paymentMethod: method,
        totalPaise: total,
        items: items,
      );
    }
    return orders;
  }

  ProviderContainer buildContainer({
    FakeOrdersRepository? orders,
    FakeInventoryRepository? inventory,
    FakeCustomerLedgerRepository? ledger,
    FakeSettingsRepository? settings,
  }) {
    final container = ProviderContainer(
      overrides: [
        ordersRepositoryProvider.overrideWithValue(
          orders ?? FakeOrdersRepository(),
        ),
        inventoryRepositoryProvider.overrideWithValue(
          inventory ?? FakeInventoryRepository(),
        ),
        customerLedgerRepositoryProvider.overrideWithValue(
          ledger ?? FakeCustomerLedgerRepository(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          settings ?? FakeSettingsRepository(),
        ),
        staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Waits for the dashboard build to settle and returns its snapshot.
  /// Polls state instead of reading `.future`, which never completes when a
  /// build errors (Riverpod 3 pitfall).
  Future<DashboardSnapshot> settle(ProviderContainer container) async {
    await _waitFor(
      () => container.read(dashboardControllerProvider) is AsyncData,
    );
    return container.read(dashboardControllerProvider).requireValue;
  }

  Future<DashboardSnapshot> refresh(ProviderContainer container) async {
    container.invalidate(dashboardControllerProvider);
    return settle(container);
  }

  test('empty repositories produce an honest empty snapshot', () async {
    final container = buildContainer();

    final snapshot = await settle(container);
    expect(snapshot.daySalesPaise, 0);
    expect(snapshot.dayProfitPaise, isNull);
    expect(snapshot.totalBills, 0);
    expect(snapshot.dayOrderCount, 0);
    expect(snapshot.dayItemCount, 0);
    expect(snapshot.paymentSplitPaise, isEmpty);
    expect(snapshot.weeklySalesPaise, List.filled(7, 0));
    expect(snapshot.recentBills, isEmpty);
    expect(snapshot.productCount, 0);
    expect(snapshot.lowStockCount, 0);
    expect(snapshot.outOfStockCount, 0);
    expect(snapshot.categoryCount, 0);
    expect(snapshot.dueCustomers.dueCustomerCount, 0);
    expect(snapshot.dueCustomers.totalOutstandingPaise, 0);
  });

  test('selecting a past date shifts the day KPIs and payment split', () async {
    final container = buildContainer(
      orders: ordersWith([
        (0, 100000, PaymentMethod.cash, [exampleItem()]),
        (1, 50000, PaymentMethod.upi, [exampleItem()]),
        (7, 80000, PaymentMethod.bank, [exampleItem()]),
      ]),
    );
    await settle(container);
    container.read(dashboardDateProvider.notifier).select(daysAgo(1));

    final snapshot = await refresh(container);
    expect(snapshot.daySalesPaise, 50000);
    expect(snapshot.dayOrderCount, 1);
    expect(snapshot.dayItemCount, 1);
    expect(snapshot.paymentSplitPaise, {PaymentMethod.upi: 50000});
  });

  test('credit sales count in day revenue but stay out of the split', () async {
    final orders = ordersWith([
      (0, 100000, PaymentMethod.cash, [exampleItem()]),
    ]);
    orders.add(
      receiptNumber: 'BF-901',
      createdAt: today(),
      paymentStatus: PaymentStatus.notPaid,
      totalPaise: 60000,
      items: [exampleItem()],
    );
    final container = buildContainer(orders: orders);

    final snapshot = await settle(container);
    expect(snapshot.daySalesPaise, 160000);
    expect(snapshot.dayOrderCount, 2);
    expect(snapshot.paymentSplitPaise, {PaymentMethod.cash: 100000});
  });

  test('profit uses recorded cost prices for the selected day', () async {
    final inventory = FakeInventoryRepository();
    await inventory.createCategory('Drinks');
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Filter Coffee',
      sellingPricePaise: 1000,
      costPricePaise: 400,
      stockQuantity: 10,
      isActive: true,
    );
    final container = buildContainer(
      orders: ordersWith([
        (
          0,
          2000,
          PaymentMethod.cash,
          [exampleItem(productId: 'product-1', quantity: 2)],
        ),
      ]),
      inventory: inventory,
    );

    final snapshot = await settle(container);
    expect(snapshot.dayProfitPaise, 1200);
  });

  test('profit is null when no sold line resolves to a cost price', () async {
    final inventory = FakeInventoryRepository();
    await inventory.createCategory('Drinks');
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Filter Coffee',
      sellingPricePaise: 1000,
      stockQuantity: 10,
      isActive: true,
    );
    final container = buildContainer(
      orders: ordersWith([
        (0, 1000, PaymentMethod.cash, [exampleItem(productId: 'product-1')]),
      ]),
      inventory: inventory,
    );

    final snapshot = await settle(container);
    expect(snapshot.dayProfitPaise, isNull);
  });

  test('weekly sales buckets orders into their local days', () async {
    final container = buildContainer(
      orders: ordersWith([
        (0, 1000, PaymentMethod.cash, [exampleItem()]),
        (3, 2000, PaymentMethod.upi, [exampleItem()]),
        (6, 3000, PaymentMethod.bank, [exampleItem()]),
      ]),
    );

    final snapshot = await settle(container);
    expect(snapshot.weeklySalesPaise, [3000, 0, 0, 2000, 0, 0, 1000]);
  });

  test('recent bills are the five newest overall', () async {
    final container = buildContainer(
      orders: ordersWith([
        for (var i = 0; i < 6; i++)
          (i, 1000 * (i + 1), PaymentMethod.cash, [exampleItem()]),
      ]),
    );

    final snapshot = await settle(container);
    expect(snapshot.recentBills.length, 5);
    expect(snapshot.recentBills.first.receiptNumber, 'BF-100');
    expect(snapshot.recentBills.last.totalPaise, 5000);
  });

  test('inventory counts and alerts reflect real products', () async {
    final inventory = FakeInventoryRepository();
    await inventory.createCategory('Drinks');
    await inventory.createCategory('Snacks');
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Low Stock Item',
      sellingPricePaise: 500,
      stockQuantity: 3,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Out Item',
      sellingPricePaise: 500,
      stockQuantity: 0,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: 'category-2',
      name: 'Healthy Item',
      sellingPricePaise: 500,
      stockQuantity: 10,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: 'category-2',
      name: 'Hidden Item',
      sellingPricePaise: 500,
      stockQuantity: 2,
      isActive: false,
    );
    final container = buildContainer(inventory: inventory);

    final snapshot = await settle(container);
    expect(snapshot.productCount, 4);
    expect(snapshot.categoryCount, 2);
    expect(snapshot.lowStockCount, 1);
    expect(snapshot.outOfStockCount, 1);
  });

  test('the low-stock threshold comes from the saved shop settings', () async {
    final inventory = FakeInventoryRepository();
    await inventory.createCategory('Drinks');
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Mid Stock Item',
      sellingPricePaise: 500,
      stockQuantity: 7,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Nearly Out Item',
      sellingPricePaise: 500,
      stockQuantity: 2,
      isActive: true,
    );
    final settings = FakeSettingsRepository()
      ..stored = const ShopSettings(
        shopName: 'Tea Kadai',
        lowStockThreshold: 10,
      );
    final container = buildContainer(inventory: inventory, settings: settings);

    final snapshot = await settle(container);
    expect(snapshot.lowStockThreshold, 10);
    expect(snapshot.lowStockCount, 2);
  });

  test('a higher saved threshold is honored instead of the default', () async {
    final inventory = FakeInventoryRepository();
    await inventory.createCategory('Drinks');
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Plenty Left',
      sellingPricePaise: 500,
      stockQuantity: 5,
      isActive: true,
    );
    final settings = FakeSettingsRepository()
      ..stored = const ShopSettings(
        shopName: 'Tea Kadai',
        lowStockThreshold: 3,
      );
    final container = buildContainer(inventory: inventory, settings: settings);

    final snapshot = await settle(container);
    expect(snapshot.lowStockThreshold, 3);
    expect(snapshot.lowStockCount, 0);
  });

  test('total bills counts every completed sale regardless of day', () async {
    final container = buildContainer(
      orders: ordersWith([
        (0, 1000, PaymentMethod.cash, [exampleItem()]),
        (3, 2000, PaymentMethod.upi, [exampleItem()]),
        (9, 3000, PaymentMethod.bank, [exampleItem()]),
        (30, 4000, PaymentMethod.cash, [exampleItem()]),
      ]),
    );

    final snapshot = await settle(container);
    expect(snapshot.totalBills, 4);
  });

  test('orders failure surfaces as a safe AsyncError', () async {
    final orders = FakeOrdersRepository()
      ..ordersError = const UnexpectedOrdersFailure();
    final container = buildContainer(orders: orders);

    await _waitFor(() => container.read(dashboardControllerProvider).hasError);
    final state = container.read(dashboardControllerProvider);
    expect(state.error, isA<UnexpectedOrdersFailure>());
    expect(
      dashboardErrorMessage(const UnexpectedOrdersFailure()),
      'Something went wrong. Please try again.',
    );
  });

  test('inventory failure surfaces as a safe AsyncError', () async {
    final inventory = FakeInventoryRepository()..loadError = Exception('db');
    final container = buildContainer(inventory: inventory);

    await _waitFor(() => container.read(dashboardControllerProvider).hasError);
    expect(
      container.read(dashboardControllerProvider).error,
      isA<UnexpectedOrdersFailure>(),
    );
  });

  test('recovering after an error rebuilds the snapshot', () async {
    final orders = FakeOrdersRepository()..ordersError = Exception('db');
    final container = buildContainer(orders: orders);
    await _waitFor(() => container.read(dashboardControllerProvider).hasError);

    orders.ordersError = null;
    final snapshot = await refresh(container);
    expect(snapshot.dayOrderCount, 0);
  });

  group('due reminders', () {
    FakeLedgerBill bill({
      required String id,
      required String customerId,
      required int totalPaise,
    }) => FakeLedgerBill(
      id: id,
      customerId: customerId,
      receiptNumber: 'BF-$id',
      createdAt: DateTime.utc(2026, 1, 1),
      totalPaise: totalPaise,
    );

    test(
      'aggregates customers with outstanding dues into the snapshot',
      () async {
        final ledger = FakeCustomerLedgerRepository();
        ledger.bills.addAll([
          bill(id: 's1', customerId: 'c1', totalPaise: 10000),
          bill(id: 's2', customerId: 'c2', totalPaise: 5000),
          bill(id: 's3', customerId: 'c2', totalPaise: 20000),
        ]);
        await ledger.recordPayment(
          customerId: 'c2',
          saleId: 's3',
          amountPaise: 5000,
          paymentMethod: PaymentMethod.cash,
        );

        final snapshot = await settle(buildContainer(ledger: ledger));
        expect(snapshot.dueCustomers.dueCustomerCount, 2);
        expect(snapshot.dueCustomers.totalOutstandingPaise, 30000);
      },
    );

    test('fully settled customers do not count as due', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.add(bill(id: 's1', customerId: 'c1', totalPaise: 10000));
      await ledger.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 10000,
        paymentMethod: PaymentMethod.upi,
      );

      final snapshot = await settle(buildContainer(ledger: ledger));
      expect(snapshot.dueCustomers.dueCustomerCount, 0);
      expect(snapshot.dueCustomers.totalOutstandingPaise, 0);
    });

    test('ledger failure surfaces as a safe AsyncError', () async {
      final ledger = FakeCustomerLedgerRepository()
        ..dueSummaryError = const UnexpectedLedgerFailure();
      final container = buildContainer(ledger: ledger);

      await _waitFor(
        () => container.read(dashboardControllerProvider).hasError,
      );
      expect(
        container.read(dashboardControllerProvider).error,
        isA<UnexpectedLedgerFailure>(),
      );
      expect(
        dashboardErrorMessage(const UnexpectedLedgerFailure()),
        'Something went wrong. Please try again.',
      );
    });
  });
}

/// A minimal line for seeding orders.
OrderItem exampleItem({String? productId, int quantity = 1}) => OrderItem(
  productName: 'Filter Coffee',
  sku: 'SKU-1',
  unitPricePaise: 1000,
  quantity: quantity,
  lineTotalPaise: 1000 * quantity,
  productId: productId,
);

/// Polls microtasks until [condition] holds (test-side, never blocks).
Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition not met within the poll budget.');
}
