import 'dart:convert';

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// PHASE 7.4K — transaction sync outbox tests.
///
/// Verifies that billing, customer-payment, and expense writes correctly
/// enqueue their outbox entries through the SyncOutboxCoordinator, with
/// correct wire-model payloads, atomicity, fast-sync trigger, and
/// duplicate protection.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late DriftSyncRepository sync;
  late SyncOutboxCoordinator coordinator;
  late DriftBillingRepository billing;
  late DriftCustomerLedgerRepository ledger;
  late DriftExpensesRepository expenses;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sync = DriftSyncRepository(db);
    coordinator = SyncOutboxCoordinator(
      sync,
      () async => const SyncSessionContext(
        deviceId: 'test-device',
        shopId: 'shop-test',
        userId: 'user-test',
      ),
    );
    billing = DriftBillingRepository(db, outboxCoordinator: coordinator);
    ledger = DriftCustomerLedgerRepository(db, outboxCoordinator: coordinator);
    expenses = DriftExpensesRepository(db, outboxCoordinator: coordinator);
  });

  tearDown(() => db.close());

  // ---- helpers -----------------------------------------------------------

  Future<void> seedProduct({
    required String id,
    required String name,
    int stock = 10,
    int pricePaise = 12000,
  }) async {
    await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(id: Value(id), name: 'Cat $id'));
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sellingPricePaise: pricePaise,
            stockQuantity: Value(stock),
          ),
        );
  }

  Future<void> seedCustomer(String id) async {
    await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(id: Value(id), name: 'Customer $id'));
  }

  Future<String> seedSale({
    required String id,
    required String customerId,
    required int totalPaise,
    String paymentStatus = 'NOT_PAID',
  }) async {
    final now = DateTime.now().toUtc();
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: Value(id),
            receiptNumber: 'BF-TEST',
            customerId: Value(customerId),
            subtotalPaise: totalPaise,
            totalPaise: totalPaise,
            paymentStatus: Value(paymentStatus),
            paymentMethod: Value('CASH'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// Query all PENDING outbox entries for a given entity type and return
  /// decoded payloads.
  Future<List<({SyncOutboxEntry entry, Map<String, dynamic> payload})>>
  outboxPayloads(String entityWire) async {
    final rows =
        await (db.select(db.syncOutbox)
              ..where(
                (t) => t.entity.equals(entityWire) & t.status.equals('PENDING'),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return [
      for (final r in rows)
        (
          entry: SyncOutboxEntry(
            id: r.id,
            deviceId: r.deviceId,
            shopId: r.shopId,
            entity: r.entity,
            entityId: r.entityId,
            operation: r.operation,
            payload: r.payload,
            status: r.status,
            attemptCount: r.attemptCount,
          ),
          payload: jsonDecode(r.payload) as Map<String, dynamic>,
        ),
    ];
  }

  // ========================================================================
  // TEST 1 — SALE outbox
  // ========================================================================
  group('TEST 1 — Sale outbox', () {
    test('completeSale enqueues SyncSale with correct fields', () async {
      await seedProduct(id: 'p1', name: 'Coffee', stock: 5);
      final completed = await billing.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Coffee',
            unitPricePaise: 12000,
            quantity: 2,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      final results = await outboxPayloads('SALE');
      expect(results, hasLength(1));

      final r = results.first;
      expect(r.entry.entity, 'SALE');
      expect(r.entry.entityId, completed.sale.id);
      expect(r.entry.operation, 'UPSERT');
      expect(r.entry.status, 'PENDING');

      expect(r.payload['id'], completed.sale.id);
      expect(r.payload['shopId'], 'shop-test');
      expect(r.payload['receiptNumber'], completed.sale.receiptNumber);
      expect(r.payload['subtotalPaise'], completed.sale.subtotalPaise);
      expect(r.payload['totalPaise'], completed.sale.totalPaise);
      expect(r.payload['paymentStatus'], 'PAID');
      expect(r.payload['paymentMethod'], 'CASH');
      expect(r.payload['customerId'], isNull);
    });
  });

  // ========================================================================
  // TEST 2 — SALE ITEM outbox
  // ========================================================================
  group('TEST 2 — Sale-item outbox', () {
    test(
      'completeSale enqueues one SyncSaleItem per line with correct fields',
      () async {
        await seedProduct(
          id: 'p1',
          name: 'Coffee',
          stock: 5,
          pricePaise: 12000,
        );
        await seedProduct(id: 'p2', name: 'Tea', stock: 3, pricePaise: 8000);

        final completed = await billing.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Coffee',
              sku: 'FC-01',
              unitPricePaise: 12000,
              quantity: 2,
              maxQuantity: 5,
            ),
            const CartLine(
              productId: 'p2',
              productName: 'Tea',
              unitPricePaise: 8000,
              quantity: 1,
              maxQuantity: 3,
            ),
          ],
          paymentMethod: PaymentMethod.upi,
        );

        final results = await outboxPayloads('SALE_ITEM');
        expect(results, hasLength(2));

        // First item
        expect(results[0].payload['saleId'], completed.sale.id);
        expect(results[0].payload['shopId'], 'shop-test');
        expect(results[0].payload['productId'], 'p1');
        expect(results[0].payload['productName'], 'Coffee');
        expect(results[0].payload['sku'], 'FC-01');
        expect(results[0].payload['unitPricePaise'], 12000);
        expect(results[0].payload['quantity'], 2);
        expect(results[0].payload['lineTotalPaise'], 24000);
        expect(results[0].payload['variantId'], isNull);

        // Second item
        expect(results[1].payload['saleId'], completed.sale.id);
        expect(results[1].payload['productId'], 'p2');
        expect(results[1].payload['productName'], 'Tea');
        expect(results[1].payload['unitPricePaise'], 8000);
        expect(results[1].payload['quantity'], 1);
        expect(results[1].payload['lineTotalPaise'], 8000);
      },
    );
  });

  // ========================================================================
  // TEST 3 — CUSTOMER PAYMENT outbox
  // ========================================================================
  group('TEST 3 — Customer-payment outbox', () {
    test(
      'recordPayment enqueues SyncCustomerPayment with correct fields',
      () async {
        await seedCustomer('c1');
        await seedSale(id: 's1', customerId: 'c1', totalPaise: 50000);

        final payment = await ledger.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 20000,
          paymentMethod: PaymentMethod.upi,
          note: 'Partial payment',
        );

        final results = await outboxPayloads('CUSTOMER_PAYMENT');
        expect(results, hasLength(1));

        final r = results.first;
        expect(r.entry.entity, 'CUSTOMER_PAYMENT');
        expect(r.entry.entityId, payment.id);
        expect(r.entry.status, 'PENDING');

        expect(r.payload['id'], payment.id);
        expect(r.payload['shopId'], 'shop-test');
        expect(r.payload['customerId'], 'c1');
        expect(r.payload['saleId'], 's1');
        expect(r.payload['amountPaise'], 20000);
        expect(r.payload['paymentMethod'], 'UPI');
        expect(r.payload['note'], 'Partial payment');
        expect(r.payload['reversed'], false);
        expect(r.payload['reversedAt'], isNull);
      },
    );

    test(
      'recordPayment still settles sale when fully paid (Phase 7.2 unchanged)',
      () async {
        await seedCustomer('c1');
        await seedSale(id: 's1', customerId: 'c1', totalPaise: 30000);

        await ledger.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 30000,
          paymentMethod: PaymentMethod.cash,
        );

        // Sale should now be PAID
        final sale = await (db.select(
          db.sales,
        )..where((t) => t.id.equals('s1'))).getSingle();
        expect(sale.paymentStatus, 'PAID');
        expect(sale.paymentMethod, 'CASH');

        // Outbox entry exists
        final results = await outboxPayloads('CUSTOMER_PAYMENT');
        expect(results, hasLength(1));
      },
    );
  });

  // ========================================================================
  // TEST 4 — EXPENSE CREATE outbox
  // ========================================================================
  group('TEST 4 — Expense-create outbox', () {
    test('createExpense enqueues SyncExpense with all fields', () async {
      final expense = await expenses.createExpense(
        name: 'Coffee beans',
        amountPaise: 25500,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.upi,
        expenseDate: DateTime.utc(2026, 8, 10),
        note: 'Weekly order',
      );

      final results = await outboxPayloads('EXPENSE');
      expect(results, hasLength(1));

      final r = results.first;
      expect(r.entry.entity, 'EXPENSE');
      expect(r.entry.entityId, expense.id);
      expect(r.entry.status, 'PENDING');

      expect(r.payload['id'], expense.id);
      expect(r.payload['shopId'], 'shop-test');
      expect(r.payload['name'], 'Coffee beans');
      expect(r.payload['amountPaise'], 25500);
      expect(r.payload['category'], 'SUPPLIES');
      expect(r.payload['paymentMethod'], 'UPI');
      expect(r.payload['paymentStatus'], 'PAID');
      expect(r.payload['note'], 'Weekly order');
      expect(r.payload['isActive'], true);
    });
  });

  // ========================================================================
  // TEST 5 — EXPENSE UPDATE outbox
  // ========================================================================
  group('TEST 5 — Expense-update outbox', () {
    test('updateExpense enqueues SyncExpense with updated values', () async {
      final expense = await expenses.createExpense(
        name: 'Original',
        amountPaise: 1000,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.utc(2026, 8, 10),
      );

      // Clear the create entry to isolate the update
      for (final r in await outboxPayloads('EXPENSE')) {
        await sync.markDone(r.entry.id);
      }

      await expenses.updateExpense(
        id: expense.id,
        name: 'Updated expense',
        amountPaise: 5000,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.upi,
        expenseDate: DateTime.utc(2026, 8, 15),
        note: 'Updated note',
        isActive: true,
        paymentStatus: ExpensePaymentStatus.notPaid,
      );

      final results = await outboxPayloads('EXPENSE');
      expect(results, hasLength(1));

      expect(results.first.payload['name'], 'Updated expense');
      expect(results.first.payload['amountPaise'], 5000);
      expect(results.first.payload['category'], 'RENT');
      expect(results.first.payload['paymentMethod'], 'UPI');
      expect(results.first.payload['paymentStatus'], 'NOT_PAID');
      expect(results.first.payload['note'], 'Updated note');
    });
  });

  // ========================================================================
  // TEST 6 — EXPENSE ACTIVE/DELETE STATE outbox
  // ========================================================================
  group('TEST 6 — Expense-active outbox', () {
    test(
      'setExpenseActive enqueues SyncExpense with toggled isActive',
      () async {
        final expense = await expenses.createExpense(
          name: 'Deactivatable',
          amountPaise: 1000,
          category: ExpenseCategory.supplies,
          paymentMethod: PaymentMethod.cash,
          expenseDate: DateTime.utc(2026, 8, 10),
        );

        // Clear create entry
        for (final r in await outboxPayloads('EXPENSE')) {
          await sync.markDone(r.entry.id);
        }

        await expenses.setExpenseActive(expense.id, false);

        final results = await outboxPayloads('EXPENSE');
        expect(results, hasLength(1));

        expect(results.first.payload['id'], expense.id);
        expect(results.first.payload['isActive'], false);
      },
    );
  });

  // ========================================================================
  // TEST 7 — ATOMICITY
  // ========================================================================
  group('TEST 7 — Atomicity', () {
    test(
      'if local write fails, no orphan outbox entry is created (billing)',
      () async {
        expect(
          () => billing.completeSale(
            lines: [],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<EmptyCartFailure>()),
        );
        expect(await sync.pendingOutboxCount(), 0);
      },
    );

    test(
      'if local write fails, no orphan outbox entry is created (expenses)',
      () async {
        expect(
          () => expenses.createExpense(
            name: '', // empty name throws
            amountPaise: 1000,
            category: ExpenseCategory.supplies,
            paymentMethod: PaymentMethod.cash,
            expenseDate: DateTime.utc(2026, 1, 1),
          ),
          throwsA(isA<UnexpectedExpensesFailure>()),
        );
        expect(await sync.pendingOutboxCount(), 0);
      },
    );
  });

  // ========================================================================
  // TEST 8 — FAST SYNC TRIGGER
  // ========================================================================
  group('TEST 8 — Fast-sync trigger', () {
    test('onEnqueue fires exactly once per successful sale', () async {
      var kicks = 0;
      final coord = SyncOutboxCoordinator(
        sync,
        () async => const SyncSessionContext(
          deviceId: 'test-device',
          shopId: 'shop-test',
          userId: 'user-test',
        ),
        onEnqueue: () => kicks++,
      );
      final b = DriftBillingRepository(db, outboxCoordinator: coord);

      await seedProduct(id: 'p1', name: 'Coffee', stock: 5);
      await b.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Coffee',
            unitPricePaise: 12000,
            quantity: 1,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      // completeSale enqueues 1 SALE + 1 SALE_ITEM via one coordinator.run
      expect(kicks, 1);
    });

    test('onEnqueue fires once for expense create', () async {
      var kicks = 0;
      final coord = SyncOutboxCoordinator(
        sync,
        () async => const SyncSessionContext(
          deviceId: 'test-device',
          shopId: 'shop-test',
          userId: 'user-test',
        ),
        onEnqueue: () => kicks++,
      );
      final e = DriftExpensesRepository(db, outboxCoordinator: coord);

      await e.createExpense(
        name: 'Test',
        amountPaise: 1000,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.utc(2026, 1, 1),
      );

      expect(kicks, 1);
    });

    test('onEnqueue fires once for customer payment', () async {
      var kicks = 0;
      final coord = SyncOutboxCoordinator(
        sync,
        () async => const SyncSessionContext(
          deviceId: 'test-device',
          shopId: 'shop-test',
          userId: 'user-test',
        ),
        onEnqueue: () => kicks++,
      );
      final l = DriftCustomerLedgerRepository(db, outboxCoordinator: coord);

      await seedCustomer('c1');
      await seedSale(id: 's1', customerId: 'c1', totalPaise: 50000);
      await l.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 10000,
        paymentMethod: PaymentMethod.cash,
      );

      expect(kicks, 1);
    });
  });

  // ========================================================================
  // TEST 9 — DUPLICATE PROTECTION
  // ========================================================================
  group('TEST 9 — Duplicate protection', () {
    test(
      'repeated completeSale produces separate outbox entries (different sale ids)',
      () async {
        await seedProduct(id: 'p1', name: 'Coffee', stock: 20);

        await billing.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Coffee',
              unitPricePaise: 12000,
              quantity: 1,
              maxQuantity: 20,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        );
        await billing.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Coffee',
              unitPricePaise: 12000,
              quantity: 1,
              maxQuantity: 20,
            ),
          ],
          paymentMethod: PaymentMethod.upi,
        );

        final saleResults = await outboxPayloads('SALE');
        final itemResults = await outboxPayloads('SALE_ITEM');
        expect(saleResults, hasLength(2));
        expect(itemResults, hasLength(2));

        // Each entry has a unique entity id
        final saleIds = saleResults.map((r) => r.entry.entityId).toSet();
        expect(saleIds.length, 2);
        final itemIds = itemResults.map((r) => r.entry.entityId).toSet();
        expect(itemIds.length, 2);
      },
    );

    test(
      'two distinct payments produce separate outbox entries (different payment ids)',
      () async {
        await seedCustomer('c1');
        await seedSale(id: 's1', customerId: 'c1', totalPaise: 50000);

        await ledger.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 10000,
          paymentMethod: PaymentMethod.cash,
          note: 'First payment',
        );
        await ledger.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 10000,
          paymentMethod: PaymentMethod.cash,
          note: 'Second payment',
        );

        final results = await outboxPayloads('CUSTOMER_PAYMENT');
        expect(results, hasLength(2));

        // Each payment has a unique entity id (different UUIDs).
        final ids = results.map((r) => r.entry.entityId).toSet();
        expect(ids.length, 2);
      },
    );

    test(
      'deterministic outbox id means re-enqueue of same entity collapses',
      () async {
        // Simulate the same logical change being enqueued twice by
        // using the coordinator directly with a fixed entity id.
        final id = 'fixed-payment-id';
        final payload = <String, dynamic>{
          'id': id,
          'shopId': 'shop-test',
          'amountPaise': 5000,
        };

        await coordinator.run<void>(
          write: () async {},
          snapshots: (_, ctx) async => [
            OutboxAppend(
              entity: MasterEntity.customerPayment,
              entityId: id,
              payload: payload,
            ),
          ],
        );
        // Enqueue the exact same entity again.
        await coordinator.run<void>(
          write: () async {},
          snapshots: (_, ctx) async => [
            OutboxAppend(
              entity: MasterEntity.customerPayment,
              entityId: id,
              payload: payload,
            ),
          ],
        );

        final results = await outboxPayloads('CUSTOMER_PAYMENT');
        expect(results, hasLength(1));
      },
    );
  });
}
