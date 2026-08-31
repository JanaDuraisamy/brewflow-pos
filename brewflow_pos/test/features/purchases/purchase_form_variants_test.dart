import 'package:brewflow_pos/app/app.dart';
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

  ProductVariant variant(
    String id,
    String productId,
    String name, {
    String? sku,
    int? costPaise,
    int stock = 10,
    bool isActive = true,
  }) => ProductVariant(
    id: id,
    productId: productId,
    name: name,
    sku: sku,
    sellingPricePaise: 15000,
    costPricePaise: costPaise,
    stockQuantity: stock,
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
    List<ProductVariant> variants = const [],
  }) => Product(
    id: id,
    categoryId: 'c1',
    name: name,
    sku: sku,
    sellingPricePaise: 12000,
    costPricePaise: costPaise,
    stockQuantity: stock,
    isActive: isActive,
    variants: variants,
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

  group('variant receiving', () {
    testWidgets('a variant product opens the variant sheet and adds lines', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [
            variant('v1', 'p1', 'Small', sku: 'CB-S', costPaise: 8000),
            variant('v2', 'p1', 'Large', sku: 'CB-L', costPaise: 10000),
          ],
        ),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      expect(find.textContaining('2 variants'), findsOneWidget);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      expect(find.text('Receive Coffee Beans'), findsOneWidget);
      expect(find.textContaining('SKU: CB-S'), findsOneWidget);
      expect(find.textContaining('Stock: 10'), findsNWidgets(2));
      expect(find.textContaining('Cost: ₹80.00'), findsOneWidget);
      expect(find.textContaining('Cost: ₹100.00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v2')));
      await pumpAsync(tester);

      expect(find.text('Items to receive (2)'), findsOneWidget);
      expect(find.text('Coffee Beans — Small'), findsOneWidget);
      expect(find.text('Coffee Beans — Large'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await pumpAsync(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹180.00',
      );
    });

    testWidgets('variant quantity editing updates the live line and totals', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [variant('v1', 'p1', 'Small', costPaise: 8000)],
        ),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);
      await tester.tap(find.text('Done'));
      await pumpAsync(tester);

      await tester.enterText(find.byKey(const Key('qty-v1')), '5');
      await pumpAsync(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('line-total-v1'))).data,
        '₹400.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹400.00',
      );
      expect(find.textContaining('After receive: 15'), findsOneWidget);
    });

    testWidgets('variant cost defaults to the variant cost and can be edited', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          costPaise: 9999,
          variants: [
            variant('v1', 'p1', 'Small', sku: 'CB-S', costPaise: 8000),
          ],
        ),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);
      await tester.tap(find.text('Done'));
      await pumpAsync(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('line-total-v1'))).data,
        '₹80.00',
      );

      await tester.enterText(find.byKey(const Key('cost-v1')), '90.50');
      await pumpAsync(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('line-total-v1'))).data,
        '₹90.50',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹90.50',
      );
    });

    testWidgets('a variant already in the cart cannot be added again', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [
            variant('v1', 'p1', 'Small'),
            variant('v2', 'p1', 'Large'),
          ],
        ),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);

      expect(find.byKey(const Key('add-v1')), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Items to receive (1)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-v2')));
      await pumpAsync(tester);
      expect(find.text('Items to receive (2)'), findsOneWidget);
    });

    testWidgets('the picker row marks done only when all variants are in '
        'the cart', (tester) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [
            variant('v1', 'p1', 'Small'),
            variant('v2', 'p1', 'Large'),
          ],
        ),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);

      expect(find.byKey(const Key('add-p1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-v2')));
      await pumpAsync(tester);

      expect(find.byKey(const Key('add-p1')), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    });

    testWidgets('submission snapshots the variant identity and the detail '
        'shows it', (tester) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [variant('v1', 'p1', 'Small', costPaise: 8000)],
        ),
      );
      fakePurchases.variantNames['v1'] = 'Small';
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);
      await tester.tap(find.text('Done'));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('qty-v1')), '3');
      await pumpAsync(tester);

      await tapReceive(tester);

      expect(fakePurchases.receiveCalls, 1);
      expect(fakePurchases.lastLines.single.productId, 'p1');
      expect(fakePurchases.lastLines.single.variantId, 'v1');
      expect(fakePurchases.lastLines.single.quantity, 3);
      expect(fakePurchases.lastLines.single.unitCostPaise, 8000);

      expect(find.byType(PurchaseDetailPage), findsOneWidget);
      expect(find.text('Product p1 — Small'), findsOneWidget);
      expect(find.text('₹240.00'), findsWidgets);
    });

    testWidgets('removing a variant line keeps the others', (tester) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [
            variant('v1', 'p1', 'Small', costPaise: 8000),
            variant('v2', 'p1', 'Large', costPaise: 10000),
          ],
        ),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v2')));
      await pumpAsync(tester);
      await tester.tap(find.text('Done'));
      await pumpAsync(tester);
      expect(find.text('Items to receive (2)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-v1')));
      await pumpAsync(tester);

      expect(find.text('Items to receive (1)'), findsOneWidget);
      expect(find.text('Coffee Beans — Large'), findsOneWidget);
      expect(find.text('Coffee Beans — Small'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-value'))).data,
        '₹100.00',
      );
    });
  });

  group('non-variant regression', () {
    testWidgets('plain products still add, edit and submit without variants', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product('p1', 'Coffee Beans', costPaise: 10000),
      );
      await pumpAuthenticated(tester);
      await openForm(tester);

      expect(find.textContaining('2 variants'), findsNothing);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);

      expect(find.text('Items to receive (1)'), findsOneWidget);
      expect(find.text('Coffee Beans'), findsNWidgets(2));

      await tester.enterText(find.byKey(const Key('qty-p1')), '2');
      await pumpAsync(tester);
      await tapReceive(tester);

      expect(fakePurchases.lastLines.single.productId, 'p1');
      expect(fakePurchases.lastLines.single.variantId, isNull);
      expect(fakePurchases.lastLines.single.quantity, 2);
      expect(find.byType(PurchaseDetailPage), findsOneWidget);
      expect(find.text('Product p1'), findsOneWidget);
    });
  });

  group('validation with variants', () {
    testWidgets('supplier validation still guards a variant receive', (
      tester,
    ) async {
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Coffee Beans',
          variants: [variant('v1', 'p1', 'Small', costPaise: 8000)],
        ),
      );
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      fakePurchases.receiveError = const InactiveSupplierFailure();
      await pumpAuthenticated(tester);
      await openForm(tester);

      await scrollFormTo(tester, find.byKey(const Key('add-p1')));
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-v1')));
      await pumpAsync(tester);
      await tester.tap(find.text('Done'));
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
      expect(find.text('Coffee Beans — Small'), findsOneWidget);
    });
  });
}
