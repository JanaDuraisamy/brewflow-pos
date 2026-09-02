import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_customers_repository.dart';
import '../helpers/fake_expenses_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_purchases_repository.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_shop_name_repository.dart';
import '../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// The saved theme preference must reach the root MaterialApp: the settings
/// controller reads it from the repository, [appThemeModeProvider] maps it
/// onto a [ThemeMode] and app.dart wires it into the widget tree.
void main() {
  Widget app(FakeSettingsRepository settings) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(settings),
      shopNameRepositoryProvider.overrideWithValue(FakeShopNameRepository()),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      suppliersRepositoryProvider.overrideWithValue(FakeSuppliersRepository()),
      purchasesRepositoryProvider.overrideWithValue(FakePurchasesRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(
    WidgetTester tester,
    FakeSettingsRepository settings,
  ) async {
    final auth = FakeAuthRepository();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(settings));
    auth.emit(_owner);
    await tester.pumpAndSettle();
  }

  ThemeMode? rootThemeMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

  testWidgets('the root applies the saved dark theme preference', (
    tester,
  ) async {
    final settings = FakeSettingsRepository()
      ..stored = ShopSettings.defaults().copyWith(theme: ThemePreference.dark);

    await pumpAuthenticated(tester, settings);

    expect(rootThemeMode(tester), ThemeMode.dark);
  });

  testWidgets('the root applies the saved light theme preference', (
    tester,
  ) async {
    final settings = FakeSettingsRepository()
      ..stored = ShopSettings.defaults().copyWith(theme: ThemePreference.light);

    await pumpAuthenticated(tester, settings);

    expect(rootThemeMode(tester), ThemeMode.light);
  });

  testWidgets('the root follows the system theme by default', (tester) async {
    await pumpAuthenticated(tester, FakeSettingsRepository());

    expect(rootThemeMode(tester), ThemeMode.system);
  });

  testWidgets('saving a theme preference re-themes the running app', (
    tester,
  ) async {
    final settings = FakeSettingsRepository();
    await pumpAuthenticated(tester, settings);
    expect(rootThemeMode(tester), ThemeMode.system);

    final element = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(element);
    await container
        .read(shopSettingsProvider.notifier)
        .save(ShopSettings.defaults().copyWith(theme: ThemePreference.dark));
    await tester.pumpAndSettle();

    expect(rootThemeMode(tester), ThemeMode.dark);
  });
}
