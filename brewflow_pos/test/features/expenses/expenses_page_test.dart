import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/presentation/expense_form_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
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

void main() {
  late FakeAuthRepository fakeAuth;
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
    expenseDate: expenseDate ?? todayUtc,
    note: note,
    isActive: isActive,
    createdAt: now.toUtc(),
    updatedAt: now.toUtc(),
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeExpenses = FakeExpensesRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
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
    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
  }

  /// Pumps a few frames and settles. Provider rebuilds scheduled after an
  /// invalidation need more than a single settle to become visible.
  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openExpenses(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.expenses);
    await pumpAsync(tester);
  }

  /// The form is a scrollable column, so its action buttons only exist in the
  /// tree once scrolled into view. ensureVisible alone leaves the target
  /// hanging off the bottom edge, so drag until it is actually tappable.
  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.descendant(
      of: find.byType(ExpenseFormPage),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 8 && tester.any(finder.hitTestable()) == false; i++) {
      await tester.drag(scrollable.first, const Offset(0, -160));
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle();
  }

  group('expenses landing page', () {
    testWidgets('shows the empty state when there are no expenses', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      expect(find.byType(ExpensesPage), findsOneWidget);
      expect(find.text('No expenses yet'), findsOneWidget);
      expect(
        find.text('Add your first expense to start tracking spending.'),
        findsOneWidget,
      );
    });

    testWidgets('lists expenses with amounts and labels', (tester) async {
      fakeExpenses.storedExpenses.addAll([
        expense(
          'e1',
          'Coffee beans',
          amountPaise: 25500,
          category: ExpenseCategory.supplies,
          paymentMethod: PaymentMethod.upi,
        ),
        expense(
          'e2',
          'Electricity bill',
          amountPaise: 4800,
          category: ExpenseCategory.utilities,
          paymentMethod: PaymentMethod.cash,
          expenseDate: todayUtc.subtract(const Duration(days: 5)),
          isActive: false,
        ),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      expect(find.text('Coffee beans'), findsOneWidget);
      expect(find.text('₹255.00'), findsOneWidget);
      expect(find.text('Supplies'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('Electricity bill'), findsOneWidget);
      expect(find.text('₹48.00'), findsOneWidget);
      expect(find.text('Utilities'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      // One filter chip label plus one badge per matching expense.
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.text('Inactive'), findsNWidgets(2));
    });

    testWidgets('search narrows the list by name and note', (tester) async {
      fakeExpenses.storedExpenses.addAll([
        expense('e1', 'Coffee beans', note: 'Weekly order'),
        expense('e2', 'Electricity bill'),
        expense('e3', 'Milk packets', note: 'daily'),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.enterText(find.byType(TextField), 'coffee');
      await pumpAsync(tester);
      expect(find.text('Coffee beans'), findsOneWidget);
      expect(find.text('Electricity bill'), findsNothing);

      await tester.enterText(find.byType(TextField), 'weekly');
      await pumpAsync(tester);
      expect(find.text('Coffee beans'), findsOneWidget);
      expect(find.text('Milk packets'), findsNothing);
    });

    testWidgets('status filter narrows the list', (tester) async {
      fakeExpenses.storedExpenses.addAll([
        expense('e1', 'Coffee beans'),
        expense('e2', 'Written off stock', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.tap(find.widgetWithText(AppFilterChip, 'Inactive'));
      await pumpAsync(tester);

      expect(find.text('Written off stock'), findsOneWidget);
      expect(find.text('Coffee beans'), findsNothing);
    });

    testWidgets('category filter narrows the list', (tester) async {
      fakeExpenses.storedExpenses.addAll([
        expense('e1', 'Coffee beans', category: ExpenseCategory.supplies),
        expense('e2', 'Electricity bill', category: ExpenseCategory.utilities),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.tap(find.text('All categories'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<ExpenseCategory>),
          matching: find.text('Utilities'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Electricity bill'), findsOneWidget);
      expect(find.text('Coffee beans'), findsNothing);
    });

    testWidgets('payment filter narrows the list', (tester) async {
      fakeExpenses.storedExpenses.addAll([
        expense('e1', 'Coffee beans', paymentMethod: PaymentMethod.cash),
        expense('e2', 'Rent transfer', paymentMethod: PaymentMethod.upi),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.tap(find.text('All payments'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<PaymentMethod>),
          matching: find.text('UPI'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rent transfer'), findsOneWidget);
      expect(find.text('Coffee beans'), findsNothing);
    });

    testWidgets('date preset filter narrows to today', (tester) async {
      fakeExpenses.storedExpenses.addAll([
        expense('e1', 'Today entry', expenseDate: todayUtc),
        expense(
          'e2',
          'Old entry',
          expenseDate: todayUtc.subtract(const Duration(days: 15)),
        ),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<OrdersDatePreset>),
          matching: find.text('Today'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Today entry'), findsOneWidget);
      expect(find.text('Old entry'), findsNothing);
    });

    testWidgets('clearing a dead-end filter restores the full list', (
      tester,
    ) async {
      fakeExpenses.storedExpenses.add(expense('e1', 'Coffee beans'));
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await pumpAsync(tester);

      expect(find.text('No expenses match your filters'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await pumpAsync(tester);

      expect(find.text('Coffee beans'), findsOneWidget);
      expect(find.text('No expenses match your filters'), findsNothing);
    });

    testWidgets('load failures show an error state that can retry', (
      tester,
    ) async {
      fakeExpenses.loadError = const UnexpectedExpensesFailure();
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      fakeExpenses.loadError = null;
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);

      expect(find.text('No expenses yet'), findsOneWidget);
    });

    testWidgets('shows the shop payable summary for NOT_PAID expenses', (
      tester,
    ) async {
      fakeExpenses.storedExpenses.addAll([
        expense('e1', 'Coffee beans', amountPaise: 25500),
        expense(
          'e2',
          'Rent',
          amountPaise: 5000000,
          paymentStatus: ExpensePaymentStatus.notPaid,
        ),
      ]);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      expect(find.text('Shop Payable'), findsOneWidget);
      expect(find.text('Expenses recorded but not paid yet.'), findsOneWidget);
      expect(find.text('₹50,000.00'), findsWidgets);
      expect(find.text('Not paid'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('shop payable is zero when everything is settled', (
      tester,
    ) async {
      fakeExpenses.storedExpenses.add(
        expense('e1', 'Coffee beans', amountPaise: 4800),
      );
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      expect(find.text('Shop Payable'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('₹48.00'), findsOneWidget);
    });

    testWidgets('deactivating an expense asks for confirmation first', (
      tester,
    ) async {
      fakeExpenses.storedExpenses.add(expense('e1', 'Coffee beans'));
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      final deactivate = find.byIcon(Icons.delete_outline);
      await tester.ensureVisible(deactivate);
      await tester.pump();
      await tester.tap(deactivate);
      await pumpAsync(tester);

      expect(find.text('Deactivate expense?'), findsOneWidget);
      expect(fakeExpenses.storedExpenses.single.isActive, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await pumpAsync(tester);

      expect(fakeExpenses.storedExpenses.single.isActive, isFalse);
      expect(find.text('Expense deactivated.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('cancelling deactivation keeps the expense active', (
      tester,
    ) async {
      fakeExpenses.storedExpenses.add(expense('e1', 'Coffee beans'));
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      final deactivate = find.byIcon(Icons.delete_outline);
      await tester.ensureVisible(deactivate);
      await tester.pump();
      await tester.tap(deactivate);
      await pumpAsync(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await pumpAsync(tester);

      expect(find.text('Deactivate expense?'), findsNothing);
      expect(fakeExpenses.storedExpenses.single.isActive, isTrue);
    });
  });

  group('expense form', () {
    Future<void> openNewExpenseForm(WidgetTester tester) async {
      await openExpenses(tester);
      await tester.tap(find.text('Add Expense').first);
      await pumpAsync(tester);
      expect(find.byType(ExpenseFormPage), findsOneWidget);
    }

    testWidgets('add expense button opens the form and cancel returns', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewExpenseForm(tester);

      expect(find.text('New Expense'), findsOneWidget);

      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await scrollFormTo(tester, cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseFormPage), findsNothing);
      expect(find.byType(ExpensesPage), findsOneWidget);
    });

    testWidgets('saves a new expense and returns to a refreshed list', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewExpenseForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Coffee beans');
      await tester.enterText(find.byType(TextFormField).at(1), '255.00');
      await tester.tap(find.text('Select a category'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<ExpenseCategory>),
          matching: find.text('Supplies'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a payment method'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<PaymentMethod>),
          matching: find.text('Cash'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save Expense');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(ExpenseFormPage), findsNothing);
      expect(find.text('Coffee beans'), findsOneWidget);
      expect(find.text('Expense added.'), findsOneWidget);

      final saved = fakeExpenses.storedExpenses.single;
      expect(saved.name, 'Coffee beans');
      expect(saved.amountPaise, 25500);
      expect(saved.category, ExpenseCategory.supplies);
      expect(saved.paymentMethod, PaymentMethod.cash);
      expect(saved.note, isNull);
      expect(saved.isActive, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('validates required fields before saving', (tester) async {
      await pumpAuthenticated(tester);
      await openNewExpenseForm(tester);

      final save = find.widgetWithText(FilledButton, 'Save Expense');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await tester.pump();

      expect(find.text('Expense name is required.'), findsOneWidget);
      expect(find.text('Enter a valid amount (e.g. 149.50)'), findsOneWidget);
      expect(find.text('Select a category.'), findsOneWidget);
      expect(find.text('Select a payment method.'), findsOneWidget);
      expect(find.text('Expense date is required.'), findsOneWidget);
      expect(find.byType(ExpenseFormPage), findsOneWidget);
      expect(fakeExpenses.storedExpenses, isEmpty);
    });

    testWidgets('rejects a zero amount inline', (tester) async {
      await pumpAuthenticated(tester);
      await openNewExpenseForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Free item');
      await tester.enterText(find.byType(TextFormField).at(1), '0');

      final save = find.widgetWithText(FilledButton, 'Save Expense');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await tester.pump();

      expect(find.text('Amount must be greater than zero.'), findsOneWidget);
      expect(fakeExpenses.storedExpenses, isEmpty);
    });

    testWidgets('records a new expense as not paid and it becomes payable', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewExpenseForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Shop rent');
      await tester.enterText(find.byType(TextFormField).at(1), '50000.00');
      await tester.tap(find.text('Select a category'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<ExpenseCategory>),
          matching: find.text('Rent'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a payment method'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<PaymentMethod>),
          matching: find.text('Bank'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DropdownMenuItem<ExpensePaymentStatus>),
          matching: find.text('Not paid'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select a date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save Expense');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(ExpenseFormPage), findsNothing);
      expect(find.text('Shop rent'), findsOneWidget);
      expect(find.text('Shop Payable'), findsOneWidget);
      expect(find.text('₹50,000.00'), findsWidgets);

      final saved = fakeExpenses.storedExpenses.single;
      expect(saved.name, 'Shop rent');
      expect(saved.paymentStatus, ExpensePaymentStatus.notPaid);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('editing a not-paid expense preselects its payment status', (
      tester,
    ) async {
      fakeExpenses.storedExpenses.add(
        expense(
          'e1',
          'Shop rent',
          amountPaise: 5000000,
          paymentStatus: ExpensePaymentStatus.notPaid,
        ),
      );
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.tap(find.text('Shop rent'));
      await pumpAsync(tester);

      expect(find.byType(ExpenseFormPage), findsOneWidget);
      expect(find.text('Not paid'), findsOneWidget);

      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      final saved = fakeExpenses.storedExpenses.single;
      expect(saved.paymentStatus, ExpensePaymentStatus.notPaid);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('editing prefills the form and saves changes', (tester) async {
      fakeExpenses.storedExpenses.add(
        expense(
          'e1',
          'Coffee beans',
          amountPaise: 25500,
          paymentMethod: PaymentMethod.upi,
          note: 'Weekly order',
        ),
      );
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      await tester.tap(find.text('Coffee beans'));
      await pumpAsync(tester);

      expect(find.byType(ExpenseFormPage), findsOneWidget);
      expect(find.text('Edit Expense'), findsOneWidget);
      expect(find.text('Coffee beans'), findsOneWidget);
      expect(find.text('255.00'), findsOneWidget);
      expect(find.text('Weekly order'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Coffee (large)',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '320.00');
      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(ExpenseFormPage), findsNothing);
      expect(find.text('Expense updated.'), findsOneWidget);

      final saved = fakeExpenses.storedExpenses.single;
      expect(saved.name, 'Coffee (large)');
      expect(saved.amountPaise, 32000);
      expect(saved.note, 'Weekly order');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('responsive layout', () {
    testWidgets('renders cards on mobile and a data table when wide', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      fakeExpenses.storedExpenses.add(
        expense('e1', 'Coffee beans', amountPaise: 25500),
      );

      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpAuthenticated(tester);
      await openExpenses(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Coffee beans'), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Coffee beans'), findsOneWidget);
    });
  });
}
