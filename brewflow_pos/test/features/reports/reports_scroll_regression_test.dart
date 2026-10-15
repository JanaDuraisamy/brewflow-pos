import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
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

import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_daily_closing_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reports scroll-position regression tests.
///
/// Every sync cycle (30 s background, 2 s post-mutation fast-sync, manual
/// "Sync now") and every local mutation invalidates [reportsControllerProvider]
/// to keep figures live. Those reloads must never flash a full-screen loader
/// nor reset the user's scroll position; the same holds while a reload is in
/// flight after a range change, and scroll must restore after an error
/// recovers. The content [ListView]s keep their data through reloads
/// (`skipLoadingOnRefresh`/`skipLoadingOnReload`) and carry stable
/// [PageStorageKey]s so a remount restores the offset.
/// ---------------------------------------------------------------------------

OrderItem _item(String name, {int price = 1500}) => OrderItem(
  productName: name,
  unitPricePaise: price,
  quantity: 1,
  lineTotalPaise: price,
  productId: null,
);

/// Pumps Reports on a short desktop viewport (800x600) so the content list
/// actually scrolls, with one sale + one expense seeding every section.
Future<ProviderContainer> _pumpScrolledReports(
  WidgetTester tester, {
  FakeOrdersRepository? orders,
  FakeExpensesRepository? expenses,
}) async {
  final now = DateTime.now();
  final seededOrders =
      orders ??
      (FakeOrdersRepository()..add(
        receiptNumber: 'R-001',
        createdAt: now.toUtc(),
        paymentMethod: PaymentMethod.cash,
        totalPaise: 3000,
        items: [_item('Chai', price: 3000)],
      ));
  final seededExpenses =
      expenses ??
      (FakeExpensesRepository()..seed(
        name: 'Shop Rent',
        amountPaise: 5000,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.cash,
        expenseDate: now.toUtc(),
      ));

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      ordersRepositoryProvider.overrideWithValue(seededOrders),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      expensesRepositoryProvider.overrideWithValue(seededExpenses),
      dailyClosingRepositoryProvider.overrideWithValue(
        FakeDailyClosingRepository(),
      ),
      ...businessScopeOverrides(),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReportsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Drags the report list to the bottom and returns the on-screen position of
/// the last card, proving the list actually scrolled.
Future<Offset> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -3000));
  await tester.pumpAndSettle();
  expect(find.text('Category Performance'), findsOneWidget);
  return tester.getTopLeft(find.text('Category Performance'));
}

void main() {
  testWidgets(
    'sync-style invalidation keeps data visible and preserves scroll',
    (tester) async {
      final container = await _pumpScrolledReports(tester);
      final before = await _scrollToBottom(tester);

      // What every sync cycle does (see invalidateDomainProviders).
      container.invalidate(reportsControllerProvider);
      await tester.pumpAndSettle();

      expect(
        find.text('Crunching your numbers…'),
        findsNothing,
        reason: 'reload must not flash the full-screen loader',
      );
      expect(find.text('Category Performance'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Category Performance')).dy,
        moreOrLessEquals(before.dy, epsilon: 1.0),
        reason: 'scroll position must survive a data reload',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('previous data stays visible while a range reload is in flight', (
    tester,
  ) async {
    final orders = FakeOrdersRepository();
    final now = DateTime.now();
    orders.add(
      receiptNumber: 'R-001',
      createdAt: now.toUtc(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 3000,
      items: [_item('Chai', price: 3000)],
    );
    final container = await _pumpScrolledReports(tester, orders: orders);
    await _scrollToBottom(tester);

    // Hold the next load open so the reload state is observable for a frame.
    orders.ordersGate = Completer<void>();
    container
        .read(reportsRangeProvider.notifier)
        .setPreset(OrdersDatePreset.last30);
    await tester.pump();

    expect(
      find.text('Crunching your numbers…'),
      findsNothing,
      reason: 'previous range data must cover the reload, no spinner flash',
    );
    expect(find.text('Category Performance'), findsOneWidget);

    orders.ordersGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Category Performance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll position restores after an error recovers', (
    tester,
  ) async {
    final orders = FakeOrdersRepository();
    final now = DateTime.now();
    orders.add(
      receiptNumber: 'R-001',
      createdAt: now.toUtc(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 3000,
      items: [_item('Chai', price: 3000)],
    );
    final container = await _pumpScrolledReports(tester, orders: orders);
    final before = await _scrollToBottom(tester);

    orders.ordersError = Exception('boom');
    container.invalidate(reportsControllerProvider);
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);

    orders.ordersError = null;
    container.invalidate(reportsControllerProvider);
    await tester.pumpAndSettle();

    expect(
      find.text('Crunching your numbers…'),
      findsNothing,
      reason: 'recovered data must render, not the loader',
    );
    expect(
      find.text('Category Performance'),
      findsOneWidget,
      reason: 'recovered list must restore the scrolled position',
    );
    expect(
      tester.getTopLeft(find.text('Category Performance')).dy,
      moreOrLessEquals(before.dy, epsilon: 1.0),
      reason: 'scroll position must restore after error recovery',
    );
    expect(tester.takeException(), isNull);
  });
}
