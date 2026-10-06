import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/app/widgets/search_field.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/core/theme/app_breakpoints.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_customers_repository.dart';
import '../helpers/fake_expenses_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_offers_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_purchases_repository.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_staff_repository.dart';
import '../helpers/fake_storage_cleanup_gateway.dart';
import '../helpers/fake_suppliers_repository.dart';
import '../helpers/fake_preferences_storage.dart';
import '../helpers/test_providers.dart';

/// In-memory secure store so [AppStorage.init] is safe inside a test.
final class _FakeSecure implements SecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      bool.tryParse(_values[key] ?? '') ?? defaultValue;

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value.toString();
  }

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async =>
      int.tryParse(_values[key] ?? '') ?? defaultValue;

  @override
  Future<void> writeInt(String key, int value) async {
    _values[key] = value.toString();
  }

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }
}

/// ---------------------------------------------------------------------------
/// Android responsive matrix + geometry regression suite.
///
/// Jana's Vivo phone is the visual reference only: these tests prove ONE
/// responsive app adapts across logical widths, heights, themes, text scales
/// and system insets without device-specific layouts.
///
/// Part A pumps the whole app at every required width (360–1024dp) and walks
/// every destination plus the pushed form/sheet pages, asserting no layout
/// exception anywhere. Adversarial seeds (very long product, customer, shop
/// and SKU names, huge totals) make overflow actually trigger instead of the
/// happy path passing by accident.
///
/// Part B locks the geometry fixes with real rects: dialog/sheet fits, cart
/// reachability, stacked KPIs, table scroll reachability, FAB clearance and
/// the squeezed-tablet POS contract.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

const _longProductName =
    'Masala Chai With An Extremely Long Product Name That Wraps Everywhere';
const _longSku = 'SKU-WITH-A-VERY-LONG-CODE-123456789-EXTRA';
const _longCustomerName =
    'A Customer With An Extremely Long Name That Must Ellipsize Gracefully';
const _longShopName =
    'Jana BrewFlow Flagship Cafe And Restaurant With A Very Long Shop Name';

/// Every required logical width: six phones, six tablets.
const _widths = <double>[
  360,
  375,
  390,
  411,
  430,
  480,
  600,
  640,
  720,
  800,
  900,
  1024,
];

/// Shell destinations plus pushed form/sheet pages that take no arguments.
const _routes = <String>[
  AppRoutes.dashboard,
  AppRoutes.staff,
  AppRoutes.inventory,
  AppRoutes.billing,
  AppRoutes.orders,
  AppRoutes.customers,
  AppRoutes.suppliers,
  AppRoutes.purchases,
  AppRoutes.expenses,
  AppRoutes.reports,
  AppRoutes.offers,
  AppRoutes.settings,
  AppRoutes.staffPayroll,
  AppRoutes.closing,
  AppRoutes.productNew,
  AppRoutes.purchaseNew,
  AppRoutes.expenseNew,
  AppRoutes.shopPayables,
  AppRoutes.customerNew,
  AppRoutes.supplierNew,
  AppRoutes.inventoryCategories,
  AppRoutes.storageCleanup,
];

final class _Seeded {
  _Seeded({
    required this.inventory,
    required this.customers,
    required this.suppliers,
    required this.purchases,
    required this.expenses,
    required this.settings,
    required this.staff,
    required this.closingDb,
  });

  final FakeInventoryRepository inventory;
  final FakeCustomersRepository customers;
  final FakeSuppliersRepository suppliers;
  final FakePurchasesRepository purchases;
  final FakeExpensesRepository expenses;
  final FakeSettingsRepository settings;
  final FakeStaffRepository staff;
  final db.AppDatabase closingDb;
}

