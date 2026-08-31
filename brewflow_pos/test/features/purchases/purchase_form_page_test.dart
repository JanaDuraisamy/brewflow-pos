import 'dart:async';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_detail_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_form_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_purchases_repository.dart';
import '../../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;
  late FakeSuppliersRepository fakeSuppliers;
  late FakePurchasesRepository fakePurchases;

  final now = DateTime.now().toUtc();

  Supplier supplier(String id, String name, {bool isActive = true}) => Supplier(
    id: id,
    name: name,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  Product product(
    String id,
    String name, {
    String? sku,
    int? costPaise,
    int stock = 20,
    bool isActive = true,
  }) => Product(
    id: id,
    categoryId: 'c1',
    name: name,
    sku: sku,
    sellingPricePaise: 12000,
    costPricePaise: costPaise,
    stockQuantity: stock,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
    fakeSuppliers = FakeSuppliersRepository();
    fakePurchases = FakePurchasesRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      inventoryRepositoryProvider.overrideWithValue(fakeInventory),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
      purchasesRepositoryProvider.overrideWithValue(fakePurchases),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.purchaseNew);
    await pumpAsync(tester);
  }

  /// The form is a scrollable column, so its action buttons only exist in the
  /// tree once scrolled into view.
  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.descendant(
      of: find.byType(PurchaseFormPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable.first);
    await tester.pump();
  }

  Future<void> tapReceive(WidgetTester tester) async {
    await scrollFormTo(tester, find.text('Receive Purchase'));
    await tester.tap(find.text('Receive Purchase'));
    await pumpAsync(tester);
  }

  group('supplier selector', () {
    testWidgets('offers walk-in and active suppliers only', (tester) async {
      fakeSuppliers.storedSuppliers.addAll([
        supplier('s1', 'Acme Supplies'),
        supplier('s2', 'Old Mills', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openForm(tester);

      expect(find.text('Walk-in / No Supplier'), findsOneWidget);

      await tester.tap(find.text('Walk-in / No Supplier'));
      await tester.pumpAndSettle();

      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Old Mills'), findsNothing);

      await tester.tap(find.text('Acme Supplies'));
      await pumpAsync(tester);

      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Walk-in / No Supplier'), findsNothing);
    });

    testWidgets('reverts to walk-in when no supplier is chosen', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openForm(tester);

      expect(find.text('Walk-in / No Supplier'), findsOneWidget);
    });
  });

  group('product picker', () {
    testWidgets('lists active products with sku, stock and cost', (
      tester,
    ) async {
      fakeInventory.storedProducts.addAll([
        product('p1', 'Coffee Beans', sku: 'CB-1', costPaise: 10000),
        product('p2', 'Filter Paper', costPaise: 5000, stock: 45),
        product('p3', 'Old Brew', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openForm(tester);

      expect(find.text('Coffee Beans'), findsOneWidget);
      expect(find.textContaining('SKU: CB-1'), findsOneWidget);
      expect(find.textContaining('Stock: 20'), findsOneWidget);
      expect(find.textContaining('Cost: ₹100.00'), findsOneWidget);
      expect(find.text('Filter Paper'), findsOneWidget);
      expect(find.textContaining('Stock: 45'), findsOneWidget);
      expect(find.text('Old Brew'), findsNothing);
    });

    testWidgets('search narrows the product list', (tester) async {
      fakeInventory.storedProducts.addAll([
        product('p1', 'Coffee Beans'),
        product('p2', 'Filter Paper'),
      ]);
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.enterText(find.byType(SearchField), 'filter');
      await tester.pump();

      expect(find.text('Filter Paper'), findsOneWidget);
      expect(find.text('Coffee Beans'), findsNothing);
    });
  });

  group('purchase cart', () {
    testWidgets('add product creates a line with default quantity and cost', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', sku: 'CB-1', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      expect(find.text('Items to receive (1)'), findsOneWidget);
      expect(find.text('Coffee Beans'), findsNWidgets(2));
      expect(
        find.text('Current stock: 20 · Receiving: 1 · After receive: 21'),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('line-total-p1'))).data,
        '₹100.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹100.00',
      );
    });

    testWidgets('a product already in the cart cannot be added again', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(product('p1', 'Coffee Beans'));
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      expect(find.byKey(const Key('add-p1')), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Items to receive (1)'), findsOneWidget);
    });

    testWidgets('quantity editing updates the live line and grand totals', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      await tester.enterText(find.byKey(const Key('qty-p1')), '5');
      await pumpAsync(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('line-total-p1'))).data,
        '₹500.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹500.00',
      );
      expect(find.textContaining('After receive: 25'), findsOneWidget);
    });

    testWidgets('cost editing updates the live totals', (tester) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('qty-p1')), '2');
      await pumpAsync(tester);

      await tester.enterText(find.byKey(const Key('cost-p1')), '120.50');
      await pumpAsync(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('line-total-p1'))).data,
        '₹241.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹241.00',
      );
    });

    testWidgets('remove line drops the product from the cart', (tester) async {
      fakeInventory.storedProducts.addAll([
        product('p1', 'Coffee Beans'),
        product('p2', 'Filter Paper', costPaise: 5000),
      ]);
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add-p2')));
      await pumpAsync(tester);
      expect(find.text('Items to receive (2)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-p1')));
      await pumpAsync(tester);

      expect(find.text('Items to receive (1)'), findsOneWidget);
      expect(find.text('Filter Paper'), findsNWidgets(2));
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹50.00',
      );
    });

    testWidgets('subtotal matches the grand total for a one-line cart', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('subtotal-value'))).data,
        '₹100.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹100.00',
      );
    });
  });

  group('validation', () {
    testWidgets('receive is disabled with an empty cart', (tester) async {
      await pumpAuthenticated(tester);
      await openForm(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Receive Purchase'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('zero quantity is rejected before the repository is called', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(product('p1', 'Coffee Beans'));
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('qty-p1')), '0');
      await pumpAsync(tester);

      await tapReceive(tester);

      expect(find.text('Quantity must be at least 1.'), findsOneWidget);
      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(fakePurchases.receiveCalls, 0);
    });

    testWidgets('an empty cost is rejected before the repository is called', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('cost-p1')), '');
      await pumpAsync(tester);

      await tapReceive(tester);

      expect(find.text('Enter a valid cost (e.g. 149.50)'), findsOneWidget);
      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(fakePurchases.receiveCalls, 0);
    });
  });

  group('submission', () {
    testWidgets('receive shows a spinner and blocks a second submission', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(product('p1', 'Coffee Beans'));
      fakePurchases.receiveGate = Completer<void>();
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      await scrollFormTo(tester, find.text('Receive Purchase'));
      await tester.tap(find.text('Receive Purchase'));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      final button = tester.widget<PrimaryButton>(
        find.byWidgetPredicate(
          (w) => w is PrimaryButton && w.label == 'Receive Purchase',
        ),
      );
      expect(button.loading, isTrue);
      expect(button.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byType(PurchaseFormPage),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PrimaryButton && w.label == 'Receive Purchase',
        ),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(fakePurchases.receiveCalls, 1);

      fakePurchases.receiveGate!.complete();
      await pumpAsync(tester);
    });

    testWidgets('a repository failure shows a safe message and keeps the '
        'form and cart intact', (tester) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      fakePurchases.receiveError = const InactiveSupplierFailure();
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      await scrollFormTo(tester, find.text('Walk-in / No Supplier'));
      await tester.tap(find.text('Walk-in / No Supplier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Supplies'));
      await pumpAsync(tester);

      await tapReceive(tester);

      expect(
        find.textContaining('This supplier is deactivated'),
        findsOneWidget,
      );
      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(find.text('Items to receive (1)'), findsOneWidget);
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹100.00',
      );
    });

    testWidgets('a successful receive shows the number and opens the detail', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('qty-p1')), '5');
      await pumpAsync(tester);

      await tapReceive(tester);

      expect(fakePurchases.receiveCalls, 1);
      expect(fakePurchases.lastLines.single.productId, 'p1');
      expect(fakePurchases.lastLines.single.quantity, 5);
      expect(fakePurchases.lastSupplierId, isNull);

      expect(
        find.textContaining('Purchase received successfully.'),
        findsOneWidget,
      );
      expect(find.textContaining('PUR-000001'), findsWidgets);
      expect(find.byType(PurchaseDetailPage), findsOneWidget);
      expect(find.text('Product p1'), findsOneWidget);
      expect(find.text('₹500.00'), findsWidgets);

      await tester.pageBack();
      await pumpAsync(tester);

      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(find.text('Items to receive (0)'), findsOneWidget);
    });
  });

  group('responsive layout', () {
    testWidgets('renders stacked without overflow on a narrow phone', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);

      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.purchaseNew);
      await pumpAsync(tester);

      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      expect(find.text('Items to receive (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await scrollFormTo(tester, find.text('Receive Purchase'));
      expect(tester.takeException(), isNull);
    });
  });
}
