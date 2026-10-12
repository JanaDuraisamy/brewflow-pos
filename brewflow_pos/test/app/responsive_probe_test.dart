import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_customers_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_staff_repository.dart';
import '../helpers/test_providers.dart';

/// Temporary probes for the responsive audit: pump the POS at squeezed
/// tablet widths with adversarial content and report what actually breaks.
/// These become permanent regression tests once the fixes land.
void main() {
  const owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

  FakeInventoryRepository inventoryWithLongNames() {
    final now = DateTime.now().toUtc();
    final repo = FakeInventoryRepository()
      ..storedCategories.add(
        Category(
          id: 'c-1',
          name: 'Beverages With An Extremely Long Category Name',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..storedProducts.add(
        Product(
          id: 'p-1',
          categoryId: 'c-1',
          name: 'Masala Chai With An Extremely Long Product Name That Wraps',
          sku: 'SKU-WITH-A-VERY-LONG-CODE-123456789',
          sellingPricePaise: 12345600,
          costPricePaise: null,
          stockQuantity: 50,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    return repo;
  }

  Future<void> pumpPos(
    WidgetTester tester, {
    required double width,
    required double height,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fake = FakeAuthRepository();
    final inventory = inventoryWithLongNames();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(
            FakeBillingRepository(inventory),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          ...businessScopeOverrides(staff: FakeStaffRepository()),
        ],
        child: const BrewFlowApp(),
      ),
    );
    fake.emit(owner);
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    // Collapse the rail first so the squeezed-tablet path is exercised.
    router.go(AppRoutes.orders);
    await tester.pumpAndSettle();
    router.go(AppRoutes.billing);
    await tester.pumpAndSettle();
    expect(find.byType(PosPage), findsOneWidget);
  }

  for (final width in [600.0, 700.0, 800.0]) {
    testWidgets('PROBE pos squeezed tablet ${width.toInt()}dp + 1.15', (
      tester,
    ) async {
      await pumpPos(tester, width: width, height: 1024, textScale: 1.15);
      final error = tester.takeException();
      // ignore: avoid_print
      print('WIDTH $width EXCEPTION: $error');
      expect(find.text('Complete Sale'), findsOneWidget);
      // The shelf really rendered cards (not the empty state).
      expect(find.textContaining('Masala Chai'), findsWidgets);
      // Every Add button is inside the viewport horizontally.
      final window = tester.view.physicalSize;
      for (final element in tester.elementList(
        find.widgetWithText(FilledButton, 'Add'),
      )) {
        final rect =
            (element.renderObject! as RenderBox).localToGlobal(Offset.zero) &
            (element.renderObject! as RenderBox).size;
        // ignore: avoid_print
        print('WIDTH $width ADD RECT: $rect (window $window)');
      }
    });
  }

  testWidgets('PROBE shell header long names 360dp + 1.15', (tester) async {
    await pumpPos(tester, width: 360, height: 800, textScale: 1.15);
    final error = tester.takeException();
    // ignore: avoid_print
    print('HEADER EXCEPTION: $error');
  });

  testWidgets('PROBE phone cart summary 360dp huge total + 1.15', (
    tester,
  ) async {
    await pumpPos(tester, width: 360, height: 800, textScale: 1.15);
    // Add the expensive product many times for a huge total.
    final add = find.widgetWithText(FilledButton, 'Add');
    for (var i = 0; i < 12; i++) {
      await tester.tap(add.first);
      await tester.pumpAndSettle();
    }
    final error = tester.takeException();
    // ignore: avoid_print
    print('CART SUMMARY EXCEPTION: $error');
    expect(find.textContaining('in cart'), findsOneWidget);
  });

  testWidgets('PROBE staff row 360dp + 1.15', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');
    final fake = FakeAuthRepository();
    final staff = FakeStaffRepository();
    await staff.claimOwnership(owner);
    await staff.createStaffProfile(
      identity: const AuthUser(
        id: 'u-long',
        email: 'a.very.long.staff.email.address@brewflow.example',
      ),
      shopId: 'shop-1',
    );
    final inventory = inventoryWithLongNames();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(
            FakeBillingRepository(inventory),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          ...businessScopeOverrides(staff: staff),
        ],
        child: const BrewFlowApp(),
      ),
    );
    fake.emit(owner);
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(Scaffold).first);
    ProviderScope.containerOf(
      element,
    ).read(appRouterProvider).go(AppRoutes.staff);
    await tester.pumpAndSettle();
    final error = tester.takeException();
    // ignore: avoid_print
    print('STAFF ROW EXCEPTION: $error');
  });
}
