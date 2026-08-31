import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';

/// Phone-size regression coverage: the phone selling flow
/// SEARCH → CATEGORY → PRODUCT → CART → CHECKOUT must render without
/// overflow at every common narrow width while every step stays usable.
///
/// Covers the phone-only card layout, the tall checkout action, large
/// touch targets in cart lines and the variant picker on the narrow shelf.

/// Seed a shelf that exercises every card shape: plain products, a long
/// product name, an untracked “Made to order” product and a variant product.
FakeInventoryRepository _seedInventory() {
  final inventory = FakeInventoryRepository();
  void category(String id, String name) {
    inventory.storedCategories.add(
      Category(
        id: id,
        name: name,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  category('c1', 'Coffee');
  category('c2', 'Snacks');
  category('c3', 'Bakery');

  // Variant product first: it must be on the visible first row of the shelf
  // grid so its card is built even at the narrowest width.
  inventory.storedProducts.add(
    Product(
      id: 'p12',
      categoryId: 'c1',
      name: 'SPL Milk Chai',
      sku: null,
      sellingPricePaise: 1500,
      costPricePaise: null,
      stockQuantity: 0,
      stockUnit: StockUnit.none,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      variants: [
        ProductVariant(
          id: 'v-100',
          productId: 'p12',
          name: '100ml',
          sellingPricePaise: 1500,
          costPricePaise: null,
          stockQuantity: 10,
          isActive: true,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
        ProductVariant(
          id: 'v-160',
          productId: 'p12',
          name: '160ml',
          sellingPricePaise: 2000,
          costPricePaise: null,
          stockQuantity: 8,
          isActive: true,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      ],
    ),
  );

  void simple({
    required String id,
    required String name,
    required String categoryId,
    int pricePaise = 15000,
    int stock = 10,
    String? sku = 'SKU-1',
  }) {
    inventory.storedProducts.add(
      Product(
        id: id,
        categoryId: categoryId,
        name: name,
        sku: sku,
        sellingPricePaise: pricePaise,
        costPricePaise: null,
        stockQuantity: stock,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  const longName = 'Almond Croissant With Butter Crumb Finish';
  simple(id: 'p1', name: longName, categoryId: 'c3', sku: 'AC-01');
  simple(id: 'p2', name: 'Espresso', categoryId: 'c1', sku: 'ES-01');
  simple(id: 'p3', name: 'Cold Brew', categoryId: 'c1', sku: 'CB-02');
  simple(id: 'p4', name: 'Veg Puff', categoryId: 'c2', sku: 'VP-03');
  simple(id: 'p5', name: 'Brownie', categoryId: 'c2', sku: 'BR-04');
  simple(id: 'p6', name: 'Sundae', categoryId: 'c1', sku: 'SU-05');
  simple(id: 'p7', name: 'Cinnamon Roll', categoryId: 'c3', sku: 'CR-06');
  simple(id: 'p8', name: 'Garlic Bread', categoryId: 'c2', sku: 'GB-07');
  simple(id: 'p9', name: 'Hot Chocolate', categoryId: 'c1', sku: 'HC-08');
  simple(id: 'p10', name: 'Bagel', categoryId: 'c3', sku: 'BG-09');

  // Untracked product: “Made to order”, never sold out.
  inventory.storedProducts.add(
    Product(
      id: 'p11',
      categoryId: 'c1',
      name: 'Golden Tumeric Latte',
      sku: 'TL-10',
      sellingPricePaise: 18000,
      costPricePaise: null,
      stockQuantity: 0,
      stockUnit: StockUnit.none,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );
  return inventory;
}

Future<void> _pumpPos(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final inventory = _seedInventory();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(inventory),
        billingRepositoryProvider.overrideWithValue(
          FakeBillingRepository(inventory),
        ),
        customersRepositoryProvider.overrideWithValue(
          FakeCustomersRepository(),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: PosPage())),
    ),
  );
  await tester.pumpAndSettle();
}

/// The shelf card's Add button for a named product.
Finder _addButtonFor(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
  matching: find.widgetWithText(FilledButton, 'Add'),
);

void main() {
  // Every width a cashier's Android phone typically reports.
  const widths = [360, 375, 390, 411, 430, 480];

  for (final width in widths) {
    const size = Size(0, 800);
    testWidgets(
      'phone width $width renders shelf, cart and checkout without overflow',
      (tester) async {
        await _pumpPos(tester, Size(width.toDouble(), size.height));
        expect(tester.takeException(), isNull);

        const longName = 'Almond Croissant With Butter Crumb Finish';
        expect(find.text(longName), findsOneWidget);

        // PRODUCT: add a plain product with a long name.
        final addButton = _addButtonFor(longName);
        await tester.ensureVisible(addButton);
        await tester.tap(addButton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('1 in cart'), findsOneWidget);
        expect(find.text('Open cart'), findsOneWidget);

        // CART: open, grow quantity with a large touch target and price out.
        await tester.tap(find.text('Open cart'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Current Sale'), findsOneWidget);
        expect(find.text('Complete Sale'), findsOneWidget);
        expect(find.text('Walk-in'), findsOneWidget);

        final increase = find.byTooltip('Increase quantity');
        await tester.ensureVisible(increase);
        await tester.tap(increase);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('\u00D7 2'), findsOneWidget);

        // CHECKOUT: Paid + Cash enables completion and keeps it on screen.
        await tester.ensureVisible(find.text('Paid'));
        await tester.tap(find.text('Paid'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cash'));
        await tester.tap(find.text('Cash'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete Sale'),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .getRect(find.widgetWithText(FilledButton, 'Complete Sale'))
              .bottom,
          lessThanOrEqualTo(size.height),
        );

        // Back to PRODUCT: SEARCH narrows the shelf, then the variant picker opens
        // cleanly at this width.
        await tester.ensureVisible(find.text('Products'));
        await tester.tap(find.text('Products'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'chai');
        await tester.pumpAndSettle();
        final variantAdd = _addButtonFor('SPL Milk Chai');
        await tester.ensureVisible(variantAdd);
        await tester.tap(variantAdd);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Choose SPL Milk Chai'), findsOneWidget);

        await tester.tap(find.text('100ml').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('3 in cart'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );
  }
}
