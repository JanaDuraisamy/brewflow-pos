import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Cloud bill fetching + customer-due consistency contract.
///
/// Supabase is the source of truth for cloud-backed bills and payments: a
/// device pulls every sale/sale_item/customer_payment row and derives its
/// customer ledger from exactly the rows it holds. These tests lock the
/// shipping symptom — bills present in the cloud but missing locally, and
/// mismatched customer dues — by proving the incremental engine fetches and
/// applies cloud-backed bill/payment rows and that the ledger derives from
/// them the same dues any device would compute.
/// ---------------------------------------------------------------------------

void main() {
  const shopA = 'shop-a';

  Future<({AppDatabase db, DriftSyncRepository sync, SyncEngine engine})>
  device(FakeRemoteStore cloud, {required String deviceId}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: const Value(shopA), name: shopA));
    final sync = DriftSyncRepository(db);
    final engine = SyncEngine(
      sync,
      FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA),
      LocalMasterDataApplier(db),
    );
    return (db: db, sync: sync, engine: engine);
  }

  Future<void> cycle(SyncEngine engine, {String deviceId = 'B'}) =>
      engine.runCycle(deviceId: deviceId, shopId: shopA);

  group('cloud bill fetching', () {
    test(
      'a fresh device fetches and applies cloud bills with their items',
      () async {
        final cloud = FakeRemoteStore();
        final b = await device(cloud, deviceId: 'B');

        final billTime = DateTime.utc(2026, 10, 5, 9, 30);
        cloud.customers['cust-bill'] = StoredRow(
          SyncCustomer(
            id: 'cust-bill',
            shopId: shopA,
            name: 'Bill Customer',
            isActive: true,
            membershipActive: false,
            whatsappStatus: 'UNKNOWN',
            createdAt: billTime,
          ),
          shopA,
          billTime,
        );
        cloud.sales['sale-bill'] = StoredRow(
          SyncSale(
            id: 'sale-bill',
            shopId: shopA,
            customerId: 'cust-bill',
            receiptNumber: 'B-1001',
            subtotalPaise: 4500,
            totalPaise: 4500,
            paymentMethod: 'CASH',
            paymentStatus: 'PAID',
            createdAt: billTime,
          ),
          shopA,
          billTime,
        );
        cloud.saleItems['item-1'] = StoredRow(
          SyncSaleItem(
            id: 'item-1',
            shopId: shopA,
            saleId: 'sale-bill',
            productId: 'prod-1',
            productName: 'Filter Coffee',
            unitPricePaise: 4500,
            quantity: 1,
            lineTotalPaise: 4500,
          ),
          shopA,
          billTime.add(const Duration(milliseconds: 1)),
        );

        await cycle(b.engine);

        final sales = await b.db.select(b.db.sales).get();
        expect(sales.map((s) => s.id), ['sale-bill']);
        expect(sales.single.totalPaise, 4500);
        expect(sales.single.paymentStatus, 'PAID');
        expect(sales.single.customerId, 'cust-bill');
        final items = await b.db.select(b.db.saleItems).get();
        expect(items.map((i) => i.id), ['item-1']);
        expect(items.single.lineTotalPaise, 4500);
        final customers = await b.db.select(b.db.customers).get();
        expect(customers.map((c) => c.id), ['cust-bill']);

        // The cursor advanced to the newest fetched row: a second cycle is an
        // incremental no-op, not a repeated full re-pull (no stale cursor).
        final pulledAt = (await b.sync.stateFor('B'))!.lastPulledAt!;
        expect(pulledAt.isAfter(SyncEngine.initialCursor), isTrue);
        await cycle(b.engine);
        expect((await b.db.select(b.db.sales).get()).single.id, 'sale-bill');
        expect(cloud.sales.length, 1);
        expect(pulledAt, (await b.sync.stateFor('B'))!.lastPulledAt);
      },
    );

    test(
      'a cloud bill updates on every device via the shared cursor',
      () async {
        final cloud = FakeRemoteStore();
        final a = await device(cloud, deviceId: 'A');
        final b = await device(cloud, deviceId: 'B');

        final billTime = DateTime.utc(2026, 10, 6, 12);
        cloud.sales['sale-edit'] = StoredRow(
          SyncSale(
            id: 'sale-edit',
            shopId: shopA,
            receiptNumber: 'B-2001',
            subtotalPaise: 2000,
            totalPaise: 2000,
            paymentStatus: 'NOT_PAID',
            createdAt: billTime,
          ),
          shopA,
          billTime,
        );
        await cycle(b.engine, deviceId: 'B');

        // The authority (device A) corrects the bill; a later cycle on B must
        // converge to the cloud state.
        final newTime = billTime.add(const Duration(hours: 1));
        cloud.sales['sale-edit'] = StoredRow(
          SyncSale(
            id: 'sale-edit',
            shopId: shopA,
            receiptNumber: 'B-2001',
            subtotalPaise: 2500,
            totalPaise: 2500,
            paymentMethod: 'UPI',
            paymentStatus: 'PAID',
            createdAt: billTime,
          ),
          shopA,
          newTime,
        );
        await cycle(a.engine, deviceId: 'A');
        await cycle(b.engine, deviceId: 'B');

        final applied = await b.db.select(b.db.sales).getSingle();
        expect(applied.totalPaise, 2500);
        expect(applied.paymentMethod, 'UPI');
        expect(applied.paymentStatus, 'PAID');
      },
    );
  });

  group('customer dues consistency', () {
    test('dues derive from the pulled cloud bill and payment rows', () async {
      final cloud = FakeRemoteStore();
      final b = await device(cloud, deviceId: 'B');
      final ledger = DriftCustomerLedgerRepository(b.db);

      cloud.customers['cust-1'] = StoredRow(
        SyncCustomer(
          id: 'cust-1',
          shopId: shopA,
          name: 'Dinesh',
          isActive: true,
          membershipActive: false,
          whatsappStatus: 'UNKNOWN',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
        shopA,
        DateTime.utc(2026, 10, 1),
      );
      final saleTime = DateTime.utc(2026, 10, 5);
      cloud.sales['sale-credit'] = StoredRow(
        SyncSale(
          id: 'sale-credit',
          shopId: shopA,
          customerId: 'cust-1',
          receiptNumber: 'R-credit',
          subtotalPaise: 5000,
          totalPaise: 5000,
          paymentStatus: 'NOT_PAID',
          createdAt: saleTime,
        ),
        shopA,
        saleTime,
      );
      final payTime = saleTime.add(const Duration(days: 1));
      cloud.customerPayments['pay-1'] = StoredRow(
        SyncCustomerPayment(
          id: 'pay-1',
          shopId: shopA,
          customerId: 'cust-1',
          saleId: 'sale-credit',
          amountPaise: 2000,
          paymentMethod: 'CASH',
          paidAt: payTime,
          reversed: false,
          createdAt: payTime,
        ),
        shopA,
        payTime,
      );

      await cycle(b.engine);

      final summary = await ledger.summary('cust-1');
      expect(summary.totalPurchasesPaise, 5000);
      expect(summary.totalPaidPaise, 2000);
      expect(summary.outstandingPaise, 3000);
      expect(summary.purchaseCount, 1);
      expect(summary.paymentCount, 1);
    });
  });
}
