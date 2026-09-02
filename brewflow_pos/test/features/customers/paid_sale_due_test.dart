import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BUG 4 — PAID sales must NOT create customer due; only NOT_PAID (credit)
/// sales do.
///
/// A PAID customer-linked sale is settled at the counter and must never bump
/// the customer's outstanding balance. Cover two customers (part of the
/// observed bug) and verify isolation, multiple paid sales, and paid+unpaid
/// mixing.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftCustomerLedgerRepository ledger;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    ledger = DriftCustomerLedgerRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> seedCustomer(String id) async {
    await database
        .into(database.customers)
        .insert(CustomersCompanion.insert(id: Value(id), name: 'Customer $id'));
    return id;
  }

  Future<String> seedSale({
    required String customerId,
    required int totalPaise,
    required PaymentStatus status,
    String? id,
  }) async {
    final saleId = id ?? 's-${const Uuid().v4()}';
    final now = DateTime.now().toUtc();
    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: Value(saleId),
            receiptNumber: 'BF-$saleId',
            customerId: Value(customerId),
            subtotalPaise: totalPaise,
            totalPaise: totalPaise,
            paymentStatus: Value(status.dbValue),
            paymentMethod: Value(
              status == PaymentStatus.notPaid ? null : 'CASH',
            ),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return saleId;
  }

  group('BUG 4 paid vs unpaid due', () {
    test('PAID sale leaves customer outstanding unchanged (zero)', () async {
      await seedCustomer('c1');
      await seedSale(
        customerId: 'c1',
        totalPaise: 24000,
        status: PaymentStatus.paid,
      );

      final summary = await ledger.summary('c1');
      expect(summary.outstandingPaise, 0);
      expect(summary.totalPurchasesPaise, 0);
      expect(await ledger.outstandingForCustomer('c1'), 0);
      expect(await ledger.customerIdsWithDue(), isEmpty);
      final due = await ledger.dueCustomersSummary();
      expect(due.dueCustomerCount, 0);
      expect(due.totalOutstandingPaise, 0);
    });

    test(
      'UNPAID sale increases customer outstanding by the full amount',
      () async {
        await seedCustomer('c1');
        await seedSale(
          customerId: 'c1',
          totalPaise: 24000,
          status: PaymentStatus.notPaid,
        );

        final summary = await ledger.summary('c1');
        expect(summary.outstandingPaise, 24000);
        expect(summary.totalPurchasesPaise, 24000);
        expect(await ledger.outstandingForCustomer('c1'), 24000);
        expect(await ledger.customerIdsWithDue(), ['c1']);
        final due = await ledger.dueCustomersSummary();
        expect(due.dueCustomerCount, 1);
        expect(due.totalOutstandingPaise, 24000);

        final purchases = await ledger.purchases('c1');
        expect(purchases.single.totalPaise, 24000);
        expect(purchases.single.duePaise, 24000);
        expect(purchases.single.status, SalePaymentStatus.unpaid);
      },
    );

    test('two customers stay isolated (paid vs unpaid)', () async {
      await seedCustomer('a');
      await seedCustomer('b');
      await seedSale(
        customerId: 'a',
        totalPaise: 10000,
        status: PaymentStatus.paid,
      );
      await seedSale(
        customerId: 'b',
        totalPaise: 30000,
        status: PaymentStatus.notPaid,
      );

      final a = await ledger.summary('a');
      final b = await ledger.summary('b');
      expect(a.outstandingPaise, 0, reason: 'A paid sale must not affect A');
      expect(b.outstandingPaise, 30000, reason: 'B owes only its credit sale');
      expect(await ledger.customerIdsWithDue(), ['b']);

      final due = await ledger.dueCustomersSummary();
      expect(due.dueCustomerCount, 1);
      expect(due.totalOutstandingPaise, 30000);
    });

    test('multiple PAID sales produce no incorrect due', () async {
      await seedCustomer('c1');
      for (var i = 0; i < 4; i++) {
        await seedSale(
          customerId: 'c1',
          totalPaise: 5000 * (i + 1),
          status: PaymentStatus.paid,
        );
      }

      final summary = await ledger.summary('c1');
      expect(summary.purchaseCount, 0);
      expect(summary.totalPurchasesPaise, 0);
      expect(summary.outstandingPaise, 0);
      expect(await ledger.customerIdsWithDue(), isEmpty);

      final purchases = await ledger.purchases('c1');
      expect(purchases, hasLength(4));
      expect(
        purchases.every((p) => p.status == SalePaymentStatus.paid),
        isTrue,
        reason: 'every paid sale must read as settled',
      );
      expect(
        purchases.every((p) => p.duePaise == 0),
        isTrue,
        reason: 'every paid sale must carry zero due',
      );
    });

    test('mixed paid + unpaid: only unpaid contributes to due', () async {
      await seedCustomer('c1');
      await seedSale(
        customerId: 'c1',
        totalPaise: 10000,
        status: PaymentStatus.paid,
      );
      await seedSale(
        customerId: 'c1',
        totalPaise: 20000,
        status: PaymentStatus.notPaid,
      );
      await seedSale(
        customerId: 'c1',
        totalPaise: 40000,
        status: PaymentStatus.paid,
      );

      final summary = await ledger.summary('c1');
      expect(
        summary.totalPurchasesPaise,
        20000,
        reason: 'only the credit sale',
      );
      expect(summary.outstandingPaise, 20000);

      final purchases = await ledger.purchases('c1');
      expect(purchases, hasLength(3));
      final unpaid = purchases.singleWhere((p) => p.totalPaise == 20000);
      expect(unpaid.status, SalePaymentStatus.unpaid);
      expect(unpaid.duePaise, 20000);
      for (final p in purchases.where((p) => p.totalPaise != 20000)) {
        expect(p.status, SalePaymentStatus.paid);
        expect(p.duePaise, 0);
      }
    });

    test(
      'UNPAID sale fully settled via payment flips to PAID and clears due',
      () async {
        await seedCustomer('c1');
        final saleId = await seedSale(
          customerId: 'c1',
          totalPaise: 24000,
          status: PaymentStatus.notPaid,
        );

        expect((await ledger.summary('c1')).outstandingPaise, 24000);

        await ledger.recordPayment(
          customerId: 'c1',
          saleId: saleId,
          amountPaise: 24000,
          paymentMethod: PaymentMethod.cash,
        );

        final sale = await (database.select(
          database.sales,
        )..where((t) => t.id.equals(saleId))).getSingle();
        expect(sale.paymentStatus, 'PAID');
        final summary = await ledger.summary('c1');
        expect(summary.outstandingPaise, 0, reason: 'settled bill has no due');
        expect(summary.totalPurchasesPaise, 0);
        expect(await ledger.customerIdsWithDue(), isEmpty);

        final purchases = await ledger.purchases('c1');
        expect(purchases.single.status, SalePaymentStatus.paid);
        expect(purchases.single.duePaise, 0);
      },
    );
  });

  group('BUG 4 sync preserves paid/due state', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late AppDatabase syncDb;
    late LocalMasterDataApplier applier;
    late DriftCustomerLedgerRepository syncLedger;

    setUp(() async {
      syncDb = AppDatabase(NativeDatabase.memory());
      // Seed the canonical single-shop row the synced sale's shop_id FK needs.
      await syncDb
          .into(syncDb.shops)
          .insert(
            ShopsCompanion.insert(
              id: const Value('shop-1'),
              name: 'BrewFlow POS',
            ),
          );
      applier = LocalMasterDataApplier(syncDb);
      syncLedger = DriftCustomerLedgerRepository(syncDb);
    });

    tearDown(() => syncDb.close());

    Future<void> seedCustomerOnSyncDb(String id) async {
      await syncDb
          .into(syncDb.customers)
          .insert(
            CustomersCompanion.insert(id: Value(id), name: 'Customer $id'),
          );
    }

    Future<void> applySyncedSale({
      required String id,
      required int totalPaise,
      required String paymentStatus,
    }) async {
      final now = DateTime.now().toUtc();
      // This is exactly what SyncEngine does for a pulled sale row.
      await applier.applySalePage([
        SyncSale(
          id: id,
          shopId: 'shop-1',
          receiptNumber: 'BF-$id',
          customerId: 'c1',
          subtotalPaise: totalPaise,
          totalPaise: totalPaise,
          paymentStatus: paymentStatus,
          paymentMethod: paymentStatus == 'NOT_PAID' ? null : 'CASH',
          createdAt: now,
        ),
      ], now);
    }

    test('PAID sale received via sync applier leaves due at zero', () async {
      await seedCustomerOnSyncDb('c1');
      await applySyncedSale(
        id: 's-paid',
        totalPaise: 24000,
        paymentStatus: 'PAID',
      );

      final row = await (syncDb.select(
        syncDb.sales,
      )..where((t) => t.id.equals('s-paid'))).getSingle();
      expect(row.paymentStatus, 'PAID', reason: 'sync persisted paid state');

      final summary = await syncLedger.summary('c1');
      expect(summary.outstandingPaise, 0, reason: 'paid sale adds no due');
      expect(summary.totalPurchasesPaise, 0);
      expect(await syncLedger.customerIdsWithDue(), isEmpty);
      final purchases = await syncLedger.purchases('c1');
      expect(purchases.single.status, SalePaymentStatus.paid);
      expect(purchases.single.duePaise, 0);
    });

    test('UNPAID sale received via sync applier creates due', () async {
      await seedCustomerOnSyncDb('c1');
      await applySyncedSale(
        id: 's-credit',
        totalPaise: 24000,
        paymentStatus: 'NOT_PAID',
      );

      final row = await (syncDb.select(
        syncDb.sales,
      )..where((t) => t.id.equals('s-credit'))).getSingle();
      expect(
        row.paymentStatus,
        'NOT_PAID',
        reason: 'sync persisted credit state',
      );

      final summary = await syncLedger.summary('c1');
      expect(
        summary.outstandingPaise,
        24000,
        reason: 'credit sale creates due',
      );
      expect(summary.totalPurchasesPaise, 24000);
      expect(await syncLedger.customerIdsWithDue(), ['c1']);
      final purchases = await syncLedger.purchases('c1');
      expect(purchases.single.status, SalePaymentStatus.unpaid);
      expect(purchases.single.duePaise, 24000);
    });
  });
}
