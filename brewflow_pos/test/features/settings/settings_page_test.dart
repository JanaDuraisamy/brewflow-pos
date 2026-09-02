import 'dart:async';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/domain/settings_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
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

  setUp(() {
    settings = FakeSettingsRepository();
  });

  Widget app(FakeAuthRepository auth) => ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      shopNameRepositoryProvider.overrideWithValue(FakeShopNameRepository()),
      authRepositoryProvider.overrideWithValue(auth),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
    ],
    child: const BrewFlowApp(),
  );

  /// Signs in and navigates to the settings route without waiting for the
  /// settings page to settle, so gated loading states stay observable.
  Future<void> pumpAuthenticated(WidgetTester tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(app(auth));
    auth.emit(_owner);
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.settings);
    await tester.pump();
    await tester.pump();
  }

  /// Taps the sticky save button at the bottom of the settings page.
  ///
  /// Unfocuses first: a focused [TextFormField] keeps its caret on screen and
  /// can interfere with the tap.
  Future<void> tapSave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Settings'));
  }

  group('Settings page states', () {
    testWidgets('shows defaults when nothing is saved', (tester) async {
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Business identity'), findsOneWidget);
      expect(find.text('Business Name'), findsOneWidget);
      expect(find.text('Owner Name'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('BrewFlow POS'), findsOneWidget);
      expect(find.text('Not set'), findsNWidgets(4));
      expect(find.text('Low Stock Alert'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Save Settings'), findsOneWidget);
      expect(
        find.text('${AppConstants.appName} v${AppConstants.appVersion}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a loading state while settings load', (tester) async {
      settings.loadGate = Completer<void>();
      final auth = FakeAuthRepository();
      await tester.pumpWidget(app(auth));
      auth.emit(_owner);
      // Bounded pumps instead of pumpAndSettle: the app root watches
      // settings for theming and the dashboard for its low-stock threshold,
      // so a gated settings load keeps loading spinners alive forever.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.settings);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Loading settings…'), findsOneWidget);

      settings.loadGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Save Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an error state with a working retry', (tester) async {
      settings.loadError = const UnexpectedSettingsFailure();
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.text('Could not load settings. Please try again.'),
        findsOneWidget,
      );

      settings.loadError = null;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Save Settings'), findsOneWidget);
      expect(find.text('Something went wrong'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prefills persisted values into the form', (tester) async {
      settings.stored = const ShopSettings(
        shopName: 'Cafe Marina',
        ownerName: 'Jana',
        phone: '9876543210',
        email: 'hi@marina.example',
        address: 'Beach Road',
        lowStockThreshold: 3,
        theme: ThemePreference.dark,
      );
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      expect(find.text('Cafe Marina'), findsOneWidget);
      expect(find.text('Jana'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('hi@marina.example'), findsOneWidget);
      expect(find.text('Beach Road'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Settings form', () {
    /// Opens the edit dialog for a setting row and commits the typed value.
    Future<void> editRow(
      WidgetTester tester,
      String rowLabel,
      String value,
    ) async {
      await tester.ensureVisible(find.text(rowLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(rowLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), value);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates the required shop name', (tester) async {
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Business Name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Shop name is required.'), findsOneWidget);
      expect(settings.saved, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('validates the low stock threshold', (tester) async {
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Low Stock Alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Low Stock Alert'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a number above 0.'), findsOneWidget);
      expect(settings.saved, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('validates a malformed email address', (tester) async {
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(settings.saved, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves edited values and confirms with a snackbar', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      await editRow(tester, 'Business Name', 'Cafe Marina');
      await editRow(tester, 'Owner Name', 'Jana');
      await editRow(tester, 'Low Stock Alert', '2');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('Settings saved.'), findsOneWidget);
      expect(settings.saved, hasLength(1));
      expect(settings.saved.single.shopName, 'Cafe Marina');
      expect(settings.saved.single.ownerName, 'Jana');
      expect(settings.saved.single.lowStockThreshold, 2);
      expect(settings.saved.single.theme, ThemePreference.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a user-safe message when saving fails', (tester) async {
      settings.saveError = const UnexpectedSettingsSaveFailure();
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      await editRow(tester, 'Business Name', 'Cafe Marina');
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save settings. Please try again.'),
        findsOneWidget,
      );
      expect(settings.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the form usable after a failed save', (tester) async {
      settings.saveError = const UnexpectedSettingsSaveFailure();
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      await editRow(tester, 'Business Name', 'Cafe Marina');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.text('Cafe Marina'), findsOneWidget);

      // The failure snackbar floats over the save button; dismiss it so the
      // retry can reach the button again.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();

      settings.saveError = null;
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(settings.saved.single.shopName, 'Cafe Marina');
      expect(find.text('Settings saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Responsive layout', () {
    testWidgets('renders on a narrow phone viewport', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      expect(find.text('Save Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on the smallest supported phone viewport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      expect(find.text('Save Settings'), findsOneWidget);
      expect(find.text('Business Name'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on a wide desktop viewport', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpAuthenticated(tester);
      await tester.pumpAndSettle();

      expect(find.text('Save Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
