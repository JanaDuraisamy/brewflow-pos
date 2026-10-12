import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_page.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
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
/// BrewFlow POS — Shared Stock overview (Phase 1, read-only) contract.
///
/// The page displays existing ingredient/recipe mappings and nothing else:
/// no writes, no seed interference. Entry is owner-only; the route itself
/// stays behind the inventory `viewInventory` guard; every read is scoped to
/// the active business exactly like the inventory product list.
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

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
  });

  group('sharedStockOverviewProvider', () {
    test('groups consumers under their ingredient with quantities', () async {
      fakeInventory.storedProducts.addAll([
        product('ing-1', 'Maggi Packet', stockQuantity: 10, isIngredient: true),
        product('dish-1', 'Plain Maggi'),
        product('dish-2', 'Cheese Maggi'),
      ]);
      await mapRecipe('dish-1', quantity: 2);
      final container = buildContainer();
      addTearDown(container.dispose);

      final overview = await container.read(sharedStockOverviewProvider.future);

      expect(overview.ingredients, hasLength(1));
      final entry = overview.ingredients.single;
      expect(entry.product.name, 'Maggi Packet');
      expect(entry.product.stockQuantity, 10);
      expect(entry.consumers, hasLength(1));
      expect(entry.consumers.single.productName, 'Plain Maggi');
      expect(entry.consumers.single.variantName, isNull);
      expect(entry.consumers.single.quantityPerSale, 2);
      expect(entry.consumers.single.unitLabel, 'Pieces');
      expect(overview.unmappedSellables.map((item) => item.name), [
        'Cheese Maggi',
      ]);
    });

    test('labels variant-scoped rows with the variant name', () async {
      fakeInventory.storedProducts.addAll([
        product('ing-1', 'Milk', stockQuantity: 20, isIngredient: true),
        product(
          'dish-1',
          'Chai',
          variants: [variant('v1', 'dish-1', 'Kulhad')],
        ),
      ]);
      await mapRecipe('dish-1', ingredientId: 'ing-1', variantId: 'v1');
      final container = buildContainer();
      addTearDown(container.dispose);

      final overview = await container.read(sharedStockOverviewProvider.future);

      expect(
        overview.ingredients.single.consumers.single.variantName,
        'Kulhad',
      );
      expect(overview.unmappedSellables, isEmpty);
    });

    test('a staff session only sees its own shop', () async {
      fakeInventory.storedProducts.addAll([
        product('ing-1', 'Cafe Sugar', isIngredient: true),
        product('dish-1', 'Cafe Chai'),
        product(
          'ing-2',
          'Truck Sugar',
          isIngredient: true,
          shopId: kTestFoodTruckShopId,
        ),
        product('dish-2', 'Truck Chai', shopId: kTestFoodTruckShopId),
      ]);
      await mapRecipe('dish-1', ingredientId: 'ing-1');
      await fakeInventory.setRecipe(
        productId: 'dish-2',
        ingredients: [
          const RecipeIngredientInput(ingredientProductId: 'ing-2'),
        ],
        shopId: kTestFoodTruckShopId,
      );
      final container = buildContainer(
        profile: testStaffProfile(shopId: kTestFoodTruckShopId),
      );
      addTearDown(container.dispose);

      final overview = await container.read(sharedStockOverviewProvider.future);

      // Staff are single-shop by contract: never the Cafe catalogue.
      expect(overview.ingredients.map((entry) => entry.product.name), [
        'Truck Sugar',
      ]);
      expect(
        overview.ingredients.single.consumers.single.productName,
        'Truck Chai',
      );
      expect(overview.unmappedSellables, isEmpty);
    });

    test('surfaces InventoryFailure without wrapping it', () async {
      fakeInventory.loadError = const UnexpectedInventoryFailure('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(sharedStockOverviewProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(sharedStockOverviewProvider);
      expect(state.hasError, isTrue);
      expect(
        state.error,
        isA<UnexpectedInventoryFailure>().having(
          (failure) => failure.message,
          'message',
          'boom',
        ),
      );
    });
  });

  group('SharedStockPage', () {
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

    testWidgets('owner sees the Shared Stock entry on inventory', (
      tester,
    ) async {
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventory);

      expect(find.byType(InventoryPage), findsOneWidget);
      expect(find.text('Shared Stock'), findsOneWidget);
    });

    testWidgets('staff never sees the Shared Stock entry', (tester) async {
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
      await openRoute(tester, AppRoutes.inventory);

      expect(find.byType(InventoryPage), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Shared Stock'), findsNothing);
    });

    testWidgets('shows ingredients, consumers and unmapped dishes', (
      tester,
    ) async {
      fakeInventory.storedProducts.addAll([
        product('ing-1', 'Maggi Packet', stockQuantity: 10, isIngredient: true),
        product('dish-1', 'Plain Maggi'),
        product('dish-2', 'Cheese Maggi'),
      ]);
      await mapRecipe('dish-1', quantity: 2);
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      expect(find.byType(SharedStockPage), findsOneWidget);
      expect(find.text('Maggi Packet'), findsOneWidget);
      expect(find.text('10 Pieces in stock · 1 dish'), findsOneWidget);
      expect(find.text('Plain Maggi'), findsOneWidget);
      expect(find.text('×2 Pieces'), findsOneWidget);
      expect(find.text('Dishes without a recipe'), findsOneWidget);
      expect(find.text('Cheese Maggi'), findsOneWidget);
    });

    testWidgets('shows the empty state when there is no shared stock', (
      tester,
    ) async {
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      expect(find.text('No shared stock yet'), findsOneWidget);
    });

    testWidgets('search narrows by ingredient and dish name', (tester) async {
      fakeInventory.storedProducts.addAll([
        product('ing-1', 'Maggi Packet', stockQuantity: 10, isIngredient: true),
        product('ing-2', 'Milk', stockQuantity: 20, isIngredient: true),
        product('dish-1', 'Plain Maggi'),
      ]);
      await mapRecipe('dish-1');
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      await tester.enterText(find.byType(TextField), 'milk');
      await pumpAsync(tester);

      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Maggi Packet'), findsNothing);
      expect(find.text('Plain Maggi'), findsNothing);
    });

    testWidgets('error state retries the load', (tester) async {
      fakeInventory.loadError = const UnexpectedInventoryFailure(
        'The shelf is unreachable.',
      );
      await pumpAuthenticatedAsOwner(tester);
      await openRoute(tester, AppRoutes.inventoryRecipes);

      expect(find.text('The shelf is unreachable.'), findsOneWidget);

      fakeInventory.loadError = null;
      fakeInventory.storedProducts.add(
        product('ing-1', 'Maggi Packet', stockQuantity: 10, isIngredient: true),
      );
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);

      expect(find.text('Maggi Packet'), findsOneWidget);
    });
  });
}
