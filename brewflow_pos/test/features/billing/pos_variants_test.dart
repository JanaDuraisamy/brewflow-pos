import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';

void main() {
  Category category(String id, String name) => Category(
    id: id,
    name: name,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  ProductVariant variant({
    required String id,
    required String name,
    required int pricePaise,
    int stock = 5,
    String? sku,
    bool membershipEnabled = false,
    int? memberPricePaise,
    bool isActive = true,
  }) => ProductVariant(
    id: id,
    productId: 'p1',
    name: name,
    sku: sku,
    sellingPricePaise: pricePaise,
    costPricePaise: null,
    stockQuantity: stock,
    lowStockMode: LowStockMode.useDefault,
    lowStockThreshold: null,
    membershipEnabled: membershipEnabled,
    memberPricePaise: memberPricePaise,
    isActive: isActive,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  Product product({
    String id = 'p1',
    String name = 'Filter Coffee',
    List<ProductVariant> variants = const [],
    int stock = 5,
  }) => Product(
    id: id,
    categoryId: 'c1',
    name: name,
    sku: null,
    sellingPricePaise: 12000,
    costPricePaise: null,
    stockQuantity: stock,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    variants: variants,
  );

  FakeInventoryRepository seedInventory({
    List<ProductVariant> variants = const [],
    int stock = 5,
  }) {
    final inventory = FakeInventoryRepository();
    inventory.storedCategories.add(category('c1', 'Beverages'));
    inventory.storedProducts.add(
      product(
        id: 'p1',
        name: 'Filter Coffee',
        variants: variants,
        stock: stock,
      ),
    );
    return inventory;
  }

  FakeCustomersRepository seedCustomers() {
    final customers = FakeCustomersRepository();
    customers.storedCustomers.add(
      Customer(
        id: 'c1',
        name: 'Anand',
        phone: '9845012345',
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return customers;
  }

  Future<
    (FakeInventoryRepository, FakeBillingRepository, FakeCustomersRepository)
  >
  pumpPos(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    List<ProductVariant> variants = const [],
    int stock = 5,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final inventory = seedInventory(variants: variants, stock: stock);
    final billing = FakeBillingRepository(inventory);
    final customers = seedCustomers();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(billing),
          customersRepositoryProvider.overrideWithValue(customers),
        ],
        child: const MaterialApp(home: Scaffold(body: PosPage())),
      ),
    );
    await tester.pumpAndSettle();
    return (inventory, billing, customers);
  }

  /// Lets any auto-hiding snackbar timer elapse so the test ends cleanly.
  Future<void> flushSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Finder addButtonFor(String productName) => find.descendant(
    of: find.ancestor(of: find.text(productName), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  Future<void> addVariant(WidgetTester tester, String variantName) async {
    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(variantName).last);
    await tester.pumpAndSettle();
  }

  testWidgets('variant card opens a picker and adding shows the variant line', (
    tester,
  ) async {
    await pumpPos(
      tester,
      variants: [
        variant(
          id: 'v1',
          name: 'Small',
          pricePaise: 9000,
          stock: 3,
          sku: 'FC-S',
        ),
        variant(
          id: 'v2',
          name: 'Large',
          pricePaise: 15000,
          stock: 4,
          sku: 'FC-L',
        ),
      ],
      stock: 7,
    );

    expect(find.textContaining('2 variants'), findsOneWidget);
    expect(
      find.text('₹90.00'),
      findsOneWidget,
      reason: 'primary variant price',
    );
    expect(find.textContaining('Stock 7'), findsOneWidget);

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Filter Coffee'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('SKU FC-S · Stock 3'), findsOneWidget);
    expect(find.text('₹90.00'), findsNWidgets(2), reason: 'card + sheet');

    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    expect(find.text('Filter Coffee — Large'), findsOneWidget);
    expect(find.text('₹150.00 × 1'), findsOneWidget);
    expect(find.text('1 in cart'), findsOneWidget);
    await flushSnackBars(tester);
  });

  testWidgets('variant lines are separate and cap at their own stock', (
    tester,
  ) async {
    await pumpPos(
      tester,
      variants: [
        variant(id: 'v1', name: 'Small', pricePaise: 9000, stock: 1),
        variant(id: 'v2', name: 'Large', pricePaise: 15000, stock: 2),
      ],
      stock: 3,
    );

    await addVariant(tester, 'Small');
    await addVariant(tester, 'Large');
    expect(find.text('Filter Coffee — Small'), findsOneWidget);
    expect(find.text('Filter Coffee — Large'), findsOneWidget);
    expect(find.text('2 in cart'), findsOneWidget);
    expect(
      find.text('2'),
      findsOneWidget,
      reason: 'quantity badge sums both variant lines',
    );

    await addVariant(tester, 'Small');
    expect(
      find.text('Filter Coffee does not have enough stock.'),
      findsOneWidget,
    );
    await flushSnackBars(tester);
  });

  testWidgets(
    'member pricing toggle applies variant member prices at checkout',
    (tester) async {
      final (_, billing, _) = await pumpPos(
        tester,
        variants: [
          variant(
            id: 'v1',
            name: 'Small',
            pricePaise: 9000,
            membershipEnabled: true,
            memberPricePaise: 7500,
          ),
        ],
        stock: 4,
      );

      await addVariant(tester, 'Small');
      expect(find.text('Member pricing'), findsOneWidget);
      expect(find.text('₹90.00 × 1'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('₹75.00 × 1'), findsOneWidget, reason: 'charged price');
      expect(find.text('₹75.00'), findsOneWidget, reason: 'total');

      await tester.ensureVisible(find.text('UPI'));

      await tester.ensureVisible(find.text('UPI'));

      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
      await tester.pumpAndSettle();

      expect(find.text('Sale Complete'), findsOneWidget);
      expect(
        billing.storedSales.single.totalPaise,
        7500,
        reason: 'member price charged',
      );
      final savedLine = (await billing.saleItemsFor(
        billing.storedSales.single.id,
      )).single;
      expect(savedLine.unitPricePaise, 7500);
      expect(savedLine.variantId, 'v1');
      expect(savedLine.variantName, 'Small');

      await tester.tap(find.text('New Sale'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);
    },
  );

  testWidgets('carting the last units disables the add button', (tester) async {
    await pumpPos(
      tester,
      variants: [
        variant(id: 'v1', name: 'Small', pricePaise: 9000, stock: 1),
        variant(id: 'v2', name: 'Large', pricePaise: 15000, stock: 1),
      ],
      stock: 2,
    );

    await addVariant(tester, 'Small');
    await addVariant(tester, 'Large');
    final soldOut = find.widgetWithText(FilledButton, 'Sold out');
    expect(soldOut, findsOneWidget);
    expect(tester.widget<FilledButton>(soldOut).onPressed, isNull);
    await flushSnackBars(tester);
  });

  testWidgets('inactive variants are not offered', (tester) async {
    await pumpPos(
      tester,
      variants: [
        variant(id: 'v1', name: 'Small', pricePaise: 9000, stock: 2),
        variant(
          id: 'v2',
          name: 'Retired',
          pricePaise: 15000,
          stock: 2,
          isActive: false,
        ),
      ],
      stock: 2,
    );

    expect(find.textContaining('1 variants'), findsOneWidget);
    await addVariant(tester, 'Small');
    expect(find.text('Retired'), findsNothing);
    await flushSnackBars(tester);
  });

  testWidgets('receipt lists the variant name after checkout', (tester) async {
    await pumpPos(
      tester,
      variants: [variant(id: 'v1', name: 'Large', pricePaise: 15000, stock: 4)],
      stock: 4,
    );

    await addVariant(tester, 'Large');
    await tester.ensureVisible(find.text('UPI'));
    await tester.ensureVisible(find.text('UPI'));
    await tester.tap(find.text('UPI'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
    await tester.pumpAndSettle();

    expect(find.text('Filter Coffee — Large'), findsOneWidget);
    expect(find.text('₹150.00 × 1'), findsOneWidget);
    await tester.tap(find.text('New Sale'));
    await tester.pumpAndSettle();
    await flushSnackBars(tester);
  });
}
