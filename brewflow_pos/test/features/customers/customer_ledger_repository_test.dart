import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftCustomerLedgerRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftCustomerLedgerRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCustomer(String id) async {
    await database
        .into(database.customers)
        .insert(CustomersCompanion.insert(id: Value(id), name: 'Customer $id'));
  }

  Future<String> seedSale({
    required String id,
    required String customerId,
    required String receiptNumber,
    required int totalPaise,
    DateTime? createdAt,
    String paymentStatus = 'NOT_PAID',
  }) async {
    final now = createdAt ?? DateTime.now().toUtc();
    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: Value(id),
            receiptNumber: receiptNumber,
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

  Future<int> countPayments() async {
    final query = database.selectOnly(database.customerPayments)
      ..addColumns([database.customerPayments.id.count()]);
    return query
        .map((row) => row.read(database.customerPayments.id.count())!)
        .getSingle();
  }

  group('recordPayment', () {
    test(
      'persists a payment with all fields and allocates it to the sale',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 50000,
        );

        final payment = await repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 30000,
          paymentMethod: PaymentMethod.upi,
          note: '  First instalment  ',
        );

        expect(payment.customerId, 'c1');
        expect(payment.saleId, 's1');
        expect(payment.amountPaise, 30000);
        expect(payment.paymentMethod, PaymentMethod.upi);
        expect(payment.note, 'First instalment');
        expect(payment.reversed, isFalse);
        expect(payment.reversedAt, isNull);
        expect(payment.paidAt.isUtc, isTrue);
        expect(payment.createdAt.isUtc, isTrue);
        expect(payment.updatedAt.isUtc, isTrue);
        expect(payment.id, isNotEmpty);
        expect(await countPayments(), 1);
      },
    );

    test('rejects zero and negative amounts without writing', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 0,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InvalidPaymentAmountFailure>()),
      );
      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: -100,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InvalidPaymentAmountFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('accepts a payment exactly equal to the remaining due', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      final payment = await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.cash,
      );
      expect(payment.amountPaise, 50000);
      expect(await repository.outstandingForCustomer('c1'), 0);
    });

    test('rejects a payment above the remaining due', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 50001,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('allows multiple partial payments and rejects the one that would '
        'overpay', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 100000,
      );

      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 30000,
        paymentMethod: PaymentMethod.cash,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 40000,
        paymentMethod: PaymentMethod.upi,
      );

      final purchases = await repository.purchases('c1');
      expect(purchases.single.paidPaise, 70000);
      expect(purchases.single.duePaise, 30000);
      expect(purchases.single.status, SalePaymentStatus.partial);

      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 30001,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );

      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 30000,
        paymentMethod: PaymentMethod.cash,
      );
      expect(await repository.outstandingForCustomer('c1'), 0);
      expect(await countPayments(), 3);
    });

    test('rejects payments on a fully paid sale', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.cash,
      );

      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 100,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
    });

    test('rejects a missing sale', () async {
      await seedCustomer('c1');

      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 'missing',
          amountPaise: 10000,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<SaleNotFoundFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('rejects a sale that belongs to another customer', () async {
      await seedCustomer('c1');
      await seedCustomer('c2');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      await expectLater(
        repository.recordPayment(
          customerId: 'c2',
          saleId: 's1',
          amountPaise: 10000,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<SaleNotFoundFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('rejects a missing customer', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      await expectLater(
        repository.recordPayment(
          customerId: 'missing',
          saleId: 's1',
          amountPaise: 10000,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('two sequential full payments cannot both succeed', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.cash,
      );
      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 50000,
          paymentMethod: PaymentMethod.upi,
        ),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
      expect(await countPayments(), 1);
      expect(await repository.outstandingForCustomer('c1'), 0);
    });
  });

  group('purchases', () {
    test(
      'returns customer-linked sales newest first with derived amounts',
      () async {
        await seedCustomer('c1');
        final older = DateTime.utc(2026, 1, 1, 10);
        final newer = DateTime.utc(2026, 1, 2, 10);
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 100000,
          createdAt: older,
        );
        await seedSale(
          id: 's2',
          customerId: 'c1',
          receiptNumber: 'BF-000002',
          totalPaise: 50000,
          createdAt: newer,
        );
        await repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 40000,
          paymentMethod: PaymentMethod.cash,
        );

        final purchases = await repository.purchases('c1');
        expect(purchases.length, 2);
        expect(purchases[0].saleId, 's2');
        expect(purchases[0].receiptNumber, 'BF-000002');
        expect(purchases[0].totalPaise, 50000);
        expect(purchases[0].paidPaise, 0);
        expect(purchases[0].duePaise, 50000);
        expect(purchases[0].status, SalePaymentStatus.unpaid);
        expect(purchases[1].saleId, 's1');
        expect(purchases[1].receiptNumber, 'BF-000001');
        expect(purchases[1].paidPaise, 40000);
        expect(purchases[1].duePaise, 60000);
        expect(purchases[1].status, SalePaymentStatus.partial);
        expect(purchases[1].customerId, 'c1');
        expect(purchases[1].createdAt, older);
      },
    );

    test('derives paid status once payments cover the total', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 60000,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 30000,
        paymentMethod: PaymentMethod.cash,
      );
      expect(
        (await repository.purchases('c1')).single.status,
        SalePaymentStatus.partial,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 30000,
        paymentMethod: PaymentMethod.cash,
      );
      final purchase = (await repository.purchases('c1')).single;
      expect(purchase.status, SalePaymentStatus.paid);
      expect(purchase.duePaise, 0);
    });

    test('excludes walk-in sales entirely', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );
      await database
          .into(database.sales)
          .insert(
            SalesCompanion.insert(
              id: const Value('s2'),
              receiptNumber: 'BF-000002',
              subtotalPaise: 20000,
              totalPaise: 20000,
              paymentMethod: Value('UPI'),
            ),
          );

      final purchases = await repository.purchases('c1');
      expect(purchases.map((p) => p.saleId), ['s1']);
    });

    test('rejects unknown customers', () async {
      await expectLater(
        repository.purchases('missing'),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
    });
  });

  group('payments', () {
    test('returns payments newest first with all fields mapped', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 100000,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 30000,
        paymentMethod: PaymentMethod.cash,
        note: 'First',
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 20000,
        paymentMethod: PaymentMethod.bank,
      );

      final payments = await repository.payments('c1');
      expect(payments.length, 2);
      expect(payments[0].amountPaise, 20000);
      expect(payments[0].paymentMethod, PaymentMethod.bank);
      expect(payments[0].note, isNull);
      expect(payments[1].amountPaise, 30000);
      expect(payments[1].paymentMethod, PaymentMethod.cash);
      expect(payments[1].note, 'First');
      expect(payments[0].paidAt.isAfter(payments[1].paidAt), isTrue);
    });

    test('rejects unknown customers', () async {
      await expectLater(
        repository.payments('missing'),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
    });
  });

  group('summary', () {
    test('aggregates purchases, payments and outstanding', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 100000,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 50000,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 70000,
        paymentMethod: PaymentMethod.cash,
      );

      final summary = await repository.summary('c1');
      expect(summary.totalPurchasesPaise, 150000);
      expect(summary.totalPaidPaise, 70000);
      expect(summary.outstandingPaise, 80000);
      expect(summary.purchaseCount, 2);
      expect(summary.paymentCount, 1);
    });

    test('returns all-zero totals for a customer without data', () async {
      await seedCustomer('c1');
      final summary = await repository.summary('c1');
      expect(summary.totalPurchasesPaise, 0);
      expect(summary.totalPaidPaise, 0);
      expect(summary.outstandingPaise, 0);
      expect(summary.purchaseCount, 0);
      expect(summary.paymentCount, 0);
    });

    test('rejects unknown customers', () async {
      await expectLater(
        repository.summary('missing'),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
    });
  });

  group('outstandingForCustomer', () {
    test('returns exact remaining balance and zero after settlement', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );

      expect(await repository.outstandingForCustomer('c1'), 50000);
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 20000,
        paymentMethod: PaymentMethod.cash,
      );
      expect(await repository.outstandingForCustomer('c1'), 30000);
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 30000,
        paymentMethod: PaymentMethod.cash,
      );
      expect(await repository.outstandingForCustomer('c1'), 0);
    });

    test('rejects unknown customers', () async {
      await expectLater(
        repository.outstandingForCustomer('missing'),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
    });
  });

  group('dueCustomersSummary', () {
    test('counts only customers with outstanding balances', () async {
      await seedCustomer('c1');
      await seedCustomer('c2');
      await seedCustomer('c3');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 30000,
      );
      await seedSale(
        id: 's3',
        customerId: 'c2',
        receiptNumber: 'BF-000003',
        totalPaise: 20000,
      );
      // c3 has no sales at all and c2 is fully paid later.
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.cash,
      );

      final summary = await repository.dueCustomersSummary();
      expect(summary.dueCustomerCount, 2);
      expect(summary.totalOutstandingPaise, 50000);
    });

    test('returns zeros when every customer has settled', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 40000,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 40000,
        paymentMethod: PaymentMethod.cash,
      );

      final summary = await repository.dueCustomersSummary();
      expect(summary.dueCustomerCount, 0);
      expect(summary.totalOutstandingPaise, 0);
    });

    test('ignores walk-in sales', () async {
      await seedCustomer('c1');
      await database
          .into(database.sales)
          .insert(
            SalesCompanion.insert(
              id: const Value('s1'),
              receiptNumber: 'BF-000001',
              subtotalPaise: 50000,
              totalPaise: 50000,
              paymentMethod: Value('CASH'),
            ),
          );

      final summary = await repository.dueCustomersSummary();
      expect(summary.dueCustomerCount, 0);
      expect(summary.totalOutstandingPaise, 0);
    });
  });

  group('deactivated customers', () {
    test(
      'a deactivated customer can still settle their outstanding dues',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 50000,
        );
        await (database.update(database.customers)
              ..where((table) => table.id.equals('c1')))
            .write(const CustomersCompanion(isActive: Value(false)));

        final payment = await repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 20000,
          paymentMethod: PaymentMethod.cash,
        );

        expect(payment.customerId, 'c1');
        final summary = await repository.summary('c1');
        expect(summary.outstandingPaise, 30000);
        expect(
          (await repository.purchases('c1')).single.status,
          SalePaymentStatus.partial,
        );
      },
    );

    test(
      'deactivated customers with dues still appear in the due summary',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 50000,
        );
        await (database.update(database.customers)
              ..where((table) => table.id.equals('c1')))
            .write(const CustomersCompanion(isActive: Value(false)));

        final summary = await repository.dueCustomersSummary();
        expect(summary.dueCustomerCount, 1);
        expect(summary.totalOutstandingPaise, 50000);
      },
    );

    test('deactivation does not erase ledger history', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.cash,
      );
      await (database.update(database.customers)
            ..where((table) => table.id.equals('c1')))
          .write(const CustomersCompanion(isActive: Value(false)));

      final purchases = await repository.purchases('c1');
      expect(purchases.single.status, SalePaymentStatus.paid);
      expect((await repository.summary('c1')).outstandingPaise, 0);
      expect((await repository.payments('c1')), hasLength(1));
    });
  });

  group('payment status consistency', () {
    test(
      'fully settling a NOT_PAID sale flips payment_status to PAID',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 50000,
          paymentStatus: 'NOT_PAID',
        );

        // Confirm initial state.
        final before = await (database.select(
          database.sales,
        )..where((t) => t.id.equals('s1'))).getSingle();
        expect(before.paymentStatus, 'NOT_PAID');

        await repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 50000,
          paymentMethod: PaymentMethod.upi,
        );

        final after = await (database.select(
          database.sales,
        )..where((t) => t.id.equals('s1'))).getSingle();
        expect(after.paymentStatus, 'PAID');
        expect(after.paymentMethod, 'UPI');
      },
    );

    test('a partial payment does NOT flip payment_status', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
        paymentStatus: 'NOT_PAID',
      );

      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 20000,
        paymentMethod: PaymentMethod.cash,
      );

      final sale = await (database.select(
        database.sales,
      )..where((t) => t.id.equals('s1'))).getSingle();
      expect(sale.paymentStatus, 'NOT_PAID');
    });

    test('receipt number is preserved after payment', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
        paymentStatus: 'NOT_PAID',
      );

      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.cash,
      );

      final sale = await (database.select(
        database.sales,
      )..where((t) => t.id.equals('s1'))).getSingle();
      expect(sale.receiptNumber, 'BF-000001');
    });

    test('two rapid payments cannot both succeed (race-safe guard)', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 50000,
        paymentStatus: 'NOT_PAID',
      );

      // Simulate near-simultaneous payments by running them sequentially
      // without checking intermediate state — the SQL guard must reject.
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 40000,
        paymentMethod: PaymentMethod.cash,
      );
      await expectLater(
        repository.recordPayment(
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 40000,
          paymentMethod: PaymentMethod.upi,
        ),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
      expect(await countPayments(), 1);
    });
  });
}