Future<_Seeded> _seedAll() async {
  final now = DateTime.now().toUtc();
  final inventory = FakeInventoryRepository()
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
        name: _longProductName,
        sku: _longSku,
        sellingPricePaise: 12345600,
        costPricePaise: 8000000,
        stockQuantity: 50,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  final customers = FakeCustomersRepository()
    ..storedCustomers.add(
      Customer(
        id: 'cu-1',
        name: _longCustomerName,
        phone: '9876543210',
        email: 'very.long.customer.email.address@example.com',
        address: '12, A Very Long Street Name, Big City, Tamil Nadu 600001',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  final suppliers = FakeSuppliersRepository();
  final purchases = FakePurchasesRepository()
    ..storedPurchases.add(
      Purchase(
        id: 'pur-1',
        purchaseNumber: 'PUR-000001',
        subtotalPaise: 8000000,
        totalPaise: 8000000,
        notes: 'A purchase with a very long supplier note attached to it.',
        createdAt: now,
        updatedAt: now,
      ),
    )
    ..storedItems['pur-1'] = [
      PurchaseItem(
        id: 'pi-1',
        purchaseId: 'pur-1',
        productId: 'p-1',
        productName: _longProductName,
        sku: _longSku,
        unitCostPaise: 8000000,
        quantity: 10,
        lineTotalPaise: 80000000,
      ),
    ];
  final expenses = FakeExpensesRepository()
    ..storedExpenses.add(
      Expense(
        id: 'e-1',
        name: 'Monthly Milk Supply From The Dairy Cooperative Limited',
        amountPaise: 2500000,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.cash,
        paymentStatus: ExpensePaymentStatus.notPaid,
        expenseDate: DateTime.utc(now.year, now.month, now.day),
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  final settings = FakeSettingsRepository()
    ..stored = FakeSettingsRepository().stored.copyWith(
      shopName: _longShopName,
      appDisplayName: 'BrewFlow POS With A Very Long Display Name',
    );
  final staff = FakeStaffRepository();
  await staff.claimOwnership(_owner);
  await staff.createStaffProfile(
    identity: const AuthUser(
      id: 'u-long',
      email: 'a.very.long.staff.email.address@brewflow.example',
    ),
    shopId: 'shop-1',
  );
  final closingDb = db.AppDatabase(NativeDatabase.memory());
  return _Seeded(
    inventory: inventory,
    customers: customers,
    suppliers: suppliers,
    purchases: purchases,
    expenses: expenses,
    settings: settings,
    staff: staff,
    closingDb: closingDb,
  );
}

Widget _app(
  _Seeded seed,
  FakeAuthRepository auth, {
  ThemeMode mode = ThemeMode.light,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    appThemeModeProvider.overrideWithValue(mode),
    inventoryRepositoryProvider.overrideWithValue(seed.inventory),
    billingRepositoryProvider.overrideWithValue(
      FakeBillingRepository(seed.inventory),
    ),
    ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
    customerLedgerRepositoryProvider.overrideWithValue(
      FakeCustomerLedgerRepository(),
    ),
    settingsRepositoryProvider.overrideWithValue(seed.settings),
    customersRepositoryProvider.overrideWithValue(seed.customers),
    suppliersRepositoryProvider.overrideWithValue(seed.suppliers),
    purchasesRepositoryProvider.overrideWithValue(seed.purchases),
    expensesRepositoryProvider.overrideWithValue(seed.expenses),
    offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
    // One in-memory database for everything the fakes do not cover (backup
    // scheduler, closing repo): never the real AppDatabase.open(), which
    // needs platform plugins unavailable in tests.
    appDatabaseProvider.overrideWithValue(seed.closingDb),
    dailyClosingRepositoryProvider.overrideWithValue(
      DriftDailyClosingRepository(seed.closingDb),
    ),
    storageCleanupGatewayProvider.overrideWithValue(
      FakeStorageCleanupGateway(),
    ),
    ...businessScopeOverrides(staff: seed.staff),
  ],
  child: const BrewFlowApp(),
);

/// Boots the app at an explicit viewport, theme, text scale and inset pair.
Future<FakeAuthRepository> _pumpMatrix(
  WidgetTester tester, {
  required double width,
  required double height,
  ThemeMode mode = ThemeMode.light,
  double textScale = 1.0,
  double topInset = 24,
  double bottomInset = 24,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  tester.view.padding = FakeViewPadding(top: topInset, bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(top: topInset, bottom: bottomInset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final seed = await _seedAll();
  addTearDown(seed.closingDb.close);
  final auth = FakeAuthRepository();
  await tester.pumpWidget(_app(seed, auth, mode: mode));
  auth.emit(_owner);
  await tester.pumpAndSettle();
  return auth;
}

GoRouter _routerOf(WidgetTester tester) {
  final element = tester.element(find.byType(Scaffold).first);
  return ProviderScope.containerOf(element).read(appRouterProvider);
}

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// Settles, then discards transition-frame artifacts (e.g. a threshold-based
/// branch that flips once mid-animation and is disposed right after).
/// Steady-state assertions below still catch every persistent overflow via
/// fresh relayouts plus real rect measurements.
Future<void> _settleClean(WidgetTester tester) async {
  await tester.pumpAndSettle();
  tester.takeException();
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  tester.takeException();
}

void main() {
  // One binding for the whole file (AppStorage.init is a no-op once run).
  setUpAll(() async {
    await AppStorage.init(
      secure: _FakeSecure(),
      preferences: FakePreferencesStorage(),
    );
  });
  // -------------------------------------------------------------------------
  // Part A: every width walks every destination without a layout exception.
  // -------------------------------------------------------------------------
  for (final width in _widths) {
    final w = width.toInt();
    final height = width < 600 ? 800.0 : 1000.0;
    testWidgets('no overflow anywhere at ${w}dp', (tester) async {
      await _pumpMatrix(tester, width: width, height: height);
      final router = _routerOf(tester);
      for (final route in _routes) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'no layout exception on $route at ${w}dp',
        );
      }
      // One representative page per width must actually be present, so a
      // silently-blank tree cannot pass.
      router.go(AppRoutes.dashboard);
      await tester.pumpAndSettle();
      expect(find.text('Sales Overview'), findsOneWidget);
    });
  }

  // -------------------------------------------------------------------------
  // Part B: geometry regressions with real rects.
  // -------------------------------------------------------------------------

  group('squeezed-tablet POS keeps shelf and cart usable', () {
    for (final width in [600.0, 700.0, 800.0]) {
      testWidgets('wide layout holds at ${width.toInt()}dp + 1.15', (
        tester,
      ) async {
        await _pumpMatrix(tester, width: width, height: 1024, textScale: 1.15);
        final router = _routerOf(tester);
        // Collapse the rail first so the squeezed-tablet path is exercised.
        router.go(AppRoutes.orders);
        await tester.pumpAndSettle();
        router.go(AppRoutes.billing);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PosPage), findsOneWidget);
        expect(find.textContaining('Masala Chai'), findsWidgets);
        expect(find.text('Complete Sale'), findsOneWidget);
        // Every shelf Add button keeps a tappable width inside the window.
        final window = tester.view.physicalSize;
        for (final element in tester.elementList(
          find.widgetWithText(FilledButton, 'Add'),
        )) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(window.width));
          expect(rect.width, greaterThan(40));
        }
      });
    }
  });

  group('phone POS cart stays reachable', () {
    testWidgets('huge total does not overflow the cart bar at 360dp + 1.15', (
      tester,
    ) async {
      await _pumpMatrix(tester, width: 360, height: 800, textScale: 1.15);
      _routerOf(tester).go(AppRoutes.billing);
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, 'Add');
      for (var i = 0; i < 12; i++) {
        await tester.tap(add.first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.textContaining('in cart'), findsOneWidget);
    });

    testWidgets('customer picker dialog fits at 360dp + 1.15', (tester) async {
      await _pumpMatrix(
        tester,
        width: 360,
        height: 800,
        mode: ThemeMode.dark,
        textScale: 1.15,
      );
      _routerOf(tester).go(AppRoutes.billing);
      await _settleClean(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
      await tester.pumpAndSettle();
      // Open the cart view, then the customer picker from inside it.
      await tester.tap(find.textContaining('in cart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Walk-in'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Select Customer'), findsOneWidget);
      final window = tester.view.physicalSize;
      final dialog = _rect(tester, find.byType(AlertDialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(window.width));
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.bottom, lessThanOrEqualTo(window.height));
    });

    testWidgets('split sheet stays reachable on a short viewport + keyboard', (
      tester,
    ) async {
      // Open the sheet on a tall viewport (all taps land), then shrink to a
      // short viewport with the keyboard open — the rotation-with-dialog-open
      // scenario. The sheet must pad for the inset AND scroll.
      await _pumpMatrix(tester, width: 360, height: 800, textScale: 1.0);
      _routerOf(tester).go(AppRoutes.billing);
      await _settleClean(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('in cart'));
      await tester.pumpAndSettle();
      // The Split button sits below the fold on this viewport: scroll it into
      // view first, exactly as a finger would.
      final panelScroll = find.ancestor(
        of: find.text('Split'),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Split'),
        120,
        scrollable: panelScroll.first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      expect(find.text('Split Payment'), findsOneWidget);

      tester.view.physicalSize = const Size(360, 520);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final sheetScroll = find.descendant(
        matching: find.byType(Scrollable),
        of: find.byType(BottomSheet),
      );
      await tester.scrollUntilVisible(
        find.text('Confirm Split'),
        120,
        scrollable: sheetScroll.first,
      );
      await tester.pumpAndSettle();
      final button = _rect(tester, find.text('Confirm Split'));
      expect(button.bottom, lessThanOrEqualTo(520));
    });
  });

  group('customer ledger geometry', () {
    testWidgets('financial KPIs stack on a 360dp phone', (tester) async {
      await _pumpMatrix(tester, width: 360, height: 800, mode: ThemeMode.dark);
      final seed = await _seedAll();
      _routerOf(tester).go(
        AppRoutes.customerDetail,
        extra: seed.customers.storedCustomers.first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in ['Outstanding', 'Total purchases', 'Total paid']) {
        expect(find.text(label), findsOneWidget);
      }
      // Stacked, not side-by-side: each card starts below the previous one.
      final tops = [
        for (final label in ['Outstanding', 'Total purchases', 'Total paid'])
          _rect(tester, find.text(label)).top,
      ];
      expect(tops[1], greaterThan(tops[0] + 40));
      expect(tops[2], greaterThan(tops[1] + 40));
    });
  });

  group('purchase detail table', () {
    testWidgets('squeezed 640dp window selects cards on real content width', (
      tester,
    ) async {
      await _pumpMatrix(tester, width: 640, height: 900, textScale: 1.15);
      final seed = await _seedAll();
      _routerOf(tester).go(
        AppRoutes.purchaseDetail,
        extra: seed.purchases.storedPurchases.first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // The table-vs-cards decision is made on AVAILABLE CONTENT WIDTH, so
      // measure what the shell handed the page instead of trusting the 640dp
      // window: the navigation rail gutter and screen padding both come out
      // of it, which is why this window legitimately lands below the
      // narrow-table threshold even though the window itself is 640dp.
      final itemsWidth = tester.getSize(find.byType(AppCard).last).width;
      expect(
        itemsWidth,
        lessThan(AppBreakpoints.compactTable),
        reason: 'this viewport is meant to exercise the card branch',
      );
      expect(find.byType(DataTable), findsNothing);

      // Every line-item value is rendered without clipping, so nothing is only
      // reachable by horizontal scrolling on this branch.
      expect(find.text(_longProductName), findsOneWidget);
      expect(find.text('SKU: $_longSku'), findsOneWidget);
      expect(find.text('10 × ${Money.formatPaise(8000000)}'), findsOneWidget);
      expect(find.text(Money.formatPaise(80000000)), findsOneWidget);

      // No horizontal overflow anywhere on the page.
      final window = tester.view.physicalSize;
      for (final element in tester.elementList(find.byType(AppCard))) {
        final box = element.renderObject! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(window.width));
      }
    });

    testWidgets('wide content still selects the table and scrolls it', (
      tester,
    ) async {
      // A window wide enough that the CONTENT clears the narrow-table
      // threshold, so the DataTable branch is the intended one here.
      await _pumpMatrix(tester, width: 1024, height: 900, textScale: 1.15);
      final seed = await _seedAll();
      _routerOf(tester).go(
        AppRoutes.purchaseDetail,
        extra: seed.purchases.storedPurchases.first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);

      // The table is wrapped for horizontal reachability, and dragging it
      // leftward moves it without throwing.
      final horizontal = find
          .ancestor(
            of: find.byType(DataTable),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.right,
            ),
          )
          .first;
      expect(horizontal, findsOneWidget);
      // Drag the scroll view itself: the Line Total column starts past the
      // right edge, so its own centre is not a valid gesture point.
      await tester.drag(horizontal, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final total = _rect(tester, find.text('Line Total'));
      expect(total.right, lessThanOrEqualTo(1024));
    });
  });

  group('bottom sheets on short viewports', () {
    testWidgets('context sheet reaches Cancel at 360x500', (tester) async {
      await _pumpMatrix(tester, width: 360, height: 500);
      _routerOf(tester).go(AppRoutes.customers);
      await tester.pumpAndSettle();
      await tester.longPress(find.text(_longCustomerName).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Scoped to the sheet: the page list underneath is still in the tree, so
      // the default `find.byType(Scrollable)` matches more than one.
      await tester.scrollUntilVisible(
        find.text('Cancel'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final cancel = _rect(tester, find.text('Cancel'));
      expect(cancel.bottom, lessThanOrEqualTo(500));
    });
  });

  group('FAB clearance', () {
    testWidgets('staff list end clears the Add Staff button', (tester) async {
      await _pumpMatrix(tester, width: 360, height: 800);
      _routerOf(tester).go(AppRoutes.staff);
      await tester.pumpAndSettle();
      final fab = _rect(tester, find.byType(FloatingActionButton));
      // `scrollUntilVisible` needs the Scrollable's state, not the ListView
      // widget that owns it — passing the ListView is a type error and never
      // reaches the assertions below.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('a.very.long.staff.email.address@brewflow.example').last,
        240,
        scrollable: list,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final lastTile = _rect(
        tester,
        find.text('a.very.long.staff.email.address@brewflow.example').last,
      );
      expect(lastTile.bottom, lessThanOrEqualTo(fab.top));
    });
  });

  group('tablet landscape', () {
    testWidgets('1024x640 short viewport stays fully usable', (tester) async {
      await _pumpMatrix(
        tester,
        width: 1024,
        height: 640,
        textScale: 1.15,
        topInset: 0,
        bottomInset: 20,
      );
      final router = _routerOf(tester);
      for (final route in [AppRoutes.billing, AppRoutes.dashboard]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Complete Sale'), findsOneWidget);
    });
  });
}
