import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftBillingRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftBillingRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct({
    required String id,
    required String name,
    int stock = 10,
    bool active = true,
    String? sku,
    int pricePaise = 12000,
  }) async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sku: Value(sku),
            sellingPricePaise: pricePaise,
            stockQuantity: Value(stock),
            isActive: Value(active),
          ),
        );
  }

  List<CartLine> lines(List<(String, int)> entries, {int pricePaise = 12000}) =>
      [
        for (final (id, quantity) in entries)
          CartLine(
            productId: id,
            productName: 'Name $id',
            sku: null,
            unitPricePaise: pricePaise,
            quantity: quantity,
            maxQuantity: 99,
          ),
      ];

  Future<int> countSales() async {
    final query = database.selectOnly(database.sales)
      ..addColumns([database.sales.id.count()]);
    return query.map((row) => row.read(database.sales.id.count())!).getSingle();
  }

  Future<int> stockOf(String id) async {
    final row = await (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
    return row.stockQuantity;
  }

  Future<void> seedCustomer({required String id, bool active = true}) async {
    await database
        .into(database.customers)
        .insert(
          CustomersCompanion.insert(
            id: Value(id),
            name: 'Customer $id',
            isActive: Value(active),
          ),
        );
  }

  Future<String?> customerIdOf(String saleId) async {
    final row = await (database.select(
      database.sales,
    )..where((t) => t.id.equals(saleId))).getSingle();
    return row.customerId;
  }

  /// Test-only trigger on an isolated in-memory database that aborts every
  /// insert into [table], forcing the checkout transaction to roll back.
  Future<void> createFailTrigger(String table, String name) async {
    await database.customStatement(
      "CREATE TRIGGER $name BEFORE INSERT ON $table "
      "BEGIN SELECT RAISE(ABORT, 'forced failure'); END",
    );
  }

  Future<int> saleItemCount() async {
    final query = database.selectOnly(database.saleItems)
      ..addColumns([database.saleItems.id.count()]);
    return query
        .map((row) => row.read(database.saleItems.id.count())!)
        .getSingle();
  }

  group('completeSale', () {
    test(
      'persists header, snapshot items and deducts stock atomically',
      () async {
        await seedProduct(
          id: 'p1',
          name: 'Filter Coffee',
          stock: 5,
          sku: 'FC-01',
        );
        await seedProduct(
          id: 'p2',
          name: 'Green Tea',
          stock: 3,
          pricePaise: 8000,
        );

        final completed = await repository.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Filter Coffee',
              sku: 'FC-01',
              unitPricePaise: 12000,
              quantity: 2,
              maxQuantity: 5,
            ),
            const CartLine(
              productId: 'p2',
              productName: 'Green Tea',
              unitPricePaise: 8000,
              quantity: 1,
              maxQuantity: 3,
            ),
          ],
          paymentMethod: PaymentMethod.upi,
        );

        final sale = completed.sale;
        expect(sale.receiptNumber, 'BF-000001');
        expect(sale.subtotalPaise, 32000);
        expect(sale.totalPaise, 32000);
        expect(sale.paymentMethod, PaymentMethod.upi);
        expect(completed.items.length, 2);
        expect(completed.items[0].productName, 'Filter Coffee');
        expect(completed.items[0].sku, 'FC-01');
        expect(completed.items[0].unitPricePaise, 12000);
        expect(completed.items[0].quantity, 2);
        expect(completed.items[0].lineTotalPaise, 24000);
        expect(completed.items[0].saleId, sale.id);

        expect(await stockOf('p1'), 3);
        expect(await stockOf('p2'), 2);

        final loaded = await repository.saleById(sale.id);
        expect(loaded!.receiptNumber, 'BF-000001');
        expect(loaded.paymentMethod, PaymentMethod.upi);
        expect((await repository.saleItemsFor(sale.id)).length, 2);
        expect((await repository.sales()).length, 1);
      },
    );

    test('issues gapless sequential receipt numbers across sales', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 20);
      for (var i = 1; i <= 3; i++) {
        final completed = await repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentMethod: PaymentMethod.cash,
        );
        expect(
          completed.sale.receiptNumber,
          'BF-${i.toString().padLeft(6, '0')}',
        );
      }
      final all = await repository.sales();
      expect(all.map((s) => s.receiptNumber).toSet(), {
        'BF-000001',
        'BF-000002',
        'BF-000003',
      });
      expect(await stockOf('p1'), 17);
    });

    test('succeeds when quantity equals available stock exactly', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 3);
      final completed = await repository.completeSale(
        lines: lines([('p1', 3)]),
        paymentMethod: PaymentMethod.cash,
      );
      expect(completed.sale.totalPaise, 36000);
      expect(await stockOf('p1'), 0);
    });

    test('rejects empty line lists', () async {
      expect(
        () => repository.completeSale(
          lines: const [],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<EmptyCartFailure>()),
      );
    });

    test('rejects quantity above stock and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 2);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1), ('p2', 5)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(
          isA<InsufficientStockFailure>().having(
            (f) => f.productName,
            'productName',
            'Name p2',
          ),
        ),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 2);
      expect(await stockOf('p2'), 3);

      // The failed attempt must not consume a receipt sequence value.
      final next = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );
      expect(next.sale.receiptNumber, 'BF-000001');
    });

    test('rejects inactive products and rolls back', () async {
      await seedProduct(
        id: 'p1',
        name: 'Filter Coffee',
        stock: 5,
        active: false,
      );

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<UnavailableProductFailure>()),
      );
      expect(await countSales(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects missing products and rolls back', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await (database.delete(
        database.products,
      )..where((t) => t.id.equals('p1'))).go();

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<UnavailableProductFailure>()),
      );
      expect(await countSales(), 0);
    });

    test('never leaves partial data when the second line fails', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 1);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 0);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1), ('p2', 1)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 1);
      final salesTable = database.selectOnly(database.saleItems)
        ..addColumns([database.saleItems.id.count()]);
      expect(
        await salesTable
            .map((r) => r.read(database.saleItems.id.count())!)
            .getSingle(),
        0,
      );
    });

    test('rejects line totals above the safe ceiling', () async {
      await seedProduct(
        id: 'p1',
        name: 'Filter Coffee',
        stock: 1000,
        pricePaise: 9999999999,
      );
      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 2)], pricePaise: 9999999999),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<UnexpectedBillingFailure>()),
      );
      expect(await countSales(), 0);
      expect(await stockOf('p1'), 1000);
    });
  });

  group('customer linked sales', () {
    test('persists the customer reference on the sale', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedCustomer(id: 'c1');

      final completed = await repository.completeSale(
        lines: lines([('p1', 2)]),
        paymentMethod: PaymentMethod.cash,
        customerId: 'c1',
      );

      expect(completed.sale.customerId, 'c1');
      expect(await customerIdOf(completed.sale.id), 'c1');
      final loaded = await repository.saleById(completed.sale.id);
      expect(loaded!.customerId, 'c1');
    });

    test('keeps walk-in sales with a null customer reference', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      final completed = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );

      expect(completed.sale.customerId, isNull);
      expect(await customerIdOf(completed.sale.id), isNull);
    });

    test('rejects a missing customer and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentMethod: PaymentMethod.cash,
          customerId: 'missing',
        ),
        throwsA(isA<CustomerNotFoundFailure>()),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 5);

      // The failed attempt must not consume a receipt sequence value.
      final next = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );
      expect(next.sale.receiptNumber, 'BF-000001');
    });

    test('rejects a deactivated customer and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedCustomer(id: 'c1', active: false);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentMethod: PaymentMethod.cash,
          customerId: 'c1',
        ),
        throwsA(isA<InactiveCustomerFailure>()),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 5);
    });
  });

  group('NOT_PAID credit sales', () {
    test('requires a customer and persists nothing', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentStatus: PaymentStatus.notPaid,
        ),
        throwsA(isA<MissingCustomerForCreditSaleFailure>()),
      );

      expect(await countSales(), 0);
      expect(await saleItemCount(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects an unknown customer and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'missing',
        ),
        throwsA(isA<CustomerNotFoundFailure>()),
      );

      expect(await countSales(), 0);
      expect(await saleItemCount(), 0);
      expect(await stockOf('p1'), 5);

      // The failed attempt must not consume a receipt sequence value.
      await seedCustomer(id: 'c1');
      final next = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentStatus: PaymentStatus.notPaid,
        customerId: 'c1',
      );
      expect(next.sale.receiptNumber, 'BF-000001');
    });

    test('rejects a deactivated customer and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedCustomer(id: 'c1', active: false);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        ),
        throwsA(isA<InactiveCustomerFailure>()),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('persists NOT_PAID with a null method and full audit trail', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);
      await seedCustomer(id: 'c1');

      final completed = await repository.completeSale(
        lines: lines([('p1', 2), ('p2', 1)]),
        paymentStatus: PaymentStatus.notPaid,
        customerId: 'c1',
      );

      final sale = completed.sale;
      expect(sale.paymentStatus, PaymentStatus.notPaid);
      expect(sale.paymentMethod, isNull);
      expect(sale.customerId, 'c1');
      expect(sale.totalPaise, 36000);

      final loaded = await repository.saleById(sale.id);
      expect(loaded!.paymentStatus, PaymentStatus.notPaid);
      expect(loaded.paymentMethod, isNull);
      expect(loaded.customerId, 'c1');

      expect(await stockOf('p1'), 3);
      expect(await stockOf('p2'), 2);

      final stock = DriftStockMovementRepository(database);
      for (final productId in ['p1', 'p2']) {
        final movements = await stock.movementsFor(productId);
        expect(movements, hasLength(1));
        expect(movements.single.movementType, StockMovementType.sale);
        expect(movements.single.referenceId, sale.id);
      }

      final all = await repository.sales();
      expect(all.single.paymentStatus, PaymentStatus.notPaid);
      expect(all.single.paymentMethod, isNull);
    });

    test(
      'creates customer debt equal to the sale total via the ledger',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await seedCustomer(id: 'c1');

        await repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        );

        final ledger = DriftCustomerLedgerRepository(database);
        final summary = await ledger.summary('c1');
        expect(summary.totalPurchasesPaise, 24000);
        expect(summary.totalPaidPaise, 0);
        expect(summary.outstandingPaise, 24000);
        expect(summary.purchaseCount, 1);
        expect(summary.paymentCount, 0);

        final purchases = await ledger.purchases('c1');
        expect(purchases, hasLength(1));
        expect(purchases.single.totalPaise, 24000);
        expect(purchases.single.paidPaise, 0);
        expect(purchases.single.duePaise, 24000);
        expect(purchases.single.status, SalePaymentStatus.unpaid);
      },
    );

    test('a paid linked sale keeps the pre-existing ledger behavior', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedCustomer(id: 'c1');

      final completed = await repository.completeSale(
        lines: lines([('p1', 2)]),
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
        customerId: 'c1',
      );

      // The sale itself is PAID with its method — exactly as before 15A.
      final loaded = await repository.saleById(completed.sale.id);
      expect(loaded!.paymentStatus, PaymentStatus.paid);
      expect(loaded.paymentMethod, PaymentMethod.cash);
      expect(loaded.customerId, 'c1');

      // The customer ledger sees the same purchase it always has (linked
      // sales are settled by recording ledger payments — unchanged).
      final ledger = DriftCustomerLedgerRepository(database);
      final summary = await ledger.summary('c1');
      expect(summary.totalPurchasesPaise, 24000);
      expect(summary.totalPaidPaise, 0);
      expect(summary.purchaseCount, 1);
      expect(summary.paymentCount, 0);
      final purchases = await ledger.purchases('c1');
      expect(purchases.single.status, SalePaymentStatus.unpaid);
    });

    test(
      'multi-item credit sale creates one debt for the combined total',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);
        await seedCustomer(id: 'c1');

        final completed = await repository.completeSale(
          lines: lines([('p1', 2), ('p2', 1)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        );

        final ledger = DriftCustomerLedgerRepository(database);
        final purchases = await ledger.purchases('c1');
        expect(purchases, hasLength(1));
        expect(purchases.single.saleId, completed.sale.id);
        expect(purchases.single.totalPaise, 36000);
        expect(purchases.single.duePaise, 36000);
      },
    );

    test('a failed credit sale leaves no debt or audit trail behind', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);
      await seedCustomer(id: 'c1');

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1), ('p2', 5)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await countSales(), 0);
      expect(await saleItemCount(), 0);
      expect(await stockOf('p1'), 5);
      expect(await stockOf('p2'), 3);
      final ledger = DriftCustomerLedgerRepository(database);
      expect(await ledger.purchases('c1'), isEmpty);
      final summary = await ledger.summary('c1');
      expect(summary.outstandingPaise, 0);
    });

    test('receipt sequence is reusable after a failed credit sale', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedCustomer(id: 'c1');

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 9)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final next = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentStatus: PaymentStatus.notPaid,
        customerId: 'c1',
      );
      expect(next.sale.receiptNumber, 'BF-000001');
      expect(next.sale.paymentStatus, PaymentStatus.notPaid);
    });

    test(
      'sale item insert failure rolls back a credit sale completely',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await seedCustomer(id: 'c1');
        await createFailTrigger('sale_items', 'fail_credit_item_insert');

        await expectLater(
          repository.completeSale(
            lines: lines([('p1', 2)]),
            paymentStatus: PaymentStatus.notPaid,
            customerId: 'c1',
          ),
          throwsA(isA<UnexpectedBillingFailure>()),
        );

        expect(await countSales(), 0);
        expect(await saleItemCount(), 0);
        expect(await stockOf('p1'), 5);
        final ledger = DriftCustomerLedgerRepository(database);
        expect(await ledger.purchases('c1'), isEmpty);

        await database.customStatement('DROP TRIGGER fail_credit_item_insert');
        final next = await repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        );
        expect(next.sale.receiptNumber, 'BF-000001');
      },
    );

    test('concurrent credit checkouts for different customers commit '
        'atomically', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 10);
      await seedCustomer(id: 'c1');
      await seedCustomer(id: 'c2');

      final outcomes = await Future.wait<Object?>([
        repository
            .completeSale(
              lines: lines([('p1', 3)]),
              paymentStatus: PaymentStatus.notPaid,
              customerId: 'c1',
            )
            .then<Object?>((completed) => completed)
            .catchError((Object error) => error),
        repository
            .completeSale(
              lines: lines([('p1', 4)]),
              paymentStatus: PaymentStatus.notPaid,
              customerId: 'c2',
            )
            .then<Object?>((completed) => completed)
            .catchError((Object error) => error),
      ]);

      expect(outcomes.whereType<CompletedSale>(), hasLength(2));
      expect(await stockOf('p1'), 3);
      expect(await countSales(), 2);

      final ledger = DriftCustomerLedgerRepository(database);
      final c1 = await ledger.summary('c1');
      final c2 = await ledger.summary('c2');
      expect(c1.outstandingPaise, 36000);
      expect(c2.outstandingPaise, 48000);
    });
  });

  group('sale stock movements', () {
    test('writes one SALE movement per line with the sale reference', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);

      final completed = await repository.completeSale(
        lines: lines([('p1', 2), ('p2', 1)]),
        paymentMethod: PaymentMethod.upi,
      );

      final stock = DriftStockMovementRepository(database);
      final p1 = await stock.movementsFor('p1');
      expect(p1, hasLength(1));
      expect(p1.single.movementType, StockMovementType.sale);
      expect(p1.single.quantity, -2);
      expect(p1.single.stockBefore, 5);
      expect(p1.single.stockAfter, 3);
      expect(p1.single.referenceType, 'SALE');
      expect(p1.single.referenceId, completed.sale.id);
      expect(p1.single.reason, isNull);
      expect(p1.single.note, isNull);

      final p2 = await stock.movementsFor('p2');
      expect(p2, hasLength(1));
      expect(p2.single.movementType, StockMovementType.sale);
      expect(p2.single.quantity, -1);
      expect(p2.single.stockBefore, 3);
      expect(p2.single.stockAfter, 2);
      expect(p2.single.referenceId, completed.sale.id);

      expect(await stockOf('p1'), 3);
      expect(await stockOf('p2'), 2);
    });

    test('keeps the audit chain consistent across OPENING and SALE', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 0);
      final stock = DriftStockMovementRepository(database);
      await stock.recordOpening(productId: 'p1', quantity: 25);

      await repository.completeSale(
        lines: lines([('p1', 5)]),
        paymentMethod: PaymentMethod.cash,
      );

      final history = await stock.movementsFor('p1');
      expect(history, hasLength(2));
      expect(history[0].movementType, StockMovementType.sale);
      expect(history[0].stockBefore, 25);
      expect(history[0].stockAfter, 20);
      expect(history[0].stockBefore, history[1].stockAfter);
      expect(history[1].movementType, StockMovementType.opening);
      expect(history[1].quantity, 25);
      expect(history[1].stockBefore, 0);
      expect(history[1].stockAfter, 25);
      expect(await stockOf('p1'), 20);
    });

    test('failed checkout leaves no movements behind', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 2);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 1), ('p2', 5)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      final stock = DriftStockMovementRepository(database);
      expect(await stock.movementsFor('p1'), isEmpty);
      expect(await stock.movementsFor('p2'), isEmpty);
      expect(await stockOf('p1'), 2);
      expect(await stockOf('p2'), 3);
    });

    test('sale that empties stock writes stockAfter zero', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 3);

      await repository.completeSale(
        lines: lines([('p1', 3)]),
        paymentMethod: PaymentMethod.cash,
      );

      final p1 = await DriftStockMovementRepository(
        database,
      ).movementsFor('p1');
      expect(p1.single.movementType, StockMovementType.sale);
      expect(p1.single.quantity, -3);
      expect(p1.single.stockBefore, 3);
      expect(p1.single.stockAfter, 0);
    });
  });

  group('checkout hardening', () {
    test('sale snapshots survive later product edits', () async {
      await seedProduct(
        id: 'p1',
        name: 'Filter Coffee',
        stock: 5,
        sku: 'FC-01',
      );

      final completed = await repository.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Filter Coffee',
            sku: 'FC-01',
            unitPricePaise: 12000,
            quantity: 2,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      await (database.update(database.products)).write(
        ProductsCompanion(
          name: const Value('Filter Coffee Supreme'),
          sellingPricePaise: const Value(99900),
        ),
      );

      final items = await repository.saleItemsFor(completed.sale.id);
      expect(items.single.productName, 'Filter Coffee');
      expect(items.single.sku, 'FC-01');
      expect(items.single.unitPricePaise, 12000);
      expect(items.single.quantity, 2);
      expect(items.single.lineTotalPaise, 24000);
      final loaded = await repository.saleById(completed.sale.id);
      expect(loaded!.totalPaise, 24000);
    });

    test(
      'revalidates stock against the database, not the cart snapshot',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

        // The stock drops after the cart line was added (cart says max 5).
        await (database.update(database.products)
              ..where((t) => t.id.equals('p1')))
            .write(ProductsCompanion(stockQuantity: const Value(2)));

        await expectLater(
          repository.completeSale(
            lines: lines([('p1', 3)]),
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<InsufficientStockFailure>()),
        );

        expect(await countSales(), 0);
        expect(await stockOf('p1'), 2);
      },
    );

    test(
      'charges the cart price snapshot even after the price changes',
      () async {
        await seedProduct(
          id: 'p1',
          name: 'Filter Coffee',
          stock: 5,
          pricePaise: 10000,
        );

        await (database.update(database.products)
              ..where((t) => t.id.equals('p1')))
            .write(ProductsCompanion(sellingPricePaise: const Value(9000)));

        final completed = await repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentMethod: PaymentMethod.cash,
        );

        final items = await repository.saleItemsFor(completed.sale.id);
        expect(items.single.unitPricePaise, 12000);
        expect(items.single.lineTotalPaise, 24000);
        expect(completed.sale.totalPaise, 24000);
      },
    );

    test('audit chain stays consistent across consecutive sales', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 0);
      final stock = DriftStockMovementRepository(database);
      await stock.recordOpening(productId: 'p1', quantity: 25);

      await repository.completeSale(
        lines: lines([('p1', 5)]),
        paymentMethod: PaymentMethod.cash,
      );
      await repository.completeSale(
        lines: lines([('p1', 3)]),
        paymentMethod: PaymentMethod.upi,
      );

      final history = await stock.movementsFor('p1');
      expect(history, hasLength(3));
      expect(history[0].movementType, StockMovementType.sale);
      expect(history[0].quantity, -3);
      expect(history[0].stockBefore, 20);
      expect(history[0].stockAfter, 17);
      expect(history[0].stockBefore, history[1].stockAfter);
      expect(history[1].movementType, StockMovementType.sale);
      expect(history[1].quantity, -5);
      expect(history[1].stockBefore, 25);
      expect(history[1].stockAfter, 20);
      expect(history[1].stockBefore, history[2].stockAfter);
      expect(history[2].movementType, StockMovementType.opening);
      expect(history[2].quantity, 25);
      expect(history[2].stockBefore, 0);
      expect(await stockOf('p1'), 17);
    });

    test('concurrent checkouts cannot oversell one product', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      final outcomes = await Future.wait<Object?>([
        repository
            .completeSale(
              lines: lines([('p1', 4)]),
              paymentMethod: PaymentMethod.cash,
            )
            .then<Object?>((completed) => completed)
            .catchError((Object error) => error),
        repository
            .completeSale(
              lines: lines([('p1', 4)]),
              paymentMethod: PaymentMethod.upi,
            )
            .then<Object?>((completed) => completed)
            .catchError((Object error) => error),
      ]);

      final successes = outcomes.whereType<CompletedSale>().toList();
      final failures = outcomes.whereType<BillingFailure>().toList();
      expect(successes, hasLength(1));
      expect(failures, hasLength(1));
      expect(failures.single, isA<InsufficientStockFailure>());
      expect(await stockOf('p1'), 1);
      expect(await countSales(), 1);

      final stock = DriftStockMovementRepository(database);
      final p1 = await stock.movementsFor('p1');
      expect(p1, hasLength(1));
      expect(p1.single.movementType, StockMovementType.sale);
      expect(p1.single.quantity, -4);
      expect(p1.single.stockBefore, 5);
      expect(p1.single.stockAfter, 1);
      expect(p1.single.referenceId, successes.single.sale.id);
    });

    test('concurrent multi-item checkouts commit atomically', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 5);

      final outcomes = await Future.wait<Object?>([
        repository
            .completeSale(
              lines: lines([('p1', 4), ('p2', 4)]),
              paymentMethod: PaymentMethod.cash,
            )
            .then<Object?>((completed) => completed)
            .catchError((Object error) => error),
        repository
            .completeSale(
              lines: lines([('p1', 4), ('p2', 4)]),
              paymentMethod: PaymentMethod.upi,
            )
            .then<Object?>((completed) => completed)
            .catchError((Object error) => error),
      ]);

      final successes = outcomes.whereType<CompletedSale>().toList();
      final failures = outcomes.whereType<BillingFailure>().toList();
      expect(successes, hasLength(1));
      expect(failures, hasLength(1));
      expect(failures.single, isA<InsufficientStockFailure>());
      expect(await stockOf('p1'), 1);
      expect(await stockOf('p2'), 1);
      expect(await countSales(), 1);

      final stock = DriftStockMovementRepository(database);
      final p1 = await stock.movementsFor('p1');
      final p2 = await stock.movementsFor('p2');
      expect(p1, hasLength(1));
      expect(p2, hasLength(1));
      expect(p1.single.stockAfter, 1);
      expect(p2.single.stockAfter, 1);
      expect(p1.single.referenceId, successes.single.sale.id);
      expect(p2.single.referenceId, successes.single.sale.id);
    });

    test('sale insert failure rolls back stock, items and movements', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await createFailTrigger('sales', 'fail_sale_insert');

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<UnexpectedBillingFailure>()),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 5);
      expect(await saleItemCount(), 0);
      expect(
        await DriftStockMovementRepository(database).movementsFor('p1'),
        isEmpty,
      );

      await database.customStatement('DROP TRIGGER fail_sale_insert');
      final next = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );
      expect(next.sale.receiptNumber, 'BF-000001');
    });

    test('sale item insert failure rolls back stock and movements', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await createFailTrigger('sale_items', 'fail_sale_item_insert');

      await expectLater(
        repository.completeSale(
          lines: lines([('p1', 2)]),
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<UnexpectedBillingFailure>()),
      );

      expect(await countSales(), 0);
      expect(await stockOf('p1'), 5);
      expect(await saleItemCount(), 0);
      expect(
        await DriftStockMovementRepository(database).movementsFor('p1'),
        isEmpty,
      );

      await database.customStatement('DROP TRIGGER fail_sale_item_insert');
      final next = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );
      expect(next.sale.receiptNumber, 'BF-000001');
    });

    test(
      'SALE movement insert failure rolls back the whole checkout',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await createFailTrigger('stock_movements', 'fail_movement_insert');

        await expectLater(
          repository.completeSale(
            lines: lines([('p1', 2)]),
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<UnexpectedBillingFailure>()),
        );

        expect(await countSales(), 0);
        expect(await stockOf('p1'), 5);
        expect(await saleItemCount(), 0);
        expect(
          await DriftStockMovementRepository(database).movementsFor('p1'),
          isEmpty,
        );

        await database.customStatement('DROP TRIGGER fail_movement_insert');
        final next = await repository.completeSale(
          lines: lines([('p1', 1)]),
          paymentMethod: PaymentMethod.cash,
        );
        expect(next.sale.receiptNumber, 'BF-000001');
      },
    );
  });

  group('reads', () {
    test('saleById returns null for unknown ids', () async {
      expect(await repository.saleById('missing'), isNull);
    });

    test('sales() returns newest first', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 20);
      await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );
      await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.upi,
      );
      final all = await repository.sales();
      expect(all.length, 2);
      expect(all[0].paymentMethod, PaymentMethod.upi);
      expect(all[1].paymentMethod, PaymentMethod.cash);
    });
  });

  group('voidSale', () {
    test('restores stock, keeps the row and marks it voided', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      final completed = await repository.completeSale(
        lines: lines([('p1', 2)]),
        paymentMethod: PaymentMethod.cash,
      );
      final saleId = completed.sale.id;
      expect(await stockOf('p1'), 3);

      await repository.voidSale(saleId);

      // Stock is restored and the sale row is retained (never hard-deleted).
      expect(await stockOf('p1'), 5);
      expect(await countSales(), 1);
      final loaded = await repository.saleById(saleId);
      expect(loaded?.voided, isTrue);
      expect(loaded?.voidedAt, isA<DateTime>());
    });

    test('rejects voiding a sale twice', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      final completed = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
      );

      await repository.voidSale(completed.sale.id);
      await expectLater(
        repository.voidSale(completed.sale.id),
        throwsA(isA<SaleAlreadyVoidedFailure>()),
      );
      // The double-void must not restore stock a second time.
      expect(await stockOf('p1'), 5);
    });

    test('rejects voiding an unknown sale', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await expectLater(
        repository.voidSale('missing'),
        throwsA(isA<SaleNotFoundFailure>()),
      );
      expect(await stockOf('p1'), 5);
    });

    test('reverses customer payments linked to the voided sale', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedCustomer(id: 'c1');
      final completed = await repository.completeSale(
        lines: lines([('p1', 1)]),
        paymentMethod: PaymentMethod.cash,
        customerId: 'c1',
      );
      final saleId = completed.sale.id;
      final now = DateTime.now().toUtc();
      await database
          .into(database.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: Value('pay-1'),
              customerId: 'c1',
              saleId: Value<String?>(saleId),
              amountPaise: 12000,
              paymentMethod: 'CASH',
              paidAt: now,
            ),
          );

      await repository.voidSale(saleId);

      final payment = await (database.select(
        database.customerPayments,
      )..where((t) => t.id.equals('pay-1'))).getSingle();
      expect(payment.reversed, isTrue);
      expect(payment.reversedAt, isA<DateTime>());
    });
  });
}
