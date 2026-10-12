import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/domain/payment_attribution.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/test_providers.dart';

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
        // Shop-scoped dashboard reads resolve their scope from the signed-in
        // profile, so the fixture must declare the owner session explicitly.
        ...businessScopeOverrides(),
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
    expect(snapshot.dayDueCollectedPaise, 0);
    expect(snapshot.dayDueCollections, isEmpty);
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

  test('credit sales are reported as Not Paid and still reconcile', () async {
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
    // The credit sale was previously dropped from the split entirely; it is
    // now surfaced as the unpaid total for the selected day.
    expect(snapshot.dayNotPaidPaise, 60000);
    // Cash + UPI + Not Paid must reconcile with the day total.
    final cash = snapshot.paymentSplitPaise[PaymentMethod.cash] ?? 0;
    final upi = snapshot.paymentSplitPaise[PaymentMethod.upi] ?? 0;
    expect(cash + upi + snapshot.dayNotPaidPaise, snapshot.daySalesPaise);
  });

  test('a split sale is attributed from its legs, not the NULL header', () {
    // A split sale is PAID with payment_method = NULL, so it used to vanish
    // from the day split and break the summary's arithmetic.
    final orders = ordersWith([]);
    orders.add(
      receiptNumber: 'BF-902',
      createdAt: today(),
      paymentStatus: PaymentStatus.paid,
      totalPaise: 30000,
      items: [exampleItem()],
      splitLegs: {PaymentMethod.cash: 12000, PaymentMethod.upi: 18000},
    );

    final attribution = attributePayments(
      orders.storedSummaries,
      legsBySaleId: {
        for (final order in orders.storedSummaries)
          if (orders.paymentLegs[order.id] != null)
            order.id: orders.paymentLegs[order.id]!,
      },
    );
    expect(attribution.cashPaise, 12000);
    expect(attribution.upiPaise, 18000);
    expect(attribution.notPaidPaise, 0);
    expect(attribution.totalPaise, 30000);
  });

  test('legacy BANK sales fold into Cash and never become Not Paid', () async {
    final orders = ordersWith([
      (0, 100000, PaymentMethod.bank, [exampleItem()]),
    ]);
    final container = buildContainer(orders: orders);

    final snapshot = await settle(container);
    expect(snapshot.daySalesPaise, 100000);
    // BANK is not a current category...
    expect(snapshot.paymentSplitPaise.containsKey(PaymentMethod.bank), isFalse);
    // ...its settled money is in Cash, not in Not Paid.
    expect(snapshot.paymentSplitPaise, {PaymentMethod.cash: 100000});
    expect(snapshot.dayNotPaidPaise, 0);
  });

  group('due collections', () {
    FakeLedgerBill dueBill({
      required String id,
      required String customerId,
      required int totalPaise,
      String? shopId,
      String? customerName,
    }) => FakeLedgerBill(
      id: id,
      customerId: customerId,
      receiptNumber: 'BF-$id',
      createdAt: DateTime.utc(2026, 1, 1),
      totalPaise: totalPaise,
      shopId: shopId ?? kTestCafeShopId,
      customerName: customerName,
    );

    /// A UTC instant for [hour] o'clock on [day] (a local-midnight day).
    DateTime atHour(DateTime day, int hour) =>
        DateTime(day.year, day.month, day.day, hour).toUtc();

    test(
      'today\'s ledger payments total into the card, newest first',
      () async {
        final ledger = FakeCustomerLedgerRepository();
        ledger.bills.addAll([
          dueBill(
            id: 's1',
            customerId: 'c1',
            totalPaise: 10000,
            customerName: 'Asha',
          ),
          dueBill(
            id: 's2',
            customerId: 'c2',
            totalPaise: 20000,
            customerName: 'Bala',
          ),
        ]);
        final day = today();
        ledger.seedPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 4000,
          paymentMethod: PaymentMethod.cash,
          paidAt: atHour(day, 9),
        );
        ledger.seedPayment(
          customerId: 'c2',
          saleId: 's2',
          amountPaise: 7000,
          paymentMethod: PaymentMethod.upi,
          paidAt: atHour(day, 18),
        );

        final snapshot = await settle(buildContainer(ledger: ledger));

        expect(snapshot.dayDueCollectedPaise, 11000);
        expect(snapshot.dayDueCollections.length, 2);
        expect(snapshot.dayDueCollections.first.customerName, 'Bala');
        expect(snapshot.dayDueCollections.first.amountPaise, 7000);
        expect(
          snapshot.dayDueCollections.first.paymentMethod,
          PaymentMethod.upi,
        );
        expect(snapshot.dayDueCollections.last.customerName, 'Asha');
        expect(snapshot.dayDueCollections.last.amountPaise, 4000);
        expect(
          snapshot.dayDueCollections.last.paymentMethod,
          PaymentMethod.cash,
        );
        // Single-shop reads carry no business label.
        expect(
          snapshot.dayDueCollections.every((c) => c.shopLabel == null),
          isTrue,
        );
      },
    );

    test('day bounds are inclusive on both ends', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.add(dueBill(id: 's1', customerId: 'c1', totalPaise: 50000));
      final day = today();
      final from = day.toUtc();
      final to = DateTime(day.year, day.month, day.day)
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1))
          .toUtc();
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 1000,
        paymentMethod: PaymentMethod.cash,
        paidAt: from,
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 2000,
        paymentMethod: PaymentMethod.upi,
        paidAt: to,
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 4000,
        paymentMethod: PaymentMethod.cash,
        paidAt: from.subtract(const Duration(microseconds: 1)),
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 8000,
        paymentMethod: PaymentMethod.cash,
        paidAt: to.add(const Duration(microseconds: 1)),
      );

      final snapshot = await settle(buildContainer(ledger: ledger));

      expect(snapshot.dayDueCollectedPaise, 3000);
      expect(snapshot.dayDueCollections.length, 2);
    });

    test('selecting a past date shifts due collections to that day', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.add(dueBill(id: 's1', customerId: 'c1', totalPaise: 50000));
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 9000,
        paymentMethod: PaymentMethod.cash,
        paidAt: atHour(today(), 10),
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 5000,
        paymentMethod: PaymentMethod.upi,
        paidAt: atHour(daysAgo(1), 10),
      );
      final container = buildContainer(ledger: ledger);

      var snapshot = await settle(container);
      expect(snapshot.dayDueCollectedPaise, 9000);
      expect(snapshot.dayDueCollections.length, 1);

      container.read(dashboardDateProvider.notifier).select(daysAgo(1));
      snapshot = await refresh(container);
      expect(snapshot.dayDueCollectedPaise, 5000);
      expect(snapshot.dayDueCollections.length, 1);
      expect(
        snapshot.dayDueCollections.single.paymentMethod,
        PaymentMethod.upi,
      );
    });

    test('collections are scoped to the signed-in shop', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.addAll([
        dueBill(
          id: 's1',
          customerId: 'c1',
          totalPaise: 10000,
          shopId: kTestCafeShopId,
          customerName: 'Asha',
        ),
        dueBill(
          id: 's2',
          customerId: 'c2',
          totalPaise: 20000,
          shopId: kTestFoodTruckShopId,
          customerName: 'Bala',
        ),
      ]);
      final day = today();
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 4000,
        paymentMethod: PaymentMethod.cash,
        paidAt: atHour(day, 10),
      );
      ledger.seedPayment(
        customerId: 'c2',
        saleId: 's2',
        amountPaise: 9000,
        paymentMethod: PaymentMethod.upi,
        paidAt: atHour(day, 11),
      );

      final snapshot = await settle(buildContainer(ledger: ledger));

      expect(snapshot.dayDueCollectedPaise, 4000);
      expect(snapshot.dayDueCollections.length, 1);
      expect(snapshot.dayDueCollections.single.customerName, 'Asha');
    });

    test('combined view labels each collection with its business', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.add(
        dueBill(
          id: 's1',
          customerId: 'c1',
          totalPaise: 10000,
          shopId: kTestCafeShopId,
          customerName: 'Asha',
        ),
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 4000,
        paymentMethod: PaymentMethod.cash,
        paidAt: atHour(today(), 10),
      );
      final container = buildContainer(ledger: ledger);
      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.all);

      final snapshot = await refresh(container);

      expect(snapshot.dayDueCollectedPaise, 4000);
      expect(snapshot.dayDueCollections.single.shopLabel, 'Cafe');
    });

    test('reversed payments never count (void semantics)', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.add(dueBill(id: 's1', customerId: 'c1', totalPaise: 10000));
      final day = today();
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 6000,
        paymentMethod: PaymentMethod.cash,
        paidAt: atHour(day, 10),
        reversed: true,
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 2500,
        paymentMethod: PaymentMethod.upi,
        paidAt: atHour(day, 11),
      );

      final snapshot = await settle(buildContainer(ledger: ledger));

      expect(snapshot.dayDueCollectedPaise, 2500);
      expect(snapshot.dayDueCollections.length, 1);
    });

    test('collections on opening-balance dues count', () async {
      final ledger = FakeCustomerLedgerRepository();
      ledger.bills.add(
        FakeLedgerBill(
          id: 'opening-1',
          customerId: 'c1',
          receiptNumber: 'BF-9001',
          createdAt: DateTime.utc(2026, 1, 1),
          totalPaise: 5000,
          shopId: kTestCafeShopId,
          customerName: 'Asha',
          isOpeningBalance: true,
        ),
      );
      ledger.seedPayment(
        customerId: 'c1',
        saleId: 'opening-1',
        amountPaise: 5000,
        paymentMethod: PaymentMethod.upi,
        paidAt: atHour(today(), 11),
      );

      final snapshot = await settle(buildContainer(ledger: ledger));

      expect(snapshot.dayDueCollectedPaise, 5000);
      expect(snapshot.dayDueCollections.single.customerName, 'Asha');
    });

    test('counter sales without ledger payments collect nothing', () async {
      final container = buildContainer(
        orders: ordersWith([
          (0, 100000, PaymentMethod.cash, [exampleItem()]),
        ]),
      );

      final snapshot = await settle(container);

      expect(snapshot.daySalesPaise, 100000);
      expect(snapshot.dayDueCollectedPaise, 0);
      expect(snapshot.dayDueCollections, isEmpty);
    });

    test('due-collections failure surfaces as a safe AsyncError', () async {
      final ledger = FakeCustomerLedgerRepository()
        ..dueCollectionsError = const UnexpectedLedgerFailure();
      final container = buildContainer(ledger: ledger);

      await _waitFor(
        () => container.read(dashboardControllerProvider).hasError,
      );
      expect(
        container.read(dashboardControllerProvider).error,
        isA<UnexpectedLedgerFailure>(),
      );
    });
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

  group('day bills and items', () {
    OrderItem variantItem(
      String product,
      String variant, {
      int price = 5000,
      int quantity = 1,
    }) => OrderItem(
      productName: product,
      variantName: variant,
      variantId: 'v-$variant',
      unitPricePaise: price,
      quantity: quantity,
      lineTotalPaise: price * quantity,
      productId: 'product-1',
    );

    DateTime atHour(DateTime day, int hour) => day.add(Duration(hours: hour));

    test('dayBills lists the selected day newest first', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'BF-OLD',
        createdAt: daysAgo(1),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 5000,
        items: [exampleItem()],
        shopId: kTestCafeShopId,
      );
      orders.add(
        receiptNumber: 'BF-1',
        createdAt: atHour(today(), 9),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [exampleItem(quantity: 3)],
        shopId: kTestCafeShopId,
      );
      orders.add(
        receiptNumber: 'BF-2',
        createdAt: atHour(today(), 18),
        paymentMethod: PaymentMethod.upi,
        totalPaise: 7000,
        items: [exampleItem()],
        shopId: kTestCafeShopId,
      );

      final snapshot = await settle(buildContainer(orders: orders));

      expect(snapshot.dayBills.map((b) => b.receiptNumber).toList(), [
        'BF-2',
        'BF-1',
      ]);
      expect(snapshot.dayBills.first.totalPaise, 7000);
      expect(snapshot.dayBills.first.paymentMethod, PaymentMethod.upi);
      expect(snapshot.dayBills.first.itemCount, 1);
      expect(snapshot.dayBills.last.itemCount, 3);
    });

    test('selecting a past date shifts dayBills to that day', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'BF-TODAY',
        createdAt: atHour(today(), 10),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [exampleItem()],
        shopId: kTestCafeShopId,
      );
      orders.add(
        receiptNumber: 'BF-YESTERDAY',
        createdAt: atHour(daysAgo(1), 10),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 9000,
        items: [exampleItem()],
        shopId: kTestCafeShopId,
      );
      final container = buildContainer(orders: orders);

      var snapshot = await settle(container);
      expect(snapshot.dayBills.map((b) => b.receiptNumber).toList(), [
        'BF-TODAY',
      ]);

      container.read(dashboardDateProvider.notifier).select(daysAgo(1));
      snapshot = await refresh(container);
      expect(snapshot.dayBills.map((b) => b.receiptNumber).toList(), [
        'BF-YESTERDAY',
      ]);
    });

    test('dayBills are scoped to the signed-in shop', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'BF-CAFE',
        createdAt: atHour(today(), 10),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [exampleItem()],
        shopId: kTestCafeShopId,
      );
      orders.add(
        receiptNumber: 'FT-1',
        createdAt: atHour(today(), 11),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 8000,
        items: [exampleItem()],
        shopId: kTestFoodTruckShopId,
      );

      final snapshot = await settle(buildContainer(orders: orders));

      expect(snapshot.dayBills.map((b) => b.receiptNumber).toList(), [
        'BF-CAFE',
      ]);
    });

    test(
      'dayItemBreakdown aggregates by product and variant, revenue first',
      () async {
        final orders = FakeOrdersRepository();
        orders.add(
          receiptNumber: 'BF-1',
          createdAt: atHour(today(), 9),
          paymentMethod: PaymentMethod.cash,
          totalPaise: 11000,
          items: [variantItem('Maggi', 'Cheese', quantity: 2), exampleItem()],
          shopId: kTestCafeShopId,
        );
        orders.add(
          receiptNumber: 'BF-2',
          createdAt: atHour(today(), 18),
          paymentMethod: PaymentMethod.upi,
          totalPaise: 17000,
          items: [
            variantItem('Maggi', 'Cheese'),
            variantItem('Maggi', 'Plain', price: 4000, quantity: 3),
          ],
          shopId: kTestCafeShopId,
        );
        final container = buildContainer(orders: orders);
        await settle(container);

        final rows = await container
            .read(dashboardControllerProvider.notifier)
            .dayItemBreakdown();

        // Same product, two variants plus the plain line: three rows.
        expect(rows.map((r) => r.displayName).toList(), [
          'Maggi — Cheese',
          'Maggi — Plain',
          'Filter Coffee',
        ]);
        expect(rows[0].unitsSold, 3);
        expect(rows[0].revenuePaise, 15000);
        expect(rows[1].unitsSold, 3);
        expect(rows[1].revenuePaise, 12000);
        expect(rows[2].unitsSold, 1);
        expect(rows[2].revenuePaise, 1000);
      },
    );

    test(
      'dayItemBreakdown is empty without sales and ignores other days',
      () async {
        final orders = FakeOrdersRepository();
        orders.add(
          receiptNumber: 'BF-OLD',
          createdAt: atHour(daysAgo(2), 10),
          paymentMethod: PaymentMethod.cash,
          totalPaise: 3000,
          items: [exampleItem()],
          shopId: kTestCafeShopId,
        );
        final container = buildContainer(orders: orders);
        await settle(container);

        final rows = await container
            .read(dashboardControllerProvider.notifier)
            .dayItemBreakdown();
        expect(rows, isEmpty);
      },
    );

    test('dayItemBreakdown respects the shop scope', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'BF-CAFE',
        createdAt: atHour(today(), 10),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [exampleItem(quantity: 3)],
        shopId: kTestCafeShopId,
      );
      orders.add(
        receiptNumber: 'FT-1',
        createdAt: atHour(today(), 11),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 8000,
        items: [exampleItem(quantity: 8)],
        shopId: kTestFoodTruckShopId,
      );
      final container = buildContainer(orders: orders);
      await settle(container);

      final rows = await container
          .read(dashboardControllerProvider.notifier)
          .dayItemBreakdown();
      expect(rows.length, 1);
      expect(rows.single.unitsSold, 3);
      expect(rows.single.revenuePaise, 3000);
    });

    test('dashboardDayItemsProvider serves the breakdown lazily', () async {
      final orders = FakeOrdersRepository();
      orders.add(
        receiptNumber: 'BF-1',
        createdAt: atHour(today(), 10),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [exampleItem(quantity: 3)],
        shopId: kTestCafeShopId,
      );
      final container = buildContainer(orders: orders);
      await settle(container);

      // The snapshot itself carries no item rows: they load on demand.
      expect(
        container.read(dashboardControllerProvider).requireValue.dayItemCount,
        3,
      );
      final rows = await container.read(dashboardDayItemsProvider.future);
      expect(rows.single.displayName, 'Filter Coffee');
      expect(rows.single.unitsSold, 3);
      expect(rows.single.revenuePaise, 3000);
    });

    test('dayItemBreakdown surfaces order failures safely', () async {
      final orders = FakeOrdersRepository()..detailError = Exception('db');
      orders.add(
        receiptNumber: 'BF-1',
        createdAt: atHour(today(), 10),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [exampleItem()],
        shopId: kTestCafeShopId,
      );
      final container = buildContainer(orders: orders);
      await settle(container);

      await expectLater(
        container.read(dashboardControllerProvider.notifier).dayItemBreakdown(),
        throwsA(isA<UnexpectedOrdersFailure>()),
      );
    });
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
