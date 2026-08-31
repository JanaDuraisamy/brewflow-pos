import 'package:brewflow_pos/core/database/app_database.dart' show AppDatabase;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repository tests against a real in-memory Drift database: migrations,
/// CHECK constraints and SQL filtering all behave exactly like production.
void main() {
  late AppDatabase database;
  late DriftExpensesRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftExpensesRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Expense> createExpense({
    String name = 'Expense',
    int amountPaise = 1500,
    ExpenseCategory category = ExpenseCategory.supplies,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    DateTime? expenseDate,
    String? note,
    bool isActive = true,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
  }) => repository.createExpense(
    name: name,
    amountPaise: amountPaise,
    category: category,
    paymentMethod: paymentMethod,
    expenseDate: expenseDate ?? DateTime.utc(2026, 8, 10),
    note: note,
    isActive: isActive,
    paymentStatus: paymentStatus,
  );

  group('createExpense', () {
    test(
      'persists an expense with a generated id and UTC timestamps',
      () async {
        final expense = await createExpense(
          name: 'Coffee beans',
          amountPaise: 25500,
          category: ExpenseCategory.supplies,
          paymentMethod: PaymentMethod.upi,
          expenseDate: DateTime.utc(2026, 8, 10),
          note: 'Weekly order',
        );

        expect(expense.id, isNotEmpty);
        expect(expense.name, 'Coffee beans');
        expect(expense.amountPaise, 25500);
        expect(expense.category, ExpenseCategory.supplies);
        expect(expense.paymentMethod, PaymentMethod.upi);
        expect(expense.expenseDate, DateTime.utc(2026, 8, 10));
        expect(expense.note, 'Weekly order');
        expect(expense.isActive, isTrue);
        expect(expense.createdAt.isUtc, isTrue);
        expect(expense.updatedAt.isUtc, isTrue);

        final all = await repository.expenses();
        expect(all, hasLength(1));
        expect(all.single.name, 'Coffee beans');
      },
    );

    test('trims name and treats blank notes as absent', () async {
      final expense = await createExpense(name: '  Milk refill  ', note: '   ');

      expect(expense.name, 'Milk refill');
      expect(expense.note, isNull);
    });

    test('blank name is rejected', () async {
      await expectLater(
        createExpense(name: '   '),
        throwsA(isA<UnexpectedExpensesFailure>()),
      );
      expect(await repository.expenses(), isEmpty);
    });

    test('negative amounts are rejected', () async {
      await expectLater(
        createExpense(name: 'Refund', amountPaise: -1),
        throwsA(isA<UnexpectedExpensesFailure>()),
      );
      expect(await repository.expenses(), isEmpty);
    });

    test('defaults to an active expense and stores inactivity', () async {
      final expense = await createExpense();
      expect(expense.isActive, isTrue);

      final inactive = await createExpense(
        name: 'Written off',
        isActive: false,
      );
      expect(inactive.isActive, isFalse);
    });
  });

  group('updateExpense', () {
    test('updates details and the UTC updatedAt', () async {
      final expense = await createExpense(name: 'Coffee beans');

      await repository.updateExpense(
        id: expense.id,
        name: 'Coffee beans (large)',
        amountPaise: 32000,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.bank,
        expenseDate: DateTime.utc(2026, 8, 11),
        note: 'Quarterly order',
        isActive: true,
        paymentStatus: ExpensePaymentStatus.notPaid,
      );

      final updated = await repository.expenseById(expense.id);
      expect(updated!.name, 'Coffee beans (large)');
      expect(updated.amountPaise, 32000);
      expect(updated.paymentMethod, PaymentMethod.bank);
      expect(updated.paymentStatus, ExpensePaymentStatus.notPaid);
      expect(updated.expenseDate, DateTime.utc(2026, 8, 11));
      expect(updated.note, 'Quarterly order');
      expect(updated.createdAt, expense.createdAt);
      expect(
        updated.updatedAt.isAfter(expense.updatedAt),
        isTrue,
        reason: 'updatedAt must advance on every change',
      );
    });

    test('clearing the note and changing category works', () async {
      final expense = await createExpense(
        name: 'Electricity bill',
        category: ExpenseCategory.supplies,
        note: 'July bill',
      );

      await repository.updateExpense(
        id: expense.id,
        name: 'Electricity bill',
        amountPaise: expense.amountPaise,
        category: ExpenseCategory.utilities,
        paymentMethod: expense.paymentMethod,
        expenseDate: expense.expenseDate,
        note: '',
        isActive: true,
        paymentStatus: ExpensePaymentStatus.paid,
      );

      final updated = await repository.expenseById(expense.id);
      expect(updated!.category, ExpenseCategory.utilities);
      expect(updated.note, isNull);
    });
  });

  group('expenseById', () {
    test('returns the expense', () async {
      final expense = await createExpense(name: 'Coffee beans');

      expect((await repository.expenseById(expense.id))!.name, 'Coffee beans');
    });

    test('returns null for an unknown id', () async {
      expect(await repository.expenseById('missing'), isNull);
    });
  });

  group('setExpenseActive', () {
    test('deactivates and reactivates an expense', () async {
      final expense = await createExpense(name: 'Coffee beans');
      expect(expense.isActive, isTrue);

      await repository.setExpenseActive(expense.id, false);
      expect((await repository.expenseById(expense.id))!.isActive, isFalse);

      await repository.setExpenseActive(expense.id, true);
      expect((await repository.expenseById(expense.id))!.isActive, isTrue);
    });

    test('deactivation does not delete the expense', () async {
      final expense = await createExpense(name: 'Coffee beans');
      await repository.setExpenseActive(expense.id, false);

      final all = await repository.expenses(status: ExpenseStatusFilter.all);
      expect(all, hasLength(1));
      expect(all.single.isActive, isFalse);
    });
  });

  group('payment status and payable', () {
    test('created expenses default to paid', () async {
      final expense = await createExpense(name: 'Coffee beans');

      expect(expense.paymentStatus, ExpensePaymentStatus.paid);
      expect(await repository.payablePaise(), 0);
    });

    test('NOT_PAID persists across loads and counts as payable', () async {
      final expense = await createExpense(
        name: 'Rent',
        amountPaise: 5000000,
        paymentStatus: ExpensePaymentStatus.notPaid,
      );

      final reloaded = await repository.expenseById(expense.id);
      expect(reloaded!.paymentStatus, ExpensePaymentStatus.notPaid);
      expect(await repository.payablePaise(), 5000000);
    });

    test('payable sums active NOT_PAID expenses only', () async {
      await createExpense(name: 'Paid supply', amountPaise: 1500);
      await createExpense(
        name: 'Unpaid rent',
        amountPaise: 5000000,
        paymentStatus: ExpensePaymentStatus.notPaid,
      );
      await createExpense(
        name: 'Deferred bill',
        amountPaise: 30000,
        paymentStatus: ExpensePaymentStatus.notPaid,
        isActive: false,
      );

      expect(await repository.payablePaise(), 5000000);

      // Deactivating the unpaid expense removes it from the payable total.
      final rent = await repository.expenses(search: 'Unpaid rent');
      await repository.setExpenseActive(rent.single.id, false);
      expect(await repository.payablePaise(), 0);
    });

    test(
      'updateExpense changes the payment status and refreshes payable',
      () async {
        final expense = await createExpense(
          name: 'Electricity bill',
          amountPaise: 4800,
        );
        expect(await repository.payablePaise(), 0);

        await repository.updateExpense(
          id: expense.id,
          name: expense.name,
          amountPaise: expense.amountPaise,
          category: expense.category,
          paymentMethod: expense.paymentMethod,
          expenseDate: expense.expenseDate,
          note: null,
          isActive: true,
          paymentStatus: ExpensePaymentStatus.notPaid,
        );

        final updated = await repository.expenseById(expense.id);
        expect(updated!.paymentStatus, ExpensePaymentStatus.notPaid);
        expect(await repository.payablePaise(), 4800);

        await repository.updateExpense(
          id: expense.id,
          name: expense.name,
          amountPaise: expense.amountPaise,
          category: expense.category,
          paymentMethod: expense.paymentMethod,
          expenseDate: expense.expenseDate,
          note: null,
          isActive: true,
          paymentStatus: ExpensePaymentStatus.paid,
        );

        expect(
          (await repository.expenseById(expense.id))!.paymentStatus,
          ExpensePaymentStatus.paid,
        );
        expect(await repository.payablePaise(), 0);
      },
    );

    test('payable is zero when there are no outstanding expenses', () async {
      await createExpense(name: 'Coffee beans', amountPaise: 25500);

      expect(await repository.payablePaise(), 0);
    });
  });

  group('expenses query', () {
    setUp(() async {
      await createExpense(
        name: 'Coffee beans',
        amountPaise: 25500,
        category: ExpenseCategory.supplies,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.utc(2026, 8, 10),
        note: 'Weekly order',
      );
      await createExpense(
        name: 'Electricity bill',
        amountPaise: 4800,
        category: ExpenseCategory.utilities,
        paymentMethod: PaymentMethod.upi,
        expenseDate: DateTime.utc(2026, 8, 5),
      );
      await createExpense(
        name: 'Printer repair',
        amountPaise: 1200,
        category: ExpenseCategory.maintenance,
        paymentMethod: PaymentMethod.cash,
        expenseDate: DateTime.utc(2026, 8, 8),
        isActive: false,
      );
    });

    test('returns all expenses sorted newest date first', () async {
      final all = await repository.expenses();
      expect(all.map((e) => e.name).toList(), [
        'Coffee beans',
        'Printer repair',
        'Electricity bill',
      ]);
    });

    test('same-day expenses sort newest created first', () async {
      await createExpense(
        name: 'Late entry',
        category: ExpenseCategory.misc,
        expenseDate: DateTime.utc(2026, 8, 10),
      );

      final all = await repository.expenses();
      final sameDay = all.take(2).map((e) => e.name).toList();
      expect(sameDay, contains('Late entry'));
      expect(sameDay, contains('Coffee beans'));
    });

    test('searches by name case-insensitively', () async {
      final results = await repository.expenses(search: 'COFFEE');
      expect(results.map((e) => e.name).toList(), ['Coffee beans']);
    });

    test('searches by note', () async {
      final results = await repository.expenses(search: 'weekly');
      expect(results.map((e) => e.name).toList(), ['Coffee beans']);
    });

    test('filters by category', () async {
      final results = await repository.expenses(
        category: ExpenseCategory.utilities,
      );
      expect(results.map((e) => e.name).toList(), ['Electricity bill']);
    });

    test('filters by payment method', () async {
      final results = await repository.expenses(
        paymentMethod: PaymentMethod.upi,
      );
      expect(results.map((e) => e.name).toList(), ['Electricity bill']);
    });

    test('filters by an inclusive UTC range', () async {
      final results = await repository.expenses(
        fromUtc: DateTime.utc(2026, 8, 8),
        toUtc: DateTime.utc(2026, 8, 10, 23, 59, 59),
      );
      expect(results.map((e) => e.name).toList(), [
        'Coffee beans',
        'Printer repair',
      ]);
    });

    test('filters by status', () async {
      final active = await repository.expenses(
        status: ExpenseStatusFilter.active,
      );
      expect(active.map((e) => e.name).toList(), [
        'Coffee beans',
        'Electricity bill',
      ]);

      final inactive = await repository.expenses(
        status: ExpenseStatusFilter.inactive,
      );
      expect(inactive.map((e) => e.name).toList(), ['Printer repair']);
    });

    test('combined filters narrow together', () async {
      final results = await repository.expenses(
        search: 'bill',
        category: ExpenseCategory.utilities,
        paymentMethod: PaymentMethod.upi,
        status: ExpenseStatusFilter.active,
        fromUtc: DateTime.utc(2026, 8, 1),
        toUtc: DateTime.utc(2026, 8, 31, 23, 59, 59),
      );
      expect(results.map((e) => e.name).toList(), ['Electricity bill']);
    });
  });
}
