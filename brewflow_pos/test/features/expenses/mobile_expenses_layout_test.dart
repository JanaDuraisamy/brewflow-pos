import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// All logical phone widths the phone-only layout must survive without
/// overflow (the original bug was "BOTTOM OVERFLOWED BY 4.3 PIXELS").
const _phoneWidths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

void main() {
  late FakeExpensesRepository fakeExpenses;

  final now = DateTime.now();
  final todayUtc = DateTime(now.year, now.month, now.day).toUtc();

  Expense expense(
    String id,
    String name, {
    int amountPaise = 25500,
    ExpenseCategory category = ExpenseCategory.supplies,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
    bool isActive = true,
  }) => Expense(
    id: id,
    name: name,
    amountPaise: amountPaise,
    category: category,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus,
    expenseDate: todayUtc,
    note: null,
    isActive: isActive,
    createdAt: now.toUtc(),
    updatedAt: now.toUtc(),
  );

  setUp(() {
    fakeExpenses = FakeExpensesRepository();
  });

  Widget buildApp(FakeAuthRepository auth) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      expensesRepositoryProvider.overrideWithValue(fakeExpenses),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(buildApp(fake));
    fake.emit(_owner);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  }

  Future<void> openExpenses(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.expenses);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  for (final width in _phoneWidths) {
    testWidgets(
      'expenses phone layout has zero overflow at ${width}dp with a list',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        fakeExpenses.storedExpenses.addAll([
          expense(
            'e1',
            'Coffee beans',
            amountPaise: 25500,
            paymentMethod: PaymentMethod.upi,
          ),
          expense(
            'e2',
            'Rent',
            amountPaise: 5000000,
            paymentStatus: ExpensePaymentStatus.notPaid,
          ),
        ]);

        await pumpAuthenticated(tester);
        await openExpenses(tester);

        expect(find.byType(ExpensesPage), findsOneWidget);
        // A NOT_PAID expense renders the payable summary + amount.
        expect(find.text('Shop Payable'), findsOneWidget);
        expect(find.text('Coffee beans'), findsOneWidget);
        expect(find.text('Rent'), findsOneWidget);
        expect(find.text('₹50,000.00'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');
      },
    );

    testWidgets(
      'expenses phone layout has zero overflow at ${width}dp when empty',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await pumpAuthenticated(tester);
        await openExpenses(tester);

        expect(find.byType(ExpensesPage), findsOneWidget);
        expect(find.text('No expenses yet'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');
      },
    );
  }

  testWidgets('long-press on phone expense card opens sheet and deactivate '
      'confirms', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    fakeExpenses.storedExpenses.addAll([
      expense('e1', 'Coffee beans'),
      expense('e2', 'Rent'),
    ]);

    await pumpAuthenticated(tester);
    await openExpenses(tester);

    final card = find.ancestor(
      of: find.text('Coffee beans'),
      matching: find.byType(AppCard),
    );
    expect(card, findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Deactivate expense'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();

    final coffee = fakeExpenses.storedExpenses.firstWhere(
      (expense) => expense.id == 'e1',
    );
    expect(coffee.isActive, isFalse);
  });

  testWidgets('long-press on tablet expense card opens sheet', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    fakeExpenses.storedExpenses.addAll([
      expense('e1', 'Coffee beans'),
      expense('e2', 'Rent'),
    ]);

    await pumpAuthenticated(tester);
    await openExpenses(tester);

    // Tablet (600-799dp) renders the wider _ExpenseCard, not the table.
    expect(find.byType(DataTable), findsNothing);

    final card = find.ancestor(
      of: find.text('Rent'),
      matching: find.byType(AppCard),
    );
    expect(card, findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });
}
