import 'package:brewflow_pos/core/database/app_database.dart'
    hide CustomerPayment;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/orders/data/orders_dao.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
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
    bool voided = false,
    String? shopId,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc();
    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            receiptNumber: receiptNumber,
            customerId: Value(customerId),
            subtotalPaise: totalPaise,
            totalPaise: totalPaise,
            paymentStatus: Value(paymentStatus),
            paymentMethod: Value('CASH'),
            createdAt: Value(now),
            updatedAt: Value(now),
            voided: Value(voided),
            voidedAt: voided ? Value(now) : const Value(null),
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

    test('excludes voided sales so they are never shown as due', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 18700,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 4500,
        voided: true,
      );

      final purchases = await repository.purchases('c1');
      expect(purchases.map((p) => p.saleId), ['s1']);
      expect(purchases.single.duePaise, 18700);
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

    test('excludes voided NOT_PAID sales from purchases, payments and '
        'outstanding', () async {
      await seedCustomer('c1');
      // The reported bug: a NOT_PAID sale that was afterwards voided still
      // showed up in the UI total (₹187 + ₹45 = ₹232 outstanding) even though
      // the collection RPC only ever aggregates `voided = false`, so a genuine
      // ₹20 payment was rejected against a balance the device could not see.
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 18700,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 4500,
        voided: true,
      );

      final summary = await repository.summary('c1');
      expect(summary.totalPurchasesPaise, 18700);
      expect(summary.totalPaidPaise, 0);
      expect(summary.outstandingPaise, 18700);
      expect(summary.purchaseCount, 1);
      expect(summary.paymentCount, 0);
      expect(await repository.outstandingForCustomer('c1'), 18700);
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

    test('excludes voided sales from the due totals', () async {
      await seedCustomer('c1');
      await seedCustomer('c2');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 4500,
        voided: true,
      );
      await seedSale(
        id: 's2',
        customerId: 'c2',
        receiptNumber: 'BF-000002',
        totalPaise: 50000,
      );

      final summary = await repository.dueCustomersSummary();
      expect(summary.dueCustomerCount, 1);
      expect(summary.totalOutstandingPaise, 50000);
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

  group('collectCustomerPayment', () {
    Future<List<CustomerPayment>> collect({
      required String customerId,
      required String paymentGroupId,
      required int amountPaise,
      PaymentMethod paymentMethod = PaymentMethod.cash,
      String? note,
    }) => repository.collectCustomerPayment(
      customerId: customerId,
      paymentGroupId: paymentGroupId,
      amountPaise: amountPaise,
      paymentMethod: paymentMethod,
      note: note,
    );

    Future<String> saleStatus(String saleId) async {
      final sale = await (database.select(
        database.sales,
      )..where((t) => t.id.equals(saleId))).getSingle();
      return sale.paymentStatus;
    }

    test(
      'allocates across the oldest open bills first, stamping every row',
      () async {
        final old = DateTime.now().toUtc().subtract(const Duration(days: 3));
        final recent = DateTime.now().toUtc().subtract(const Duration(days: 1));
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 10000,
          createdAt: old,
        );
        await seedSale(
          id: 's2',
          customerId: 'c1',
          receiptNumber: 'BF-000002',
          totalPaise: 10000,
          createdAt: recent,
        );

        final payments = await collect(
          customerId: 'c1',
          paymentGroupId: 'group-1',
          amountPaise: 15000,
          paymentMethod: PaymentMethod.upi,
          note: '  Instalment  ',
        );

        // Oldest bill first: s1 fully cleared (100.00), s2 partially (50.00).
        expect(payments, hasLength(2));
        expect(payments.map((p) => p.saleId).toList(), ['s1', 's2']);
        expect(payments.map((p) => p.amountPaise).toList(), [10000, 5000]);
        expect(payments.every((p) => p.paymentGroupId == 'group-1'), isTrue);
        expect(
          payments.every((p) => p.paymentMethod == PaymentMethod.upi),
          isTrue,
        );
        expect(payments.every((p) => p.note == 'Instalment'), isTrue);
        expect(payments.every((p) => p.paidAt.isUtc), isTrue);
        // The fully cleared oldest bill is flipped to PAID in the same
        // transaction; the partially paid newer bill stays open.
        expect(await saleStatus('s1'), 'PAID');
        expect(await saleStatus('s2'), 'NOT_PAID');
      },
    );

    test('leaves newer bills untouched when the walk covers the due', () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 3));
      final recent = DateTime.now().toUtc().subtract(const Duration(days: 1));
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 10000,
        createdAt: old,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 10000,
        createdAt: recent,
      );

      final payments = await collect(
        customerId: 'c1',
        paymentGroupId: 'group-1',
        amountPaise: 6000,
      );

      expect(payments, hasLength(1));
      expect(payments.single.saleId, 's1');
      expect(payments.single.amountPaise, 6000);
      expect(await saleStatus('s1'), 'NOT_PAID');
      expect(await saleStatus('s2'), 'NOT_PAID');
    });

    test(
      'rejects an amount above the total outstanding, writing nothing',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 10000,
        );

        await expectLater(
          collect(
            customerId: 'c1',
            paymentGroupId: 'group-1',
            amountPaise: 10001,
          ),
          throwsA(isA<PaymentExceedsDueFailure>()),
        );
        expect(await countPayments(), 0);
        expect(await saleStatus('s1'), 'NOT_PAID');
      },
    );

    test('accepts a payment genuinely within the applicable outstanding even '
        'when another open bill is voided', () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 3));
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 18700,
        createdAt: old,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 4500,
        voided: true,
      );

      // Reported bug: ₹232 shown overall (₹187 open + ₹45 voided), a ₹20
      // payment rejected because the voided bill is not collectible. The
      // real applicable outstanding is ₹187, so ₹20 must go through (while
      // the server only ever sees `voided = false` sales).
      final payments = await collect(
        customerId: 'c1',
        paymentGroupId: 'group-1',
        amountPaise: 2000,
      );

      expect(payments, hasLength(1));
      expect(payments.single.saleId, 's1');
      expect(payments.single.amountPaise, 2000);
      expect(await saleStatus('s1'), 'NOT_PAID');
    });

    test('accepts a payment strictly below a partially-paid sale remaining, '
        'allocating only the entered amount to that sale', () async {
      await seedCustomer('c1');
      // Reported physical-bug numbers: sale total ₹232, already ₹45 paid,
      // remaining ₹187. A ₹20 collection must go through and touch the
      // partially-paid sale itself (never against its full total).
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 23200,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 4500,
        paymentMethod: PaymentMethod.cash,
      );
      expect((await repository.purchases('c1')).single.duePaise, 18700);

      final payments = await collect(
        customerId: 'c1',
        paymentGroupId: 'group-1',
        amountPaise: 2000,
      );

      expect(payments, hasLength(1));
      expect(payments.single.saleId, 's1');
      expect(payments.single.amountPaise, 2000);
      expect(await saleStatus('s1'), 'NOT_PAID');
      expect(await repository.outstandingForCustomer('c1'), 16700);
    });

    test('rejects an actual overpayment above a partially-paid sale remaining, '
        'writing nothing', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 23200,
      );
      await repository.recordPayment(
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 4500,
        paymentMethod: PaymentMethod.cash,
      );

      // Remaining is ₹187; a collection of ₹200 overpays the only open bill.
      await expectLater(
        collect(
          customerId: 'c1',
          paymentGroupId: 'group-1',
          amountPaise: 20000,
        ),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
      expect(await countPayments(), 1);
      expect(await saleStatus('s1'), 'NOT_PAID');
      expect(await repository.outstandingForCustomer('c1'), 18700);
    });

    test('rejects a payment when only voided NOT_PAID bills remain, writing '
        'nothing', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 18700,
        voided: true,
      );
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 4500,
        voided: true,
      );

      // 100% voided open bills: the UI used to fabricate ₹232 outstanding
      // from them while the RPC computes zero — a ₹20 payment was rejected
      // as "more than the remaining balance". With the client fix the
      // summary reads zero and collection rejects up front, matching the
      // RPC instead of surfacing a phantom balance.
      final summary = await repository.summary('c1');
      expect(summary.totalPurchasesPaise, 0);
      expect(summary.outstandingPaise, 0);

      await expectLater(
        collect(customerId: 'c1', paymentGroupId: 'group-1', amountPaise: 2000),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
      expect(await countPayments(), 0);
      expect(await saleStatus('s1'), 'NOT_PAID');
      expect(await saleStatus('s2'), 'NOT_PAID');
    });

    test('rejects an unknown customer, writing nothing', () async {
      await expectLater(
        collect(
          customerId: 'ghost',
          paymentGroupId: 'group-1',
          amountPaise: 1000,
        ),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('rejects zero and negative amounts, writing nothing', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 10000,
      );

      await expectLater(
        collect(customerId: 'c1', paymentGroupId: 'group-1', amountPaise: 0),
        throwsA(isA<InvalidPaymentAmountFailure>()),
      );
      await expectLater(
        collect(customerId: 'c1', paymentGroupId: 'group-1', amountPaise: -5),
        throwsA(isA<InvalidPaymentAmountFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test('rejects a collection when no outstanding bills exist', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 10000,
        paymentStatus: 'PAID',
      );

      await expectLater(
        collect(customerId: 'c1', paymentGroupId: 'group-1', amountPaise: 1000),
        throwsA(isA<PaymentExceedsDueFailure>()),
      );
      expect(await countPayments(), 0);
    });

    test(
      'replaying the same group is a no-op (idempotent, never doubles)',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 10000,
        );

        final first = await collect(
          customerId: 'c1',
          paymentGroupId: 'group-1',
          amountPaise: 10000,
        );
        final second = await collect(
          customerId: 'c1',
          paymentGroupId: 'group-1',
          amountPaise: 10000,
        );

        expect(first, hasLength(1));
        expect(second, hasLength(1));
        expect(second.single.id, first.single.id);
        expect(await countPayments(), 1);
        expect(await saleStatus('s1'), 'PAID');
      },
    );
  });

  group('receivables', () {
    Future<void> seedCustomerWithName(String id, String name) async {
      await database
          .into(database.customers)
          .insert(CustomersCompanion.insert(id: Value(id), name: name));
    }

    /// `sales.shop_id` is a real foreign key, so any shop-scoped fixture has
    /// to create the shop rows first.
    Future<void> seedShops(List<String> ids) async {
      for (final id in ids) {
        await database
            .into(database.shops)
            .insert(
              ShopsCompanion.insert(
                id: Value(id),
                name: 'Shop $id',
                createdAt: Value(DateTime.utc(2026, 1, 1)),
                updatedAt: Value(DateTime.utc(2026, 1, 1)),
              ),
            );
      }
    }

    test(
      'surfaces only open sales with oldest-bill drill-down and name order',
      () async {
        final old = DateTime.now().toUtc().subtract(const Duration(days: 3));
        final recent = DateTime.now().toUtc().subtract(const Duration(days: 1));
        await seedCustomerWithName('c1', 'Priya');
        await seedCustomerWithName('c2', 'Arun');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000001',
          totalPaise: 10000,
          createdAt: old,
        );
        await seedSale(
          id: 's2',
          customerId: 'c1',
          receiptNumber: 'BF-000002',
          totalPaise: 10000,
          createdAt: recent,
        );
        await seedSale(
          id: 's3',
          customerId: 'c2',
          receiptNumber: 'BF-000003',
          totalPaise: 5000,
          createdAt: old,
        );

        final receivables = await repository.receivables();

        expect(receivables, hasLength(2));
        // Customers ordered by name: Arun first, Priya last.
        expect(receivables.map((r) => r.customerName).toList(), [
          'Arun',
          'Priya',
        ]);
        final priya = receivables.firstWhere((r) => r.customerId == 'c1');
        expect(priya.outstandingBillCount, 2);
        expect(priya.totalDuePaise, 20000);
        expect(priya.bills.map((b) => b.saleId).toList(), ['s1', 's2']);
        expect(priya.bills.first.duePaise, 10000);
        final arun = receivables.firstWhere((r) => r.customerId == 'c2');
        expect(arun.outstandingBillCount, 1);
        expect(arun.totalDuePaise, 5000);
        expect(arun.bills.single.saleId, 's3');
      },
    );

    test('a date range bounds which bills count as receivable', () async {
      // Regression: the Reports Customer Receivables card showed the
      // all-time balance inside a date-scoped report. The DAO now filters
      // candidate bills by the range on the bill's own createdAt.
      final now = DateTime.now().toUtc();
      await seedCustomerWithName('c1', 'Priya');
      await seedShops(const ['shop-1']);
      await seedSale(
        id: 'today',
        customerId: 'c1',
        receiptNumber: 'BF-T',
        totalPaise: 7000,
        createdAt: now,
        shopId: 'shop-1',
      );
      await seedSale(
        id: 'yesterday',
        customerId: 'c1',
        receiptNumber: 'BF-Y',
        totalPaise: 9000,
        createdAt: now.subtract(const Duration(days: 1)),
        shopId: 'shop-1',
      );
      await seedSale(
        id: 'lastWeek',
        customerId: 'c1',
        receiptNumber: 'BF-W',
        totalPaise: 11000,
        createdAt: now.subtract(const Duration(days: 6)),
        shopId: 'shop-1',
      );
      await seedSale(
        id: 'ancient',
        customerId: 'c1',
        receiptNumber: 'BF-A',
        totalPaise: 13000,
        createdAt: now.subtract(const Duration(days: 10)),
        shopId: 'shop-1',
      );

      // Unbounded: the all-time reading is still available.
      final all = await repository.receivables(shopIds: ['shop-1']);
      expect(all.single.totalDuePaise, 40000);
      expect(all.single.outstandingBillCount, 4);

      // Today only: the three historical bills must not appear.
      final local = DateTime.now();
      final todayStart = DateTime(local.year, local.month, local.day);
      final todayEnd = todayStart
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1));
      final onlyToday = await repository.receivables(
        shopIds: ['shop-1'],
        fromUtc: todayStart.toUtc(),
        toUtc: todayEnd.toUtc(),
      );
      expect(onlyToday.single.totalDuePaise, 7000);
      expect(onlyToday.single.outstandingBillCount, 1);
      expect(onlyToday.single.bills.single.saleId, 'today');

      // Last 7 days: today + yesterday + 6-days-ago, but not 10-days-ago.
      final weekStart = todayStart.subtract(const Duration(days: 6));
      final last7 = await repository.receivables(
        shopIds: ['shop-1'],
        fromUtc: weekStart.toUtc(),
        toUtc: todayEnd.toUtc(),
      );
      expect(last7.single.totalDuePaise, 27000);
      expect(last7.single.outstandingBillCount, 3);
      expect(last7.single.bills.map((b) => b.saleId), [
        'lastWeek',
        'yesterday',
        'today',
      ]);
    });

    test('a range never leaks another shop\'s credit', () async {
      // Shop isolation must hold inside the range too: a Food Truck credit
      // bill must not appear in a Cafe-scoped report.
      final now = DateTime.now().toUtc();
      await seedCustomerWithName('c1', 'Priya');
      await seedShops(const ['cafe-shop', 'truck-shop']);
      await seedSale(
        id: 'cafe',
        customerId: 'c1',
        receiptNumber: 'BF-C',
        totalPaise: 5000,
        createdAt: now,
        shopId: 'cafe-shop',
      );
      await seedSale(
        id: 'truck',
        customerId: 'c1',
        receiptNumber: 'BF-T',
        totalPaise: 60000,
        createdAt: now,
        shopId: 'truck-shop',
      );

      final cafe = await repository.receivables(shopIds: ['cafe-shop']);
      expect(cafe.single.totalDuePaise, 5000);
      expect(cafe.single.bills.single.saleId, 'cafe');

      final truck = await repository.receivables(shopIds: ['truck-shop']);
      expect(truck.single.totalDuePaise, 60000);
      expect(truck.single.bills.single.saleId, 'truck');

      // Both businesses together stay separated per bill, never merged into
      // one invented balance row.
      final combined = await repository.receivables(
        shopIds: ['cafe-shop', 'truck-shop'],
      );
      expect(combined, hasLength(1));
      expect(combined.single.totalDuePaise, 65000);
      expect(combined.single.bills.map((b) => b.saleId).toList(), [
        'cafe',
        'truck',
      ]);
    });

    test('a part-collected in-range bill shows only what is left', () async {
      final now = DateTime.now().toUtc();
      await seedCustomerWithName('c1', 'Priya');
      await seedShops(const ['shop-1']);
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-1',
        totalPaise: 10000,
        createdAt: now,
        shopId: 'shop-1',
      );
      await database
          .into(database.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: const Value('p1'),
              customerId: 'c1',
              saleId: const Value('s1'),
              amountPaise: 4000,
              paymentMethod: 'CASH',
              paidAt: now,
              reversed: const Value(false),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      final receivables = await repository.receivables(
        shopIds: ['shop-1'],
        fromUtc: now.subtract(const Duration(hours: 1)),
        toUtc: now.add(const Duration(hours: 1)),
      );
      expect(receivables.single.totalDuePaise, 6000);
      expect(receivables.single.outstandingBillCount, 1);
    });
  });

  group('outstandingAsOf', () {
    Future<void> seedCustomerProfile(
      String id, {
      required String name,
      String? phone,
    }) async {
      await database
          .into(database.customers)
          .insert(
            CustomersCompanion.insert(
              id: Value(id),
              name: name,
              phone: Value(phone),
            ),
          );
    }

    Future<void> seedShop(String id) async {
      await database
          .into(database.shops)
          .insert(ShopsCompanion.insert(id: Value(id), name: 'Shop $id'));
    }

    Future<void> seedPayment({
      required String id,
      required String customerId,
      required String saleId,
      required int amountPaise,
      required DateTime paidAt,
    }) async {
      await database
          .into(database.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: Value(id),
              customerId: customerId,
              saleId: Value(saleId),
              amountPaise: amountPaise,
              paymentMethod: 'CASH',
              paidAt: paidAt,
              reversed: const Value(false),
              createdAt: Value(paidAt),
              updatedAt: Value(paidAt),
            ),
          );
    }

    final toUtc = DateTime.utc(2026, 2, 28, 23, 59, 59, 999999);

    test('snapshots balances as of the date with name and phone', () async {
      await seedCustomerProfile('c1', name: 'Priya', phone: '9812345678');
      await seedCustomerProfile('c2', name: 'Arun');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 30000,
        createdAt: DateTime.utc(2026, 2, 10),
      );
      await seedPayment(
        id: 'p1',
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 10000,
        paidAt: DateTime.utc(2026, 2, 15),
      );
      // Created after the snapshot date: must not count.
      await seedSale(
        id: 's2',
        customerId: 'c1',
        receiptNumber: 'BF-000002',
        totalPaise: 90000,
        createdAt: DateTime.utc(2026, 3, 5),
      );
      await seedSale(
        id: 's3',
        customerId: 'c2',
        receiptNumber: 'BF-000003',
        totalPaise: 5000,
        createdAt: DateTime.utc(2026, 2, 20),
      );

      final rows = await repository.outstandingAsOf(toUtc: toUtc);

      expect([for (final row in rows) row.customerName], ['Arun', 'Priya']);
      expect(rows[0].phone, isNull);
      expect(rows[0].outstandingPaise, 5000);
      expect(rows[1].phone, '9812345678');
      expect(rows[1].outstandingPaise, 20000);
    });

    test(
      'ignores after-date payments, counter-paid sales, and zero balances',
      () async {
        await seedCustomerProfile('c1', name: 'Meena');
        await seedCustomerProfile('c2', name: 'Kavya');
        await seedCustomerProfile('c3', name: 'Ravi');
        // Open bill whose only payment landed AFTER the snapshot date: the
        // whole balance stays.
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000101',
          totalPaise: 10000,
          createdAt: DateTime.utc(2026, 2, 10),
        );
        await seedPayment(
          id: 'p1',
          customerId: 'c1',
          saleId: 's1',
          amountPaise: 4000,
          paidAt: DateTime.utc(2026, 3, 1, 9),
        );
        // Counter-paid sale (PAID, no payment rows): never generates due.
        await seedSale(
          id: 's2',
          customerId: 'c1',
          receiptNumber: 'BF-000102',
          totalPaise: 8000,
          createdAt: DateTime.utc(2026, 2, 12),
          paymentStatus: 'PAID',
        );
        // Bill fully settled before the snapshot date: zero, dropped.
        await seedSale(
          id: 's3',
          customerId: 'c2',
          receiptNumber: 'BF-000103',
          totalPaise: 7000,
          createdAt: DateTime.utc(2026, 2, 10),
        );
        await seedPayment(
          id: 'p2',
          customerId: 'c2',
          saleId: 's3',
          amountPaise: 3000,
          paidAt: DateTime.utc(2026, 2, 25),
        );
        // Credit bill collected in FULL AFTER the snapshot date (PAID with
        // payment rows): keeps its whole as-of-date balance.
        await seedSale(
          id: 's4',
          customerId: 'c3',
          receiptNumber: 'BF-000104',
          totalPaise: 5000,
          createdAt: DateTime.utc(2026, 2, 15),
          paymentStatus: 'PAID',
        );
        await seedPayment(
          id: 'p3',
          customerId: 'c3',
          saleId: 's4',
          amountPaise: 5000,
          paidAt: DateTime.utc(2026, 3, 2, 10),
        );

        final rows = await repository.outstandingAsOf(toUtc: toUtc);

        expect(
          [for (final row in rows) row.customerName],
          ['Kavya', 'Meena', 'Ravi'],
        );
        expect(rows[0].outstandingPaise, 4000);
        expect(rows[1].outstandingPaise, 10000);
        expect(rows[2].outstandingPaise, 5000);
      },
    );

    test('restricts the scan to the given shops', () async {
      await seedShop('shop-1');
      await seedShop('shop-2');
      await seedCustomerProfile('c1', name: 'Shop A Customer');
      await seedCustomerProfile('c2', name: 'Shop B Customer');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000201',
        totalPaise: 10000,
        createdAt: DateTime.utc(2026, 2, 5),
        shopId: 'shop-1',
      );
      await seedSale(
        id: 's2',
        customerId: 'c2',
        receiptNumber: 'BF-000202',
        totalPaise: 40000,
        createdAt: DateTime.utc(2026, 2, 5),
        shopId: 'shop-2',
      );

      final scoped = await repository.outstandingAsOf(
        toUtc: toUtc,
        shopIds: ['shop-1'],
      );
      expect(scoped, hasLength(1));
      expect(scoped.single.customerName, 'Shop A Customer');

      final all = await repository.outstandingAsOf(toUtc: toUtc);
      expect(all, hasLength(2));
    });
  });

  group('recordOpeningDue', () {
    Future<int> countSales() async {
      final query = database.selectOnly(database.sales)
        ..addColumns([database.sales.id.count()]);
      return query
          .map((row) => row.read(database.sales.id.count())!)
          .getSingle();
    }

    Future<int> countSaleItems() async {
      final query = database.selectOnly(database.saleItems)
        ..addColumns([database.saleItems.id.count()]);
      return query
          .map((row) => row.read(database.saleItems.id.count())!)
          .getSingle();
    }

    test(
      'creates a flagged NOT_PAID ledger entry with no sale items',
      () async {
        await seedCustomer('c1');

        await repository.recordOpeningDue(customerId: 'c1', amountPaise: 45000);

        final sale = await (database.select(
          database.sales,
        )..where((t) => t.customerId.equals('c1'))).getSingle();
        expect(sale.isOpeningBalance, isTrue);
        expect(sale.paymentStatus, 'NOT_PAID');
        expect(sale.paymentMethod, isNull);
        expect(sale.totalPaise, 45000);
        expect(sale.subtotalPaise, 45000);
        expect(sale.voided, isFalse);
        expect(sale.receiptNumber, startsWith('BF-'));
        expect(sale.shopId, isNotEmpty);
        expect(await countSales(), 1);
        // Ledger-only: opening balances never touch stock lines.
        expect(await countSaleItems(), 0);
      },
    );

    test('rejects zero and negative amounts without writing', () async {
      await seedCustomer('c1');

      await expectLater(
        repository.recordOpeningDue(customerId: 'c1', amountPaise: 0),
        throwsA(isA<InvalidPaymentAmountFailure>()),
      );
      await expectLater(
        repository.recordOpeningDue(customerId: 'c1', amountPaise: -100),
        throwsA(isA<InvalidPaymentAmountFailure>()),
      );
      expect(await countSales(), 0);
    });

    test('rejects an unknown customer without writing', () async {
      await expectLater(
        repository.recordOpeningDue(customerId: 'ghost', amountPaise: 1000),
        throwsA(isA<CustomerNotFoundFailure>()),
      );
      expect(await countSales(), 0);
    });

    test(
      'a deleted customer\'s unpaid bills stay collectible and are labelled',
      () async {
        // The customer is deleted for real (schema v25 -> v26), but the money
        // they owe does not evaporate with them: the sale keeps `customer_id`
        // and the receivable must still show up, or the owner silently loses
        // track of real debt the moment a customer is removed.
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000006',
          totalPaise: 25000,
        );

        await (database.delete(
          database.customers,
        )..where((t) => t.id.equals('c1'))).go();

        final receivables = await repository.receivables();
        final ghost = receivables.single;
        expect(ghost.customerId, 'c1');
        expect(ghost.totalDuePaise, 25000);
        expect(ghost.outstandingBillCount, 1);
        // Named for what happened, not as a generic blank-name customer.
        expect(ghost.customerName, 'Deleted customer');
        expect(ghost.bills.single.receiptNumber, 'BF-000006');

        // The due totals agree, so the summary is not quietly dropping the debt.
        final dues = await repository.dueCustomersSummary();
        expect(dues.dueCustomerCount, 1);
        expect(dues.totalOutstandingPaise, 25000);
      },
    );

    test(
      'counts toward summary, outstanding, due summary and receivables',
      () async {
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000005',
          totalPaise: 10000,
        );
        await repository.recordOpeningDue(customerId: 'c1', amountPaise: 45000);

        final summary = await repository.summary('c1');
        expect(summary.totalPurchasesPaise, 55000);
        expect(summary.outstandingPaise, 55000);
        expect(await repository.outstandingForCustomer('c1'), 55000);

        final dues = await repository.dueCustomersSummary();
        expect(dues.dueCustomerCount, 1);
        expect(dues.totalOutstandingPaise, 55000);

        final receivables = await repository.receivables();
        final c1 = receivables.single;
        expect(c1.totalDuePaise, 55000);
        expect(c1.outstandingBillCount, 2);
        final openingBill = c1.bills.firstWhere((b) => b.isOpeningBalance);
        expect(openingBill.duePaise, 45000);
        expect(
          c1.bills.where((b) => b.isOpeningBalance).length,
          1,
          reason: 'exactly one bill is the opening entry',
        );
      },
    );

    test(
      'shows as an opening purchase and is paid down by collections',
      () async {
        await seedCustomer('c1');
        await repository.recordOpeningDue(customerId: 'c1', amountPaise: 45000);

        final opening = (await repository.purchases('c1')).single;
        expect(opening.isOpeningBalance, isTrue);
        expect(opening.status, SalePaymentStatus.unpaid);
        expect(opening.duePaise, 45000);

        final first = await repository.collectCustomerPayment(
          customerId: 'c1',
          paymentGroupId: 'group-1',
          amountPaise: 20000,
          paymentMethod: PaymentMethod.cash,
        );
        expect(first.single.amountPaise, 20000);
        expect((await repository.purchases('c1')).single.duePaise, 25000);
        expect(await repository.outstandingForCustomer('c1'), 25000);

        await repository.collectCustomerPayment(
          customerId: 'c1',
          paymentGroupId: 'group-2',
          amountPaise: 25000,
          paymentMethod: PaymentMethod.upi,
        );
        expect(await repository.outstandingForCustomer('c1'), 0);
        final settled = (await repository.purchases('c1')).single;
        expect(settled.status, SalePaymentStatus.paid);
        expect(settled.isOpeningBalance, isTrue);
        expect((await repository.summary('c1')).outstandingPaise, 0);
        expect(await repository.receivables(), isEmpty);
        expect((await repository.dueCustomersSummary()).dueCustomerCount, 0);
      },
    );

    test(
      'generates sequential receipt numbers distinct from existing sales',
      () async {
        await database
            .into(database.shops)
            .insert(
              ShopsCompanion.insert(id: const Value('shop-1'), name: 'Cafe 1'),
            );
        await seedCustomer('c1');
        await seedSale(
          id: 's1',
          customerId: 'c1',
          receiptNumber: 'BF-000007',
          totalPaise: 10000,
          shopId: 'shop-1',
        );

        await repository.recordOpeningDue(
          customerId: 'c1',
          amountPaise: 1000,
          shopId: 'shop-1',
        );
        await repository.recordOpeningDue(
          customerId: 'c1',
          amountPaise: 2000,
          shopId: 'shop-1',
        );

        final openings =
            await (database.select(database.sales)
                  ..where((t) => t.isOpeningBalance.equals(true))
                  ..orderBy([(t) => OrderingTerm.asc(t.receiptNumber)]))
                .get();
        expect(openings.map((s) => s.receiptNumber).toList(), [
          'BF-000008',
          'BF-000009',
        ]);
        final seeded = await (database.select(
          database.sales,
        )..where((t) => t.id.equals('s1'))).getSingle();
        expect(seeded.receiptNumber, 'BF-000007');
      },
    );

    test('never surfaces in the orders list or order detail', () async {
      await seedCustomer('c1');
      await seedSale(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        totalPaise: 10000,
      );
      await repository.recordOpeningDue(customerId: 'c1', amountPaise: 45000);

      final orders = OrdersDao(database);
      final page = await orders.salesPage();
      expect(page.map((s) => s.id).toList(), ['s1']);

      final opening = await (database.select(
        database.sales,
      )..where((t) => t.isOpeningBalance.equals(true))).getSingle();
      expect(await orders.saleById(opening.id), isNull);
      expect(await orders.saleById('s1'), isNotNull);
    });
  });
}
