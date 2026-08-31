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

/// Seeds enough distinct products that the cart item list overflows the
/// panel at any tested height.
FakeInventoryRepository _seedInventory({int productCount = 8}) {
  final inventory = FakeInventoryRepository();
  inventory.storedCategories.add(
    Category(
      id: 'c1',
      name: 'Beverages',
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );
  for (var i = 1; i <= productCount; i++) {
    inventory.storedProducts.add(
      Product(
        id: 'p$i',
        categoryId: 'c1',
        name: 'Product $i',
        sku: null,
        sellingPricePaise: 10000,
        costPricePaise: null,
        stockQuantity: 20,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
  return inventory;
}

Future<void> _pumpPos(
  WidgetTester tester, {
  required Size size,
  required FakeInventoryRepository inventory,
  FakeCustomersRepository? customers,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final billing = FakeBillingRepository(inventory);
  final customerRepo = customers ?? FakeCustomersRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(inventory),
        billingRepositoryProvider.overrideWithValue(billing),
        customersRepositoryProvider.overrideWithValue(customerRepo),
      ],
      child: const MaterialApp(home: Scaffold(body: PosPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Finder> _addButton(WidgetTester tester, String name) async {
  return find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );
}

Rect _buttonRect(WidgetTester tester) =>
    tester.getRect(find.widgetWithText(FilledButton, 'Complete Sale'));

void main() {
  testWidgets('wide layout renders cart with pinned billing action', (
    tester,
  ) async {
    final inventory = _seedInventory();
    await _pumpPos(tester, size: const Size(1280, 800), inventory: inventory);

    expect(find.text('Current Sale'), findsOneWidget);
    expect(_buttonRect(tester).bottom, lessThanOrEqualTo(800));
  });

  testWidgets('short viewport keeps total and action visible while items '
      'scroll together', (tester) async {
    final inventory = _seedInventory(productCount: 6);
    // Below the old 560px special-case height.
    const size = Size(1200, 470);
    await _pumpPos(tester, size: size, inventory: inventory);

    for (var i = 1; i <= 5; i++) {
      final button = await _addButton(tester, 'Product $i');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();

    // Pinned action is on screen.
    final before = _buttonRect(tester);
    expect(before.bottom, lessThanOrEqualTo(size.height));

    // Scrolling the content must not move the pinned action.
    await tester.drag(
      find.text('Product 1').first,
      const Offset(0, -600),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final after = _buttonRect(tester);
    expect(after.top, before.top);
    expect(after.bottom, lessThanOrEqualTo(size.height));
  });

  testWidgets('mobile Products/Cart interaction keeps the action visible', (
    tester,
  ) async {
    final inventory = _seedInventory(productCount: 6);
    await _pumpPos(tester, size: const Size(500, 740), inventory: inventory);

    // Add from the Products tab.
    final button = await _addButton(tester, 'Product 2');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Cart'));
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Total'), findsOneWidget);
    final rect = _buttonRect(tester);
    expect(rect.bottom, lessThanOrEqualTo(740));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Complete Sale'),
          )
          .onPressed,
      isNull,
      reason: 'payment method not chosen yet',
    );
  });

  testWidgets('narrow phone cart shows payment controls and Complete Sale '
      'is tappable after selecting payment', (tester) async {
    final inventory = _seedInventory(productCount: 3);
    await _pumpPos(tester, size: const Size(390, 844), inventory: inventory);

    // Add a product from the Products tab.
    final button = await _addButton(tester, 'Product 1');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    // Switch to Cart tab.
    await tester.ensureVisible(find.text('Cart'));
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();

    // Payment Status and Payment Method must be present.
    expect(find.text('Payment Status'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Not Paid'), findsOneWidget);

    // Select Paid + Cash — Complete Sale should become enabled.
    await tester.ensureVisible(find.text('Paid'));
    await tester.tap(find.text('Paid'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cash'));
    await tester.tap(find.text('Cash'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Complete Sale'),
          )
          .onPressed,
      isNotNull,
      reason: 'Complete Sale should be enabled after Paid + Cash selected',
    );

    // Complete Sale button must be on screen.
    expect(_buttonRect(tester).bottom, lessThanOrEqualTo(844));
  });

  testWidgets('narrow phone cart NOT PAID with customer enables '
      'Complete Sale', (tester) async {
    final inventory = _seedInventory(productCount: 2);
    final customers = FakeCustomersRepository();
    customers.storedCustomers.add(
      Customer(
        id: 'c1',
        name: 'Anand',
        phone: '9845012345',
        isActive: true,
        membershipActive: false,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _pumpPos(
      tester,
      size: const Size(390, 844),
      inventory: inventory,
      customers: customers,
    );

    // Add a product.
    final button = await _addButton(tester, 'Product 1');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    // Switch to Cart tab.
    await tester.ensureVisible(find.text('Cart'));
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();

    // Select Not Paid.
    await tester.ensureVisible(find.text('Not Paid'));
    await tester.tap(find.text('Not Paid'));
    await tester.pumpAndSettle();

    // Without customer, Complete Sale should be disabled.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Complete Sale'),
          )
          .onPressed,
      isNull,
    );

    // Open customer picker and select a customer.
    await tester.ensureVisible(find.text('Walk-in'));
    await tester.tap(find.text('Walk-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anand'));
    await tester.pumpAndSettle();

    // Now Complete Sale should be enabled.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Complete Sale'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
