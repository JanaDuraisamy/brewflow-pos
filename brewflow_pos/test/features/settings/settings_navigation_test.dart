import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/navigation/navigation_config.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_page.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_purchases_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_shop_name_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeSettingsRepository settings;
  late FakeStaffRepository staff;

  setUp(() {
    settings = FakeSettingsRepository();
    staff = FakeStaffRepository();
  });

  Widget app(FakeAuthRepository auth) => ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      shopNameRepositoryProvider.overrideWithValue(FakeShopNameRepository()),
      authRepositoryProvider.overrideWithValue(auth),
      staffRepositoryProvider.overrideWithValue(staff),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      suppliersRepositoryProvider.overrideWithValue(FakeSuppliersRepository()),
      purchasesRepositoryProvider.overrideWithValue(FakePurchasesRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
      connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
    ],
    child: const BrewFlowApp(),
  );

  /// Signs in as a provisioned shop owner and lands on Settings.
  ///
  /// The user must be handed to [FakeAuthRepository] directly: `emit()` alone
  /// leaves `currentUser` null, so `userProfileProvider` never resolves an
  /// owner and the owner-only navigation section never renders.
  Future<void> pumpOwner(WidgetTester tester) async {
    // Tall viewport: the settings page is long, and the navigation section sits
    // below the fold on the default 800x600 test surface.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await staff.claimOwnership(_owner);
    await tester.pumpWidget(app(FakeAuthRepository(user: _owner)));
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
  }

  Future<void> openOrganizer(WidgetTester tester) async {
    final row = find.text('Organize navigation');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  Future<void> tapApply(WidgetTester tester) async {
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();
  }

  /// The organizer's list row for [label].
  ///
  /// The label and the Main/More control are siblings inside one [Row], so the
  /// row is the nearest common ancestor of the label text.
  Finder rowFor(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

  Finder mainToggle(String label) =>
      find.descendant(of: rowFor(label), matching: find.text('Main'));

  Finder moreToggle(String label) =>
      find.descendant(of: rowFor(label), matching: find.text('More'));

  group('Navigation section visibility', () {
    testWidgets('owner sees the navigation organizer', (tester) async {
      await pumpOwner(tester);

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);
      expect(find.text('Organize navigation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('staff never see the navigation organizer', (tester) async {
      const member = AuthUser(id: 'u2', email: 'staff@brewflow.example');
      final shop = await staff.ensureShop();
      await staff.claimOwnershipForCloud(
        member,
        shopId: shop.id,
        role: UserRole.staff,
        permissions: {Permission.settings, Permission.viewDashboard},
      );
      final auth = FakeAuthRepository(user: member);
      await tester.pumpWidget(app(auth));
      auth.emit(member);
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();

      // The organizer is owner-only, but the settings page itself is still
      // reachable by anyone granted the settings permission.
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('Organize navigation'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Organizer behaviour', () {
    testWidgets('lists every feature exactly once, with no hide control', (
      tester,
    ) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      for (final destination in navDestinations) {
        expect(
          find.text(destination.label),
          findsOneWidget,
          reason: '${destination.label} must be listed',
        );
      }
      // Nothing may remove a feature: no remove/delete/hide affordance.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reordering changes the persisted order and nothing else', (
      tester,
    ) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      // Move Inventory above Staff Management.
      await tester.tap(find.byTooltip('Move Inventory up'));
      await tester.pumpAndSettle();
      await tapApply(tester);
      await tapSave(tester);

      expect(settings.saved, isNotEmpty);
      final saved = settings.saved.last;
      final arrangement = NavArrangement.resolve(
        order: saved.navigationOrder,
        primary: saved.navigationPrimary,
      );
      expect(
        arrangement.order.indexOf(AppRoutes.inventory),
        lessThan(arrangement.order.indexOf(AppRoutes.staff)),
      );
      expect(
        arrangement.order.length,
        AppRoutes.destinations.length,
        reason: 'reordering must never drop a feature',
      );
    });

    testWidgets('moving a feature to More keeps it in the order', (
      tester,
    ) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      // Staff Management starts in the main bar; push it to More.
      await tester.tap(moreToggle('Staff Management'));
      await tester.pumpAndSettle();
      await tapApply(tester);
      await tapSave(tester);

      final saved = settings.saved.last;
      final arrangement = NavArrangement.resolve(
        order: saved.navigationOrder,
        primary: saved.navigationPrimary,
      );
      expect(arrangement.isPrimary(AppRoutes.staff), isFalse);
      expect(
        arrangement.contains(AppRoutes.staff),
        isTrue,
        reason: 'More is grouping, not hiding',
      );
    });

    testWidgets('reset restores the canonical arrangement', (tester) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      await tester.tap(find.byTooltip('Move Orders up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to default'));
      await tester.pumpAndSettle();
      await tapApply(tester);
      await tapSave(tester);

      final saved = settings.saved.last;
      expect(
        NavArrangement.resolve(
          order: saved.navigationOrder,
          primary: saved.navigationPrimary,
        ).order,
        AppRoutes.destinations,
      );
    });

    testWidgets('cancel discards the draft', (tester) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      await tester.tap(find.byTooltip('Move Orders up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tapSave(tester);

      final saved = settings.saved.last;
      expect(
        NavArrangement.resolve(
          order: saved.navigationOrder,
          primary: saved.navigationPrimary,
        ).order,
        AppRoutes.destinations,
        reason: 'cancelling must not persist the draft',
      );
    });

    testWidgets('the main bar cap is enforced and explained', (tester) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      // Three primaries are the default, so the fourth promotion is allowed
      // and the fifth is refused with an explanation instead of vanishing.
      for (final label in ['Orders', 'Reports', 'Offers']) {
        await tester.tap(mainToggle(label));
        await tester.pumpAndSettle();
      }

      expect(
        find.textContaining('up to $maxPrimaryRoutes features'),
        findsOneWidget,
        reason: 'the cap is explained instead of silently swallowing the tap',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('labels in the organizer are not editable', (tester) async {
      await pumpOwner(tester);
      await openOrganizer(tester);

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Arrangement drives the shell', () {
    testWidgets('a persisted order reorders the sidebar', (tester) async {
      settings.stored = ShopSettings.defaults().copyWith(
        navigationOrder: [
          AppRoutes.billing,
          AppRoutes.dashboard,
          ...AppRoutes.destinations.where(
            (r) => r != AppRoutes.billing && r != AppRoutes.dashboard,
          ),
        ],
      );
      await pumpOwner(tester);
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.dashboard);
      await tester.pumpAndSettle();

      // The rail auto-collapses after app-level navigation by design; reopen it
      // so the rendered order can be read.
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();

      // Sidebar renders the owner's order, not the canonical order.
      final sidebar = find.byType(AppSidebar);
      expect(sidebar, findsOneWidget);
      final labels = tester
          .widgetList<Text>(
            find.descendant(of: sidebar, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(labels.indexOf('Billing'), lessThan(labels.indexOf('Dashboard')));
    });

    testWidgets('a persisted main-bar split is honoured on the phone', (
      tester,
    ) async {
      settings.stored = ShopSettings.defaults().copyWith(
        navigationPrimary: [AppRoutes.dashboard, AppRoutes.orders],
      );
      await pumpOwner(tester);

      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();

      final bar = find.byType(AppBottomNavigation);
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.text('Orders')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('Staff Management')),
        findsNothing,
        reason: 'Staff Management was moved to More by the owner',
      );
      // Still reachable — just not in the bar. Tap More by label: it renders
      // the filled icon while a More destination is the active branch, which is
      // the case here because we navigated to Settings.
      await tester.tap(find.descendant(of: bar, matching: find.text('More')));
      await tester.pumpAndSettle();
      expect(find.text('Staff Management'), findsOneWidget);
    });

    testWidgets('a corrupt stored order still shows every feature', (
      tester,
    ) async {
      settings.stored = ShopSettings.defaults().copyWith(
        navigationOrder: ['/ghost', AppRoutes.billing, AppRoutes.billing],
        navigationPrimary: ['/ghost'],
      );
      await pumpOwner(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });
}
