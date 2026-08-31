import 'dart:async';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/order_detail_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeOrdersRepository repository;

  setUp(() {
    repository = FakeOrdersRepository();
  });

  Widget app(FakeAuthRepository auth) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(repository),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
    ],
    child: const BrewFlowApp(),
  );

  Future<FakeAuthRepository> pumpAuthenticated(WidgetTester tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));
    fake.emit(_owner);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> goToOrders(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.orders);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  }

  /// Receipt text scoped to the table, so the search field's own text never
  /// collides with the row contents.
  Finder inTable(String text) =>
      find.descendant(of: find.byType(DataTable), matching: find.text(text));

  GoRouter routerOf(WidgetTester tester) {
    final element = tester.element(find.byType(Scaffold).first);
    return ProviderScope.containerOf(element).read(appRouterProvider);
  }

  void seedOrder({
    required String receipt,
    required DateTime createdAt,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    PaymentMethod payment = PaymentMethod.cash,
    int totalPaise = 24000,
    String? customerName,
    bool isVoided = false,
    List<OrderItem> items = const [
      OrderItem(
        productName: 'Filter Coffee',
        sku: 'FC-1',
        unitPricePaise: 12000,
        quantity: 2,
        lineTotalPaise: 24000,
      ),
    ],
  }) {
    repository.add(
      receiptNumber: receipt,
      createdAt: createdAt,
      paymentStatus: paymentStatus,
      paymentMethod: payment,
      totalPaise: totalPaise,
      items: items,
      customerName: customerName,
      isVoided: isVoided,
      voidedAt: isVoided ? createdAt : null,
    );
  }

  group('orders landing', () {
    testWidgets('shows the empty state when there is no history', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.byType(OrdersPage), findsOneWidget);
      expect(find.text('No orders yet'), findsOneWidget);
      expect(
        find.text('Completed sales from the counter will appear here.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders orders with persisted receipt, time, count, total '
        'and payment', (tester) async {
      final when = DateTime.utc(2026, 8, 10, 6, 30);
      seedOrder(
        receipt: 'BF-000042',
        createdAt: when,
        payment: PaymentMethod.upi,
        totalPaise: 45250,
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('BF-000042'), findsOneWidget);
      expect(find.text(formatDateTime(when)), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text(Money.formatPaise(45250)), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a Not paid badge for credit sales', (tester) async {
      seedOrder(
        receipt: 'BF-000043',
        createdAt: DateTime.utc(2026, 8, 11, 6, 30),
        paymentStatus: PaymentStatus.notPaid,
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('BF-000043'), findsOneWidget);
      expect(find.text('Not paid'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a Voided badge for voided sales', (tester) async {
      seedOrder(
        receipt: 'BF-000044',
        createdAt: DateTime.utc(2026, 8, 12, 6, 30),
        isVoided: true,
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(inTable('BF-000044'), findsOneWidget);
      expect(inTable('Voided'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the customer name and the walk-in label', (
      tester,
    ) async {
      seedOrder(
        receipt: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        customerName: 'Priya',
      );
      seedOrder(receipt: 'BF-000002', createdAt: DateTime.utc(2026, 1, 2));
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('Customer'), findsOneWidget);
      expect(inTable('Priya'), findsOneWidget);
      expect(inTable('Walk-in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search narrows by receipt number and product name', (
      tester,
    ) async {
      seedOrder(
        receipt: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        items: const [
          OrderItem(
            productName: 'Filter Coffee',
            unitPricePaise: 12000,
            quantity: 1,
            lineTotalPaise: 12000,
          ),
        ],
      );
      seedOrder(
        receipt: 'BF-000002',
        createdAt: DateTime.utc(2026, 1, 2),
        items: const [
          OrderItem(
            productName: 'Green Tea',
            unitPricePaise: 8000,
            quantity: 1,
            lineTotalPaise: 8000,
          ),
        ],
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('BF-000001'), findsOneWidget);
      expect(find.text('BF-000002'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'green tea');
      await tester.pumpAndSettle();
      expect(inTable('BF-000001'), findsNothing);
      expect(inTable('BF-000002'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'BF-000001');
      await tester.pumpAndSettle();
      expect(inTable('BF-000001'), findsOneWidget);
      expect(inTable('BF-000002'), findsNothing);
    });

    testWidgets('payment method filter narrows the list', (tester) async {
      seedOrder(
        receipt: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        payment: PaymentMethod.cash,
      );
      seedOrder(
        receipt: 'BF-000002',
        createdAt: DateTime.utc(2026, 1, 2),
        payment: PaymentMethod.upi,
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('BF-000001'), findsOneWidget);
      expect(find.text('BF-000002'), findsOneWidget);

      await tester.tap(find.text('All methods'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<PaymentMethod?>),
          matching: find.text('UPI'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BF-000002'), findsOneWidget);
      expect(find.text('BF-000001'), findsNothing);
    });

    testWidgets('date preset filter narrows to the selected range', (
      tester,
    ) async {
      final now = DateTime.now();
      seedOrder(
        receipt: 'BF-000001',
        createdAt: now.toUtc().subtract(const Duration(days: 10)),
      );
      seedOrder(receipt: 'BF-000002', createdAt: now.toUtc());
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('BF-000001'), findsOneWidget);
      expect(find.text('BF-000002'), findsOneWidget);

      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<OrdersDatePreset>),
          matching: find.text('Today'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BF-000002'), findsOneWidget);
      expect(find.text('BF-000001'), findsNothing);
    });

    testWidgets('clear filters restores the full history', (tester) async {
      seedOrder(
        receipt: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        payment: PaymentMethod.cash,
      );
      seedOrder(
        receipt: 'BF-000002',
        createdAt: DateTime.utc(2026, 1, 2),
        payment: PaymentMethod.upi,
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      await tester.enterText(find.byType(TextField), 'BF-000001');
      await tester.pumpAndSettle();
      expect(inTable('BF-000001'), findsOneWidget);
      expect(inTable('BF-000002'), findsNothing);

      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();
      expect(inTable('BF-000001'), findsOneWidget);
      expect(inTable('BF-000002'), findsOneWidget);
      expect(find.text('Clear Filters'), findsNothing);
    });

    testWidgets('filtered empty state offers clear filters', (tester) async {
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      await tester.enterText(find.byType(TextField), 'nothing matches');
      await tester.pumpAndSettle();
      expect(find.text('No orders match your filters'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear Filters'));
      await tester.pumpAndSettle();
      expect(find.text('No orders yet'), findsOneWidget);
    });

    testWidgets('load more appends the next page', (tester) async {
      for (var i = 1; i <= 55; i++) {
        seedOrder(
          receipt: 'BF-${i.toString().padLeft(6, '0')}',
          createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        );
      }
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(
        tester.widgetList(find.textContaining('BF-')).length,
        50,
        reason: 'first page only',
      );
      expect(find.text('BF-000055'), findsOneWidget);
      expect(find.text('BF-000001'), findsNothing);

      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();

      expect(tester.widgetList(find.textContaining('BF-')).length, 55);
      expect(find.text('BF-000001'), findsOneWidget);
      expect(find.text('Load More'), findsNothing);
    });

    testWidgets('shows a safe error state and recovers on retry', (
      tester,
    ) async {
      repository.ordersError = const UnexpectedOrdersFailure();
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.text('Could not load orders'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      repository.ordersError = null;
      seedOrder(receipt: 'BF-000001', createdAt: DateTime.utc(2026, 1, 1));
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('BF-000001'), findsOneWidget);
    });

    testWidgets('stays in a loading state until history resolves', (
      tester,
    ) async {
      await pumpAuthenticated(tester);

      // Gate only the orders feed: the dashboard landing page reads the same
      // repository, so it must settle before the gate is armed.
      repository.ordersGate = Completer<void>();
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.orders);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      repository.ordersGate!.complete();
      repository.ordersGate = null;
      await tester.pumpAndSettle();
      expect(find.text('No orders yet'), findsOneWidget);
    });
  });

  group('order detail', () {
    testWidgets('opens from a row and shows historical snapshot values', (
      tester,
    ) async {
      seedOrder(
        receipt: 'BF-000042',
        createdAt: DateTime.utc(2026, 8, 10, 6, 30),
        payment: PaymentMethod.bank,
        totalPaise: 32000,
        items: const [
          OrderItem(
            productName: 'Filter Coffee',
            sku: 'FC-1',
            unitPricePaise: 12000,
            quantity: 2,
            lineTotalPaise: 24000,
          ),
          OrderItem(
            productName: 'Green Tea',
            sku: 'GT-2',
            unitPricePaise: 8000,
            quantity: 1,
            lineTotalPaise: 8000,
          ),
        ],
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      await tester.tap(find.text('BF-000042'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailPage), findsOneWidget);
      expect(find.text('Order BF-000042'), findsOneWidget);
      expect(
        find.text(formatDateTime(DateTime.utc(2026, 8, 10, 6, 30))),
        findsOneWidget,
      );
      expect(find.text('Filter Coffee'), findsOneWidget);
      expect(find.text('SKU FC-1'), findsOneWidget);
      expect(find.text('₹120.00 × 2'), findsOneWidget);
      expect(find.text('₹240.00'), findsWidgets);
      expect(find.text('Green Tea'), findsOneWidget);
      expect(find.text('₹80.00 × 1'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail shows a Not paid badge for credit sales', (
      tester,
    ) async {
      seedOrder(
        receipt: 'BF-000043',
        createdAt: DateTime.utc(2026, 8, 11, 6, 30),
        paymentStatus: PaymentStatus.notPaid,
        customerName: 'Ravi',
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      await tester.tap(find.text('BF-000043'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailPage), findsOneWidget);
      expect(find.text('Order BF-000043'), findsOneWidget);
      expect(find.text('Not paid'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      expect(find.text('Ravi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail shows the customer name or the walk-in label', (
      tester,
    ) async {
      seedOrder(
        receipt: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        customerName: 'Priya',
      );
      seedOrder(receipt: 'BF-000002', createdAt: DateTime.utc(2026, 1, 2));
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      await tester.tap(find.text('BF-000001'));
      await tester.pumpAndSettle();
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Walk-in'), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BF-000002'));
      await tester.pumpAndSettle();
      expect(find.text('Walk-in'), findsOneWidget);
      expect(find.text('Priya'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('back navigation returns to the orders list', (tester) async {
      seedOrder(receipt: 'BF-000001', createdAt: DateTime.utc(2026, 1, 1));
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      await tester.tap(find.text('BF-000001'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetailPage), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailPage), findsNothing);
      expect(find.byType(OrdersPage), findsOneWidget);
      expect(
        routerOf(tester).routeInformationProvider.value.uri.path,
        AppRoutes.orders,
      );
    });

    testWidgets('a missing order shows a safe message', (tester) async {
      seedOrder(receipt: 'BF-000001', createdAt: DateTime.utc(2026, 1, 1));
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.goNamed('orders_detail');
      await tester.pumpAndSettle();

      expect(find.text('Order not found.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive layout', () {
    testWidgets('narrow screens render cards without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      seedOrder(
        receipt: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        items: const [
          OrderItem(
            productName: 'Very Long Filter Coffee Name That Keeps Going',
            sku: 'SKU-EXTREMELY-LONG',
            unitPricePaise: 12000,
            quantity: 2,
            lineTotalPaise: 24000,
          ),
        ],
      );
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.byType(OrdersPage), findsOneWidget);
      expect(find.text('BF-000001'), findsOneWidget);
      expect(find.text('Walk-in'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('BF-000001'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetailPage), findsOneWidget);
      expect(
        find.text('Very Long Filter Coffee Name That Keeps Going'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screens render the table without overflow', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      seedOrder(receipt: 'BF-000001', createdAt: DateTime.utc(2026, 1, 1));
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('BF-000001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('routing', () {
    testWidgets('/orders resolves for authenticated users', (tester) async {
      await pumpAuthenticated(tester);
      await goToOrders(tester);

      expect(
        routerOf(tester).routeInformationProvider.value.uri.path,
        AppRoutes.orders,
      );
      expect(find.byType(OrdersPage), findsOneWidget);
    });

    testWidgets('unauthenticated users stay locked out of /orders', (
      tester,
    ) async {
      final fake = FakeAuthRepository();
      await tester.pumpWidget(app(fake));
      fake.emit(null);
      await tester.pumpAndSettle();

      routerOf(tester).go(AppRoutes.orders);
      await tester.pumpAndSettle();

      expect(
        routerOf(tester).routeInformationProvider.value.uri.path,
        AppRoutes.auth,
      );
      expect(find.byType(AuthShell), findsOneWidget);
      expect(find.byType(OrdersPage), findsNothing);
    });
  });
}
