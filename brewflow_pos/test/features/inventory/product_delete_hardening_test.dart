import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// BrewFlow POS — Product True Delete
///
/// Locks in the contract of [DriftInventoryRepository.deleteProduct]: a product
/// is *always* really deleted. History is never a reason to refuse.
///
///   a. a sale line, b. a purchase line and c. a stock movement each keep the
///      product deletable and survive it with their own name/price snapshots —
///      schema v31 dropped the historical FKs, so those columns are plain,
///   d. a variant and the per-shop stock overlay are product *definition*, not
///      history, so they leave with the product through their CASCADE keys and
///      no orphan is left behind,
///   e. an unreferenced product deletes exactly as before,
///   f./g. the mutation is scoped, so a shared Cafe catalogue entry can never be
///      deleted through a Food Truck session (nor through an empty scope),
///   h. an unknown id fails loudly instead of silently reporting success,
///   i. the delete reaches the cloud and the other devices as a real delete, so
///      nothing resurrects and no deactivated zombie is left behind.
///
/// Runs against a real in-memory Drift database so the FK cascades, the CHECK
/// constraints and the shop-scoping predicates behave exactly as in production.
void main() {
  const String cafeShopId = 'shop-cafe';
  const String truckShopId = 'shop-truck';

  late db.AppDatabase database;
  late DriftInventoryRepository repository;
  late DriftBillingRepository billing;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftInventoryRepository(database);
    billing = DriftBillingRepository(database);
    // Exactly one shop row, so the unscoped write paths resolve to the Cafe.
    await database
        .into(database.shops)
        .insert(
          db.ShopsCompanion.insert(id: Value(cafeShopId), name: 'The Cafe'),
        );
  });

  tearDown(() async {
    await database.close();
  });

  // ---- seeding helpers --------------------------------------------------

  Future<Product> seedProduct({
    String name = 'Chai',
    int stockQuantity = 0,
    int sellingPricePaise = 10000,
    List<ProductVariantInput> variants = const [],
  }) async {
    final category = await repository.createCategory('Beverages $name');
    return repository.createProduct(
      categoryId: category.id,
      name: name,
      sellingPricePaise: sellingPricePaise,
      stockQuantity: stockQuantity,
      isActive: true,
      variants: variants,
    );
  }

  /// A paid sale line pointing at [productId], with a snapshot name that differs
  /// from the live row so a join-based renderer could not pass by accident.
  Future<void> seedSaleItem(
    String productId, {
    String productName = 'Chai',
  }) async {
    await database
        .into(database.sales)
        .insert(
          db.SalesCompanion.insert(
            id: const Value('sale-1'),
            shopId: const Value(cafeShopId),
            receiptNumber: 'BF-0001',
            subtotalPaise: 10000,
            totalPaise: 10000,
            paymentMethod: const Value('CASH'),
          ),
        );
    await database
        .into(database.saleItems)
        .insert(
          db.SaleItemsCompanion.insert(
            id: const Value('si-1'),
            shopId: const Value(cafeShopId),
            saleId: 'sale-1',
            productId: productId,
            productName: productName,
            unitPricePaise: 10000,
            quantity: 1,
            lineTotalPaise: 10000,
          ),
        );
  }

  /// A purchase line pointing at [productId].
  Future<void> seedPurchaseItem(String productId) async {
    await database
        .into(database.purchases)
        .insert(
          db.PurchasesCompanion.insert(
            id: const Value('pur-1'),
            shopId: const Value(cafeShopId),
            purchaseNumber: 'PUR-000001',
            subtotalPaise: 8000,
            totalPaise: 8000,
          ),
        );
    await database
        .into(database.purchaseItems)
        .insert(
          db.PurchaseItemsCompanion.insert(
            id: const Value('pi-1'),
            shopId: const Value(cafeShopId),
            purchaseId: 'pur-1',
            productId: productId,
            productName: 'Chai',
            unitCostPaise: 8000,
            quantity: 1,
            lineTotalPaise: 8000,
          ),
        );
  }

  Future<void> seedTruckShop() => database
      .into(database.shops)
      .insert(
        db.ShopsCompanion.insert(
          id: const Value(truckShopId),
          name: 'Food Truck',
        ),
      );

  /// Raw product row, so assertions read the database rather than a mapping.
  Future<db.Product?> row(String id) => (database.select(
    database.products,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<bool> exists(String id) async => await row(id) != null;

  Future<List<db.ProductVariant>> variantsOf(String productId) =>
      (database.select(
        database.productVariants,
      )..where((t) => t.productId.equals(productId))).get();

  Future<List<db.ShopProductStockData>> stockOf(String productId) =>
      (database.select(
        database.shopProductStock,
      )..where((t) => t.productId.equals(productId))).get();

  /// The single mutation every group below performs.
  Future<ProductDeleteResult> delete(String id) =>
      repository.deleteProduct(id, shopIds: const [cafeShopId]);

  // ---- a-c: history no longer blocks the delete --------------------------

  group('history keeps the product deletable and survives it', () {
    test('a sale line no longer stops the delete', () async {
      final product = await seedProduct();
      await seedSaleItem(product.id, productName: 'Masala Chai');

      expect(await delete(product.id), ProductDeleteResult.deleted);
      expect(
        await exists(product.id),
        isFalse,
        reason: 'a sale line is history, not a reason to keep the row',
      );
    });

    test('the sale line keeps its own snapshot for the receipt', () async {
      final product = await seedProduct(name: 'Chai');
      await seedSaleItem(product.id, productName: 'Masala Chai');

      await delete(product.id);

      final sale = await billing.saleById('sale-1');
      final items = await billing.saleItemsFor('sale-1');
      expect(sale, isNotNull);
      expect(sale!.totalPaise, 10000);
      expect(items, hasLength(1));
      expect(
        items.single.productName,
        'Masala Chai',
        reason: 'the historical name comes from the line, never the live row',
      );
      expect(items.single.unitPricePaise, 10000);
      expect(items.single.lineTotalPaise, 10000);
      expect(
        items.single.productId,
        product.id,
        reason: 'the id is kept for attribution even though the row is gone',
      );
    });

    test('a purchase line no longer stops the delete', () async {
      final product = await seedProduct();
      await seedPurchaseItem(product.id);

      expect(await delete(product.id), ProductDeleteResult.deleted);
      expect(await exists(product.id), isFalse);

      final lines = await (database.select(
        database.purchaseItems,
      )..where((t) => t.productId.equals(product.id))).get();
      expect(lines, hasLength(1));
      expect(lines.single.productName, 'Chai');
      expect(lines.single.lineTotalPaise, 8000);
    });

    test('a stock movement no longer stops the delete', () async {
      // Opening stock writes exactly one OPENING movement, which is itself
      // history — so even a product created with stock is now deletable.
      final product = await seedProduct(stockQuantity: 5);

      final movements = await (database.select(
        database.stockMovements,
      )..where((t) => t.productId.equals(product.id))).get();
      expect(movements, hasLength(1));

      expect(await delete(product.id), ProductDeleteResult.deleted);
      expect(await exists(product.id), isFalse);

      final after = await (database.select(
        database.stockMovements,
      )..where((t) => t.productId.equals(product.id))).get();
      expect(
        after,
        hasLength(1),
        reason: 'the append-only movement log is never rewritten by a delete',
      );
    });

    test(
      'a product with sale, purchase, movement and variant history deletes in '
      'one go and leaves each of them exactly as it was',
      () async {
        final product = await seedProduct(
          // Stock lives on the variants, never on the parent.
          stockQuantity: 0,
          variants: const [
            ProductVariantInput(
              name: 'Small',
              sellingPricePaise: 10000,
              stockQuantity: 3,
            ),
          ],
        );
        await seedSaleItem(product.id, productName: 'Masala Chai');
        await seedPurchaseItem(product.id);

        final variantIds = (await variantsOf(
          product.id,
        )).map((v) => v.id).toList();
        final movementsBefore = await (database.select(
          database.stockMovements,
        )..where((t) => t.productId.equals(product.id))).get();

        expect(await delete(product.id), ProductDeleteResult.deleted);

        // Gone: the product and its definition.
        expect(await exists(product.id), isFalse);
        expect(
          await variantsOf(product.id),
          isEmpty,
          reason: 'variants are definition and cascade away',
        );
        expect(
          await stockOf(product.id),
          isEmpty,
          reason: 'the current stock overlay is definition and cascades away',
        );

        // Kept: every historical ledger row, untouched.
        expect(
          (await (database.select(
            database.saleItems,
          )..where((t) => t.productId.equals(product.id))).get()),
          hasLength(1),
        );
        expect(
          (await (database.select(
            database.purchaseItems,
          )..where((t) => t.productId.equals(product.id))).get()),
          hasLength(1),
        );
        final movementsAfter = await (database.select(
          database.stockMovements,
        )..where((t) => t.productId.equals(product.id))).get();
        expect(movementsAfter, hasLength(movementsBefore.length));
        expect(
          movementsAfter.first.movementType,
          movementsBefore.first.movementType,
        );
        expect(movementsAfter.first.quantity, movementsBefore.first.quantity);
        expect(
          movementsAfter.first.stockAfter,
          movementsBefore.first.stockAfter,
        );

        // The receipt still renders off the snapshots.
        final items = await billing.saleItemsFor('sale-1');
        expect(items.single.productName, 'Masala Chai');

        // Nothing above depended on the variant ids still resolving.
        expect(variantIds, isNotEmpty);
      },
    );
  });

  // ---- d: definition cascades -------------------------------------------

  group('variants and current stock are removed with the product', () {
    test('a variant leaves instead of becoming a zombie', () async {
      final product = await seedProduct(
        variants: const [
          ProductVariantInput(
            name: 'Small',
            sellingPricePaise: 10000,
            stockQuantity: 0,
          ),
          ProductVariantInput(
            name: 'Large',
            sellingPricePaise: 12000,
            stockQuantity: 0,
          ),
        ],
      );
      expect(await variantsOf(product.id), hasLength(2));

      expect(await delete(product.id), ProductDeleteResult.deleted);

      expect(await variantsOf(product.id), isEmpty);
      final orphan = (await database.select(database.productVariants).get())
          .where((v) => product.id == v.productId);
      expect(orphan, isEmpty);
    });

    test("another business's stock overlay leaves with the product too", () async {
      // The overlay is the *second shelf*: an owned product keeps its quantity in
      // `products.stock_quantity`, so an overlay row only ever exists for a
      // foreign product. That makes it the right fixture for the cascade — the
      // Cafe owns this product and the Food Truck stocks it.
      final product = await seedProduct(
        // Stock lives on the variants, never on the parent.
        stockQuantity: 0,
        variants: const [
          ProductVariantInput(
            name: 'Small',
            sellingPricePaise: 10000,
            stockQuantity: 3,
          ),
        ],
      );
      await seedTruckShop();
      final variant = (await variantsOf(product.id)).single;

      // One product-level row and one variant-level row for the truck.
      for (final entry in <(String, String?, int)>[
        ('sps-truck-product', null, 99),
        ('sps-truck-variant', variant.id, 50),
      ]) {
        await database
            .into(database.shopProductStock)
            .insert(
              db.ShopProductStockCompanion.insert(
                id: Value(entry.$1),
                shopId: truckShopId,
                productId: product.id,
                variantId: Value(entry.$2),
                quantity: Value(entry.$3),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
      }
      expect(await stockOf(product.id), hasLength(2));

      await delete(product.id);

      expect(await exists(product.id), isFalse);
      expect(
        await stockOf(product.id),
        isEmpty,
        reason:
            'deleting a catalogue row removes every shop\'s overlay with it — the '
            'delete is scoped to the product, never to one business',
      );
    });
  });

  // ---- e: an unreferenced product still deletes --------------------------

  group('an unreferenced product deletes exactly as before', () {
    test('removes the row and reports deleted', () async {
      final product = await seedProduct();

      expect(await delete(product.id), ProductDeleteResult.deleted);
      expect(await exists(product.id), isFalse);
    });

    test('deleting an already-deactivated product still removes it', () async {
      final product = await seedProduct();
      await repository.setProductActive(
        product.id,
        false,
        shopIds: const [cafeShopId],
      );

      expect(await delete(product.id), ProductDeleteResult.deleted);
      expect(await exists(product.id), isFalse);
    });

    test('deleting one product leaves its siblings alone', () async {
      final kept = await seedProduct(name: 'Coffee');
      final removed = await seedProduct(name: 'Juice');

      await delete(removed.id);

      expect(await exists(removed.id), isFalse);
      expect(await exists(kept.id), isTrue);
    });
  });

  // ---- f/g: the mutation is shop-scoped --------------------------------

  group('delete is scoped to the resolved businesses', () {
    test('an empty scope is refused and the row survives', () async {
      final product = await seedProduct();

      await expectLater(
        repository.deleteProduct(product.id, shopIds: const []),
        throwsA(isA<InventoryFailure>()),
      );
      expect(await exists(product.id), isTrue);
    });

    test('a scope that excludes the owning shop refuses the delete', () async {
      final product = await seedProduct();
      await seedTruckShop();

      // The Food Truck session does not own the Cafe catalogue row.
      await expectLater(
        repository.deleteProduct(product.id, shopIds: const [truckShopId]),
        throwsA(isA<ForeignShopRowFailure>()),
      );
      expect((await row(product.id))?.isActive, isTrue);
    });

    test(
      'an owner with both businesses can still delete the shared row',
      () async {
        final product = await seedProduct();
        await seedTruckShop();

        final result = await repository.deleteProduct(
          product.id,
          shopIds: const [cafeShopId, truckShopId],
        );

        expect(result, ProductDeleteResult.deleted);
        expect(await exists(product.id), isFalse);
      },
    );
  });

  // ---- h: an unknown id fails loudly -----------------------------------

  test('deleting an unknown id surfaces a failure', () async {
    await expectLater(
      repository.deleteProduct('does-not-exist', shopIds: const [cafeShopId]),
      throwsA(isA<InventoryFailure>()),
    );
  });

  // ---- i: the delete really reaches the cloud and the peers ------------

  group('the delete is propagated through the outbox', () {
    late db.AppDatabase syncDatabase;
    late FakeRemoteStore cloud;
    late SyncOutboxCoordinator coordinator;
    late SyncEngine engine;
    late DriftSyncRepository sync;
    late DriftInventoryRepository wiredRepository;

    /// A peer device with its own database, engine and view of the same cloud.
    ({SyncEngine engine, DriftInventoryRepository repo}) device(String id) {
      final otherDb = db.AppDatabase(NativeDatabase.memory());
      addTearDown(otherDb.close);
      final otherSync = DriftSyncRepository(otherDb);
      // The peer is a real install of the same business, so it has its own copy
      // of the shop identity row the pulled masters reference.
      otherDb
          .into(otherDb.shops)
          .insert(
            db.ShopsCompanion.insert(
              id: const Value(cafeShopId),
              name: 'The Cafe',
            ),
          );
      return (
        engine: SyncEngine(
          otherSync,
          FakeRemoteMasterDataGateway(cloud, viewerShopId: cafeShopId),
          LocalMasterDataApplier(otherDb),
        ),
        repo: DriftInventoryRepository(otherDb),
      );
    }

    setUp(() async {
      syncDatabase = db.AppDatabase(NativeDatabase.memory());
      addTearDown(syncDatabase.close);

      await syncDatabase
          .into(syncDatabase.shops)
          .insert(
            db.ShopsCompanion.insert(
              id: const Value(cafeShopId),
              name: 'The Cafe',
            ),
          );

      sync = DriftSyncRepository(syncDatabase);
      cloud = FakeRemoteStore();
      final gateway = FakeRemoteMasterDataGateway(
        cloud,
        viewerShopId: cafeShopId,
      );
      coordinator = SyncOutboxCoordinator(
        sync,
        () async => const SyncSessionContext(
          deviceId: 'A',
          shopId: cafeShopId,
          userId: 'owner',
        ),
      );
      engine = SyncEngine(sync, gateway, LocalMasterDataApplier(syncDatabase));
      wiredRepository = DriftInventoryRepository(
        syncDatabase,
        outboxCoordinator: coordinator,
      );
    });

    /// Creates a product on the shared cloud and on device A.
    Future<Product> seedSynced({int stockQuantity = 0}) async {
      final category = await wiredRepository.createCategory('Beverages');
      return wiredRepository.createProduct(
        categoryId: category.id,
        name: 'Chai',
        sellingPricePaise: 10000,
        stockQuantity: stockQuantity,
        isActive: true,
      );
    }

    test(
      'the remote row is really gone after a cycle, not just tombstoned',
      () async {
        final product = await seedSynced();
        // Push it so the cloud genuinely holds the row before we delete it.
        await engine.runCycle(deviceId: 'A', shopId: cafeShopId);
        expect(cloud.products.containsKey(product.id), isTrue);

        await wiredRepository.deleteProduct(
          product.id,
          shopIds: const [cafeShopId],
        );
        await engine.runCycle(deviceId: 'A', shopId: cafeShopId);

        expect(await exists(product.id), isFalse);
        expect(await sync.pendingOutboxCount(), 0);
        expect(
          cloud.products.containsKey(product.id),
          isFalse,
          reason:
              'the cloud row must be deleted, not left for every fresh device to '
              'pull and resurrect',
        );
        expect(
          cloud.deletions.values.any((d) => d.row.id == product.id),
          isTrue,
          reason: 'the tombstone is what makes the other devices drop it too',
        );
      },
    );

    test(
      'a product with history is still tombstoned, never re-upserted',
      () async {
        final product = await seedSynced(stockQuantity: 5); // history
        await engine.runCycle(deviceId: 'A', shopId: cafeShopId);
        expect(cloud.products.containsKey(product.id), isTrue);

        final result = await wiredRepository.deleteProduct(
          product.id,
          shopIds: const [cafeShopId],
        );
        expect(result, ProductDeleteResult.deleted);

        await engine.runCycle(deviceId: 'A', shopId: cafeShopId);

        expect(cloud.products.containsKey(product.id), isFalse);
        expect(
          cloud.deletions.values.any((d) => d.row.id == product.id),
          isTrue,
        );
      },
    );

    test('a peer that already had the product really deletes it', () async {
      final product = await seedSynced();
      final peer = device('B');

      // The peer pulls the product so it genuinely holds the row.
      await engine.runCycle(deviceId: 'A', shopId: cafeShopId);
      await peer.engine.runCycle(deviceId: 'B', shopId: cafeShopId);
      final pulled = await peer.repo.products(shopIds: const [cafeShopId]);
      expect(pulled.any((p) => p.id == product.id), isTrue);

      await wiredRepository.deleteProduct(
        product.id,
        shopIds: const [cafeShopId],
      );
      await engine.runCycle(deviceId: 'A', shopId: cafeShopId);

      await peer.engine.runCycle(deviceId: 'B', shopId: cafeShopId);

      final after = await peer.repo.products(shopIds: const [cafeShopId]);
      expect(
        after.any((p) => p.id == product.id),
        isFalse,
        reason: 'the peer must really delete the row, not deactivate a zombie',
      );
    });

    test('a peer that never had the product cannot resurrect it', () async {
      final product = await seedSynced();
      await engine.runCycle(deviceId: 'A', shopId: cafeShopId);

      // Delete happens while the peer is offline, so the peer never sees the row.
      await wiredRepository.deleteProduct(
        product.id,
        shopIds: const [cafeShopId],
      );
      await engine.runCycle(deviceId: 'A', shopId: cafeShopId);
      expect(cloud.products.containsKey(product.id), isFalse);

      final peer = device('B');
      await peer.engine.runCycle(deviceId: 'B', shopId: cafeShopId);

      final after = await peer.repo.products(shopIds: const [cafeShopId]);
      expect(
        after.any((p) => p.id == product.id),
        isFalse,
        reason: 'nothing may re-introduce the deleted row on a first sync',
      );
    });
  });
}
