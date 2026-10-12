import 'package:brewflow_pos/core/database/app_database.dart'
    show AppDatabase, ShopsCompanion;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/shop_payables_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shop payable expense-detail drill-down.
///
/// The summary card stays a summary; tapping it opens the underlying unpaid
/// expenses of exactly one (shop, payee) row. Same-name payees in Cafe and
/// Food Truck never mix.
/// ---------------------------------------------------------------------------

void main() {
  group('shop-aware grouping (real database)', () {
    late AppDatabase database;
    late DriftExpensesRepository repository;

    const cafe = 'cafe-1';
    const truck = 'truck-1';

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      repository = DriftExpensesRepository(database);
      await database
          .into(database.shops)
          .insert(ShopsCompanion.insert(id: const Value(cafe), name: 'Cafe'));
      await database
          .into(database.shops)
          .insert(
            ShopsCompanion.insert(id: const Value(truck), name: 'Food Truck'),
          );
    });

    tearDown(() async {
      await database.close();
    });

    Future<void> unpaid(
      String name,
      int amountPaise, {
      required String shopId,
      required DateTime date,
    }) => repository.createExpense(
      name: name,
      amountPaise: amountPaise,
      category: ExpenseCategory.supplies,
      paymentMethod: PaymentMethod.cash,
      expenseDate: date,
      paymentStatus: ExpensePaymentStatus.notPaid,
      shopId: shopId,
    );

    test('same payee name in two shops stays two isolated rows', () async {
      await unpaid(
        'Naren',
        120000,
        shopId: cafe,
        date: DateTime.utc(2026, 10, 5),
      );
      await unpaid(
        'Naren',
        97200,
        shopId: cafe,
        date: DateTime.utc(2026, 10, 1),
      );
      await unpaid(
        'Naren',
        50000,
        shopId: truck,
        date: DateTime.utc(2026, 10, 3),
      );

      final payables = await repository.shopPayables(
        shopIds: const [cafe, truck],
      );
      expect(payables, hasLength(2));
      final cafeRow = payables.firstWhere((p) => p.shopId == cafe);
      final truckRow = payables.firstWhere((p) => p.shopId == truck);
      expect(cafeRow.payeeKey, 'naren');
      expect(cafeRow.totalPaise, 217200);
      expect(cafeRow.expenseCount, 2);
      expect(truckRow.totalPaise, 50000);
      expect(truckRow.expenseCount, 1);
    });

    test('detail rows of one shop sum to its unpaid total', () async {
      await unpaid(
        'Maggi Purchase',
        120000,
        shopId: cafe,
        date: DateTime.utc(2026, 10, 5),
      );
      await unpaid(
        'Oil Purchase',
        97200,
        shopId: cafe,
        date: DateTime.utc(2026, 10, 1),
      );
      // Same-name decoy in the other shop must not leak in.
      await unpaid(
        'Maggi Purchase',
        999999,
        shopId: truck,
        date: DateTime.utc(2026, 10, 2),
      );

      final cafeRows = await repository.payables(shopIds: const [cafe]);
      final maggi = [
        for (final e in cafeRows)
          if (PayeeKey.of(e.name) == 'maggi purchase') e,
      ];
      expect(maggi, hasLength(1));
      expect(maggi.fold<int>(0, (sum, e) => sum + e.amountPaise), 120000);

      final narenCafe = await repository.shopPayables(shopIds: const [cafe]);
      expect(narenCafe, hasLength(2));
      expect(narenCafe.fold<int>(0, (sum, p) => sum + p.totalPaise), 217200);
    });
  });

  group('payable detail sheet (widget)', () {
    Expense expense(
      String name,
      int amountPaise,
      DateTime date, {
      ExpensePaymentStatus status = ExpensePaymentStatus.notPaid,
      String? note,
    }) => Expense(
      id: 'e-${name.hashCode}-$amountPaise',
      name: name,
      amountPaise: amountPaise,
      category: ExpenseCategory.supplies,
      paymentMethod: PaymentMethod.cash,
      paymentStatus: status,
      expenseDate: date,
      note: note,
      isActive: true,
      createdAt: date,
      updatedAt: date,
    );

    Future<void> pumpPayables(
      WidgetTester tester,
      FakeExpensesRepository fake,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesRepositoryProvider.overrideWithValue(fake),
            ...businessScopeOverrides(),
          ],
          child: const MaterialApp(home: ShopPayablesPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a card opens its expense details', (tester) async {
      final fake = FakeExpensesRepository()
        ..storedExpenses.addAll([
          expense('Naren', 120000, DateTime.utc(2026, 10, 5)),
          expense(
            'Naren',
            97200,
            DateTime.utc(2026, 10, 1),
            note: 'Oil purchase',
          ),
        ]);
      await pumpPayables(tester, fake);

      // Summary card: one grouped row.
      expect(find.text('Naren'), findsOneWidget);
      expect(find.textContaining('2 expenses'), findsOneWidget);
      await tester.tap(find.text('Naren'));
      await tester.pumpAndSettle();

      // Detail: each underlying expense with date, amount and status.
      expect(find.text('Naren'), findsWidgets);
      expect(find.text('₹1,200.00'), findsWidgets);
      expect(find.text('₹972.00'), findsWidgets);
      expect(find.text('Unpaid'), findsWidgets);
      expect(find.text('5 Oct 2026'), findsOneWidget);
      expect(find.text('1 Oct 2026'), findsOneWidget);
      expect(find.textContaining('Oil purchase'), findsOneWidget);
      // Aggregate total matches the detail rows.
      expect(find.textContaining('₹2,172.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('settled payee shows the paid state cleanly', (tester) async {
      final fake = FakeExpensesRepository()
        ..storedExpenses.add(expense('Milk', 100000, DateTime.utc(2026, 10, 4)))
        ..storedPayablePayments.add(
          ExpensePayment(
            id: 'pay-1',
            payeeKey: 'milk',
            payeeName: 'Milk',
            amountPaise: 100000,
            paymentMethod: PaymentMethod.cash,
            paidAt: DateTime.utc(2026, 10, 6),
            reversed: false,
            createdAt: DateTime.utc(2026, 10, 6),
          ),
        );
      await pumpPayables(tester, fake);

      expect(find.text('Settled'), findsOneWidget);
      expect(find.textContaining('fully paid'), findsOneWidget);
      await tester.tap(find.text('Settled'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsWidgets);
      expect(find.text('Unpaid'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty shop shows the empty state', (tester) async {
      await pumpPayables(tester, FakeExpensesRepository());

      expect(find.text('Nothing payable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow 360dp phone lays out without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fake = FakeExpensesRepository()
        ..storedExpenses.add(
          expense(
            'Extra Long Supplier Name For Narrow Phone Wrapping Test Case',
            217200,
            DateTime.utc(2026, 10, 5),
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            expensesRepositoryProvider.overrideWithValue(fake),
            ...businessScopeOverrides(),
          ],
          child: const MaterialApp(home: ShopPayablesPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('1 expense'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Expenses ('), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
