import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// P0 FIX 4 / 6 / 7 — variant selection, inline customer creation and
/// one-tap membership enrolment from the billing screen.
/// ---------------------------------------------------------------------------

const String _chaiId = 'p-chai';

Product _chai() {
  return Product(
    id: _chaiId,
    categoryId: 'cat-1',
    name: 'SPL Milk Chai',
    sku: null,
    sellingPricePaise: 1500,
    costPricePaise: null,
    stockQuantity: 0,
    stockUnit: StockUnit.none,
    lowStockMode: LowStockMode.off,
    membershipEnabled: true,
    memberPricePaise: 1200,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    variants: [
      ProductVariant(
        id: 'v-100',
        productId: _chaiId,
        name: '100ml',
        sellingPricePaise: 1500,
        stockQuantity: 0,
        lowStockMode: LowStockMode.off,
        membershipEnabled: true,
        memberPricePaise: 1200,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      ProductVariant(
        id: 'v-160',
        productId: _chaiId,
        name: '160ml',
        sellingPricePaise: 2000,
        stockQuantity: 0,
        lowStockMode: LowStockMode.off,
        membershipEnabled: true,
        memberPricePaise: 1600,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ],
  );
}

Customer _customer({String id = 'c-1', String name = 'Anand'}) {
  return Customer(
    id: id,
    name: name,
    phone: '9845012345',
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );
}

Future<void> _pump(WidgetTester tester) async {
  final inventory = FakeInventoryRepository();
  inventory.storedProducts.add(_chai());
  final customers = FakeCustomersRepository()..storedCustomers.add(_customer());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(inventory),
        billingRepositoryProvider.overrideWithValue(
          FakeBillingRepository(inventory),
        ),
        customersRepositoryProvider.overrideWithValue(customers),
        ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
        staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: PosPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('variant product opens the picker with per-variant prices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();

    expect(find.text('Choose SPL Milk Chai'), findsOneWidget);
    expect(find.text('100ml'), findsOneWidget);
    expect(find.text('160ml'), findsOneWidget);

    await tester.tap(find.text('160ml'));
    await tester.pumpAndSettle();

    expect(find.text('1 in cart'), findsOneWidget);
    expect(find.text('\u20B920.00'), findsOneWidget);
  });

  testWidgets('multiple variants stay distinct lines with own prices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);

    Future<void> pick(String variantName) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(variantName).last);
      await tester.pumpAndSettle();
    }

    await pick('100ml');
    await pick('160ml');
    await pick('100ml');

    expect(find.text('3 in cart'), findsOneWidget);

    await tester.tap(find.text('Open cart'));
    await tester.pumpAndSettle();
    expect(find.text('SPL Milk Chai \u2014 100ml'), findsOneWidget);
    expect(find.text('SPL Milk Chai \u2014 160ml'), findsOneWidget);
    expect(find.text('\u20B915.00 \u00D7 2'), findsOneWidget);
    expect(find.text('\u20B920.00 \u00D7 1'), findsOneWidget);
  });

  testWidgets('+ Add Customer creates and links without leaving billing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);

    // Phone layout: summary bar → cart panel → walk-in selector → picker.
    await tester.tap(find.text('Cart').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Walk-in'));
    await tester.pumpAndSettle();

    expect(find.text('Select Customer'), findsOneWidget);
    await tester.tap(find.text('Add Customer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Kumar');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone'),
      '9000011111',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Kumar'), findsOneWidget);
  });

  testWidgets('Member + enrols an existing customer and re-prices the bill', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);

    // Add the chai 100ml first (regular ₹15).
    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('100ml').last);
    await tester.pumpAndSettle();

    // Open cart → customer picker → enrol Anand as a member.
    await tester.tap(find.text('Open cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Walk-in'));
    await tester.pumpAndSettle();

    expect(find.text('Member +'), findsOneWidget);
    await tester.tap(find.text('Member +'));
    await tester.pumpAndSettle();

    // Picker closed, Anand attached, member pricing engaged: ₹15 → ₹12.
    expect(find.byType(AlertDialog), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Billing & POS')),
    );
    expect(container.read(cartProvider).memberPricing, isTrue);
    expect(container.read(cartProvider).chargedTotalPaise, 1200);
  });
}
