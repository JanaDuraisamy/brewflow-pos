import 'package:brewflow_pos/core/database/app_database.dart'
    hide Product, StockMovement;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_cloud_gateway.dart';
import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared stock / recipe consumption contract.
///
/// Several menu products (Plain / Cheese / Egg / Veg Maggi) consume one
/// underlying stock source (Maggi Packet) without the shop knowing the split
/// in advance. A sale of a product WITH recipe rows deducts ONLY its
/// ingredients; products WITHOUT rows keep the historical own-stock path.
///
/// Covered against the real Drift stack:
///   create/restock/map, multi-product shared consumption, exact remainder,
///   no double deduction, insufficient stock, atomic concurrent deduction,
///   offline-first writes, outbox + cross-device sync, shop isolation,
///   hard-delete compatibility, bill preservation, alert integration and the
///   normal-product regression.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late DriftInventoryRepository inventory;
  late DriftStockMovementRepository movements;
  late DriftBillingRepository billing;

  const shop = 'shop-1';
  const otherShop = 'shop-2';

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
            name: 'Maggi',
            shopId: const Value(shop),
          ),
        );
  });

  tearDown(() => db.close());

  Future<Product> ingredient({
    String id = 'maggi-packet',
    int stock = 60,
    String shopId = shop,
  }) => inventory.createProduct(
    categoryId: 'cat-1',
    name: 'Maggi Packet $id',
    sellingPricePaise: 2000,
    stockQuantity: stock,
    isActive: true,
    shopId: shopId,
    isIngredient: true,
  );

  Future<Product> menu(
    String id,
    String name, {
    String shopId = shop,
    String categoryId = 'cat-1',
  }) => inventory.createProduct(
    categoryId: categoryId,
    name: name,
    sellingPricePaise: 4500,
    stockQuantity: 0,
    stockUnit: StockUnit.none,
    isActive: true,
    shopId: shopId,
  );

  Future<void> mapRecipe(
    String productId, {
    String ingredientId = 'maggi-packet',
    int quantity = 1,
    String? variantId,
    String? ingredientVariantId,
  }) => inventory.setRecipe(
    productId: productId,
    variantId: variantId,
    ingredients: [
      RecipeIngredientInput(
        ingredientProductId: ingredientId,
        ingredientVariantId: ingredientVariantId,
        quantity: quantity,
      ),
    ],
    shopId: shop,
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

  /// SALE movements of one product (opening/restock rows excluded).
  Future<List<StockMovement>> saleMovements(String productId) async =>
      (await movements.movementsFor(
        productId,
      )).where((m) => m.movementType == StockMovementType.sale).toList();

  group('setup', () {
    test('creates an ingredient stock source hidden from the shelf', () async {
      final packet = await ingredient();
      expect(packet.isIngredient, isTrue);
      expect(packet.stockQuantity, 60);

      // The sale shelf hides ingredients; inventory keeps them visible.
      final shelf = (await inventory.products(
        status: ProductStatusFilter.active,
        shopIds: const [shop],
      )).where((p) => !p.isIngredient).toList();
      expect(shelf.map((p) => p.id), isNot(contains(packet.id)));
      expect(
        await inventory.products(
          status: ProductStatusFilter.active,
          shopIds: const [shop],
        ),
        isNotEmpty,
      );
    });

    test('purchase restock increases the shared source', () async {
      final packet = await ingredient(stock: 60);
      await movements.adjustStock(
        productId: packet.id,
        delta: 40,
        reason: StockAdjustmentReason.purchase,
      );
      expect(await stockOf(packet.id), 100);
    });

    test('maps a menu product to its ingredient', () async {
      final packet = await ingredient();
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      final rows = await inventory.recipesForProduct(
        plain.id,
        shopIds: const [shop],
      );
      expect(rows, hasLength(1));
      expect(rows.single.ingredientProductId, packet.id);
      expect(rows.single.quantity, 1);
    });

    test('recipe validation rejects bad mappings', () async {
      final packet = await ingredient();
      final plain = await menu('plain', 'Plain Maggi');
      final untracked = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Made To Order',
        sellingPricePaise: 100,
        stockQuantity: 0,
        stockUnit: StockUnit.none,
        isActive: true,
        shopId: shop,
      );

      await expectLater(
        inventory.setRecipe(
          productId: plain.id,
          ingredients: [
            RecipeIngredientInput(ingredientProductId: packet.id, quantity: 0),
          ],
          shopId: shop,
        ),
        throwsA(isA<InventoryFailure>()),
      );
      await expectLater(
        inventory.setRecipe(
          productId: plain.id,
          ingredients: [RecipeIngredientInput(ingredientProductId: plain.id)],
          shopId: shop,
        ),
        throwsA(isA<InventoryFailure>()),
      );
      await expectLater(
        inventory.setRecipe(
          productId: plain.id,
          ingredients: [
            RecipeIngredientInput(ingredientProductId: untracked.id),
          ],
          shopId: shop,
        ),
        throwsA(isA<InventoryFailure>()),
      );
      expect(
        await inventory.recipesForProduct(plain.id, shopIds: const [shop]),
        isEmpty,
      );
    });
  });

  group('recipe mapping guards at the repository', () {
    test('a foreign-shop ingredient is refused (no cross-shop spend)', () async {
      // The ingredient belongs to shop-2: a Cafe product the shop merely sees.
      // Mapping it would deduct shop-2's stock on every sale here.
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('cat-2'),
              name: 'Truck menu',
              shopId: const Value(otherShop),
            ),
          );
      final foreignPacket = await inventory.createProduct(
        categoryId: 'cat-2',
        name: 'Truck Milk',
        sellingPricePaise: 2000,
        stockQuantity: 50,
        isActive: true,
        shopId: otherShop,
        isIngredient: true,
      );
      final dish = await menu('foreign-dish', 'Local Maggi');

      await expectLater(
        inventory.setRecipe(
          productId: dish.id,
          ingredients: [
            RecipeIngredientInput(ingredientProductId: foreignPacket.id),
          ],
          shopId: shop,
        ),
        throwsA(isA<ForeignShopRowFailure>()),
      );
      // Nothing was written, and the foreign stock is untouched.
      expect(
        await inventory.recipesForProduct(dish.id, shopIds: const [shop]),
        isEmpty,
      );
      expect(await stockOf(foreignPacket.id), 50);
    });

    test('a same-shop or shared-catalog ingredient still maps', () async {
      final packet = await ingredient();
      final dish = await menu('local-dish', 'Local Maggi');
      await mapRecipe(dish.id, ingredientId: packet.id);
      expect(
        await inventory.recipesForProduct(dish.id, shopIds: const [shop]),
        hasLength(1),
      );
    });

    test(
      'product-wide and variant scopes are refused at the repository',
      () async {
        final packet = await ingredient();
        final dish = await inventory.createProduct(
          categoryId: 'cat-1',
          name: 'Chai',
          sellingPricePaise: 3000,
          stockQuantity: 0,
          stockUnit: StockUnit.none,
          isActive: true,
          shopId: shop,
          variants: [
            const ProductVariantInput(
              name: 'Kulhad',
              sellingPricePaise: 3000,
              stockQuantity: 0,
            ),
          ],
        );
        final variantId = dish.variants.single.id;

        // A variant recipe exists: a product-wide save would double-deduct.
        await mapRecipe(dish.id, ingredientId: packet.id, variantId: variantId);
        await expectLater(
          inventory.setRecipe(
            productId: dish.id,
            ingredients: [
              RecipeIngredientInput(ingredientProductId: packet.id),
            ],
            shopId: shop,
          ),
          throwsA(isA<RecipeOverlapFailure>()),
        );
        expect(
          (await inventory.recipesForProduct(
            dish.id,
            shopIds: const [shop],
          )).map((r) => r.variantId),
          [variantId],
        );

        // Clearing is exempt (it only removes rows) and is how the owner
        // untangles an overlap.
        await inventory.setRecipe(
          productId: dish.id,
          variantId: variantId,
          ingredients: const [],
          shopId: shop,
        );
        await mapRecipe(dish.id, ingredientId: packet.id);

        // The mirror: a product-wide recipe blocks a variant save.
        await expectLater(
          inventory.setRecipe(
            productId: dish.id,
            variantId: variantId,
            ingredients: [
              RecipeIngredientInput(ingredientProductId: packet.id),
            ],
            shopId: shop,
          ),
          throwsA(isA<RecipeOverlapFailure>()),
        );
        expect(
          (await inventory.recipesForProduct(
            dish.id,
            shopIds: const [shop],
          )).map((r) => r.variantId),
          [isNull],
        );
      },
    );
  });

  group('checkout consumption', () {
    test('the Maggi example: 60 - (5+8+3+4) = 40', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      final cheese = await menu('cheese', 'Cheese Maggi');
      final veg = await menu('veg', 'Veg Maggi');
      final egg = await menu('egg', 'Egg Maggi');
      for (final item in [plain, cheese, veg, egg]) {
        await mapRecipe(item.id, ingredientId: packet.id);
      }

      await billing.completeSale(
        lines: [
          line(plain.id, 'Plain Maggi', 5),
          line(cheese.id, 'Cheese Maggi', 8),
          line(veg.id, 'Veg Maggi', 3),
          line(egg.id, 'Egg Maggi', 4),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 40);
    });

    test('no double deduction: menu own stock untouched', () async {
      final packet = await ingredient(stock: 60);
      // A tracked menu product with its own stock plus a recipe: the recipe
      // wins and the own shelf never moves.
      final menuTracked = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Cheese Maggi',
        sellingPricePaise: 4500,
        stockQuantity: 7,
        isActive: true,
        shopId: shop,
      );
      await mapRecipe(menuTracked.id, ingredientId: packet.id);

      await billing.completeSale(
        lines: [line(menuTracked.id, 'Cheese Maggi', 2)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 58);
      expect(await stockOf(menuTracked.id), 7);
    });

    test('insufficient shared stock fails the whole sale', () async {
      final packet = await ingredient(stock: 2);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      await expectLater(
        billing.completeSale(
          lines: [line(plain.id, 'Plain Maggi', 3)],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      expect(await stockOf(packet.id), 2);
      final sales = await db.select(db.sales).get();
      expect(sales, isEmpty);
    });

    test('concurrent sales cannot drive the source negative', () async {
      final packet = await ingredient(stock: 5);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      Future<Object?> attempt(int quantity) => billing
          .completeSale(
            lines: [line(plain.id, 'Plain Maggi', quantity)],
            paymentMethod: PaymentMethod.cash,
            shopId: shop,
          )
          .then<Object?>((_) => null)
          .catchError((Object e) => e);

      final results = await Future.wait([attempt(3), attempt(3)]);
      expect(
        results.whereType<InsufficientStockFailure>(),
        hasLength(1),
        reason: 'exactly one of the two racing sales must fail',
      );
      expect(await stockOf(packet.id), 2);
    });

    test('consumption quantity scales per unit sold', () async {
      final packet = await ingredient(stock: 10);
      final family = await menu('family', 'Family Maggi');
      await inventory.setRecipe(
        productId: family.id,
        ingredients: [
          RecipeIngredientInput(ingredientProductId: packet.id, quantity: 2),
        ],
        shopId: shop,
      );

      await billing.completeSale(
        lines: [line(family.id, 'Family Maggi', 3)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 4);
    });

    test('voiding a recipe sale restores the shared source', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      final completed = await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 55);

      await billing.voidSale(completed.sale.id);
      expect(await stockOf(packet.id), 60);
    });

    test('void restores the sale-time ingredient, not a later remap', () async {
      final packet = await ingredient(stock: 60);
      final other = await ingredient(id: 'maggi-masala', stock: 40);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      final completed = await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 55);

      // The mapping is edited AFTER the sale: only the snapshot is trustworthy.
      await mapRecipe(plain.id, ingredientId: other.id);

      await billing.voidSale(completed.sale.id);

      // The ORIGINAL ingredient is restored; the new mapping is never consulted.
      expect(await stockOf(packet.id), 60);
      expect(await stockOf(other.id), 40);
    });

    test(
      'a legacy sale with recorded movements restores the ingredient once',
      () async {
        final packet = await ingredient(stock: 60);
        final plain = await menu('plain', 'Plain Maggi');
        await mapRecipe(plain.id, ingredientId: packet.id);

        final completed = await billing.completeSale(
          lines: [line(plain.id, 'Plain Maggi', 5)],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        );
        expect(await stockOf(packet.id), 55);

        // Simulate a pre-snapshot row: no consumed snapshot on any line, so the
        // void must fall back to the recorded SALE movements — which for a
        // mapped line live on the INGREDIENT, not the menu product.
        await db.customStatement(
          'UPDATE sale_items SET consumed = NULL WHERE sale_id = ?',
          [completed.sale.id],
        );

        await billing.voidSale(completed.sale.id);

        expect(await stockOf(packet.id), 60);
      },
    );

    test('a mixed snapshot/NULL sale fails safe and restores nothing', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      final water = await menu('water', 'Water');
      await mapRecipe(plain.id, ingredientId: packet.id);

      final completed = await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5), line(water.id, 'Water', 2)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 55);

      // Force a mix: one snapshotted line loses its snapshot.
      await db.customStatement(
        'UPDATE sale_items SET consumed = NULL WHERE sale_id = ? AND product_id = ?',
        [completed.sale.id, water.id],
      );

      await expectLater(
        billing.voidSale(completed.sale.id),
        throwsA(isA<VoidHistoryPrunedFailure>()),
      );

      // Nothing restored, and the sale stays open for the no-restore path.
      expect(await stockOf(packet.id), 55);
      final saleRow = await (db.select(
        db.sales,
      )..where((t) => t.id.equals(completed.sale.id))).getSingle();
      expect(saleRow.voided, isFalse);
    });
  });

  group('offline-first', () {
    test('recipe mapping and sales work with no cloud or outbox', () async {
      // No connectivity service, no gateway, no coordinator: the repository
      // pair behaves exactly as the offline install does.
      final packet = await ingredient(stock: 10);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);
      await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 4)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 6);
    });
  });

  group('sync and cross-device', () {
    test('recipe rows ride the existing outbox to a second device', () async {
      final cloud = FakeRemoteStore();
      // Device A: inventory + billing sharing one database and outbox.
      final dbA = AppDatabase(NativeDatabase.memory());
      addTearDown(dbA.close);
      await dbA
          .into(dbA.shops)
          .insert(ShopsCompanion.insert(id: const Value(shop), name: 'Cafe'));
      await dbA
          .into(dbA.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('cat-1'),
              name: 'Maggi',
              shopId: const Value(shop),
            ),
          );
      final syncA = DriftSyncRepository(dbA);
      final coordinatorA = SyncOutboxCoordinator(
        syncA,
        () async => const SyncSessionContext(
          deviceId: 'A',
          shopId: shop,
          userId: 'owner',
        ),
      );
      final inventoryA = DriftInventoryRepository(
        dbA,
        outboxCoordinator: coordinatorA,
      );
      final packetA = await inventoryA.createProduct(
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        sellingPricePaise: 2000,
        stockQuantity: 60,
        isActive: true,
        shopId: shop,
        isIngredient: true,
      );
      final plainA = await inventoryA.createProduct(
        categoryId: 'cat-1',
        name: 'Plain Maggi',
        sellingPricePaise: 4500,
        stockQuantity: 0,
        stockUnit: StockUnit.none,
        isActive: true,
        shopId: shop,
      );
      await inventoryA.setRecipe(
        productId: plainA.id,
        ingredients: [RecipeIngredientInput(ingredientProductId: packetA.id)],
        shopId: shop,
      );
      expect(await syncA.pendingOutboxCount(), greaterThanOrEqualTo(3));

      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: shop);
      final engineA = SyncEngine(syncA, gatewayA, LocalMasterDataApplier(dbA));
      await engineA.runCycle(deviceId: 'A', shopId: shop);
      expect(cloud.productRecipes, hasLength(1));

      // Device B knows the same catalogue ids (synced products) and pulls.
      final dbB = AppDatabase(NativeDatabase.memory());
      addTearDown(dbB.close);
      await dbB
          .into(dbB.shops)
          .insert(ShopsCompanion.insert(id: const Value(shop), name: 'Cafe'));
      await dbB
          .into(dbB.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('cat-1'),
              name: 'Maggi',
              shopId: const Value(shop),
            ),
          );
      for (final source in [packetA, plainA]) {
        await dbB
            .into(dbB.products)
            .insert(
              ProductsCompanion.insert(
                id: Value(source.id),
                shopId: Value(shop),
                categoryId: 'cat-1',
                name: source.name,
                sellingPricePaise: source.sellingPricePaise,
                stockQuantity: Value(source.stockQuantity),
              ),
            );
      }
      final syncB = DriftSyncRepository(dbB);
      final engineB = SyncEngine(
        syncB,
        FakeRemoteMasterDataGateway(cloud, viewerShopId: shop),
        LocalMasterDataApplier(dbB),
      );
      await engineB.runCycle(deviceId: 'B', shopId: shop);
      final pulled = await dbB.select(dbB.productRecipes).get();
      expect(pulled, hasLength(1));
      expect(pulled.single.productId, plainA.id);
      expect(pulled.single.ingredientProductId, packetA.id);
      expect(pulled.single.quantity, 1);
    });

    test('ingredient stock levels sync through the sale outbox', () async {
      final cloud = FakeRemoteStore();
      final dbA = AppDatabase(NativeDatabase.memory());
      addTearDown(dbA.close);
      await dbA
          .into(dbA.shops)
          .insert(ShopsCompanion.insert(id: const Value(shop), name: 'Cafe'));
      await dbA
          .into(dbA.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('cat-1'),
              name: 'Maggi',
              shopId: const Value(shop),
            ),
          );
      final syncA = DriftSyncRepository(dbA);
      final coordinatorA = SyncOutboxCoordinator(
        syncA,
        () async => const SyncSessionContext(
          deviceId: 'A',
          shopId: shop,
          userId: 'owner',
        ),
      );
      final inventoryA = DriftInventoryRepository(
        dbA,
        outboxCoordinator: coordinatorA,
      );
      final billingA = DriftBillingRepository(
        dbA,
        outboxCoordinator: coordinatorA,
      );
      final packet = await inventoryA.createProduct(
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        sellingPricePaise: 2000,
        stockQuantity: 60,
        isActive: true,
        shopId: shop,
        isIngredient: true,
      );
      final plain = await inventoryA.createProduct(
        categoryId: 'cat-1',
        name: 'Plain Maggi',
        sellingPricePaise: 4500,
        stockQuantity: 0,
        stockUnit: StockUnit.none,
        isActive: true,
        shopId: shop,
      );
      await inventoryA.setRecipe(
        productId: plain.id,
        ingredients: [RecipeIngredientInput(ingredientProductId: packet.id)],
        shopId: shop,
      );
      await billingA.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      final engineA = SyncEngine(
        syncA,
        FakeRemoteMasterDataGateway(cloud, viewerShopId: shop),
        LocalMasterDataApplier(dbA),
      );
      await engineA.runCycle(deviceId: 'A', shopId: shop);
      // The deducted ingredient level reached the cloud on the PRODUCT row.
      final pushed = cloud.products[packet.id]!;
      expect(pushed.row.stockQuantity, 55);
      expect(pushed.row.isIngredient, isTrue);
    });
  });

  group('shop isolation', () {
    test('recipes never leak across shops', () async {
      final packet = await ingredient();
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      // The other shop sees no recipe for the same menu id scope.
      expect(
        await inventory.recipesForProduct(plain.id, shopIds: const [otherShop]),
        isEmpty,
      );
      // And a sale in the other shop (same menu name, own product) deducts
      // its own stock instead.
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('cat-2'),
              name: 'Truck',
              shopId: const Value(otherShop),
            ),
          );
      final truckMenu = await menu(
        'truck-mag',
        'Truck Maggi',
        shopId: otherShop,
        categoryId: 'cat-2',
      );
      await billing.completeSale(
        lines: [line(truckMenu.id, 'Truck Maggi', 1)],
        paymentMethod: PaymentMethod.cash,
        shopId: otherShop,
      );
      expect(await stockOf(packet.id), 60);
    });
  });

  group('hard delete and history', () {
    test(
      'deleting the ingredient drops its mappings, bills stay intact',
      () async {
        final packet = await ingredient(stock: 60);
        final plain = await menu('plain', 'Plain Maggi');
        await mapRecipe(plain.id, ingredientId: packet.id);
        final completed = await billing.completeSale(
          lines: [line(plain.id, 'Plain Maggi', 5)],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        );

        await inventory.deleteProduct(packet.id, shopIds: const [shop]);

        expect(
          await inventory.recipesForProduct(plain.id, shopIds: const [shop]),
          isEmpty,
        );
        // The bill keeps its own name/price snapshot after the delete.
        final items = await db.select(db.saleItems).get();
        expect(items, hasLength(1));
        expect(items.single.productId, plain.id);
        expect(items.single.productName, 'Plain Maggi');
        expect(items.single.quantity, 5);
        final sales = await db.select(db.sales).get();
        expect(sales.map((s) => s.id), contains(completed.sale.id));
      },
    );

    test('past bills keep snapshots when products change', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);
      await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 2)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      await inventory.updateProduct(
        id: plain.id,
        categoryId: 'cat-1',
        name: 'Plain Maggi Deluxe',
        sellingPricePaise: 9900,
        stockQuantity: 0,
        stockUnit: StockUnit.none,
        isActive: true,
        shopIds: const [shop],
      );

      final items = await db.select(db.saleItems).get();
      expect(items.single.productName, 'Plain Maggi');
      expect(items.single.unitPricePaise, 4500);
    });
  });

  group('alerts and regression', () {
    test('a drained shared source raises low then out alerts', () async {
      final packet = await ingredient(stock: 5);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      Product snapshot(int stock) => Product(
        id: packet.id,
        categoryId: 'cat-1',
        name: 'Maggi Packet',
        sellingPricePaise: 2000,
        stockQuantity: stock,
        isActive: true,
        shopId: shop,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      expect(
        buildStockAlerts([snapshot(5)], 5).single.kind,
        StockAlertKind.lowStock,
      );

      await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      final after = buildStockAlerts([snapshot(await stockOf(packet.id))], 5);
      expect(after.single.kind, StockAlertKind.outOfStock);
    });

    test('normal products without recipes deduct their own stock', () async {
      final tea = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Milk Tea',
        sellingPricePaise: 3000,
        stockQuantity: 10,
        isActive: true,
        shopId: shop,
      );
      await billing.completeSale(
        lines: [line(tea.id, 'Milk Tea', 3)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(tea.id), 7);
    });
  });

  group('five-consumer shared stock (Plain/Cheese/Veg/Egg/Masala)', () {
    Future<Product> dish(String id, String name) =>
        menu(id, name, categoryId: 'cat-1');

    Future<Map<String, Product>> fiveDishes() async {
      final dishes = <String, Product>{};
      for (final entry in const [
        ('plain', 'Plain Maggi'),
        ('cheese', 'Cheese Maggi'),
        ('veg', 'Veg Maggi'),
        ('egg', 'Egg Maggi'),
        ('masala', 'Masala Maggi'),
      ]) {
        dishes[entry.$1] = await dish(entry.$1, entry.$2);
      }
      return dishes;
    }

    Future<void> mapAll(
      Map<String, Product> dishes,
      String ingredientId,
    ) async {
      for (final product in dishes.values) {
        await mapRecipe(product.id, ingredientId: ingredientId);
      }
    }

    Future<List<StockMovement>> packetMovements(String packetId) =>
        saleMovements(packetId);

    test('three dishes x1 each: 60 - 3 = 57, one deduction total', () async {
      final packet = await ingredient(stock: 60);
      final dishes = await fiveDishes();
      await mapAll(dishes, packet.id);

      await billing.completeSale(
        lines: [
          line(dishes['plain']!.id, 'Plain Maggi', 1),
          line(dishes['cheese']!.id, 'Cheese Maggi', 1),
          line(dishes['veg']!.id, 'Veg Maggi', 1),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 57);
      // Different dishes deduct the SAME ingredient stock, never their own.
      for (final product in dishes.values) {
        expect(await stockOf(product.id), 0);
      }
      // Exactly one aggregated deduction for the shared ingredient.
      final moves = await packetMovements(packet.id);
      expect(moves, hasLength(1));
      expect(moves.single.quantity, -3);
      expect(moves.single.stockBefore, 60);
      expect(moves.single.stockAfter, 57);
    });

    test('all five mixed quantities aggregate into one deduction', () async {
      final packet = await ingredient(stock: 60);
      final dishes = await fiveDishes();
      await mapAll(dishes, packet.id);

      await billing.completeSale(
        lines: [
          line(dishes['plain']!.id, 'Plain Maggi', 2),
          line(dishes['cheese']!.id, 'Cheese Maggi', 1),
          line(dishes['veg']!.id, 'Veg Maggi', 3),
          line(dishes['egg']!.id, 'Egg Maggi', 1),
          line(dishes['masala']!.id, 'Masala Maggi', 2),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 51);
      expect(await packetMovements(packet.id), hasLength(1));
    });
  });

  group('recipe matching levels', () {
    Future<Product> variantDish() => inventory.createProduct(
      categoryId: 'cat-1',
      name: 'Maggi',
      sellingPricePaise: 4500,
      stockQuantity: 0,
      stockUnit: StockUnit.none,
      isActive: true,
      shopId: shop,
      variants: const [
        ProductVariantInput(
          name: 'Cheese',
          sellingPricePaise: 5000,
          stockQuantity: 0,
          isActive: true,
        ),
        ProductVariantInput(
          name: 'Plain',
          sellingPricePaise: 4500,
          stockQuantity: 0,
          isActive: true,
        ),
      ],
    );

    CartLine variantLine({
      required String productId,
      required String variantId,
      required String variantName,
      required int quantity,
    }) => CartLine(
      productId: productId,
      productName: 'Maggi',
      sku: null,
      unitPricePaise: 5000,
      quantity: quantity,
      maxQuantity: 99,
      variantId: variantId,
      variantName: variantName,
    );

    test('one product-level row covers every variant', () async {
      final packet = await ingredient(stock: 60);
      final maggi = await variantDish();
      final cheese = maggi.variants.firstWhere((v) => v.name == 'Cheese');
      final plain = maggi.variants.firstWhere((v) => v.name == 'Plain');
      await inventory.setRecipe(
        productId: maggi.id,
        ingredients: [RecipeIngredientInput(ingredientProductId: packet.id)],
        shopId: shop,
      );

      await billing.completeSale(
        lines: [
          variantLine(
            productId: maggi.id,
            variantId: cheese.id,
            variantName: 'Cheese',
            quantity: 2,
          ),
          variantLine(
            productId: maggi.id,
            variantId: plain.id,
            variantName: 'Plain',
            quantity: 1,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 57);
    });

    test('a variant-specific row applies only to that variant', () async {
      final packet = await ingredient(stock: 60);
      final maggi = await variantDish();
      final cheese = maggi.variants.firstWhere((v) => v.name == 'Cheese');
      final plain = maggi.variants.firstWhere((v) => v.name == 'Plain');
      await inventory.setRecipe(
        productId: maggi.id,
        variantId: cheese.id,
        ingredients: [RecipeIngredientInput(ingredientProductId: packet.id)],
        shopId: shop,
      );

      await billing.completeSale(
        lines: [
          variantLine(
            productId: maggi.id,
            variantId: cheese.id,
            variantName: 'Cheese',
            quantity: 1,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 59);

      // The unmapped sibling variant consumes nothing anywhere: its own
      // NONE stock is untracked and the packet is untouched.
      await billing.completeSale(
        lines: [
          variantLine(
            productId: maggi.id,
            variantId: plain.id,
            variantName: 'Plain',
            quantity: 1,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 59);
      final moves = await db.select(db.stockMovements).get();
      expect(moves.where((m) => m.referenceType == 'SALE'), hasLength(1));
    });
  });

  group('retry and replay safety', () {
    test('a failed multi-line sale leaves no partial deduction', () async {
      final packet = await ingredient(stock: 3);
      final plain = await menu('plain', 'Plain Maggi');
      final cheese = await menu('cheese', 'Cheese Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);
      await mapRecipe(cheese.id, ingredientId: packet.id);

      // Aggregated need is 4 against 3: the whole sale rolls back.
      await expectLater(
        billing.completeSale(
          lines: [
            line(plain.id, 'Plain Maggi', 2),
            line(cheese.id, 'Cheese Maggi', 2),
          ],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      expect(await stockOf(packet.id), 3);
      expect(await db.select(db.sales).get(), isEmpty);
      // The ingredient's OPENING movement stays; no SALE movement exists.
      expect(await saleMovements(packet.id), isEmpty);
    });

    test('a restocked retry deducts exactly once', () async {
      final packet = await ingredient(stock: 2);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      await expectLater(
        billing.completeSale(
          lines: [line(plain.id, 'Plain Maggi', 3)],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      expect(await stockOf(packet.id), 2);

      await movements.adjustStock(
        productId: packet.id,
        delta: 2,
        reason: StockAdjustmentReason.purchase,
      );
      await billing.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 3)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 1);
      expect((await db.select(db.sales).get()).length, 1);
    });

    test('re-saving a mapping converges on one row', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);
      final first = (await inventory.recipesForProduct(
        plain.id,
        shopIds: const [shop],
      )).single;

      await mapRecipe(plain.id, ingredientId: packet.id);
      final rows = await inventory.recipesForProduct(
        plain.id,
        shopIds: const [shop],
      );
      expect(rows, hasLength(1));
      expect(rows.single.id, first.id);

      // A quantity edit updates the row instead of orphaning it.
      await mapRecipe(plain.id, ingredientId: packet.id, quantity: 2);
      final updated = await inventory.recipesForProduct(
        plain.id,
        shopIds: const [shop],
      );
      expect(updated, hasLength(1));
      expect(updated.single.id, first.id);
      expect(updated.single.quantity, 2);
    });
  });

  group('cloud-path mirror parity', () {
    DriftBillingRepository cloudBilling() =>
        DriftBillingRepository(db, cloudGateway: FakeBillingCloudGateway());

    test('a cloud sale of mapped dishes deducts the packet only', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      await cloudBilling().completeSale(
        lines: [line(plain.id, 'Plain Maggi', 4)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(packet.id), 56);
      expect(await stockOf(plain.id), 0);
      final moves = await saleMovements(packet.id);
      expect(moves, hasLength(1));
      expect(moves.single.quantity, -4);
      expect(moves.single.stockBefore, 60);
      expect(moves.single.stockAfter, 56);
    });

    test(
      'a cloud sale of a tracked mapped dish leaves own stock alone',
      () async {
        final packet = await ingredient(stock: 60);
        final tracked = await inventory.createProduct(
          categoryId: 'cat-1',
          name: 'Cheese Maggi',
          sellingPricePaise: 4500,
          stockQuantity: 7,
          isActive: true,
          shopId: shop,
        );
        await mapRecipe(tracked.id, ingredientId: packet.id);

        await cloudBilling().completeSale(
          lines: [line(tracked.id, 'Cheese Maggi', 2)],
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        );

        expect(await stockOf(tracked.id), 7);
        expect(await stockOf(packet.id), 58);
      },
    );

    test('a cloud sale without recipes still deducts own stock', () async {
      final tea = await inventory.createProduct(
        categoryId: 'cat-1',
        name: 'Milk Tea',
        sellingPricePaise: 3000,
        stockQuantity: 10,
        isActive: true,
        shopId: shop,
      );

      await cloudBilling().completeSale(
        lines: [line(tea.id, 'Milk Tea', 3)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );

      expect(await stockOf(tea.id), 7);
      final moves = await saleMovements(tea.id);
      expect(moves.single.quantity, -3);
    });

    test('a cloud void of a mapped sale restores the packet', () async {
      final packet = await ingredient(stock: 60);
      final plain = await menu('plain', 'Plain Maggi');
      await mapRecipe(plain.id, ingredientId: packet.id);

      final cloud = cloudBilling();
      final completed = await cloud.completeSale(
        lines: [line(plain.id, 'Plain Maggi', 5)],
        paymentMethod: PaymentMethod.cash,
        shopId: shop,
      );
      expect(await stockOf(packet.id), 55);

      await cloud.voidSale(completed.sale.id);
      expect(await stockOf(packet.id), 60);
      expect(await stockOf(plain.id), 0);
    });
  });

  group('food truck independence', () {
    test(
      'the truck maps its own packet; the cafe packet is untouched',
      () async {
        final cafePacket = await ingredient(stock: 60);
        final plain = await menu('plain', 'Plain Maggi');
        await mapRecipe(plain.id, ingredientId: cafePacket.id);

        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: const Value('cat-truck'),
                name: 'Truck',
                shopId: const Value(otherShop),
              ),
            );
        final truckPacket = await inventory.createProduct(
          categoryId: 'cat-truck',
          name: 'Maggi Packet',
          sellingPricePaise: 2000,
          stockQuantity: 30,
          isActive: true,
          shopId: otherShop,
          isIngredient: true,
        );
        final truckMaggi = await menu(
          'truck-mag',
          'Truck Maggi',
          shopId: otherShop,
          categoryId: 'cat-truck',
        );
        await inventory.setRecipe(
          productId: truckMaggi.id,
          ingredients: [
            RecipeIngredientInput(ingredientProductId: truckPacket.id),
          ],
          shopId: otherShop,
        );

        await billing.completeSale(
          lines: [line(truckMaggi.id, 'Truck Maggi', 2)],
          paymentMethod: PaymentMethod.cash,
          shopId: otherShop,
        );

        expect(await stockOf(truckPacket.id), 28);
        expect(await stockOf(cafePacket.id), 60);
      },
    );
  });
}
