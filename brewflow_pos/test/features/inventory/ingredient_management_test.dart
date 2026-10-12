import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/ingredient_detail_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/ingredient_form_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_history_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_form_page.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/test_providers.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_stock_movement_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Ingredient Management (Phase 3) contract.
///
/// Owners create tracked stock-source ingredients through the existing
/// product flow (`isIngredient: true`, zero stock, no movements) and audit
/// them through the existing history / purchase / adjustment workflows.
/// Creation never touches existing products, recipes or stock; the
/// controller enforces ownership and write scoping — hidden buttons are
/// never the only protection.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;

  final now = DateTime.now().toUtc();

  Category category(String id, String name) => Category(
    id: id,
    name: name,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    shopId: kTestCafeShopId,
  );

  Product product(
    String id,
    String name, {
    int stockQuantity = 0,
    StockUnit stockUnit = StockUnit.count,
    bool isIngredient = false,
    String shopId = kTestCafeShopId,
  }) => Product(
    id: id,
    categoryId: 'c1',
    name: name,
    sellingPricePaise: 4500,
    stockQuantity: stockQuantity,
    stockUnit: stockUnit,
    isActive: true,
    shopId: shopId,
    isIngredient: isIngredient,
    createdAt: now,
    updatedAt: now,
  );

  void seedMaggiWorld() {
    fakeInventory.storedCategories.add(category('c1', 'Dry Goods'));
    fakeInventory.storedProducts.addAll([
      product('ing-1', 'Maggi Packet', stockQuantity: 10, isIngredient: true),
      product('dish-1', 'Plain Maggi'),
    ]);
  }

  Future<void> mapRecipe(String productId, {String ingredientId = 'ing-1'}) =>
      fakeInventory.setRecipe(
        productId: productId,
        ingredients: [RecipeIngredientInput(ingredientProductId: ingredientId)],
      );

  ProviderContainer buildContainer({UserProfile? profile}) => ProviderContainer(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(fakeInventory),
      ...businessScopeOverrides(profile: profile),
      ...connectivityOverrides(),
    ],
  );

  /// A signed-in STAFF member with inventory-edit permission: proves the
  /// owner gate specifically, since the permission gate alone would pass.
  Future<ProviderContainer> staffContainer() async {
    final staffRepo = FakeStaffRepository();
    const member = AuthUser(id: 'staff-1', email: 'staff@brewflow.test');
    final shop = await staffRepo.ensureShop();
    await staffRepo.claimOwnershipForCloud(
      member,
      shopId: shop.id,
      role: UserRole.staff,
      permissions: {Permission.editInventory, Permission.viewInventory},
    );
    final container = ProviderContainer(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(fakeInventory),
        staffRepositoryProvider.overrideWithValue(staffRepo),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: member),
        ),
      ],
    );
    addTearDown(container.dispose);
    final profile = await container.read(userProfileProvider.future);
    expect(profile!.isOwner, isFalse);
    return container;
  }

  Future<Product?> productById(String id) async {
    final items = await fakeInventory.products();
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
  });

  group('createIngredient', () {
    test('creates a tracked hidden ingredient at zero stock', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);

      final created = await container
          .read(sharedStockOverviewProvider.notifier)
          .createIngredient(
            categoryId: 'c1',
            name: 'Sugar',
            stockUnit: StockUnit.gram,
          );

      expect(created.isIngredient, isTrue);
      expect(created.name, 'Sugar');
      expect(created.stockQuantity, 0);
      expect(created.stockUnit, StockUnit.gram);
      expect(created.isActive, isTrue);
      expect(created.sellingPricePaise, 0);
      expect(created.shopId, kTestCafeShopId);
      // No mapping was invented for it, and the overview picks it up.
      expect(await fakeInventory.recipesForProduct(created.id), isEmpty);
      final overview = await container.read(sharedStockOverviewProvider.future);
      expect(
        overview.ingredients.map((entry) => entry.product.name),
        contains('Sugar'),
      );
    });

    test('refuses a same-shop twin without writing', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);
      final before = fakeInventory.storedProducts.length;

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .createIngredient(
              categoryId: 'c1',
              name: 'maggi PACKET',
              stockUnit: StockUnit.count,
            ),
        throwsA(
          isA<DuplicateIngredientNameFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Maggi Packet'),
          ),
        ),
      );
      expect(fakeInventory.storedProducts, hasLength(before));
    });

    test('allows the same name in another shop', () async {
      seedMaggiWorld();
      fakeInventory.storedProducts.add(
        product('ing-2', 'Sugar', isIngredient: true, shopId: 'shop-2'),
      );
      final container = buildContainer();
      addTearDown(container.dispose);

      final created = await container
          .read(sharedStockOverviewProvider.notifier)
          .createIngredient(
            categoryId: 'c1',
            name: 'sugar',
            stockUnit: StockUnit.gram,
          );

      // A different row in this shop — the truck's Sugar is untouched.
      expect(created.shopId, kTestCafeShopId);
      expect(await productById('ing-2'), isNotNull);
    });

    test('refuses untracked stock without writing', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .createIngredient(
              categoryId: 'c1',
              name: 'Loose Garnish',
              stockUnit: StockUnit.none,
            ),
        throwsA(isA<RecipeUntrackedIngredientFailure>()),
      );
      expect(
        fakeInventory.storedProducts.map((item) => item.name),
        isNot(contains('Loose Garnish')),
      );
    });

    test('refuses blank names and unknown categories', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sharedStockOverviewProvider.notifier);

      await expectLater(
        notifier.createIngredient(
          categoryId: 'c1',
          name: '   ',
          stockUnit: StockUnit.count,
        ),
        throwsA(isA<UnexpectedInventoryFailure>()),
      );
      await expectLater(
        notifier.createIngredient(
          categoryId: 'nope',
          name: 'Sugar',
          stockUnit: StockUnit.count,
        ),
        throwsA(isA<UnexpectedInventoryFailure>()),
      );
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    test('a staff member with edit permission cannot create', () async {
      seedMaggiWorld();
      final container = await staffContainer();

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .createIngredient(
              categoryId: 'c1',
              name: 'Sugar',
              stockUnit: StockUnit.gram,
            ),
        throwsA(isA<PermissionDeniedFailure>()),
      );
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    test('fails closed from the read-only All view', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);
      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.all);

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .createIngredient(
              categoryId: 'c1',
              name: 'Sugar',
              stockUnit: StockUnit.gram,
            ),
        throwsA(isA<RecipeReadOnlyScopeFailure>()),
      );
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    test('leaves Maggi mappings and stock exactly as they were', () async {
      seedMaggiWorld();
      await mapRecipe('dish-1');
      final rowsBefore = await fakeInventory.recipesForProduct('dish-1');
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(sharedStockOverviewProvider.notifier)
          .createIngredient(
            categoryId: 'c1',
            name: 'Sugar',
            stockUnit: StockUnit.gram,
          );

      final rowsAfter = await fakeInventory.recipesForProduct('dish-1');
      expect(rowsAfter.map((row) => row.id), rowsBefore.map((row) => row.id));
      expect((await productById('ing-1'))!.stockQuantity, 10);
    });
  });

  group('IngredientFormSheet', () {
    Widget app({FakeStaffRepository? staff, UserProfile? profile}) =>
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
            customerLedgerRepositoryProvider.overrideWithValue(
              FakeCustomerLedgerRepository(),
            ),
            staffRepositoryProvider.overrideWithValue(
              staff ?? FakeStaffRepository(),
            ),
            userProfileProvider.overrideWithBuild(
              (ref, notifier) => profile ?? testOwnerProfile(),
            ),
            connectivityServiceProvider.overrideWithValue(
              fakeConnectivityService(),
            ),
          ],
          child: const BrewFlowApp(),
        );

    Future<void> pumpAuthenticatedAsOwner(WidgetTester tester) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(_owner);
      fakeAuth.user = _owner;
      await tester.pumpWidget(app(staff: staffRepo));
      fakeAuth.emit(_owner);
      await tester.pumpAndSettle();
    }

    Future<void> pumpAsync(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> openRoute(WidgetTester tester, String route) async {
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(route);
      await pumpAsync(tester);
    }

    Finder inForm(String text) => find.descendant(
      of: find.byType(IngredientFormSheet),
      matching: find.text(text),
    );

    Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
      final scrollable = find.descendant(
        of: find.byType(IngredientFormSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: scrollable.first,
      );
      await tester.pump();
    }

    testWidgets('owner sees the New ingredient entry', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      expect(find.byTooltip('New ingredient'), findsOneWidget);
    });

    testWidgets('staff never sees the New ingredient entry', (tester) async {
      seedMaggiWorld();
      await tester.pumpWidget(
        app(profile: testStaffProfile(shopId: kTestCafeShopId)),
      );
      fakeAuth.user = const AuthUser(
        id: 'test-staff',
        email: 'staff@brewflow.test',
      );
      fakeAuth.emit(
        const AuthUser(id: 'test-staff', email: 'staff@brewflow.test'),
      );
      await tester.pumpAndSettle();
      await openRoute(tester, AppRoutes.inventoryRecipes);

      expect(find.text('Maggi Packet'), findsOneWidget);
      expect(find.byTooltip('New ingredient'), findsNothing);
      expect(find.byTooltip('Ingredient details'), findsNothing);
    });

    testWidgets('creates an ingredient through the form', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New ingredient'));
      await pumpAsync(tester);
      expect(find.byType(IngredientFormSheet), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(IngredientFormSheet),
          matching: find.byType(TextField),
        ),
        'Sugar',
      );
      await tester.pump();
      // Category + unit both default usefully, but the flow must work
      // through explicit picks too.
      await tester.tap(inForm('Select a category'));
      await pumpAsync(tester);
      await tester.tap(find.text('Dry Goods').last);
      await pumpAsync(tester);

      final save = find.widgetWithText(FilledButton, 'Add ingredient');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(IngredientFormSheet), findsNothing);
      expect(
        find.text('Ingredient added. Stock it through Purchases.'),
        findsOneWidget,
      );
      // The new card shows zero stock in the picked unit, no consumers yet.
      expect(find.text('Sugar'), findsOneWidget);
      expect(find.text('0 Pieces in stock · 0 dishes'), findsOneWidget);
    });

    testWidgets('validation explains blank names inline', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New ingredient'));
      await pumpAsync(tester);

      final save = find.widgetWithText(FilledButton, 'Add ingredient');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(inForm('Give the ingredient a name.'), findsOneWidget);
      expect(find.byType(IngredientFormSheet), findsOneWidget);
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    testWidgets('duplicate names are refused with the draft intact', (
      tester,
    ) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New ingredient'));
      await pumpAsync(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(IngredientFormSheet),
          matching: find.byType(TextField),
        ),
        'maggi packet',
      );
      await tester.pump();
      await tester.tap(inForm('Select a category'));
      await pumpAsync(tester);
      await tester.tap(find.text('Dry Goods').last);
      await pumpAsync(tester);

      final save = find.widgetWithText(FilledButton, 'Add ingredient');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(
        inForm('An ingredient named "Maggi Packet" already exists.'),
        findsOneWidget,
      );
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    testWidgets('cancel writes nothing', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New ingredient'));
      await pumpAsync(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(IngredientFormSheet),
          matching: find.byType(TextField),
        ),
        'Sugar',
      );
      await tester.pump();
      final cancel = inForm('Cancel');
      await scrollFormTo(tester, cancel);
      await tester.tap(cancel);
      await pumpAsync(tester);

      expect(find.byType(IngredientFormSheet), findsNothing);
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    testWidgets('save errors stay in the sheet with the draft intact', (
      tester,
    ) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New ingredient'));
      await pumpAsync(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(IngredientFormSheet),
          matching: find.byType(TextField),
        ),
        'Sugar',
      );
      await tester.pump();
      await tester.tap(inForm('Select a category'));
      await pumpAsync(tester);
      await tester.tap(find.text('Dry Goods').last);
      await pumpAsync(tester);

      fakeInventory.loadError = const UnexpectedInventoryFailure(
        'The shelf is unreachable.',
      );
      final save = find.widgetWithText(FilledButton, 'Add ingredient');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(inForm('The shelf is unreachable.'), findsOneWidget);
      expect(find.byType(IngredientFormSheet), findsOneWidget);
      fakeInventory.loadError = null;
      expect(fakeInventory.storedProducts, hasLength(2));
    });

    testWidgets('a double tap submits only one create', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New ingredient'));
      await pumpAsync(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(IngredientFormSheet),
          matching: find.byType(TextField),
        ),
        'Sugar',
      );
      await tester.pump();
      await tester.tap(inForm('Select a category'));
      await pumpAsync(tester);
      await tester.tap(find.text('Dry Goods').last);
      await pumpAsync(tester);

      final save = find.widgetWithText(FilledButton, 'Add ingredient');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      // Second tap lands while the first save is still in flight.
      await tester.tap(save);
      await pumpAsync(tester);

      expect(
        fakeInventory.storedProducts.where((item) => item.name == 'Sugar'),
        hasLength(1),
      );
    });
  });

  group('IngredientDetailSheet', () {
    Widget app({FakeStaffRepository? staff, UserProfile? profile}) =>
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            inventoryRepositoryProvider.overrideWithValue(fakeInventory),
            stockMovementRepositoryProvider.overrideWithValue(
              FakeStockMovementRepository(),
            ),
            ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
            customerLedgerRepositoryProvider.overrideWithValue(
              FakeCustomerLedgerRepository(),
            ),
            staffRepositoryProvider.overrideWithValue(
              staff ?? FakeStaffRepository(),
            ),
            userProfileProvider.overrideWithBuild(
              (ref, notifier) => profile ?? testOwnerProfile(),
            ),
            connectivityServiceProvider.overrideWithValue(
              fakeConnectivityService(),
            ),
          ],
          child: const BrewFlowApp(),
        );

    Future<void> pumpAuthenticatedAsOwner(WidgetTester tester) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(_owner);
      fakeAuth.user = _owner;
      await tester.pumpWidget(app(staff: staffRepo));
      fakeAuth.emit(_owner);
      await tester.pumpAndSettle();
    }

    Future<void> pumpAsync(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> openRoute(WidgetTester tester, String route) async {
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(route);
      await pumpAsync(tester);
    }

    Finder inDetail(String text) => find.descendant(
      of: find.byType(IngredientDetailSheet),
      matching: find.text(text),
    );

    Future<void> scrollDetailTo(WidgetTester tester, Finder finder) async {
      final scrollable = find.descendant(
        of: find.byType(IngredientDetailSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: scrollable.first,
      );
      await tester.pump();
    }

    testWidgets('shows stock, unit, consumers and the three links', (
      tester,
    ) async {
      seedMaggiWorld();
      await mapRecipe('dish-1');
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('Ingredient details'));
      await pumpAsync(tester);

      expect(find.byType(IngredientDetailSheet), findsOneWidget);
      expect(inDetail('10 Pieces in stock · 1 dish'), findsOneWidget);
      expect(inDetail('Plain Maggi'), findsOneWidget);
      expect(inDetail('View stock history'), findsOneWidget);
      expect(inDetail('Record purchase'), findsOneWidget);
      expect(inDetail('Adjust stock'), findsOneWidget);
    });

    testWidgets('history link opens the existing history page', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('Ingredient details'));
      await pumpAsync(tester);
      final history = inDetail('View stock history');
      await scrollDetailTo(tester, history);
      await tester.tap(history);
      await pumpAsync(tester);

      expect(find.byType(StockMovementHistoryPage), findsOneWidget);
    });

    testWidgets('purchase link opens the existing purchase form', (
      tester,
    ) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('Ingredient details'));
      await pumpAsync(tester);
      final purchase = inDetail('Record purchase');
      await scrollDetailTo(tester, purchase);
      await tester.tap(purchase);
      await pumpAsync(tester);

      expect(find.byType(PurchaseFormPage), findsOneWidget);
    });

    testWidgets('adjust link opens the existing adjust dialog', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('Ingredient details'));
      await pumpAsync(tester);
      final adjust = inDetail('Adjust stock');
      await scrollDetailTo(tester, adjust);
      await tester.tap(adjust);
      await pumpAsync(tester);

      expect(find.byType(StockAdjustmentDialog), findsOneWidget);
    });
  });
}
