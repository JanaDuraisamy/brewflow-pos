import 'dart:io';
import 'dart:math' as math;

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_form_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_thumbnail.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchases_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_connectivity_service.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_customers_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_purchases_repository.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

final _themes = [AppTheme.dark, AppTheme.light];

double _luminance(Color color) {
  final channels = [
    for (final channel in [color.r, color.g, color.b])
      channel <= 0.04045
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble(),
  ];
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

double _contrast(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _harness(ThemeData theme, Widget page, List<Object?> overrides) =>
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: theme,
        home: Scaffold(body: page),
      ),
    );

Future<void> _pumpPage(
  WidgetTester tester,
  ThemeData theme,
  Widget page,
  List<Object?> overrides, {
  Size size = const Size(900, 1400),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(_harness(theme, page, overrides));
  await tester.pumpAndSettle();
}

void _expectScaffoldBackground(WidgetTester tester, ThemeData theme) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(Scaffold).first,
          matching: find.byType(Material),
        )
        .first,
  );
  expect(material.color, theme.scaffoldBackgroundColor);
}

void main() {
  group('AppTheme contract', () {
    test('both themes register the AppThemeColors extension', () {
      final lightExt = AppTheme.light.extension<AppThemeColors>();
      final darkExt = AppTheme.dark.extension<AppThemeColors>();
      expect(lightExt, isNotNull);
      expect(darkExt, isNotNull);

      expect(lightExt!.charcoal, AppThemeColors.light.charcoal);
      expect(lightExt.background, AppThemeColors.light.background);
      expect(lightExt.surface, AppThemeColors.light.surface);
      expect(lightExt.surfaceVariant, AppThemeColors.light.surfaceVariant);
      expect(lightExt.textPrimary, AppThemeColors.light.textPrimary);
      expect(lightExt.textSecondary, AppThemeColors.light.textSecondary);
      expect(lightExt.textDisabled, AppThemeColors.light.textDisabled);
      expect(lightExt.divider, AppThemeColors.light.divider);
      expect(lightExt.outline, AppThemeColors.light.outline);
      expect(lightExt.softGreen, AppThemeColors.light.softGreen);
      expect(lightExt.lightGray, AppThemeColors.light.lightGray);

      expect(darkExt!.charcoal, AppThemeColors.dark.charcoal);
      expect(darkExt.background, AppThemeColors.dark.background);
      expect(darkExt.surface, AppThemeColors.dark.surface);
      expect(darkExt.surfaceVariant, AppThemeColors.dark.surfaceVariant);
      expect(darkExt.textPrimary, AppThemeColors.dark.textPrimary);
      expect(darkExt.textSecondary, AppThemeColors.dark.textSecondary);
      expect(darkExt.textDisabled, AppThemeColors.dark.textDisabled);
      expect(darkExt.divider, AppThemeColors.dark.divider);
      expect(darkExt.outline, AppThemeColors.dark.outline);
      expect(darkExt.softGreen, AppThemeColors.dark.softGreen);
      expect(darkExt.lightGray, AppThemeColors.dark.lightGray);
    });

    test(
      'dark theme uses a dark scaffold distinct from the light scaffold',
      () {
        expect(AppTheme.dark.brightness, Brightness.dark);
        expect(AppTheme.light.brightness, Brightness.light);
        expect(
          AppTheme.dark.scaffoldBackgroundColor,
          isNot(AppTheme.light.scaffoldBackgroundColor),
        );
        expect(
          AppTheme.dark.extension<AppThemeColors>()!.surface,
          isNot(AppTheme.light.extension<AppThemeColors>()!.surface),
        );
      },
    );

    test('text tokens keep WCAG AA contrast on their surfaces', () {
      final dark = AppThemeColors.dark;
      expect(_contrast(dark.textPrimary, dark.surface), greaterThan(4.5));
      expect(_contrast(dark.textSecondary, dark.surface), greaterThan(4.5));
      expect(_contrast(dark.charcoal, dark.surface), greaterThan(4.5));
      expect(_contrast(dark.textPrimary, dark.background), greaterThan(4.5));

      final light = AppThemeColors.light;
      expect(_contrast(light.textPrimary, light.surface), greaterThan(4.5));
      expect(_contrast(light.textPrimary, light.background), greaterThan(4.5));
    });
  });

  group('screens render in both themes', () {
    testWidgets('Dashboard renders in light and dark without exceptions', (
      tester,
    ) async {
      final inventory = FakeInventoryRepository();
      await inventory.createCategory('Drinks');
      await inventory.createProduct(
        categoryId: 'category-1',
        name: 'Filter Coffee',
        sellingPricePaise: 1000,
        costPricePaise: 400,
        stockQuantity: 3,
        isActive: true,
      );

      for (final theme in _themes) {
        await _pumpPage(tester, theme, const DashboardPage(), [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: _owner),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          connectivityServiceProvider.overrideWithValue(
            fakeConnectivityService(),
          ),
        ], size: const Size(800, 2800));

        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Sales'), findsOneWidget);
        expect(find.text('Quick actions'), findsOneWidget);
        _expectScaffoldBackground(tester, theme);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Inventory renders in light and dark without exceptions', (
      tester,
    ) async {
      final inventory = FakeInventoryRepository();
      await inventory.createCategory('Beverages');
      await inventory.createProduct(
        categoryId: 'category-1',
        name: 'Filter Coffee',
        sellingPricePaise: 12000,
        costPricePaise: 5000,
        stockQuantity: 5,
        isActive: true,
      );

      for (final theme in _themes) {
        await _pumpPage(tester, theme, const InventoryPage(), [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: _owner),
          ),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
        ]);

        expect(find.text('Inventory'), findsOneWidget);
        expect(find.text('Filter Coffee'), findsWidgets);
        _expectScaffoldBackground(tester, theme);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('POS renders in light and dark without exceptions', (
      tester,
    ) async {
      final inventory = FakeInventoryRepository();
      await inventory.createCategory('Beverages');
      await inventory.createProduct(
        categoryId: 'category-1',
        name: 'Filter Coffee',
        sellingPricePaise: 12000,
        stockQuantity: 5,
        isActive: true,
      );
      final billing = FakeBillingRepository(inventory);

      for (final theme in _themes) {
        await _pumpPage(tester, theme, const PosPage(), [
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(billing),
          customersRepositoryProvider.overrideWithValue(
            FakeCustomersRepository(),
          ),
        ], size: const Size(1280, 800));

        expect(find.text('Filter Coffee'), findsWidgets);
        expect(find.text('Walk-in'), findsOneWidget);
        _expectScaffoldBackground(tester, theme);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Purchases renders in light and dark without exceptions', (
      tester,
    ) async {
      final suppliers = FakeSuppliersRepository();
      suppliers.storedSuppliers.add(
        Supplier(
          id: 's1',
          name: 'Acme Supplies',
          isActive: true,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      final purchases = FakePurchasesRepository();
      purchases.storedPurchases.add(
        Purchase(
          id: 'p1',
          supplierId: 's1',
          purchaseNumber: 'PUR-000001',
          subtotalPaise: 120000,
          totalPaise: 120000,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      for (final theme in _themes) {
        await _pumpPage(tester, theme, const PurchasesPage(), [
          suppliersRepositoryProvider.overrideWithValue(suppliers),
          purchasesRepositoryProvider.overrideWithValue(purchases),
        ], size: const Size(1200, 2000));

        expect(find.text('PUR-000001'), findsOneWidget);
        expect(find.text('Acme Supplies'), findsOneWidget);
        expect(find.text('New Purchase'), findsWidgets);
        _expectScaffoldBackground(tester, theme);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Settings renders in light and dark without exceptions', (
      tester,
    ) async {
      for (final theme in _themes) {
        await _pumpPage(tester, theme, const SettingsPage(), [
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
        ]);

        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Business identity'), findsOneWidget);
        _expectScaffoldBackground(tester, theme);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('product form renders in light and dark without exceptions', (
      tester,
    ) async {
      for (final theme in _themes) {
        await _pumpPage(tester, theme, const ProductFormPage(), [
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
        ]);

        expect(find.byType(ProductFormPage), findsOneWidget);
        _expectScaffoldBackground(tester, theme);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('dialogs and overlays in dark mode', () {
    testWidgets('POS customer picker dialog follows the dark theme', (
      tester,
    ) async {
      final inventory = FakeInventoryRepository();
      await inventory.createCategory('Beverages');
      await inventory.createProduct(
        categoryId: 'category-1',
        name: 'Filter Coffee',
        sellingPricePaise: 12000,
        stockQuantity: 5,
        isActive: true,
      );
      final billing = FakeBillingRepository(inventory);
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

      await _pumpPage(tester, AppTheme.dark, const PosPage(), [
        inventoryRepositoryProvider.overrideWithValue(inventory),
        billingRepositoryProvider.overrideWithValue(billing),
        customersRepositoryProvider.overrideWithValue(customers),
      ], size: const Size(1280, 800));

      await tester.tap(find.text('Walk-in'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Anand'), findsOneWidget);
      final dialogMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(dialogMaterial.color, AppThemeColors.dark.surface);
      expect(tester.takeException(), isNull);
    });
  });

  group('theme-aware widget regressions (dark)', () {
    Future<void> pumpThemed(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('AppCard resolves surface and divider from the theme', (
      tester,
    ) async {
      await pumpThemed(tester, const AppCard(child: Text('card')));

      final ink = tester.widget<Ink>(find.byType(Ink).first);
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color, AppThemeColors.dark.surface);
      expect(
        (decoration.border! as Border).top.color,
        AppThemeColors.dark.divider,
      );
    });

    testWidgets('SectionCard title uses charcoal from the theme', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const SectionCard(title: 'Section Title', child: Text('body')),
      );

      final title = tester.widget<Text>(find.text('Section Title'));
      expect(title.style?.color, AppThemeColors.dark.charcoal);
    });

    testWidgets('KpiCard value uses charcoal from the theme', (tester) async {
      await pumpThemed(
        tester,
        const KpiCard(
          label: 'Sales',
          value: '₹1,234.00',
          icon: Icons.currency_rupee,
        ),
      );

      final value = tester.widget<Text>(find.text('₹1,234.00'));
      expect(value.style?.color, AppThemeColors.dark.charcoal);
    });

    testWidgets('AppBottomNavigation follows the dark theme', (tester) async {
      await pumpThemed(
        tester,
        AppBottomNavigation(
          items: const [
            AppNavItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
            ),
            AppNavItem(
              label: 'Settings',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
            ),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      );

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.backgroundColor, AppThemeColors.dark.surface);
      expect(navBar.indicatorColor, AppThemeColors.dark.softGreen);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SearchField icons and fill follow the dark theme', (
      tester,
    ) async {
      await pumpThemed(tester, const SearchField(hintText: 'Search'));

      final searchIcon = tester.widget<Icon>(find.byIcon(Icons.search));
      expect(searchIcon.color, AppThemeColors.dark.textSecondary);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.fillColor, AppThemeColors.dark.lightGray);
    });

    testWidgets('EmptyState circle and text follow the dark theme', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Nothing here yet',
        ),
      );

      final circle = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.inventory_2_outlined),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (circle.decoration! as BoxDecoration).color,
        AppThemeColors.dark.softGreen,
      );
      final title = tester.widget<Text>(find.text('Nothing here yet'));
      expect(title.style?.color, AppThemeColors.dark.charcoal);
    });

    testWidgets('selected AppFilterChip uses brand primary in both themes', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        AppFilterChip(label: 'Beverages', selected: true, onSelected: (_) {}),
      );

      final chip = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final border = (chip.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, AppTheme.dark.colorScheme.primary);
      expect(border.top.width, 1.5);
      final label = tester.widget<Text>(find.text('Beverages'));
      expect(label.style?.color, AppTheme.dark.colorScheme.primary);
    });

    testWidgets('AlertCard pill stays white-on-accent and chevron is themed', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const AlertCard(
          icon: Icons.warning_amber_rounded,
          title: 'Low stock',
          message: 'Filter Coffee is running low',
          accent: AppColors.lowStock,
          count: 2,
          onTap: _noopTap,
        ),
      );

      final pill = tester.widget<Text>(find.text('2'));
      expect(pill.style?.color, Colors.white);
      final chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
      expect(chevron.color, AppThemeColors.dark.textDisabled);
      final title = tester.widget<Text>(find.text('Low stock'));
      expect(title.style?.color, AppThemeColors.dark.charcoal);
    });

    testWidgets('NotificationBell defaults its icon to textPrimary', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const NotificationBell(count: 0, onPressed: null),
      );

      final bell = tester.widget<Icon>(
        find.byIcon(Icons.notifications_outlined),
      );
      expect(bell.color, AppThemeColors.dark.textPrimary);
    });

    testWidgets('ProductThumbnail placeholder uses dark surface variant', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productImageStoreProvider.overrideWith(
              // No real filesystem access: the null imagePath never resolves,
              // so a dummy documents dir is enough (real IO cannot complete in
              // the widget-test fake-async zone).
              (ref) async =>
                  ProductImageStore(documentsDir: Directory('dummy_docs')),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: ProductThumbnail(imagePath: null, size: 44),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final placeholder = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.inventory_2_outlined),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (placeholder.decoration! as BoxDecoration).color,
        AppThemeColors.dark.surfaceVariant,
      );
      final glyph = tester.widget<Icon>(
        find.byIcon(Icons.inventory_2_outlined),
      );
      expect(glyph.color, AppThemeColors.dark.textDisabled);
    });

    testWidgets('AppSidebar stays brand dark with white text in dark mode', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const AppSidebar(
          items: [
            AppNavItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
            ),
          ],
          selectedIndex: 0,
          onDestinationSelected: _noop,
        ),
      );

      final sidebar = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppSidebar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(sidebar.color, AppColors.primaryDark);
      expect(find.text('BrewFlow'), findsOneWidget);
      final brand = tester.widget<Text>(find.text('BrewFlow'));
      expect(brand.style?.color, Colors.white);
    });

    testWidgets('BrandMark wordmark follows the theme on light variants', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const BrewFlowBrand(
          variant: BrandMarkVariant.onLight,
          showEdition: true,
        ),
      );

      final wordmark = tester.widget<Text>(find.text('BrewFlow'));
      expect(wordmark.style?.color, AppThemeColors.dark.charcoal);
    });
  });
}

void _noop(int index) {}

void _noopTap() {}
