import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/order_detail_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// All logical phone widths the layout must survive without overflow.
const _phoneWidths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

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

  /// Seeds one order with a real item (quantity 2) so the correct item-count
  /// label must render instead of "0 items".
  void seedOrderWithItems() {
    repository.add(
      receiptNumber: 'BF-000010',
      createdAt: DateTime.utc(2026, 1, 5, 9, 15),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 24000,
      customerName: 'Priya',
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          sku: 'FC-1',
          unitPricePaise: 12000,
          quantity: 2,
          lineTotalPaise: 24000,
        ),
      ],
    );
  }

  for (final width in _phoneWidths) {
    testWidgets(
      'order card renders a real item count and no overflow at ${width}dp',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        seedOrderWithItems();
        await pumpAuthenticated(tester);
        await goToOrders(tester);

        expect(find.byType(OrdersPage), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');

        // The order's item count must be the real count (2), never "0 items".
        expect(find.text('BF-000010'), findsOneWidget);
        expect(find.text('2 items'), findsOneWidget);
        expect(find.text('0 items'), findsNothing);
        expect(find.text('Priya'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('long-press on an order card opens the sheet with View Details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    seedOrderWithItems();
    await pumpAuthenticated(tester);
    await goToOrders(tester);

    final card = find.ancestor(
      of: find.text('BF-000010'),
      matching: find.byType(AppCard),
    );
    expect(card, findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(find.text('View Details'), findsOneWidget);

    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailPage), findsOneWidget);
  });
}
