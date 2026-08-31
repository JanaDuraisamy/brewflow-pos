import 'package:brewflow_pos/core/database/app_database.dart'
    hide CustomerPayment;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Concurrency tests for the ledger payment guard against a real in-memory
/// Drift database. The remaining-due guard is re-evaluated by SQLite at write
/// time, so racing payments serialize: exactly as much is paid as the sale
/// allows, with no lost updates and no overpayment.
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
    required int totalPaise,
  }) async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.sales)
        .insert(
          SalesCompanion.insert(
            id: Value(id),
            receiptNumber: 'BF-000001',
            customerId: Value(customerId),
            subtotalPaise: totalPaise,
            totalPaise: totalPaise,
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

  Future<int> totalPaid(String saleId) async {
    final query = database.selectOnly(database.customerPayments)
      ..addColumns([database.customerPayments.amountPaise.sum()])
      ..where(database.customerPayments.saleId.equals(saleId));
    return (await query.getSingle()).read(
      database.customerPayments.amountPaise.sum(),
    )!;
  }

  test('concurrent full payments cannot overpay a sale', () async {
    await seedCustomer('c1');
    final saleId = await seedSale(id: 's1', customerId: 'c1', totalPaise: 5000);

    final outcomes = await Future.wait<Object?>([
      repository
          .recordPayment(
            customerId: 'c1',
            saleId: saleId,
            amountPaise: 5000,
            paymentMethod: PaymentMethod.cash,
          )
          .then<Object?>((payment) => payment)
          .catchError((Object error) => error),
      repository
          .recordPayment(
            customerId: 'c1',
            saleId: saleId,
            amountPaise: 5000,
            paymentMethod: PaymentMethod.upi,
          )
          .then<Object?>((payment) => payment)
          .catchError((Object error) => error),
    ]);

    final successes = outcomes.whereType<CustomerPayment>().toList();
    final failures = outcomes.whereType<CustomerLedgerFailure>().toList();
    expect(successes, hasLength(1));
    expect(failures, hasLength(1));
    expect(failures.single, isA<PaymentExceedsDueFailure>());

    expect(await countPayments(), 1);
    expect(await totalPaid(saleId), 5000);
  });

  test(
    'concurrent partial payments are additive with no lost updates',
    () async {
      await seedCustomer('c1');
      final saleId = await seedSale(
        id: 's1',
        customerId: 'c1',
        totalPaise: 5000,
      );

      final outcomes = await Future.wait<Object?>([
        repository
            .recordPayment(
              customerId: 'c1',
              saleId: saleId,
              amountPaise: 2000,
              paymentMethod: PaymentMethod.cash,
            )
            .then<Object?>((payment) => payment)
            .catchError((Object error) => error),
        repository
            .recordPayment(
              customerId: 'c1',
              saleId: saleId,
              amountPaise: 2000,
              paymentMethod: PaymentMethod.cash,
            )
            .then<Object?>((payment) => payment)
            .catchError((Object error) => error),
      ]);

      expect(outcomes.whereType<CustomerPayment>(), hasLength(2));
      expect(await countPayments(), 2);
      expect(await totalPaid(saleId), 4000);
    },
  );
}
