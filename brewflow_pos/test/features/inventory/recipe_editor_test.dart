import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/recipe_editor_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
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

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Recipe Mapping Editor (Phase 2) contract.
///
/// Owners map a sellable dish (+ optional variant scope) to tracked
/// ingredients through the existing `setRecipe` API. Only the edited scope
/// is ever replaced; unrelated mappings (notably the seeded Maggi Packet
/// rows) are untouched, stock is never reset, and the menu seed never runs.
/// The controller enforces ownership and write scoping — hidden buttons are
/// never the only protection.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;

  final now = DateTime.now().toUtc();

  Product product(
    String id,
    String name, {
    int stockQuantity = 0,
    StockUnit stockUnit = StockUnit.count,
    bool isIngredient = false,
    String shopId = kTestCafeShopId,
    List<ProductVariant> variants = const [],
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
    variants: variants,
  );

  ProductVariant variant(String id, String productId, String name) =>
      ProductVariant(
        id: id,
        productId: productId,
        name: name,
        sellingPricePaise: 4500,
        stockQuantity: 5,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

  RecipeIngredientInput line(
    String ingredientId, {
    int quantity = 1,
    String? ingredientVariantId,
  }) => RecipeIngredientInput(
    ingredientProductId: ingredientId,
    ingredientVariantId: ingredientVariantId,
    quantity: quantity,
  );

  void seedMaggiWorld() {
    fakeInventory.storedProducts.addAll([
      product('ing-1', 'Maggi Packet', stockQuantity: 10, isIngredient: true),
      product('dish-1', 'Plain Maggi'),
      product('dish-2', 'Cheese Maggi'),
    ]);
  }

  Future<void> mapRecipe(
    String productId, {
    String ingredientId = 'ing-1',
    int quantity = 1,
    String? variantId,
  }) => fakeInventory.setRecipe(
    productId: productId,
    variantId: variantId,
    ingredients: [
      RecipeIngredientInput(
        ingredientProductId: ingredientId,
        quantity: quantity,
      ),
    ],
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
    // Wait for the profile to resolve so the gate is not skipped by a null
    // (still-loading) profile.
    final profile = await container.read(userProfileProvider.future);
    expect(profile!.isOwner, isFalse);
    return container;
  }

  Future<List<ProductRecipe>> rowsOf(String productId) =>
      fakeInventory.recipesForProduct(productId, shopIds: [kTestCafeShopId]);

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
  });

  group('saveRecipe', () {
    test('creates a mapping and the overview refetches it', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(sharedStockOverviewProvider.notifier)
          .saveRecipe(productId: 'dish-2', lines: [line('ing-1', quantity: 2)]);

      final rows = await rowsOf('dish-2');
      expect(rows, hasLength(1));
      expect(rows.single.quantity, 2);
      // The overview invalidated itself: the new consumer is visible without
      // any manual refresh.
      final overview = await container.read(sharedStockOverviewProvider.future);
      final entry = overview.ingredients.single;
      expect(
        entry.consumers.map((consumer) => consumer.productName),
        contains('Cheese Maggi'),
      );
      expect(overview.unmappedSellables.map((item) => item.id), ['dish-1']);
    });

    test('replaces only the edited scope, leaving Maggi rows intact', () async {
      seedMaggiWorld();
      await mapRecipe('dish-1', quantity: 1);
      final before = await rowsOf('dish-1');
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(sharedStockOverviewProvider.notifier)
          .saveRecipe(productId: 'dish-2', lines: [line('ing-1', quantity: 3)]);

      // The edited dish has exactly its new mapping…
      final cheese = await rowsOf('dish-2');
      expect(cheese, hasLength(1));
      expect(cheese.single.quantity, 3);
      // …and the seeded Maggi mapping is byte-for-byte unchanged.
      final plain = await rowsOf('dish-1');
      expect(plain, hasLength(1));
      expect(plain.single.id, before.single.id);
      expect(plain.single.quantity, 1);
      // No stock was reset by the write.
      final packet = fakeInventory.storedProducts.firstWhere(
        (item) => item.id == 'ing-1',
      );
      expect(packet.stockQuantity, 10);
    });

    test('rejects quantities below 1 without writing', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .saveRecipe(
              productId: 'dish-2',
              lines: [line('ing-1', quantity: 0)],
            ),
        throwsA(isA<RecipeQuantityFailure>()),
      );
      expect(await rowsOf('dish-2'), isEmpty);
    });

    test('rejects self-consumption without writing', () async {
      seedMaggiWorld();
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .saveRecipe(productId: 'dish-2', lines: [line('dish-2')]),
        throwsA(isA<RecipeSelfConsumptionFailure>()),
      );
      expect(await rowsOf('dish-2'), isEmpty);
    });

    test('rejects untracked ingredients without writing', () async {
      fakeInventory.storedProducts.addAll([
        product('dish-2', 'Cheese Maggi'),
        product(
          'untracked',
          'Loose Garnish',
          stockUnit: StockUnit.none,
          isIngredient: true,
        ),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .saveRecipe(productId: 'dish-2', lines: [line('untracked')]),
        throwsA(isA<RecipeUntrackedIngredientFailure>()),
      );
      expect(await rowsOf('dish-2'), isEmpty);
    });

    test('rejects variants outside the dish or ingredient', () async {
      fakeInventory.storedProducts.addAll([
        product(
          'dish-2',
          'Chai',
          variants: [variant('v1', 'dish-2', 'Kulhad')],
        ),
        product('ing-1', 'Milk', stockQuantity: 20, isIngredient: true),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sharedStockOverviewProvider.notifier);

      await expectLater(
        notifier.saveRecipe(
          productId: 'dish-2',
          variantId: 'nope',
          lines: [line('ing-1')],
        ),
        throwsA(isA<RecipeVariantMismatchFailure>()),
      );
      await expectLater(
        notifier.saveRecipe(
          productId: 'dish-2',
          lines: [line('ing-1', ingredientVariantId: 'nope')],
        ),
        throwsA(isA<RecipeIngredientVariantMismatchFailure>()),
      );
      expect(await rowsOf('dish-2'), isEmpty);
    });

    test('rejects overlapping product and variant scopes', () async {
      fakeInventory.storedProducts.addAll([
        product(
          'dish-2',
          'Chai',
          variants: [variant('v1', 'dish-2', 'Kulhad')],
        ),
        product('ing-1', 'Milk', stockQuantity: 20, isIngredient: true),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sharedStockOverviewProvider.notifier);

      // A variant recipe exists: a product-wide save would double-deduct.
      await mapRecipe('dish-2', variantId: 'v1');
      await expectLater(
        notifier.saveRecipe(productId: 'dish-2', lines: [line('ing-1')]),
        throwsA(
          isA<RecipeOverlapFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Kulhad'),
          ),
        ),
      );
      expect((await rowsOf('dish-2')).map((row) => row.variantId), ['v1']);

      // And the mirror: a product-wide recipe blocks a variant save.
      // Clearing is scope-addressed too: an empty product-wide write leaves
      // the variant row alone, so the variant scope is cleared explicitly.
      await fakeInventory.setRecipe(
        productId: 'dish-2',
        variantId: 'v1',
        ingredients: [],
      );
      await mapRecipe('dish-2');
      await expectLater(
        notifier.saveRecipe(
          productId: 'dish-2',
          variantId: 'v1',
          lines: [line('ing-1')],
        ),
        throwsA(
          isA<RecipeOverlapFailure>().having(
            (failure) => failure.message,
            'message',
            contains('every variant'),
          ),
        ),
      );
      expect((await rowsOf('dish-2')).map((row) => row.variantId), [isNull]);
    });

    test('a staff member with edit permission cannot save', () async {
      seedMaggiWorld();
      final container = await staffContainer();

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .saveRecipe(productId: 'dish-2', lines: [line('ing-1')]),
        throwsA(isA<PermissionDeniedFailure>()),
      );
      expect(await rowsOf('dish-2'), isEmpty);
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
            .saveRecipe(productId: 'dish-2', lines: [line('ing-1')]),
        throwsA(isA<RecipeReadOnlyScopeFailure>()),
      );
      expect(await rowsOf('dish-2'), isEmpty);
    });
  });

  group('clearRecipe', () {
    test(
      'clears one scope and the dish sells from its own stock again',
      () async {
        seedMaggiWorld();
        await mapRecipe('dish-1', quantity: 2);
        final container = buildContainer();
        addTearDown(container.dispose);

        await container
            .read(sharedStockOverviewProvider.notifier)
            .clearRecipe(productId: 'dish-1');

        expect(await rowsOf('dish-1'), isEmpty);
        final overview = await container.read(
          sharedStockOverviewProvider.future,
        );
        expect(
          overview.unmappedSellables.map((item) => item.name),
          contains('Plain Maggi'),
        );
      },
    );

    test('clearing an unmapped scope is a safe no-op', () async {
      seedMaggiWorld();
      await mapRecipe('dish-1');
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(sharedStockOverviewProvider.notifier)
          .clearRecipe(productId: 'dish-2');

      // Nothing was touched — especially not the other dish.
      expect((await rowsOf('dish-1')), hasLength(1));
    });

    test('a staff member cannot clear', () async {
      seedMaggiWorld();
      await mapRecipe('dish-1');
      final container = await staffContainer();

      await expectLater(
        container
            .read(sharedStockOverviewProvider.notifier)
            .clearRecipe(productId: 'dish-1'),
        throwsA(isA<PermissionDeniedFailure>()),
      );
      expect(await rowsOf('dish-1'), hasLength(1));
    });
  });

  group('RecipeEditorSheet', () {
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

    Finder inEditor(String text) => find.descendant(
      of: find.byType(RecipeEditorSheet),
      matching: find.text(text),
    );

    /// The editor is a tall scrollable sheet: rows below the fold have no
    /// elements until scrolled into view, so every below-fold tap scrolls
    /// first (mirrors `scrollFormTo` in the inventory page tests).
    Future<void> scrollSheetTo(WidgetTester tester, Finder finder) async {
      final scrollable = find.descendant(
        of: find.byType(RecipeEditorSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: scrollable.first,
      );
      await tester.pump();
    }

    testWidgets('creates a mapping from an unmapped dish', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      // The unmapped dish opens a blank editor for exactly that dish.
      await tester.tap(find.text('Cheese Maggi'));
      await pumpAsync(tester);
      expect(find.byType(RecipeEditorSheet), findsOneWidget);
      expect(inEditor('Cheese Maggi'), findsOneWidget);
      expect(
        inEditor('No recipe for this scope yet — saving creates one.'),
        findsOneWidget,
      );

      await scrollSheetTo(tester, inEditor('Add'));
      await tester.tap(inEditor('Add'));
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Maggi Packet'));
      await pumpAsync(tester);
      expect(inEditor('Maggi Packet'), findsOneWidget);

      final save = find.widgetWithText(FilledButton, 'Save recipe');
      await scrollSheetTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      // Written once, sheet closed, owner told, overview refetched:
      // Cheese Maggi now consumes, while Plain Maggi stays unmapped.
      expect((await rowsOf('dish-2')), hasLength(1));
      expect(find.byType(RecipeEditorSheet), findsNothing);
      expect(find.text('Recipe saved.'), findsOneWidget);
      expect(find.text('Cheese Maggi'), findsOneWidget);
      expect(find.text('×1 Pieces'), findsOneWidget);
      expect(find.text('Dishes without a recipe'), findsOneWidget);
      expect(find.text('Plain Maggi'), findsOneWidget);
    });

    testWidgets('replace asks for confirmation and cancel keeps the draft', (
      tester,
    ) async {
      seedMaggiWorld();
      await mapRecipe('dish-1', quantity: 1);
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('Edit recipe').first);
      await pumpAsync(tester);
      // Prefilled from the current mapping.
      expect(inEditor('Maggi Packet'), findsOneWidget);

      final increase = find.byTooltip('Increase');
      await scrollSheetTo(tester, increase);
      await tester.tap(increase);
      await tester.pump();
      final save = find.widgetWithText(FilledButton, 'Save recipe');
      await scrollSheetTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      // Explicit old-vs-new summary before anything is replaced.
      // (Scoped to the dialog: the sheet behind has its own Cancel.)
      expect(find.text('Replace recipe?'), findsOneWidget);
      expect(find.textContaining('Current mapping:'), findsOneWidget);
      final dialogCancel = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      );
      await tester.tap(dialogCancel);
      await pumpAsync(tester);
      expect((await rowsOf('dish-1')).single.quantity, 1);
      expect(find.byType(RecipeEditorSheet), findsOneWidget);

      await scrollSheetTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Replace recipe'));
      await pumpAsync(tester);

      expect((await rowsOf('dish-1')).single.quantity, 2);
      expect(find.byType(RecipeEditorSheet), findsNothing);
    });

    testWidgets('clear asks destructively and cancel keeps the mapping', (
      tester,
    ) async {
      seedMaggiWorld();
      await mapRecipe('dish-1');
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('Edit recipe').first);
      await pumpAsync(tester);
      final clear = inEditor('Clear recipe');
      await scrollSheetTo(tester, clear);
      await tester.tap(clear);
      await pumpAsync(tester);

      expect(find.text('Clear recipe?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel'),
        ),
      );
      await pumpAsync(tester);
      expect((await rowsOf('dish-1')), hasLength(1));
      expect(find.byType(RecipeEditorSheet), findsOneWidget);

      await scrollSheetTo(tester, clear);
      await tester.tap(clear);
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear recipe'));
      await pumpAsync(tester);

      expect((await rowsOf('dish-1')), isEmpty);
      expect(find.text('Recipe cleared.'), findsOneWidget);
    });

    testWidgets('cancel writes nothing', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.byTooltip('New recipe'));
      await pumpAsync(tester);
      expect(find.byType(RecipeEditorSheet), findsOneWidget);
      final cancel = inEditor('Cancel');
      await scrollSheetTo(tester, cancel);
      await tester.tap(cancel);
      await pumpAsync(tester);

      expect(find.byType(RecipeEditorSheet), findsNothing);
      expect(fakeInventory.storedRecipes, isEmpty);
      expect(find.text('Recipe saved.'), findsNothing);
    });

    testWidgets('save errors stay in the sheet with the draft intact', (
      tester,
    ) async {
      seedMaggiWorld();
      fakeInventory.loadError = const UnexpectedInventoryFailure(
        'The shelf is unreachable.',
      );
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      // Fail the catalogue load first: the sheet reports and stays closable.
      // (Scoped to the sheet: the page behind shows the same error.)
      await tester.tap(find.byTooltip('New recipe'));
      await pumpAsync(tester);
      expect(inEditor('The shelf is unreachable.'), findsOneWidget);

      // Recover and drive a save-time failure instead. The page behind
      // still shows its own error until retried.
      fakeInventory.loadError = null;
      await tester.tap(find.byTooltip('Close'));
      await pumpAsync(tester);
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);
      await tester.tap(find.text('Cheese Maggi'));
      await pumpAsync(tester);
      // The catalogue provider still holds the earlier failure until
      // retried: the sheet says so and offers its own retry.
      await tester.tap(inEditor('Try Again'));
      await pumpAsync(tester);
      await scrollSheetTo(tester, inEditor('Add'));
      await tester.tap(inEditor('Add'));
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Maggi Packet'));
      await pumpAsync(tester);
      fakeInventory.loadError = const UnexpectedInventoryFailure(
        'The shelf is unreachable.',
      );
      final save = find.widgetWithText(FilledButton, 'Save recipe');
      await scrollSheetTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(inEditor('The shelf is unreachable.'), findsOneWidget);
      expect(find.byType(RecipeEditorSheet), findsOneWidget);
      expect(inEditor('Maggi Packet'), findsOneWidget);
      // The write never happened: lift the probe to read the rows back.
      fakeInventory.loadError = null;
      expect((await rowsOf('dish-2')), isEmpty);
    });

    testWidgets('a double tap submits only one write', (tester) async {
      seedMaggiWorld();
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.tap(find.text('Cheese Maggi'));
      await pumpAsync(tester);
      await scrollSheetTo(tester, inEditor('Add'));
      await tester.tap(inEditor('Add'));
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Maggi Packet'));
      await pumpAsync(tester);

      final save = find.widgetWithText(FilledButton, 'Save recipe');
      await scrollSheetTo(tester, save);
      await tester.tap(save);
      // Second tap lands while the first save is still in flight.
      await tester.tap(save);
      await pumpAsync(tester);

      expect((await rowsOf('dish-2')), hasLength(1));
      expect(find.byType(RecipeEditorSheet), findsNothing);
    });

    testWidgets('staff sees no editor entries on a deep link', (tester) async {
      seedMaggiWorld();
      await mapRecipe('dish-1');
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

      // Readable (viewInventory), but every write entry is hidden.
      expect(find.text('Maggi Packet'), findsOneWidget);
      expect(find.byTooltip('New recipe'), findsNothing);
      expect(find.byTooltip('Edit recipe'), findsNothing);
    });
  });
}
