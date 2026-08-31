import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';

void main() {
  late FakeExpensesRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [expensesRepositoryProvider.overrideWithValue(fake)],
  );

  final now = DateTime.now().toUtc();

  Expense expense(
    String id,
    String name, {
    int amountPaise = 1500,
    ExpenseCategory category = ExpenseCategory.supplies,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
    DateTime? expenseDate,
    String? note,
    bool isActive = true,
  }) => Expense(
    id: id,
    name: name,
    amountPaise: amountPaise,
    category: category,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus,
    expenseDate: expenseDate ?? DateTime.utc(2026, 8, 10),
    note: note,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() => fake = FakeExpensesRepository());

  /// Waits (in real async) for invalidation-triggered rebuilds to settle,
  /// since reading `.future` right after a mutation can race the rebuild.
  Future<void> awaitUntil(
    ProviderContainer container,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not met within the timeout');
  }

  group('expensesProvider', () {
    test('starts loading and resolves to the stored expenses', () async {
      fake.storedExpenses.addAll([
        expense(
          'e2',
          'Electricity bill',
          expenseDate: DateTime.utc(2026, 8, 5),
        ),
        expense('e1', 'Coffee beans', expenseDate: DateTime.utc(2026, 8, 10)),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(container.read(expensesProvider), isA<AsyncLoading>());

      await container.read(expensesProvider.future);

      final expenses = container.read(expensesProvider).value!;
      // Sorted newest expense date first by the repository.
      expect(expenses.map((e) => e.name), ['Coffee beans', 'Electricity bill']);
      expect(fake.loadCalls, 1);
    });

    test('resolves to empty when there are no expenses', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.future);
      expect(container.read(expensesProvider).value, isEmpty);
    });

    test('surfaces ExpensesFailure without wrapping it', () async {
      fake.loadError = const MissingExpenseFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(expensesProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(expensesProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<MissingExpenseFailure>());
    });

    test('maps unexpected errors to UnexpectedExpensesFailure', () async {
      fake.loadError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(expensesProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(expensesProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedExpensesFailure>());
    });

    test('stays loading while the load gate is closed', () async {
      fake.storedExpenses.add(expense('e1', 'Coffee beans'));
      final gate = Completer<void>();
      fake.loadGate = gate;
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(expensesProvider);
      expect(container.read(expensesProvider), isA<AsyncLoading>());

      gate.complete();
      await container.read(expensesProvider.future);
      expect(container.read(expensesProvider).value, hasLength(1));
    });
  });

  group('expensesFilterProvider', () {
    test('setQuery rebuilds the list narrowed by the search text', () async {
      fake.storedExpenses.addAll([
        expense('e1', 'Coffee beans', note: 'Weekly order'),
        expense('e2', 'Electricity bill'),
        expense('e3', 'Milk refill', note: 'Daily supplies'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.future);
      expect(container.read(expensesProvider).value, hasLength(3));

      container.read(expensesFilterProvider.notifier).setQuery('coffee');
      await awaitUntil(
        container,
        () =>
            (container.read(expensesProvider).value ?? const <Expense>[])
                .length ==
            1,
      );
      expect(
        container.read(expensesProvider).value!.single.name,
        'Coffee beans',
      );

      container.read(expensesFilterProvider.notifier).setQuery('supplies');
      await awaitUntil(container, () {
        final list =
            container.read(expensesProvider).value ?? const <Expense>[];
        return list.length == 1 && list.single.name == 'Milk refill';
      });
      expect(
        container.read(expensesProvider).value!.single.name,
        'Milk refill',
      );

      container.read(expensesFilterProvider.notifier).setQuery('');
      await awaitUntil(
        container,
        () =>
            (container.read(expensesProvider).value ?? const <Expense>[])
                .length ==
            3,
      );
      expect(container.read(expensesProvider).value, hasLength(3));
    });

    test('setCategory narrows the list', () async {
      fake.storedExpenses.addAll([
        expense('e1', 'Coffee beans', category: ExpenseCategory.supplies),
        expense('e2', 'Electricity bill', category: ExpenseCategory.utilities),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.future);

      container
          .read(expensesFilterProvider.notifier)
          .setCategory(ExpenseCategory.utilities);
      await awaitUntil(container, () {
        final list =
            container.read(expensesProvider).value ?? const <Expense>[];
        return list.length == 1 && list.single.name == 'Electricity bill';
      });
    });

    test('setPaymentMethod narrows the list', () async {
      fake.storedExpenses.addAll([
        expense('e1', 'Coffee beans', paymentMethod: PaymentMethod.cash),
        expense('e2', 'Electricity bill', paymentMethod: PaymentMethod.upi),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.future);

      container
          .read(expensesFilterProvider.notifier)
          .setPaymentMethod(PaymentMethod.upi);
      await awaitUntil(container, () {
        final list =
            container.read(expensesProvider).value ?? const <Expense>[];
        return list.length == 1 && list.single.name == 'Electricity bill';
      });
    });

    test('setStatus narrows the list', () async {
      fake.storedExpenses.addAll([
        expense('e1', 'Coffee beans'),
        expense('e2', 'Written off', isActive: false),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.future);

      container
          .read(expensesFilterProvider.notifier)
          .setStatus(ExpenseStatusFilter.inactive);
      await awaitUntil(container, () {
        final list =
            container.read(expensesProvider).value ?? const <Expense>[];
        return list.length == 1 && list.single.name == 'Written off';
      });
    });

    test(
      'setPreset and setCustomRange bound the list, clear restores it',
      () async {
        final today = DateTime.now();
        final todayUtc = DateTime(today.year, today.month, today.day).toUtc();
        final pastUtc = todayUtc.subtract(const Duration(days: 15));
        fake.storedExpenses.addAll([
          expense('e1', 'Today entry', expenseDate: todayUtc),
          expense('e2', 'Old entry', expenseDate: pastUtc),
        ]);
        final container = buildContainer();
        addTearDown(container.dispose);

        await container.read(expensesProvider.future);
        expect(container.read(expensesProvider).value, hasLength(2));

        container
            .read(expensesFilterProvider.notifier)
            .setPreset(OrdersDatePreset.today);
        await awaitUntil(container, () {
          final list =
              container.read(expensesProvider).value ?? const <Expense>[];
          return list.length == 1;
        });
        expect(
          container.read(expensesProvider).value!.single.name,
          'Today entry',
        );

        container
            .read(expensesFilterProvider.notifier)
            .setCustomRange(today.subtract(const Duration(days: 2)), today);
        await awaitUntil(container, () {
          final list =
              container.read(expensesProvider).value ?? const <Expense>[];
          return list.length == 1 && list.single.name == 'Today entry';
        });
        expect(
          container.read(expensesFilterProvider).datePreset,
          OrdersDatePreset.custom,
        );

        container.read(expensesFilterProvider.notifier).clear();
        await awaitUntil(
          container,
          () =>
              (container.read(expensesProvider).value ?? const <Expense>[])
                  .length ==
              2,
        );
        expect(container.read(expensesProvider).value, hasLength(2));
      },
    );
  });

  group('mutations', () {
    test('create adds the expense and refreshes the list', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.future);
      expect(container.read(expensesProvider).value, isEmpty);

      await container
          .read(expensesProvider.notifier)
          .create(
            name: 'Coffee beans',
            amountPaise: 25500,
            category: ExpenseCategory.supplies,
            paymentMethod: PaymentMethod.cash,
            expenseDate: DateTime.utc(2026, 8, 10),
          );

      await awaitUntil(
        container,
        () => container.read(expensesProvider).value?.length == 1,
      );
      expect(
        container.read(expensesProvider).value!.single.name,
        'Coffee beans',
      );
    });

    test('create propagates expenses failures', () async {
      fake.loadError = const MissingExpenseFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(expensesProvider.notifier)
            .create(
              name: 'Coffee beans',
              amountPaise: 25500,
              category: ExpenseCategory.supplies,
              paymentMethod: PaymentMethod.cash,
              expenseDate: DateTime.utc(2026, 8, 10),
            ),
        throwsA(isA<MissingExpenseFailure>()),
      );
      expect(fake.storedExpenses, isEmpty);
    });

    test('updateExpense refreshes the list with new details', () async {
      fake.storedExpenses.add(
        expense('e1', 'Coffee beans', amountPaise: 25500),
      );
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(expensesProvider.notifier)
          .updateExpense(
            id: 'e1',
            name: 'Coffee beans (large)',
            amountPaise: 32000,
            category: ExpenseCategory.supplies,
            paymentMethod: PaymentMethod.bank,
            expenseDate: DateTime.utc(2026, 8, 11),
            isActive: true,
            paymentStatus: ExpensePaymentStatus.notPaid,
          );

      await awaitUntil(
        container,
        () =>
            container.read(expensesProvider).value?.single.name ==
            'Coffee beans (large)',
      );
      final updated = container.read(expensesProvider).value!.single;
      expect(updated.amountPaise, 32000);
      expect(updated.paymentMethod, PaymentMethod.bank);
    });

    test('setActive refreshes the list with the new status', () async {
      fake.storedExpenses.add(expense('e1', 'Coffee beans'));
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(expensesProvider.notifier).setActive('e1', false);

      await awaitUntil(
        container,
        () => container.read(expensesProvider).value!.single.isActive == false,
      );
      expect(container.read(expensesProvider).value!.single.isActive, isFalse);
    });

    test('unexpected mutation errors are wrapped', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      fake.loadError = StateError('boom');
      await expectLater(
        container
            .read(expensesProvider.notifier)
            .create(
              name: 'Coffee beans',
              amountPaise: 25500,
              category: ExpenseCategory.supplies,
              paymentMethod: PaymentMethod.cash,
              expenseDate: DateTime.utc(2026, 8, 10),
            ),
        throwsA(isA<UnexpectedExpensesFailure>()),
      );
    });
  });

  group('shopPayableProvider', () {
    test(
      'sums active NOT_PAID expenses and refreshes after a mutation',
      () async {
        fake.storedExpenses.addAll([
          expense('e1', 'Coffee beans', amountPaise: 25500),
          expense(
            'e2',
            'Rent',
            amountPaise: 5000000,
            paymentStatus: ExpensePaymentStatus.notPaid,
          ),
          expense(
            'e3',
            'Deferred bill',
            amountPaise: 30000,
            paymentStatus: ExpensePaymentStatus.notPaid,
            isActive: false,
          ),
        ]);
        final container = buildContainer();
        addTearDown(container.dispose);

        await container.read(shopPayableProvider.future);
        expect(container.read(shopPayableProvider).value, 5000000);

        // Marking the rent paid drops the payable total to zero.
        await container
            .read(expensesProvider.notifier)
            .updateExpense(
              id: 'e2',
              name: 'Rent',
              amountPaise: 5000000,
              category: ExpenseCategory.rent,
              paymentMethod: PaymentMethod.bank,
              expenseDate: DateTime.utc(2026, 8, 1),
              isActive: true,
              paymentStatus: ExpensePaymentStatus.paid,
            );

        await awaitUntil(
          container,
          () => container.read(shopPayableProvider).value == 0,
        );
        expect(container.read(shopPayableProvider).value, 0);
      },
    );

    test('create with NOT_PAID adds to the payable total', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(expensesProvider.notifier)
          .create(
            name: 'Rent',
            amountPaise: 5000000,
            category: ExpenseCategory.rent,
            paymentMethod: PaymentMethod.bank,
            expenseDate: DateTime.utc(2026, 8, 1),
            paymentStatus: ExpensePaymentStatus.notPaid,
          );

      await awaitUntil(
        container,
        () => container.read(shopPayableProvider).value == 5000000,
      );
      expect(
        container.read(expensesProvider).value!.single.paymentStatus,
        ExpensePaymentStatus.notPaid,
      );
    });

    test('surfaces failure when the repository throws', () async {
      fake.loadError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(shopPayableProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(shopPayableProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedExpensesFailure>());
    });
  });

  group('queries', () {
    test('expenseById returns the stored expense', () async {
      fake.storedExpenses.add(expense('e1', 'Coffee beans'));
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(
        (await container.read(expensesProvider.notifier).byId('e1'))!.name,
        'Coffee beans',
      );
      expect(
        await container.read(expensesProvider.notifier).byId('missing'),
        isNull,
      );
    });
  });
}
