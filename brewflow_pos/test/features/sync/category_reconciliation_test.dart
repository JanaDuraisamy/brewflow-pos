import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// Phase 7.4 — Master-data collision reconciliation tests.
///
/// Verifies that duplicate categories created independently on two devices
/// under the SAME shop deterministically converge to the cloud's canonical
/// id, that products/variants are repointed, sales untouched, FIFO unblocked,
/// cross-shop isolation holds, and repeated syncs stay idempotent.
/// ---------------------------------------------------------------------------

final class Device {
  Device._({
    required this.id,
    required this.shopId,
    required this.database,
    required this.sync,
    required this.gateway,
    required this.coordinator,
    required this.engine,
    required this.inventory,
  });

  final String id;
  final String shopId;
  final AppDatabase database;
  final DriftSyncRepository sync;
  final FakeRemoteMasterDataGateway gateway;
  final SyncOutboxCoordinator coordinator;
  final SyncEngine engine;
  final DriftInventoryRepository inventory;

  Future<void> runCycle() => engine.runCycle(deviceId: id, shopId: shopId);
  Future<int> pending() => sync.pendingOutboxCount();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRemoteStore cloud;

  Device makeDevice(String id, String shopId) {
    final database = AppDatabase(NativeDatabase.memory());
    final sync = DriftSyncRepository(database);
    final gateway = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopId);
    Future<SyncSessionContext> ctx() async =>
        SyncSessionContext(deviceId: id, shopId: shopId, userId: 'u-$id');
    final coordinator = SyncOutboxCoordinator(sync, ctx);
    final engine = SyncEngine(sync, gateway, LocalMasterDataApplier(database));
    return Device._(
      id: id,
      shopId: shopId,
      database: database,
      sync: sync,
      gateway: gateway,
      coordinator: coordinator,
      engine: engine,
      inventory: DriftInventoryRepository(
        database,
        outboxCoordinator: coordinator,
      ),
    );
  }

  setUp(() {
    cloud = FakeRemoteStore();
  });

  group('category reconciliation', () {
    test(
      'same shop + same name + different UUID → deterministic convergence',
      () async {
        final a = makeDevice('A', 'shop-1');
        final b = makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        // A creates MILK & CHAI first and syncs it to cloud — it becomes canonical.
        final catA = await a.inventory.createCategory('MILK & CHAI');
        await a.runCycle();
        expect(cloud.categories.length, 1);
        final canonicalId = cloud.categories.values.single.row.id;
        expect(canonicalId, catA.id);

        // B independently creates the SAME logical category with a different UUID.
        final catB = await b.inventory.createCategory('MILK & CHAI');
        expect(catB.id, isNot(canonicalId));

        // B also creates a product under its own (soon-to-be-duplicate) category.
        final productB = await b.inventory.createProduct(
          categoryId: catB.id,
          name: 'Plain Milk',
          sellingPricePaise: 5000,
          stockQuantity: 0,
          isActive: true,
        );
        expect(productB.categoryId, catB.id);

        // B's next cycle must reconcile before pushing: the duplicate category
        // is retired, the product is repointed, and the queue does not block.
        await b.runCycle();

        // Cloud still has exactly one MILK & CHAI (no duplicate row).
        expect(cloud.categories.length, 1);
        expect(cloud.categories.values.single.row.name, 'MILK & CHAI');
        expect(cloud.categories.values.single.row.id, canonicalId);

        // B's local category was remapped to the canonical id.
        final bCats = await b.inventory.categories();
        expect(bCats.length, 1);
        expect(bCats.single.id, canonicalId);
        expect(bCats.single.name, 'MILK & CHAI');

        // B's product now references the canonical category.
        final bProducts = await b.inventory.products();
        expect(bProducts.single.categoryId, canonicalId);

        // Both devices' pending queues drained — FIFO was not blocked.
        expect(await a.pending(), 0);
        expect(await b.pending(), 0);

        // Cloud received B's product under the canonical category.
        expect(cloud.products.length, 1);
        expect(cloud.products.values.single.row.categoryId, canonicalId);
      },
    );

    test('same shop + different names → both remain', () async {
      final a = makeDevice('A', 'shop-1');
      addTearDown(a.database.close);

      await a.inventory.createCategory('COFFEE');
      await a.inventory.createCategory('TEA');
      await a.runCycle();

      expect(cloud.categories.length, 2);
      final names = cloud.categories.values.map((s) => s.row.name).toSet();
      expect(names, {'COFFEE', 'TEA'});
    });

    test('different shops + same name → isolated (no remap)', () async {
      final a = makeDevice('A', 'shop-1');
      final intruder = makeDevice('EVIL', 'shop-2');
      addTearDown(a.database.close);
      addTearDown(intruder.database.close);

      await a.inventory.createCategory('MILK & CHAI');
      await a.runCycle();
      expect(cloud.categories.length, 1);

      await intruder.inventory.createCategory('MILK & CHAI');
      await intruder.runCycle();

      // Two shops → two distinct cloud rows with same name but different shop_id.
      expect(cloud.categories.length, 2);
      final shopIds = cloud.categories.values.map((s) => s.shopId).toSet();
      expect(shopIds, {'shop-1', 'shop-2'});

      // Each device still sees only its own shop's category (RLS).
      expect((await a.inventory.categories()).length, 1);
      expect((await intruder.inventory.categories()).length, 1);
    });

    test('repeated sync → idempotent (no duplicate)', () async {
      final a = makeDevice('A', 'shop-1');
      final b = makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final catA = await a.inventory.createCategory('MAGGIE');
      await a.runCycle();
      final catB = await b.inventory.createCategory('MAGGIE');
      await b.runCycle(); // first reconciliation

      final countAfterFirst = cloud.categories.length;
      await b.runCycle(); // second reconciliation — should be no-op
      await b.runCycle();
      expect(cloud.categories.length, countAfterFirst);

      // Local B still has exactly one MAGGIE, canonical.
      final bCats = await b.inventory.categories();
      expect(bCats.where((c) => c.name == 'MAGGIE').length, 1);
      expect(bCats.single.id, catA.id);
      // The duplicate B id is gone
      expect(bCats.any((c) => c.id == catB.id), isFalse);
    });

    test(
      'product variants remain attached to correct canonical product',
      () async {
        final a = makeDevice('A', 'shop-1');
        final b = makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        // A is canonical for category TEA
        final catA = await a.inventory.createCategory('TEA');
        await a.runCycle();
        // B creates same category with different id + a product with variants under it
        final catB = await b.inventory.createCategory('TEA');
        final productB = await b.inventory.createProduct(
          categoryId: catB.id,
          name: 'Chai Latte',
          sellingPricePaise: 12000,
          stockQuantity: 0,
          variants: [
            ProductVariantInput(
              name: '250ml',
              sellingPricePaise: 10000,
              stockQuantity: 5,
            ),
            ProductVariantInput(
              name: '400ml',
              sellingPricePaise: 15000,
              stockQuantity: 3,
            ),
          ],
          isActive: true,
        );
        await b.runCycle();

        // Product should be on cloud under canonical category, variants intact
        expect(cloud.products.length, 1);
        final cloudProduct = cloud.products.values.single.row;
        expect(cloudProduct.categoryId, catA.id);
        // The product id itself is preserved (products are not deduped by name)
        expect(cloudProduct.id, productB.id);

        final bProducts = await b.inventory.products();
        expect(bProducts.single.variants.length, 2);
        expect(bProducts.single.categoryId, catA.id);
        expect(cloud.productVariants.length, 2);
      },
    );

    test('existing sales are not modified by category reconciliation', () async {
      final a = makeDevice('A', 'shop-1');
      final b = makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      // Create and sync a category, then create a sale on B before merge
      final catA = await a.inventory.createCategory('FRIES');
      await a.runCycle();
      expect(cloud.categories.values.single.row.id, catA.id);
      final catB = await b.inventory.createCategory('FRIES');
      // B creates a product and a sale referencing it (sale history must survive)
      final product = await b.inventory.createProduct(
        categoryId: catB.id,
        name: 'Classic Fries',
        sellingPricePaise: 5000,
        stockQuantity: 10,
        isActive: true,
      );
      expect(product.categoryId, catB.id);
      // Simulate a sale by directly inserting a sale row (outbox not needed for this test;
      // we just verify the sale table is untouched by reconciliation).
      // Use the database directly to insert a sale.
      await b.database
          .into(b.database.sales)
          .insert(
            SalesCompanion.insert(
              receiptNumber: 'BILL-1',
              subtotalPaise: 5000,
              totalPaise: 5000,
              customerId: const Value.absent(),
            ),
          );
      final salesBefore = await b.database.select(b.database.sales).get();
      expect(salesBefore.length, 1);

      await b.runCycle();

      final salesAfter = await b.database.select(b.database.sales).get();
      expect(salesAfter.length, 1);
      expect(salesAfter.single.receiptNumber, 'BILL-1');
      // Category was remapped but sale untouched
      expect(salesAfter.single.id, salesBefore.single.id);
    });

    test(
      'customer/expense data untouched by category reconciliation',
      () async {
        final a = makeDevice('A', 'shop-1');
        final b = makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        // Seed customers/expenses on B
        await b.database
            .into(b.database.customers)
            .insert(CustomersCompanion.insert(name: 'RIN'));
        await b.database
            .into(b.database.expenses)
            .insert(
              ExpensesCompanion.insert(
                name: 'Rent',
                amountPaise: 50000,
                category: 'RENT',
                paymentMethod: 'CASH',
                expenseDate: DateTime.utc(2026, 1, 1),
              ),
            );
        final customersBefore = await b.database
            .select(b.database.customers)
            .get();
        final expensesBefore = await b.database
            .select(b.database.expenses)
            .get();

        final catA = await a.inventory.createCategory('JIGARTHANDA');
        await a.runCycle();
        expect(cloud.categories.values.single.row.id, catA.id);
        await b.inventory.createCategory('JIGARTHANDA');
        await b.runCycle();

        final customersAfter = await b.database
            .select(b.database.customers)
            .get();
        final expensesAfter = await b.database
            .select(b.database.expenses)
            .get();
        expect(customersAfter.length, customersBefore.length);
        expect(expensesAfter.length, expensesBefore.length);
        expect(customersAfter.single.name, 'RIN');
      },
    );

    test('FIFO queue no longer blocked by known duplicate', () async {
      final a = makeDevice('A', 'shop-1');
      final b = makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      // A is canonical for 8 categories
      for (final name in [
        'MILK & CHAI',
        'TEA',
        'COFFEE',
        'MAGGIE',
        'FRIES',
        'JIGARTHANDA',
        'DUET KULFI (NATURAL)',
        'POPSICLES (NATURAL)',
      ]) {
        await a.inventory.createCategory(name);
      }
      await a.runCycle();
      expect(cloud.categories.length, 8);

      // B creates the same 8 with different ids + one unique + products pending behind them
      for (final name in [
        'MILK & CHAI',
        'TEA',
        'COFFEE',
        'MAGGIE',
        'FRIES',
        'JIGARTHANDA',
        'DUET KULFI (NATURAL)',
        'POPSICLES (NATURAL)',
      ]) {
        await b.inventory.createCategory(name);
      }
      await b.inventory.createCategory('SYNC_CAT_UNIQUE');
      // Queue: 9 categories pending, head is duplicate MILK & CHAI
      expect(await b.pending(), 9);

      await b.runCycle();

      // After reconciliation, the 8 duplicates are retired (DONE) and the unique remains
      // — the queue drained, cloud has 9 total (8 canonical + 1 unique).
      expect(cloud.categories.length, 9);
      expect(await b.pending(), 0);
    });
  });
}
