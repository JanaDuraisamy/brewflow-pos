import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// Regression tests for the missing-parent sale-item sync defect.
///
/// A pulled sale_item whose parent SALE row is not yet applied locally used
/// to abort the entire page with `SqliteException(787) FOREIGN KEY constraint
/// failed` (RESTRICT FK), which left the cycle marked "incomplete" forever (a
/// fresh-bootstrap device retried the same orphan every 30s and never
/// converged). The fix DEFERS such orphans inside [LocalMasterDataApplier]:
/// the page still commits, valid siblings still apply, and the deferred row
/// converges once its parent sale lands in a later cycle.
///
/// Scenarios:
///  - direct applier contract (real in-memory Drift DB),
///  - full engine cycle against the RLS-modeled fake cloud mirror.
/// ---------------------------------------------------------------------------

final DateTime day0 = DateTime.utc(2026, 1, 1);
final DateTime day1 = DateTime.utc(2026, 1, 2);

SyncSale sale(String id, String shopId, String receipt) => SyncSale(
  id: id,
  shopId: shopId,
  receiptNumber: receipt,
  subtotalPaise: 6500,
  totalPaise: 6500,
  paymentMethod: 'CASH',
  paymentStatus: 'PAID',
  createdAt: day0,
);

SyncSaleItem item({
  required String id,
  required String shopId,
  required String saleId,
  String productId = 'p-1',
  String productName = 'Allpanso Mango',
  int quantity = 1,
}) => SyncSaleItem(
  id: id,
  shopId: shopId,
  saleId: saleId,
  productId: productId,
  productName: productName,
  unitPricePaise: 6500,
  quantity: quantity,
  lineTotalPaise: 6500 * quantity,
);

SyncShop shop(String id, String name) =>
    SyncShop(id: id, shopId: id, name: name, createdAt: day0);

SyncCategory category(String id, String name) => SyncCategory(
  id: id,
  shopId: 'shop-1',
  name: name,
  isActive: true,
  createdAt: day0,
);

