import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for FINAL E2E Failure 2:
/// `SqliteException(2067) UNIQUE constraint failed: sales.shop_id,
/// sales.receipt_number` aborted the sale pull page, so the sync cycle
/// re-pulled the same page every ~30s forever.
///
/// The cloud can legitimately hold the same (shop, receipt) under a DIFFERENT
/// uuid (multi-device offline sales, re-seeds). The incoming cloud row is
/// canonical (server last-writer-wins) and must retire the stale local
/// duplicate ONLY after repointing its history — never crash the cycle,
/// never orphan payments/movements, never delete a pending local write.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalMasterDataApplier applier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    applier = LocalMasterDataApplier(db);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: const Value('shop-a'), name: 'Cafe'));
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(id: const Value('shop-b'), name: 'Food Truck'),
        );
  });

  tearDown(() async => db.close());

  SyncSale cloudSale({
    required String id,
    required String shopId,
    required String receipt,
  }) => SyncSale(
    id: id,
    shopId: shopId,
    receiptNumber: receipt,
    subtotalPaise: 10000,
    totalPaise: 10000,
    paymentMethod: 'UPI',
    paymentStatus: 'PAID',
    createdAt: DateTime.utc(2026, 9, 1),
  );

  Future<void> seedProduct({required String id}) async {
    await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(id: Value(id), name: 'Cat $id'));
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: 'Product $id',
            sellingPricePaise: 10000,
            stockQuantity: const Value(10),
            isActive: const Value(true),
          ),
        );
  }

  Future<void> seedLocalSale({
    required String id,
    required String shopId,
    required String receipt,
  }) async {
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            receiptNumber: receipt,
            subtotalPaise: 10000,
            totalPaise: 10000,
            paymentMethod: const Value('UPI'),
            paymentStatus: const Value('PAID'),
            createdAt: Value(DateTime.utc(2026, 9, 1)),
          ),
        );
  }

  Future<void> seedLocalItem({
    required String id,
    required String saleId,
    required String productId,
  }) async {
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            id: Value(id),
            shopId: const Value('shop-a'),
            saleId: saleId,
            productId: productId,
            productName: 'Coffee',
            unitPricePaise: 10000,
            quantity: 1,
            lineTotalPaise: 10000,
          ),
        );
  }

  Future<List<Sale>> allSales() => db.select(db.sales).get();

  test(
    'same-shop same-receipt different id converges; canonical items land',
    () async {
      await seedProduct(id: 'p1');
      await seedLocalSale(
        id: 'local-sale',
        shopId: 'shop-a',
        receipt: 'BF-000001',
      );
      await seedLocalItem(
        id: 'local-item',
        saleId: 'local-sale',
        productId: 'p1',
      );

      // Before any fix this threw SqliteException 2067 and never advanced.
      await applier.applySalePage([
        cloudSale(id: 'cloud-sale', shopId: 'shop-a', receipt: 'BF-000001'),
      ], DateTime.utc(2026, 9, 12));
      // The canonical sale's own items arrive in a later page of the same pull.
      await applier.applySaleItemPage([
        SyncSaleItem(
          id: 'cloud-item',
          shopId: 'shop-a',
          saleId: 'cloud-sale',
          productId: 'p1',
          productName: 'Coffee',
          unitPricePaise: 10000,
          quantity: 1,
          lineTotalPaise: 10000,
        ),
      ], DateTime.utc(2026, 9, 12));

      final sales = await allSales();
      expect(sales.length, 1);
      expect(sales.single.id, 'cloud-sale');
      expect(sales.single.receiptNumber, 'BF-000001');

      final items = await db.select(db.saleItems).get();
      expect(items.length, 1);
      expect(items.single.id, 'cloud-item');
      expect(items.single.saleId, 'cloud-sale');
    },
  );

  test(
    'collision repoints payments and SALE stock movements to canonical',
    () async {
      await seedLocalSale(
        id: 'local-sale',
        shopId: 'shop-a',
        receipt: 'BF-000001',
      );
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: const Value('cust-1'),
              shopId: const Value('shop-a'),
              name: 'Naren',
            ),
          );
      await db
          .into(db.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: const Value('pay-1'),
              shopId: const Value('shop-a'),
              customerId: 'cust-1',
              saleId: const Value('local-sale'),
              amountPaise: 10000,
              paymentMethod: 'UPI',
              paidAt: DateTime.utc(2026, 9, 1),
            ),
          );
      await seedProduct(id: 'p1');
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: const Value('mov-1'),
              shopId: const Value('shop-a'),
              productId: 'p1',
              movementType: 'SALE',
              quantity: -1,
              stockBefore: 10,
              stockAfter: 9,
              referenceType: const Value('SALE'),
              referenceId: const Value('local-sale'),
              createdAt: Value(DateTime.utc(2026, 9, 1)),
            ),
          );

      await applier.applySalePage([
        cloudSale(id: 'cloud-sale', shopId: 'shop-a', receipt: 'BF-000001'),
      ], DateTime.utc(2026, 9, 12));

      final pay = await (db.select(
        db.customerPayments,
      )..where((t) => t.id.equals('pay-1'))).getSingle();
      expect(pay.saleId, 'cloud-sale');
      final mov = await (db.select(
        db.stockMovements,
      )..where((t) => t.id.equals('mov-1'))).getSingle();
      expect(mov.referenceId, 'cloud-sale');
      expect((await allSales()).single.id, 'cloud-sale');
    },
  );

  test(
    'pending local sale write defers convergence and never crashes',
    () async {
      await seedProduct(id: 'p1');
      await seedLocalSale(
        id: 'local-sale',
        shopId: 'shop-a',
        receipt: 'BF-000001',
      );
      await seedLocalItem(
        id: 'local-item',
        saleId: 'local-sale',
        productId: 'p1',
      );
      // The offline sale and its items are still queued for push: the pull must
      // defer, not delete and not throw. The next cycle reconciles after push.
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'dev-1',
              shopId: 'shop-a',
              entity: 'SALE',
              entityId: 'local-sale',
              payload: '{}',
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'dev-1',
              shopId: 'shop-a',
              entity: 'SALE_ITEM',
              entityId: 'local-item',
              payload: '{}',
            ),
          );

      await applier.applySalePage([
        cloudSale(id: 'cloud-sale', shopId: 'shop-a', receipt: 'BF-000001'),
      ], DateTime.utc(2026, 9, 12));

      final sales = await allSales();
      expect(sales.length, 1);
      expect(sales.single.id, 'local-sale');
    },
  );

  test('distinct receipts apply side by side', () async {
    await seedLocalSale(
      id: 'local-sale',
      shopId: 'shop-a',
      receipt: 'BF-000001',
    );
    await applier.applySalePage([
      cloudSale(id: 'cloud-sale', shopId: 'shop-a', receipt: 'BF-000002'),
    ], DateTime.utc(2026, 9, 12));
    expect((await allSales()).length, 2);
  });

  test('same receipt under the same id is an idempotent upsert', () async {
    await applier.applySalePage([
      cloudSale(id: 'c-1', shopId: 'shop-a', receipt: 'BF-000001'),
    ], DateTime.utc(2026, 9, 12));
    await applier.applySalePage([
      cloudSale(id: 'c-1', shopId: 'shop-a', receipt: 'BF-000001'),
    ], DateTime.utc(2026, 9, 12));
    expect((await allSales()).length, 1);
    expect((await allSales()).single.receiptNumber, 'BF-000001');
  });
}
