import 'package:brewflow_pos/core/database/app_database.dart' hide Product;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/data/jiggar_menu_seed.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// P0 master data — JIGGAR Tea House menu seed.
///
/// Verifies: exact catalog shape (8 categories / 43 menu products + the
/// shared Maggi Packet ingredient / 5 variants), idempotent re-runs,
/// reconciliation of drifted rows, made-to-order stock semantics (NONE +
/// zero stock, sellable), shared-stock wiring of the Maggie dishes, and full
/// A→cloud→B propagation through the REAL outbox/engine path against the
/// in-memory cloud mirror.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  DriftInventoryRepository plainRepo() => DriftInventoryRepository(db);

  group('catalog shape', () {
    test(
      'creates 8 categories, 43 menu products + packet, 5 variants',
      () async {
        final result = await JiggarMenuSeeder(plainRepo()).run();

        expect(result.categoriesCreated, 8);
        expect(result.productsCreated, 43);
        expect(result.variantsCreated, 5);
        expect(result.productsUpdated, 0);
        expect(result.productsSkipped, 0);
        // The shared-stock packet is ensured outside the menu counters.
        expect(result.ingredientsEnsured, 1);

        final products = await plainRepo().products();
        expect(products.length, 44);
        final variantProducts = products.where((p) => p.variants.isNotEmpty);
        expect(variantProducts.length, 2);
      },
    );

    test('prices land as integer paise', () async {
      await JiggarMenuSeeder(plainRepo()).run();
      final products = await plainRepo().products();
      final byName = {for (final p in products) p.name: p};

      expect(byName['Plain Milk']!.sellingPricePaise, 1500);
      expect(byName['Black Tea']!.sellingPricePaise, 1200);
      expect(byName['Super SPL Jigarthanda']!.sellingPricePaise, 10500);
      expect(byName['Gems Popsicle']!.sellingPricePaise, 6500);

      final chai = byName['SPL Milk Chai']!;
      final chai100 = chai.variants.firstWhere((v) => v.name == '100ml');
      final chai160 = chai.variants.firstWhere((v) => v.name == '160ml');
      expect(chai100.sellingPricePaise, 1500);
      expect(chai160.sellingPricePaise, 2000);
    });

    test(
      'made-to-order semantics: NONE units, zero stock, alerts off',
      () async {
        await JiggarMenuSeeder(plainRepo()).run();
        final products = await plainRepo().products();
        for (final product in products) {
          // The shared Maggi Packet is the one tracked exception: a counted,
          // alert-eligible stock source hidden from the shelf.
          if (product.isIngredient) continue;
          expect(
            product.stockUnit,
            StockUnit.none,
            reason: '${product.name} must be untracked',
          );
          expect(product.stockQuantity, 0);
          expect(product.lowStockMode, LowStockMode.off);
          for (final variant in product.variants) {
            expect(
              variant.stockQuantity,
              0,
              reason: '${product.name}/${variant.name}',
            );
          }
        }
      },
    );
  });

  group('idempotency + reconciliation', () {
    test('re-run creates nothing new and reports skips', () async {
      final seeder = JiggarMenuSeeder(plainRepo());
      await seeder.run();
      final second = await seeder.run();

      expect(second.categoriesCreated, 0);
      expect(second.categoriesSkipped, 8);
      expect(second.productsCreated, 0);
      expect(second.productsUpdated, 0);
      expect(second.productsSkipped, 43);
      expect(second.ingredientsEnsured, 0);
      expect((await plainRepo().products()).length, 44);
      expect((await plainRepo().categories()).length, 8);
    });

    test('reconciles a drifted price without duplicating', () async {
      final repo = plainRepo();
      await JiggarMenuSeeder(repo).run();
      // Simulate a manual drift: Plain Milk repriced to ₹20 via updateProduct.
      final products = await repo.products();
      final milk = products.firstWhere((p) => p.name == 'Plain Milk');
      await repo.updateProduct(
        id: milk.id,
        categoryId: milk.categoryId,
        name: milk.name,
        sku: milk.sku,
        sellingPricePaise: 2000,
        stockQuantity: milk.stockQuantity,
        imagePath: milk.imagePath,
        isActive: true,
      );

      final second = await JiggarMenuSeeder(repo).run();
      expect(second.productsUpdated, 1);
      final after = (await repo.products()).firstWhere(
        (p) => p.name == 'Plain Milk',
      );
      expect(after.sellingPricePaise, 1500);
      expect(
        (await repo.categories()).length,
        8,
        reason: 'reconciliation never duplicates',
      );
    });

    test('case-insensitive category match prevents duplicates', () async {
      final repo = plainRepo();
      // Pre-create with different case than the board ('Tea' vs 'TEA').
      await repo.createCategory('Tea');
      await JiggarMenuSeeder(repo).run();

      final names = (await repo.categories()).map((c) => c.name).toSet();
      expect(names.where((n) => n.toLowerCase() == 'tea').length, 1);
      expect(await repo.categories().then((c) => c.length), 8);
    });
  });

  group('sync propagation through real outbox path', () {
    test('A seeds → cloud → device B receives identical master data', () async {
      // Device A: seeding wired to the atomic outbox coordinator.
      final syncA = DriftSyncRepository(db);
      final cloud = FakeRemoteStore();
      // Seed the canonical single-shop row (owner bootstraps it with the same
      // id as the session shopId), so local writes, outbox payloads and the
      // pull-side FK all resolve to 'shop'.
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: const Value('shop'),
              name: 'JIGGAR Tea House',
            ),
          );
      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: 'shop');
      final coordinatorA = SyncOutboxCoordinator(
        syncA,
        () async => const SyncSessionContext(
          deviceId: 'A',
          shopId: 'shop',
          userId: 'owner',
        ),
      );
      final repoA = DriftInventoryRepository(
        db,
        outboxCoordinator: coordinatorA,
      );
      final engineA = SyncEngine(syncA, gatewayA, LocalMasterDataApplier(db));

      await JiggarMenuSeeder(repoA).run();
      await engineA.runCycle(deviceId: 'A', shopId: 'shop');

      expect(cloud.categories.length, 8);
      expect(cloud.products.length, 44);
      expect(cloud.productVariants.length, 5);
      expect(await syncA.pendingOutboxCount(), 0);

      // Device B: empty database, pulls everything down.
      final dbB = AppDatabase(NativeDatabase.memory());
      addTearDown(dbB.close);
      // Every device owns its canonical shop row; the pull lands shop-scoped
      // rows and the shop_id FK must reference it.
      await dbB
          .into(dbB.shops)
          .insert(
            ShopsCompanion.insert(
              id: const Value('shop'),
              name: 'JIGGAR Tea House',
            ),
          );
      final syncB = DriftSyncRepository(dbB);
      final gatewayB = FakeRemoteMasterDataGateway(cloud, viewerShopId: 'shop');
      final engineB = SyncEngine(syncB, gatewayB, LocalMasterDataApplier(dbB));
      await engineB.runCycle(deviceId: 'B', shopId: 'shop');

      final repoB = DriftInventoryRepository(dbB);
      final bCategories = await repoB.categories();
      final bProducts = await repoB.products();
      expect(bCategories.map((c) => c.name).toSet().length, 8);
      expect(bProducts.length, 44);

      final bByName = {for (final p in bProducts) p.name: p};
      final bChai = bByName['SPL Milk Chai']!;
      expect(
        bChai.variants.firstWhere((v) => v.name == '100ml').sellingPricePaise,
        1500,
      );
      expect(
        bChai.variants.firstWhere((v) => v.name == '160ml').sellingPricePaise,
        2000,
      );
      final bShake = bByName['SPL Milkshakes']!;
      expect(bShake.variants.map((v) => v.name).toSet(), {
        'Mango',
        'Vanilla',
        'Strawberry',
      });
      for (final v in bShake.variants) {
        expect(v.sellingPricePaise, 10000);
      }
    });

    test('cross-shop isolation: another shop never sees the menu', () async {
      final syncA = DriftSyncRepository(db);
      final cloud = FakeRemoteStore();
      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: 'shop');
      final coordinatorA = SyncOutboxCoordinator(
        syncA,
        () async => const SyncSessionContext(
          deviceId: 'A',
          shopId: 'shop',
          userId: 'owner',
        ),
      );
      final repoA = DriftInventoryRepository(
        db,
        outboxCoordinator: coordinatorA,
      );
      await JiggarMenuSeeder(repoA).run();
      await SyncEngine(
        syncA,
        gatewayA,
        LocalMasterDataApplier(db),
      ).runCycle(deviceId: 'A', shopId: 'shop');

      final intruderDb = AppDatabase(NativeDatabase.memory());
      addTearDown(intruderDb.close);
      final intruderGateway = FakeRemoteMasterDataGateway(
        cloud,
        viewerShopId: 'other-shop',
      );
      await SyncEngine(
        DriftSyncRepository(intruderDb),
        intruderGateway,
        LocalMasterDataApplier(intruderDb),
      ).runCycle(deviceId: 'EVIL', shopId: 'other-shop');

      expect(await DriftInventoryRepository(intruderDb).categories(), isEmpty);
    });
  });

  group('shared stock wiring (Maggi Packet + dish mappings)', () {
    Future<Product> packetOf(DriftInventoryRepository repo) async =>
        (await repo.products()).firstWhere((p) => p.name == 'Maggi Packet');

    Future<void> stockPacket(
      DriftInventoryRepository repo,
      int quantity,
    ) async {
      final packet = await packetOf(repo);
      await DriftStockMovementRepository(db).adjustStock(
        productId: packet.id,
        delta: quantity,
        reason: StockAdjustmentReason.purchase,
      );
    }

    test('ensures a tracked hidden packet with zero stock, once', () async {
      final repo = plainRepo();
      final result = await JiggarMenuSeeder(repo).run();

      expect(result.ingredientsEnsured, 1);
      final packet = await packetOf(repo);
      expect(packet.isIngredient, isTrue);
      expect(packet.stockUnit, StockUnit.count);
      expect(packet.stockQuantity, 0);
      expect(packet.isActive, isTrue);
      // Alert-eligible through the normal low-stock rules.
      expect(packet.lowStockMode, LowStockMode.useDefault);

      // Hidden from the sale shelf like every other ingredient.
      final shelf = (await repo.products()).where((p) => !p.isIngredient);
      expect(shelf.map((p) => p.id), isNot(contains(packet.id)));

      final second = await JiggarMenuSeeder(repo).run();
      expect(second.ingredientsEnsured, 0);
      expect(
        (await repo.products()).where((p) => p.name == 'Maggi Packet'),
        hasLength(1),
      );
    });

    test('defers dish mappings while the packet is empty', () async {
      final repo = plainRepo();
      final result = await JiggarMenuSeeder(repo).run();

      // The three board dishes exist but stay unwired: mapping them to an
      // empty source would reject every Maggi sale.
      expect(result.recipesMapped, 0);
      expect(result.recipesSkipped, 3);
      for (final name in ['Classic Maggie', 'Egg Maggie', 'Cheese Maggie']) {
        final dish = (await repo.products()).firstWhere((p) => p.name == name);
        expect(await repo.recipesForProduct(dish.id), isEmpty);
      }
    });

    test(
      'wires the board dishes on re-run after stocking, then sells shared',
      () async {
        final repo = plainRepo();
        await JiggarMenuSeeder(repo).run();
        await stockPacket(repo, 60);

        final second = await JiggarMenuSeeder(repo).run();
        expect(second.recipesMapped, 3);
        expect(second.recipesSkipped, 0);

        final packet = await packetOf(repo);
        for (final name in ['Classic Maggie', 'Egg Maggie', 'Cheese Maggie']) {
          final dish = (await repo.products()).firstWhere(
            (p) => p.name == name,
          );
          final rows = await repo.recipesForProduct(dish.id);
          expect(rows, hasLength(1));
          expect(rows.single.ingredientProductId, packet.id);
          expect(rows.single.quantity, 1);
          expect(rows.single.variantId, isNull);
        }

        final classic = (await repo.products()).firstWhere(
          (p) => p.name == 'Classic Maggie',
        );
        await DriftBillingRepository(db).completeSale(
          lines: [
            CartLine(
              productId: classic.id,
              productName: classic.name,
              unitPricePaise: classic.sellingPricePaise,
              quantity: 2,
              maxQuantity: 2,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );
        expect((await packetOf(repo)).stockQuantity, 58);
        expect(
          (await repo.products())
              .firstWhere((p) => p.name == 'Classic Maggie')
              .stockQuantity,
          0,
        );
      },
    );

    test(
      'maps live-menu spellings (Plain/Cheese/Veg/Egg/Masala Maggi) when present',
      () async {
        final repo = plainRepo();
        await JiggarMenuSeeder(repo).run();
        final maggie = (await repo.categories()).firstWhere(
          (c) => c.name == 'MAGGIE',
        );
        for (final name in ['Plain Maggi', 'Masala Maggi']) {
          await repo.createProduct(
            categoryId: maggie.id,
            name: name,
            sellingPricePaise: 6000,
            stockQuantity: 0,
            stockUnit: StockUnit.none,
            isActive: true,
          );
        }
        await stockPacket(repo, 10);

        final second = await JiggarMenuSeeder(repo).run();
        // 3 board dishes + 2 live spellings; the other three live names are
        // simply absent in this shop and skipped silently.
        expect(second.recipesMapped, 5);
        for (final name in ['Plain Maggi', 'Masala Maggi']) {
          final dish = (await repo.products()).firstWhere(
            (p) => p.name == name,
          );
          expect(await repo.recipesForProduct(dish.id), hasLength(1));
        }
      },
    );

    test('never reinterprets live rows or overwrites mappings', () async {
      final repo = plainRepo();
      final category = await repo.createCategory('MAGGIE');
      await repo.createProduct(
        categoryId: category.id,
        name: 'Maggi Packet',
        sellingPricePaise: 2000,
        stockQuantity: 10,
        isActive: true,
      );

      final result = await JiggarMenuSeeder(repo).run();
      expect(result.ingredientsEnsured, 0);
      expect(result.recipesMapped, 0);
      expect(result.recipesSkipped, 3);
      final packet = await packetOf(repo);
      expect(packet.isIngredient, isFalse);
      expect(packet.stockQuantity, 10);

      // An owner mapping survives later imports untouched.
      final classic = (await repo.products()).firstWhere(
        (p) => p.name == 'Classic Maggie',
      );
      await repo.setRecipe(
        productId: classic.id,
        ingredients: [
          RecipeIngredientInput(ingredientProductId: packet.id, quantity: 2),
        ],
      );
      final second = await JiggarMenuSeeder(repo).run();
      expect(second.recipesMapped, 0);
      final rows = await repo.recipesForProduct(classic.id);
      expect(rows.single.quantity, 2);
    });
  });

  group('NONE billing integration (menu items are sellable at zero stock)', () {
    test(
      'checkout sells a NONE product with zero stock; no movement rows',
      () async {
        final repo = DriftInventoryRepository(db);
        await JiggarMenuSeeder(repo).run();
        final products = await repo.products();
        final tea = products.firstWhere((p) => p.name == 'Black Tea');

        final billing = DriftBillingRepository(db);
        final completed = await billing.completeSale(
          lines: [
            CartLine(
              productId: tea.id,
              productName: tea.name,
              unitPricePaise: tea.sellingPricePaise,
              quantity: 2,
              maxQuantity: 2,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );

        expect(completed.sale.totalPaise, 2400);
        final movements = await (db.select(
          db.stockMovements,
        )..where((t) => t.productId.equals(tea.id))).get();
        expect(
          movements,
          isEmpty,
          reason: 'untracked products record no SALE movement',
        );
        final after = (await repo.products()).firstWhere(
          (p) => p.name == 'Black Tea',
        );
        expect(
          after.stockQuantity,
          0,
          reason: 'no artificial deduction on untracked items',
        );
      },
    );

    test('variant line of a NONE product bills at its own price', () async {
      final repo = DriftInventoryRepository(db);
      await JiggarMenuSeeder(repo).run();
      final products = await repo.products();
      final chai = products.firstWhere((p) => p.name == 'SPL Milk Chai');
      final big = chai.variants.firstWhere((v) => v.name == '160ml');

      final completed = await DriftBillingRepository(db).completeSale(
        lines: [
          CartLine(
            productId: chai.id,
            productName: chai.name,
            variantId: big.id,
            variantName: big.name,
            unitPricePaise: big.sellingPricePaise,
            quantity: 1,
            maxQuantity: 1,
          ),
        ],
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.upi,
      );
      expect(completed.sale.totalPaise, 2000);
    });

    test('tracked products still enforce stock (regression guard)', () async {
      final repo = DriftInventoryRepository(db);
      final category = await repo.createCategory('Packaged');
      final product = await repo.createProduct(
        categoryId: category.id,
        name: 'Bottled Water',
        sellingPricePaise: 2000,
        stockQuantity: 1,
        stockUnit: StockUnit.count,
        isActive: true,
      );
      final billing = DriftBillingRepository(db);

      // One unit sells fine and deducts.
      await billing.completeSale(
        lines: [
          CartLine(
            productId: product.id,
            productName: product.name,
            unitPricePaise: product.sellingPricePaise,
            quantity: 1,
            maxQuantity: 1,
          ),
        ],
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );
      final soldOut = (await repo.products()).firstWhere(
        (p) => p.id == product.id,
      );
      expect(soldOut.stockQuantity, 0);

      // Second sale is refused — tracked semantics unchanged.
      await expectLater(
        billing.completeSale(
          lines: [
            CartLine(
              productId: product.id,
              productName: product.name,
              unitPricePaise: product.sellingPricePaise,
              quantity: 1,
              maxQuantity: 1,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final movements = await (db.select(
        db.stockMovements,
      )..where((t) => t.productId.equals(product.id))).get();
      expect(
        movements.where((m) => m.movementType == 'SALE').map((m) => m.quantity),
        [-1],
      );
    });
  });
}