SyncProduct product(String id) => SyncProduct(
  id: id,
  shopId: 'shop-1',
  categoryId: 'cat-1',
  name: 'Allpanso Mango',
  sellingPricePaise: 6500,
  stockQuantity: 5,
  stockUnit: SyncStockUnit.none,
  lowStockMode: SyncLowStockMode.useDefault,
  membershipEnabled: false,
  isActive: true,
  createdAt: day0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('applySaleItemPage missing-parent guard', () {
    late AppDatabase database;
    late LocalMasterDataApplier applier;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      applier = LocalMasterDataApplier(database);
      addTearDown(database.close);
      // Catalog parents: shop + category + product (sale_items.product_id is
      // a RESTRICT FK too, mirroring the real pull order products → items).
      await applier.applyShopPage([shop('shop-1', 'My Shop')], day0);
      await applier.applyCategoryPage([category('cat-1', 'Beverages')], day0);
      await applier.applyProductPage([product('p-1')], day0);
    });

    test(
      'missing parent defers the orphan and applies valid siblings',
      () async {
        await applier.applySalePage([sale('s-valid', 'shop-1', 'BF-2')], day1);

        // i-orphan has NO local/remote parent sale; i-valid has one. The page
        // must apply i-valid and leave i-orphan untouched — no FK exception.
        await applier.applySaleItemPage([
          item(id: 'i-orphan', shopId: 'shop-1', saleId: 's-missing'),
          item(id: 'i-valid', shopId: 'shop-1', saleId: 's-valid'),
        ], day1);

        final items = await (database.select(database.saleItems)).get();
        expect(items.map((r) => r.id), ['i-valid']);
        expect(items.single.saleId, 's-valid');
        expect(items.single.productId, 'p-1');
        // No residue for the orphan and no stray sales rows.
        final localSales = await (database.select(database.sales)).get();
        expect(localSales.map((s) => s.id), ['s-valid']);
      },
    );

    test('deferred sale_item converges once the parent sale arrives', () async {
      await applier.applySaleItemPage([
        item(id: 'i-orphan', shopId: 'shop-1', saleId: 's-later'),
      ], day0);
      expect(await (database.select(database.saleItems)).get(), isEmpty);

      // Parent arrives in a later pull.
      await applier.applySalePage([sale('s-later', 'shop-1', 'BF-9')], day1);

      // Same row re-presented (later cycle) → converges normally.
      await applier.applySaleItemPage([
        item(id: 'i-orphan', shopId: 'shop-1', saleId: 's-later'),
      ], day1);

      final rows = await (database.select(database.saleItems)).get();
      expect(rows.single.id, 'i-orphan');
      expect(rows.single.saleId, 's-later');
      expect(rows.single.quantity, 1);
      expect(rows.single.unitPricePaise, 6500);
      expect(rows.single.lineTotalPaise, 6500);
    });

    test('valid parent preserves same-id update on replay', () async {
      await applier.applySalePage([sale('s-valid', 'shop-1', 'BF-2')], day0);
      await applier.applySaleItemPage([
        item(id: 'i-a', shopId: 'shop-1', saleId: 's-valid'),
      ], day0);

      // Idempotent replay of the SAME id with a new quantity updates in
      // place — exactly one row, snapshot fields refreshed.
      await applier.applySaleItemPage([
        item(id: 'i-a', shopId: 'shop-1', saleId: 's-valid', quantity: 3),
      ], day1);

      final rows = await (database.select(database.saleItems)).get();
      expect(rows.length, 1);
      expect(rows.single.id, 'i-a');
      expect(rows.single.quantity, 3);
      expect(rows.single.lineTotalPaise, 6500 * 3);
    });
  });

  group('sync engine tolerates an un-pulled parent sale', () {
    Future<(SyncEngine, AppDatabase)> makeEngine(
      String deviceId,
      FakeRemoteStore cloud,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      await database
          .into(database.shops)
          .insert(
            ShopsCompanion.insert(
              id: const Value('shop-1'),
              name: 'BrewFlow POS',
              createdAt: Value(day0),
            ),
          );
      final syncRepo = DriftSyncRepository(database);
      final gateway = FakeRemoteMasterDataGateway(
        cloud,
        viewerShopId: 'shop-1',
      );
      return (
        SyncEngine(syncRepo, gateway, LocalMasterDataApplier(database)),
        database,
      );
    }

    void seedCloudWithOrphan(FakeRemoteStore cloud) {
      cloud.shops['shop-1'] = StoredRow(
        shop('shop-1', 'My Shop'),
        'shop-1',
        day0,
      );
      cloud.categories['cat-1'] = StoredRow(
        category('cat-1', 'Beverages'),
        'shop-1',
        day0,
      );
      cloud.products['p-1'] = StoredRow(product('p-1'), 'shop-1', day0);
      cloud.sales['s-valid'] = StoredRow(
        sale('s-valid', 'shop-1', 'BF-2'),
        'shop-1',
        day0,
      );
      cloud.saleItems['i-valid'] = StoredRow(
        item(id: 'i-valid', shopId: 'shop-1', saleId: 's-valid'),
        'shop-1',
        day0,
      );
      // The orphan: its item lives under the viewer shop, but its parent sale
      // is a foreign-shop row that shop-1's RLS-modeled pull never returns.
      cloud.sales['s-orphan'] = StoredRow(
        sale('s-orphan', 'shop-2', 'BF-9'),
        'shop-2',
        day1,
      );
      cloud.saleItems['i-orphan'] = StoredRow(
        item(id: 'i-orphan', shopId: 'shop-1', saleId: 's-orphan'),
        'shop-1',
        day1,
      );
    }

    test('cycle continues; orphan deferred, valid sibling applied', () async {
      final cloud = FakeRemoteStore();
      seedCloudWithOrphan(cloud);

      final (engine, database) = await makeEngine('A', cloud);
      addTearDown(database.close);

      // Must NOT throw an FK exception; the cycle completes.
      await engine.runCycle(deviceId: 'A', shopId: 'shop-1');

      final items = await (database.select(database.saleItems)).get();
      expect(
        items.map((r) => r.id),
        ['i-valid'],
        reason: 'valid item lands while the orphan is deferred',
      );
      final sales = await (database.select(database.sales)).get();
      expect(sales.map((s) => s.id), ['s-valid']);
    });

    test(
      'repaired cloud converges the deferred item on a later bootstrap',
      () async {
        final cloud = FakeRemoteStore();
        seedCloudWithOrphan(cloud);

        final (engineA, databaseA) = await makeEngine('A', cloud);
        addTearDown(databaseA.close);
        await engineA.runCycle(deviceId: 'A', shopId: 'shop-1');
        expect(
          (await databaseA.select(databaseA.saleItems).get()).map((r) => r.id),
          ['i-valid'],
        );

        // Cloud repaired: the sale genuinely belongs to shop-1 now.
        cloud.sales['s-orphan'] = StoredRow(
          sale('s-orphan', 'shop-1', 'BF-9'),
          'shop-1',
          day1,
        );

        // A brand-new device bootstraps the fixed cloud and converges BOTH the
        // sales row and the previously-deferred item.
        final (engineB, databaseB) = await makeEngine('B', cloud);
        addTearDown(databaseB.close);
        await engineB.runCycle(deviceId: 'B', shopId: 'shop-1');

        final bSales = await (databaseB.select(databaseB.sales)).get();
        expect(bSales.map((s) => s.id).toSet(), {'s-valid', 's-orphan'});
        final bItems = await (databaseB.select(databaseB.saleItems)).get();
        expect(bItems.map((r) => r.id).toSet(), {'i-valid', 'i-orphan'});
        final converged = bItems.singleWhere((r) => r.id == 'i-orphan');
        expect(converged.saleId, 's-orphan');
        expect(converged.quantity, 1);
      },
    );
  });
}
