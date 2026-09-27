import 'package:brewflow_pos/core/database/app_database.dart'
    show AppDatabase, ShopsCompanion;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shop payable tests against a real in-memory Drift database: the grouping
/// SQL, the derived balance arithmetic and the payment CHECK constraints all
/// behave exactly like production.
void main() {
  late AppDatabase database;
  late DriftExpensesRepository repository;

  const cafe = 'cafe-1';
  const foodTruck = 'food-truck-1';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftExpensesRepository(database);
    await database
        .into(database.shops)
        .insert(ShopsCompanion.insert(id: Value(cafe), name: 'Cafe'));
    await database
        .into(database.shops)
        .insert(
          ShopsCompanion.insert(id: Value(foodTruck), name: 'Food Truck'),
        );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Expense> unpaid(
    String name,
    int amountPaise, {
    String shopId = cafe,
    DateTime? date,
  }) => repository.createExpense(
    name: name,
    amountPaise: amountPaise,
    category: ExpenseCategory.supplies,
    paymentMethod: PaymentMethod.cash,
    expenseDate: date ?? DateTime.utc(2026, 8, 10),
    paymentStatus: ExpensePaymentStatus.notPaid,
    shopId: shopId,
  );

  group('grouping', () {
    test(
      'two same-named unpaid expenses become one payable of the summed total',
      () async {
        await unpaid('Milk', 70000);
        await unpaid('Milk', 90000);

        final payables = await repository.shopPayables();

        expect(payables, hasLength(1));
        expect(payables.single.payeeName, 'Milk');
        expect(payables.single.totalPaise, 160000);
        expect(payables.single.paidPaise, 0);
        expect(payables.single.remainingPaise, 160000);
        expect(payables.single.expenseCount, 2);
      },
    );

    test('grouping ignores case and surrounding whitespace', () async {
      await unpaid('Milk', 70000);
      await unpaid('  milk  ', 90000);

      final payables = await repository.shopPayables();

      expect(payables, hasLength(1));
      expect(payables.single.totalPaise, 160000);
      // Display name keeps the trimmed original casing, never the key.
      expect(payables.single.payeeName, 'Milk');
    });

    test('PayeeKey normalization matches the SQL grouping', () {
      expect(PayeeKey.of('  MiLK  '), 'milk');
      expect(PayeeKey.of('Milk'), PayeeKey.of('milk'));
      expect(PayeeKey.display('  MiLK  '), 'MiLK');
    });

    test('different payees stay separate rows', () async {
      await unpaid('Milk', 70000);
      await unpaid('Sugar', 30000);

      final payables = await repository.shopPayables();

      expect(payables.map((p) => p.payeeName), ['Milk', 'Sugar']);
      // Sorted by remaining balance, largest first.
      expect(payables.first.remainingPaise, 70000);
    });

    test('paid and inactive expenses never create a payable', () async {
      await unpaid('Milk', 70000);
      await repository.createExpense(
        name: 'Rent',
        amountPaise: 50000,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.bank,
        expenseDate: DateTime.utc(2026, 8, 1),
        paymentStatus: ExpensePaymentStatus.paid,
        shopId: cafe,
      );
      final hidden = await unpaid('Sugar', 30000);
      await repository.setExpenseActive(hidden.id, false);

      final payables = await repository.shopPayables();

      expect(payables.map((p) => p.payeeName), ['Milk']);
    });
  });

  group('partial payments', () {
    test(
      'a partial payment lowers the remaining balance and the total payable',
      () async {
        await unpaid('Milk', 160000);
        expect(await repository.payablePaise(), 160000);

        await repository.recordPayablePayment(
          payeeName: 'Milk',
          amountPaise: 100000,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 12),
        );

        final payables = await repository.shopPayables();
        expect(payables.single.paidPaise, 100000);
        expect(payables.single.remainingPaise, 60000);
        expect(
          payables.single.totalPaise,
          160000,
          reason: 'gross is unchanged',
        );

        // The headline total follows the payment down.
        expect(await repository.payablePaise(), 60000);
      },
    );

    test('a second payment stacks against the same payable', () async {
      await unpaid('Milk', 160000);

      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 50000,
        paymentMethod: PaymentMethod.upi,
        paidAt: DateTime.utc(2026, 8, 13),
      );

      final payable = (await repository.shopPayables()).single;
      expect(payable.paidPaise, 150000);
      expect(payable.remainingPaise, 10000);
    });

    test('a payment is recorded against the original expense rows', () async {
      final first = await unpaid('Milk', 70000);
      final second = await unpaid('Milk', 90000);

      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );

      // The expense ledger is untouched: still two rows, still NOT_PAID, same
      // amounts. A payment settles a group, it never rewrites history.
      final expenses = await repository.expenses(
        status: ExpenseStatusFilter.all,
      );
      expect(expenses, hasLength(2));
      expect(expenses.map((e) => e.amountPaise).toList()..sort(), [
        70000,
        90000,
      ]);
      expect(
        expenses.every((e) => e.paymentStatus == ExpensePaymentStatus.notPaid),
        isTrue,
      );
      expect(await repository.expenseById(first.id), isNotNull);
      expect(await repository.expenseById(second.id), isNotNull);
    });

    test('rejects an amount above the remaining balance', () async {
      await unpaid('Milk', 160000);
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );

      await expectLater(
        repository.recordPayablePayment(
          payeeName: 'Milk',
          amountPaise: 60001,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 13),
        ),
        throwsA(isA<PayablePaymentExceedsDueFailure>()),
      );

      // The rejected payment changed nothing.
      expect((await repository.shopPayables()).single.remainingPaise, 60000);
    });

    test('accepts a payment of exactly the remaining balance', () async {
      await unpaid('Milk', 160000);

      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 60000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 13),
      );

      final payable = (await repository.shopPayables()).single;
      expect(payable.remainingPaise, 0);
      expect(payable.isSettled, isTrue);
      expect(await repository.payablePaise(), 0);
    });

    test('rejects a non-positive amount', () async {
      await unpaid('Milk', 160000);

      await expectLater(
        repository.recordPayablePayment(
          payeeName: 'Milk',
          amountPaise: 0,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 12),
        ),
        throwsA(isA<InvalidPayablePaymentFailure>()),
      );
      await expectLater(
        repository.recordPayablePayment(
          payeeName: 'Milk',
          amountPaise: -100,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 12),
        ),
        throwsA(isA<InvalidPayablePaymentFailure>()),
      );
    });

    test('rejects a payment to a payee with nothing outstanding', () async {
      await expectLater(
        repository.recordPayablePayment(
          payeeName: 'Ghost',
          amountPaise: 1000,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 12),
        ),
        throwsA(isA<PayableNotFoundFailure>()),
      );
    });

    test('paying a settled payable again is refused', () async {
      await unpaid('Milk', 70000);
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 70000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );

      await expectLater(
        repository.recordPayablePayment(
          payeeName: 'Milk',
          amountPaise: 1,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 13),
        ),
        throwsA(isA<PayableNotFoundFailure>()),
      );
    });

    test('a blank note is stored as absent', () async {
      await unpaid('Milk', 70000);

      final payment = await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 1000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        note: '   ',
      );

      expect(payment.note, isNull);
    });
  });

  group('payment history', () {
    test('lists every payment for a payee, newest first', () async {
      await unpaid('Milk', 160000);
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        note: 'first',
      );
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 20000,
        paymentMethod: PaymentMethod.upi,
        paidAt: DateTime.utc(2026, 8, 14),
        note: 'second',
      );

      final history = await repository.payablePayments(payeeName: 'Milk');

      expect(history, hasLength(2));
      expect(history.first.amountPaise, 20000);
      expect(history.first.note, 'second');
      expect(history.first.paymentMethod, PaymentMethod.upi);
      expect(history.last.amountPaise, 100000);
      expect(history.last.note, 'first');
      expect(history.every((p) => p.payeeName == 'Milk'), isTrue);
    });

    test('history is filtered by payee', () async {
      await unpaid('Milk', 160000);
      await unpaid('Sugar', 30000);
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 1000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );
      await repository.recordPayablePayment(
        payeeName: 'Sugar',
        amountPaise: 2000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );

      expect(await repository.payablePayments(payeeName: 'Milk'), hasLength(1));
      expect(await repository.payablePayments(), hasLength(2));
    });

    test('history is case-insensitive on the payee name', () async {
      await unpaid('Milk', 160000);
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 1000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
      );

      expect(
        await repository.payablePayments(payeeName: '  mILk  '),
        hasLength(1),
      );
    });
  });

  group('shop isolation', () {
    test('the same payee in two businesses stays two payables', () async {
      await unpaid('Milk', 70000, shopId: cafe);
      await unpaid('Milk', 90000, shopId: foodTruck);

      final cafePayables = await repository.shopPayables(shopIds: [cafe]);
      final truckPayables = await repository.shopPayables(shopIds: [foodTruck]);

      expect(cafePayables.single.remainingPaise, 70000);
      expect(truckPayables.single.remainingPaise, 90000);
    });

    test('a payment in one business never reduces the other', () async {
      await unpaid('Milk', 70000, shopId: cafe);
      await unpaid('Milk', 90000, shopId: foodTruck);

      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 70000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        shopId: cafe,
      );

      expect(
        (await repository.shopPayables(shopIds: [cafe])).single.remainingPaise,
        0,
      );
      expect(
        (await repository.shopPayables(
          shopIds: [foodTruck],
        )).single.remainingPaise,
        90000,
      );
    });

    test('a payment cannot exceed the balance of the scoped shop', () async {
      await unpaid('Milk', 70000, shopId: cafe);
      await unpaid('Milk', 90000, shopId: foodTruck);

      // The truck balance is larger, but the Cafe row only owes 70000, so a
      // 90000 payment scoped to Cafe must be rejected.
      await expectLater(
        repository.recordPayablePayment(
          payeeName: 'Milk',
          amountPaise: 90000,
          paymentMethod: PaymentMethod.cash,
          paidAt: DateTime.utc(2026, 8, 12),
          shopId: cafe,
        ),
        throwsA(isA<PayablePaymentExceedsDueFailure>()),
      );
    });

    test('history is scoped to the requested business', () async {
      await unpaid('Milk', 70000, shopId: cafe);
      await unpaid('Milk', 90000, shopId: foodTruck);
      await repository.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 1000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        shopId: cafe,
      );

      expect(
        await repository.payablePayments(
          payeeName: 'Milk',
          shopIds: [foodTruck],
        ),
        isEmpty,
      );
      expect(
        await repository.payablePayments(payeeName: 'Milk', shopIds: [cafe]),
        hasLength(1),
      );
    });
  });
}
