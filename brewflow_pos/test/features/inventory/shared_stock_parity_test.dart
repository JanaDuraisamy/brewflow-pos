import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart'
    hide Product, StockMovement;
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/data/jiggar_menu_seed.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/recipe_editor_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/test_providers.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Stock parity (Phase 4).
///
/// Bridges the UI write path to the real stack: mappings and ingredients
/// created through [SharedStockOverviewController] (the exact methods the
/// Phase 2/3 sheets call) land as real Drift rows and drive the existing
/// checkout/void deduction logic — shared consumption, mixed carts,
/// insufficient-stock rollback, void restoration, variant scopes, shop
/// isolation and menu-seed reruns. The backend contract itself lives in
/// `shared_stock_test.dart`; nothing here duplicates it, only the UI entry
/// point differs.
///
/// Local SQLite only: no cloud, no production database, no migrations run.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');
const shop = kTestCafeShopId;
const otherShop = kTestFoodTruckShopId;

void main() {
  late AppDatabase db;
  late DriftInventoryRepository inventory;
  late DriftStockMovementRepository movements;
  late DriftBillingRepository billing;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    inventory = DriftInventoryRepository(db);
    movements = DriftStockMovementRepository(db);
    billing = DriftBillingRepository(db);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: const Value(shop), name: 'Cafe'));
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(id: const Value(otherShop), name: 'Truck'),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: const Value('cat-1'),
            name: 'Dry Goods',
            shopId: const Value(shop),
          ),
        );
  });

  tearDown(() => db.close());

  /// The UI write path: same provider + same controller methods the sheets
  /// call, against the real Drift repository.
  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(inventory),
      ...businessScopeOverrides(),
      ...connectivityOverrides(),
    ],
  );

  Future<SharedStockOverviewController> ui() async {
    final container = buildContainer();
    addTearDown(container.dispose);
    return container.read(sharedStockOverviewProvider.notifier);
  }

  Future<Product> menu(
    String id,
    String name, {
    String shopId = shop,
    int stockQuantity = 0,
  }) => inventory.createProduct(
    categoryId: 'cat-1',
    name: name,
    sellingPricePaise: 4500,
    stockQuantity: stockQuantity,
    stockUnit: stockQuantity > 0 ? StockUnit.count : StockUnit.none,
    isActive: true,
    shopId: shopId,
  );

  CartLine line(String productId, String name, int quantity) => CartLine(
    productId: productId,
    productName: name,
    sku: null,
    unitPricePaise: 4500,
    quantity: quantity,
    maxQuantity: 99,
  );

  Future<int> stockOf(String id) async => (await (db.select(
    db.products,
  )..where((t) => t.id.equals(id))).getSingle()).stockQuantity;

  group('UI mappings drive checkout', () {
    test('shared dishes deduct one source across the cart', () async {
      final controller = await ui();
      // The Phase 3 flow: ingredient born at zero, stocked like an owner
      // would through Purchases, then mapped through the Phase 2 flow.
      final packet = await controller.createIngredient(
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        stockUnit: StockUnit.count,
      );
      expect(await movements.movementsFor(packet.id), isEmpty);
      await movements.adjustStock(
        productId: packet.id,
        delta: 60,
        reason: StockAdjustmentReason.purchase,
      );
      final plain = await menu('plain', 'Plain Maggi');
      final cheese = await menu('cheese', 'Cheese Maggi');
      await controller.saveRecipe(
        productId: plain.id,
        lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
      );
      await controller.saveRecipe(
        productId: cheese.id,
        lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
      );

      await billing.completeSale(
        lines: [
          line(plain.id, 'Plain Maggi', 5),
          line(cheese.id, 'Cheese Maggi', 8),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 47);
      expect(await stockOf(plain.id), 0);
      expect(await stockOf(cheese.id), 0);
    });

    test(
      'mixed carts: mapped lines skip own stock, unmapped keep it',
      () async {
        final controller = await ui();
        final packet = await controller.createIngredient(
          categoryId: 'cat-1',
          name: 'Maggi Packet',
          stockUnit: StockUnit.count,
        );
        await movements.adjustStock(
          productId: packet.id,
          delta: 60,
          reason: StockAdjustmentReason.purchase,
        );
        final plain = await menu('plain', 'Plain Maggi');
        final tracked = await menu('tracked', 'Tracked Chai', stockQuantity: 7);
        await controller.saveRecipe(
          productId: plain.id,
          lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
        );

        await billing.completeSale(
          lines: [
            line(plain.id, 'Plain Maggi', 2),
            line(tracked.id, 'Tracked Chai', 2),
          ],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        );

        expect(await stockOf(packet.id), 58);
        expect(await stockOf(tracked.id), 5);
      },
    );

    test(
      'insufficient shared stock fails the whole sale with no writes',
      () async {
        final controller = await ui();
        final packet = await controller.createIngredient(
          categoryId: 'cat-1',
          name: 'Maggi Packet',
          stockUnit: StockUnit.count,
        );
        await movements.adjustStock(
          productId: packet.id,
          delta: 2,
          reason: StockAdjustmentReason.purchase,
        );
        final plain = await menu('plain', 'Plain Maggi');
        await controller.saveRecipe(
          productId: plain.id,
          lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
        );

        await expectLater(
          billing.completeSale(
            lines: [line(plain.id, 'Plain Maggi', 3)],
            paymentMethod: PaymentMethod.cash,
            shopId: shop,
          ),
          throwsA(isA<InsufficientStockFailure>()),
        );
        expect(await stockOf(packet.id), 2);
        expect(await db.select(db.sales).get(), isEmpty);
      },
    );

    test('voiding a UI-mapped sale restores the shared source', () async {
      final controller = await ui();
      final packet = await controller.createIngredient(
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        stockUnit: StockUnit.count,
      );
      await movements.adjustStock(
        productId: packet.id,
        delta: 60,
        reason: StockAdjustmentReason.purchase,
      );
      final plain = await menu('plain', 'Plain Maggi');
      await controller.saveRecipe(
        productId: plain.id,
        lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
      );

      final completed = await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 55);

      await billing.voidSale(completed.sale.id);
      expect(await stockOf(packet.id), 60);
    });

    test('UI variant-scoped mapping deducts only that variant', () async {
      final controller = await ui();
      final packet = await controller.createIngredient(
        categoryId: 'cat-1',
        name: 'Milk',
        stockUnit: StockUnit.ml,
      );
      await movements.adjustStock(
        productId: packet.id,
        delta: 60,
        reason: StockAdjustmentReason.purchase,
      );
      final chai = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Chai',
        sellingPricePaise: 4500,
        stockQuantity: 0,
        stockUnit: StockUnit.none,
        isActive: true,
        shopId: shop,
        variants: const [
          ProductVariantInput(
            name: 'Kulhad',
            sellingPricePaise: 5000,
            stockQuantity: 0,
            isActive: true,
          ),
        ],
      );
      final kulhad = chai.variants.single;
      await controller.saveRecipe(
        productId: chai.id,
        variantId: kulhad.id,
        lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
      );

      await billing.completeSale(
        lines: [
          CartLine(
            productId: chai.id,
            productName: 'Chai',
            sku: null,
            unitPricePaise: 5000,
            quantity: 2,
            maxQuantity: 99,
            variantId: kulhad.id,
            variantName: 'Kulhad',
          ),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 58);
    });
  });

  group('shop isolation on the real stack', () {
    test('cafe UI rows never surface in, or deduct, the truck', () async {
      final controller = await ui();
      final packet = await controller.createIngredient(
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        stockUnit: StockUnit.count,
      );
      await movements.adjustStock(
        productId: packet.id,
        delta: 60,
        reason: StockAdjustmentReason.purchase,
      );
      final plain = await menu('plain', 'Plain Maggi');
      await controller.saveRecipe(
        productId: plain.id,
        lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
      );
      final truckPacket = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Truck Sugar',
        sellingPricePaise: 0,
        stockQuantity: 10,
        isActive: true,
        shopId: otherShop,
        isIngredient: true,
      );

      // The truck scope sees neither the cafe ingredient nor its rows.
      expect(
        await inventory.products(
          status: ProductStatusFilter.active,
          shopIds: const [otherShop],
        ),
        hasLength(1),
      );
      expect(
        await inventory.recipesForProduct(plain.id, shopIds: const [otherShop]),
        isEmpty,
      );

      // And a cafe sale moves only cafe stock.
      await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 4)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 56);
      expect(await stockOf(truckPacket.id), 10);
    });
  });

  group('menu-seed reruns preserve UI work', () {
    test(
      'rerun keeps UI mappings, UI ingredients and every stock level',
      () async {
        await JiggarMenuSeeder(inventory).run();
        final seeded = await inventory.products();
        final packet = seeded.firstWhere(
          (item) => item.name == JiggarMenuSeeder.sharedStockPacketName,
        );
        // The packet starts empty, so the seed defers every dish mapping.
        expect(packet.stockQuantity, 0);
        expect(packet.isIngredient, isTrue);

        // Owner flow: stock the packet, map one Maggie dish through the UI,
        // and add an unrelated UI ingredient — all inside shop-1.
        await movements.adjustStock(
          productId: packet.id,
          delta: 40,
          reason: StockAdjustmentReason.purchase,
        );
        final controller = await ui();
        final dishes = await inventory.products(shopIds: const [shop]);
        final classic = dishes.firstWhere(
          (item) => item.name == 'Classic Maggie',
        );
        await controller.saveRecipe(
          productId: classic.id,
          lines: [RecipeIngredientInput(ingredientProductId: packet.id)],
        );
        final maggie = (await inventory.categories()).firstWhere(
          (category) => category.name.toLowerCase() == 'maggie',
        );
        final sugar = await controller.createIngredient(
          categoryId: maggie.id,
          name: 'Sugar',
          stockUnit: StockUnit.gram,
        );
        final before = await inventory.recipesForProduct(
          classic.id,
          shopIds: const [shop],
        );
        expect(before, hasLength(1));

        final rerun = await JiggarMenuSeeder(inventory).run();

        // Nothing invented, nothing reset, nothing remapped.
        expect(rerun.productsCreated, 0);
        expect(rerun.ingredientsEnsured, 0);
        final after = await inventory.recipesForProduct(
          classic.id,
          shopIds: const [shop],
        );
        expect(after.map((row) => row.id), before.map((row) => row.id));
        expect(await stockOf(packet.id), 40);
        expect(await stockOf(sugar.id), 0);
        expect(
          (await inventory.products(
            shopIds: const [shop],
          )).where((item) => item.name == 'Sugar'),
          hasLength(1),
        );
        expect(
          (await inventory.products(shopIds: const [shop])).where(
            (item) => item.name == JiggarMenuSeeder.sharedStockPacketName,
          ),
          hasLength(1),
        );
      },
    );
  });

  group('shelf and purchase visibility of UI ingredients', () {
    test(
      'UI ingredient hides from shelf queries, stays in purchase scope',
      () async {
        final controller = await ui();
        final packet = await controller.createIngredient(
          categoryId: 'cat-1',
          name: 'Maggi Packet',
          stockUnit: StockUnit.count,
        );
        await menu('plain', 'Plain Maggi');

        // The shelf projection (billing filters ingredients out).
        final shelf = (await inventory.products(
          status: ProductStatusFilter.active,
          shopIds: const [shop],
        )).where((item) => !item.isIngredient).toList();
        expect(shelf.map((item) => item.id), isNot(contains(packet.id)));

        // The purchase picker scope (no ingredient filter) still offers it.
        final receivable = await inventory.products(
          status: ProductStatusFilter.active,
          shopIds: const [shop],
        );
        expect(receivable.map((item) => item.id), contains(packet.id));
      },
    );
  });

  group('full UI mapping flow against the real database', () {
    late FakeAuthRepository fakeAuth;

    setUp(() {
      fakeAuth = FakeAuthRepository();
    });

    Widget app({FakeStaffRepository? staff}) => ProviderScope(
      overrides: [
        // Real database: every repository (inventory, movements, billing,
        // categories) resolves against it, so UI writes and checkout share
        // one real stock truth.
        appDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(fakeAuth),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
        customerLedgerRepositoryProvider.overrideWithValue(
          FakeCustomerLedgerRepository(),
        ),
        staffRepositoryProvider.overrideWithValue(
          staff ?? FakeStaffRepository(),
        ),
        userProfileProvider.overrideWithBuild(
          (ref, notifier) => testOwnerProfile(),
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

    Finder inEditor(String text) => find.descendant(
      of: find.byType(RecipeEditorSheet),
      matching: find.text(text),
    );

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

    testWidgets('sheet mapping deducts at real checkout', (tester) async {
      // Owner-stocked source plus a sellable dish, all real rows.
      final packet = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        sellingPricePaise: 0,
        stockQuantity: 0,
        isActive: true,
        shopId: shop,
        isIngredient: true,
      );
      await movements.adjustStock(
        productId: packet.id,
        delta: 10,
        reason: StockAdjustmentReason.purchase,
      );
      final plain = await menu('plain', 'Plain Maggi');
      await pumpAuthenticatedAsOwner(tester);

      final element = tester.element(find.byType(Scaffold).first);
      ProviderScope.containerOf(
        element,
      ).read(appRouterProvider).go(AppRoutes.inventoryRecipes);
      await pumpAsync(tester);

      // Map through the real editor UI: dish → add → ingredient → save.
      await tester.tap(find.text('Plain Maggi'));
      await pumpAsync(tester);
      await scrollSheetTo(tester, inEditor('Add'));
      await tester.tap(inEditor('Add'));
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Maggi Packet'));
      await pumpAsync(tester);
      final save = find.widgetWithText(FilledButton, 'Save recipe');
      await scrollSheetTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);
      expect(find.text('Recipe saved.'), findsOneWidget);

      // The UI-written rows drive the real checkout deduction.
      await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 4)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 6);
    });
  });
}
