import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_shop_name_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeSettingsRepository settings;

  // The compact (<600dp) phone layout.
  const widths = [360, 375, 390, 411, 430, 480];

  for (final width in widths) {
    testWidgets(
      'renders the phone settings layout at $width dp without overflow',
      (tester) async {
        settings = FakeSettingsRepository();
        await tester.binding.setSurfaceSize(Size(width.toDouble(), 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final auth = FakeAuthRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settings),
              shopNameRepositoryProvider.overrideWithValue(
                FakeShopNameRepository(),
              ),
              authRepositoryProvider.overrideWithValue(auth),
              inventoryRepositoryProvider.overrideWithValue(
                FakeInventoryRepository(),
              ),
              billingRepositoryProvider.overrideWithValue(
                FakeBillingRepository(FakeInventoryRepository()),
              ),
              ordersRepositoryProvider.overrideWithValue(
                FakeOrdersRepository(),
              ),
              customerLedgerRepositoryProvider.overrideWithValue(
                FakeCustomerLedgerRepository(),
              ),
            ],
            child: const BrewFlowApp(),
          ),
        );
        auth.emit(_owner);
        await tester.pumpAndSettle();
        final element = tester.element(find.byType(Scaffold).first);
        final router = ProviderScope.containerOf(
          element,
        ).read(appRouterProvider);
        router.go(AppRoutes.settings);
        await tester.pumpAndSettle();

        // The core phone layout is present and complete.
        expect(find.text('Business Name'), findsOneWidget);
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Save Settings'), findsOneWidget);

        // Scroll to the very bottom so every section lays out and any overflow
        // surfaces before we assert a clean frame.
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the App Display Name is editable on the phone layout and persists',
    (tester) async {
      settings = FakeSettingsRepository();
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final auth = FakeAuthRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settings),
            shopNameRepositoryProvider.overrideWithValue(
              FakeShopNameRepository(),
            ),
            authRepositoryProvider.overrideWithValue(auth),
            inventoryRepositoryProvider.overrideWithValue(
              FakeInventoryRepository(),
            ),
            billingRepositoryProvider.overrideWithValue(
              FakeBillingRepository(FakeInventoryRepository()),
            ),
            ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
            customerLedgerRepositoryProvider.overrideWithValue(
              FakeCustomerLedgerRepository(),
            ),
          ],
          child: const BrewFlowApp(),
        ),
      );
      auth.emit(_owner);
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.text('App Display Name'), findsOneWidget);

      await tester.ensureVisible(find.text('App Display Name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('App Display Name'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Marina POS');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Settings'));
      await tester.pumpAndSettle();

      expect(settings.stored.appDisplayName, 'Marina POS');
      expect(settings.stored.shopName, ShopSettings.defaults().shopName);
    },
  );
}
