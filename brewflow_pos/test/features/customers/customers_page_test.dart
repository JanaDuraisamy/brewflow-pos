import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_detail_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_form_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeCustomersRepository fakeCustomers;
  late FakeCustomerLedgerRepository fakeLedger;

  final now = DateTime.now().toUtc();

  Customer customer(
    String id,
    String name, {
    String? phone,
    String? email,
    String? address,
    bool isActive = true,
  }) => Customer(
    id: id,
    name: name,
    phone: phone,
    email: email,
    address: address,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  FakeLedgerBill bill({
    String id = 's1',
    String customerId = 'c1',
    String receiptNumber = 'BF-000001',
    int totalPaise = 12000,
    DateTime? createdAt,
  }) => FakeLedgerBill(
    id: id,
    customerId: customerId,
    receiptNumber: receiptNumber,
    createdAt: createdAt ?? now,
    totalPaise: totalPaise,
  );

  CustomerPayment payment({
    String id = 'p1',
    String customerId = 'c1',
    String saleId = 's1',
    int amountPaise = 5000,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? note,
    DateTime? paidAt,
  }) => CustomerPayment(
    id: id,
    customerId: customerId,
    saleId: saleId,
    amountPaise: amountPaise,
    paymentMethod: paymentMethod,
    note: note,
    paidAt: paidAt ?? now,
    reversed: false,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeCustomers = FakeCustomersRepository();
    fakeLedger = FakeCustomerLedgerRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      customersRepositoryProvider.overrideWithValue(fakeCustomers),
      customerLedgerRepositoryProvider.overrideWithValue(fakeLedger),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
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

  Future<void> openCustomers(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.customers);
    await pumpAsync(tester);
  }

  /// The form is a scrollable column, so its action buttons only exist in the
  /// tree once scrolled into view.
  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.descendant(
      of: find.byType(CustomerFormPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(finder, 120, scrollable: scrollable.first);
    await tester.pump();
  }

  /// The customer detail page is one long ListView, so ledger sections and the
  /// Record Payment action only render once scrolled into view.
  Future<void> scrollDetailTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.descendant(
      of: find.byType(CustomerDetailPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(finder, 150, scrollable: scrollable.first);
    await tester.pump();
  }

  group('customers landing page', () {
    testWidgets('shows the empty state when there are no customers', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      expect(find.byType(CustomersPage), findsOneWidget);
      expect(find.text('No customers yet'), findsOneWidget);
      expect(
        find.text('Add your first customer to start building profiles.'),
        findsOneWidget,
      );
    });

    testWidgets('lists customers with contact details', (tester) async {
      fakeCustomers.storedCustomers.addAll([
        customer(
          'c1',
          'Priya',
          phone: '9845012345',
          email: 'priya@example.com',
        ),
        customer('c2', 'Karthik', phone: '9000012345'),
        customer('c3', 'Meena', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Karthik'), findsOneWidget);
      expect(find.text('Meena'), findsOneWidget);
      expect(find.text('9845012345'), findsOneWidget);
      expect(find.text('priya@example.com'), findsOneWidget);
      // One filter chip label plus one badge per matching customer.
      expect(find.text('Active'), findsNWidgets(3));
      expect(find.text('Inactive'), findsNWidgets(2));
    });

    testWidgets('search narrows the list by name, phone and email', (
      tester,
    ) async {
      fakeCustomers.storedCustomers.addAll([
        customer('c1', 'Priya', phone: '9845012345'),
        customer('c2', 'Karthik', phone: '9000012345'),
        customer('c3', 'Meena', email: 'meena@example.com'),
      ]);
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      await tester.enterText(find.byType(TextField), 'priya');
      await pumpAsync(tester);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Karthik'), findsNothing);

      await tester.enterText(find.byType(TextField), '900001');
      await pumpAsync(tester);
      expect(find.text('Karthik'), findsOneWidget);
      expect(find.text('Priya'), findsNothing);

      await tester.enterText(find.byType(TextField), 'meena@example');
      await pumpAsync(tester);
      expect(find.text('Meena'), findsOneWidget);
      expect(find.text('Karthik'), findsNothing);
    });

    testWidgets('status filter narrows the list', (tester) async {
      fakeCustomers.storedCustomers.addAll([
        customer('c1', 'Priya', isActive: true),
        customer('c2', 'Old Guest', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      await tester.tap(find.widgetWithText(AppFilterChip, 'Inactive'));
      await pumpAsync(tester);

      expect(find.text('Old Guest'), findsOneWidget);
      expect(find.text('Priya'), findsNothing);
    });

    testWidgets('clearing a dead-end filter restores the full list', (
      tester,
    ) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await pumpAsync(tester);

      expect(find.text('No customers match your filters'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await pumpAsync(tester);

      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('No customers match your filters'), findsNothing);
    });

    testWidgets('load failures show an error state that can retry', (
      tester,
    ) async {
      fakeCustomers.loadError = const UnexpectedCustomersFailure();
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      fakeCustomers.loadError = null;
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);

      expect(find.text('No customers yet'), findsOneWidget);
    });
  });

  group('customer form', () {
    Future<void> openNewCustomerForm(WidgetTester tester) async {
      await openCustomers(tester);
      await tester.tap(find.text('Add Customer').first);
      await pumpAsync(tester);
      expect(find.byType(CustomerFormPage), findsOneWidget);
    }

    testWidgets('add customer button opens the form and cancel returns', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewCustomerForm(tester);

      expect(find.text('New Customer'), findsOneWidget);

      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await scrollFormTo(tester, cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(CustomerFormPage), findsNothing);
      expect(find.byType(CustomersPage), findsOneWidget);
    });

    testWidgets('saves a new customer and returns to a refreshed list', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewCustomerForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Priya');
      await tester.enterText(find.byType(TextFormField).at(1), '9845012345');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'priya@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(3), 'Anna Nagar');

      final save = find.widgetWithText(FilledButton, 'Save Customer');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(CustomerFormPage), findsNothing);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Customer added.'), findsOneWidget);

      final saved = fakeCustomers.storedCustomers.single;
      expect(saved.name, 'Priya');
      expect(saved.phone, '9845012345');
      expect(saved.email, 'priya@example.com');
      expect(saved.address, 'Anna Nagar');
      expect(saved.isActive, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('validates required fields before saving', (tester) async {
      await pumpAuthenticated(tester);
      await openNewCustomerForm(tester);

      final save = find.widgetWithText(FilledButton, 'Save Customer');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await tester.pump();

      expect(find.text('Customer name is required.'), findsOneWidget);
      expect(find.byType(CustomerFormPage), findsOneWidget);
      expect(fakeCustomers.storedCustomers, isEmpty);
    });

    testWidgets('validates phone and email formats', (tester) async {
      await pumpAuthenticated(tester);
      await openNewCustomerForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Priya');
      await tester.enterText(find.byType(TextFormField).at(1), '123');
      await tester.enterText(find.byType(TextFormField).at(2), 'not-an-email');

      final save = find.widgetWithText(FilledButton, 'Save Customer');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await tester.pump();

      expect(find.text('Enter a valid phone number.'), findsOneWidget);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(fakeCustomers.storedCustomers, isEmpty);
    });

    testWidgets('rejects a duplicate phone inline without leaving the form', (
      tester,
    ) async {
      fakeCustomers.storedCustomers.add(
        customer('c1', 'Priya', phone: '9845012345'),
      );
      await pumpAuthenticated(tester);
      await openNewCustomerForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Karthik');
      await tester.enterText(find.byType(TextFormField).at(1), '9845012345');

      final save = find.widgetWithText(FilledButton, 'Save Customer');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(
        find.text('A customer with this phone already exists.'),
        findsOneWidget,
      );
      expect(find.byType(CustomerFormPage), findsOneWidget);
      expect(fakeCustomers.storedCustomers, hasLength(1));
    });
  });

  group('customer detail', () {
    Future<void> openDetail(WidgetTester tester, String name) async {
      await openCustomers(tester);
      await tester.tap(find.text(name));
      await pumpAsync(tester);
      expect(find.byType(CustomerDetailPage), findsOneWidget);
    }

    testWidgets('shows the full profile', (tester) async {
      fakeCustomers.storedCustomers.add(
        customer(
          'c1',
          'Priya',
          phone: '9845012345',
          email: 'priya@example.com',
          address: 'Anna Nagar, Chennai',
        ),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      expect(find.text('Customer Details'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('9845012345'), findsOneWidget);
      expect(find.text('priya@example.com'), findsOneWidget);
      expect(find.text('Anna Nagar, Chennai'), findsOneWidget);
      expect(find.textContaining('Customer since'), findsOneWidget);
      // Contact list, activity, and the financial ledger sections.
      expect(find.text('Contact details'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Financial summary'), findsOneWidget);
      expect(find.text('Purchase history'), findsOneWidget);
      expect(find.text('Payment history'), findsOneWidget);
      expect(find.text('No purchases yet'), findsOneWidget);
      expect(find.text('No payments yet'), findsOneWidget);
      // Nothing is owed, so recording a payment is not offered.
      final record = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Record Payment'),
      );
      expect(record.onPressed, isNull, reason: 'no dues yet');
    });

    testWidgets('toggle deactivates the customer', (tester) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      await tester.tap(find.byType(Switch));
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await pumpAsync(tester);

      expect(fakeCustomers.storedCustomers.single.isActive, isFalse);
      expect(find.text('Active customer'), findsOneWidget);
    });

    testWidgets('edit action opens a pre-filled form and saves changes', (
      tester,
    ) async {
      fakeCustomers.storedCustomers.add(
        customer('c1', 'Priya', phone: '9845012345'),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpAsync(tester);

      expect(find.byType(CustomerFormPage), findsOneWidget);
      expect(find.text('Edit Customer'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('9845012345'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), '9000012345');
      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(CustomerFormPage), findsNothing);
      expect(find.byType(CustomerDetailPage), findsOneWidget);
      expect(find.text('9000012345'), findsOneWidget);
      expect(fakeCustomers.storedCustomers.single.phone, '9000012345');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('edit keeps its own phone (self-exclusion)', (tester) async {
      fakeCustomers.storedCustomers.add(
        customer('c1', 'Priya', phone: '9845012345'),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpAsync(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Priya R');
      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(CustomerFormPage), findsNothing);
      expect(fakeCustomers.storedCustomers.single.name, 'Priya R');
      expect(fakeCustomers.storedCustomers.single.phone, '9845012345');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('ledger shows outstanding dues, purchases and payments', (
      tester,
    ) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      fakeLedger.bills
        ..add(
          bill(
            id: 's1',
            receiptNumber: 'BF-000001',
            totalPaise: 15000,
            createdAt: now.subtract(const Duration(days: 2)),
          ),
        )
        ..add(
          bill(
            id: 's2',
            receiptNumber: 'BF-000002',
            totalPaise: 8000,
            createdAt: now.subtract(const Duration(days: 1)),
          ),
        );
      fakeLedger.storedPayments
        ..add(payment(id: 'p1', saleId: 's1', amountPaise: 3000))
        ..add(
          payment(
            id: 'p2',
            saleId: 's2',
            amountPaise: 8000,
            paymentMethod: PaymentMethod.upi,
          ),
        );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      // Summary tiles: ₹230 purchases, ₹110 paid, ₹120 outstanding.
      expect(find.text('Outstanding'), findsOneWidget);
      expect(find.text('Total purchases'), findsOneWidget);
      expect(find.text('Total paid'), findsOneWidget);
      expect(find.text('₹230.00'), findsOneWidget);
      expect(find.text('₹120.00'), findsOneWidget);
      expect(find.text('₹110.00'), findsOneWidget);

      final record = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Record Payment'),
      );
      expect(record.onPressed, isNotNull, reason: 'dues exist');

      // Purchase rows with derived status and remaining dues.
      await scrollDetailTo(tester, find.text('Receipt BF-000002'));
      expect(find.text('Receipt BF-000001'), findsOneWidget);
      expect(find.text('Receipt BF-000002'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expect(find.text('Unpaid'), findsNothing);
      expect(find.text('Due ₹120.00'), findsOneWidget);
      expect(find.textContaining('Total ₹150.00'), findsOneWidget);
      expect(find.textContaining('Total ₹80.00'), findsOneWidget);

      // Payment history rows: amount, method and timestamp.
      await scrollDetailTo(tester, find.textContaining('UPI ·'));
      expect(find.textContaining('Cash ·'), findsOneWidget);
      expect(find.textContaining('UPI ·'), findsOneWidget);
      expect(find.text('₹30.00'), findsOneWidget);
      expect(find.text('₹80.00'), findsOneWidget);
    });

    testWidgets('records a payment and the ledger refreshes', (tester) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      fakeLedger.bills.add(
        bill(id: 's1', receiptNumber: 'BF-000001', totalPaise: 15000),
      );
      fakeLedger.storedPayments.add(
        payment(id: 'p1', saleId: 's1', amountPaise: 5000),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      expect(find.text('₹100.00'), findsOneWidget, reason: 'outstanding due');

      await scrollDetailTo(
        tester,
        find.widgetWithText(PrimaryButton, 'Record Payment'),
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Record Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Bill'), findsOneWidget);
      expect(find.text('Save Payment'), findsOneWidget);
      // Amount is pre-anchored to the remaining due.
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '100.00',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save Payment'));
      await pumpAsync(tester);

      expect(find.text('Payment recorded.'), findsOneWidget);
      expect(fakeLedger.storedPayments, hasLength(2));
      expect(fakeLedger.storedPayments.last.amountPaise, 10000);
      expect(fakeLedger.storedPayments.last.note, isNull);

      // Ledger refreshed: nothing outstanding, bill fully paid.
      await pumpAsync(tester);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Unpaid'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('records a payment with method and note', (tester) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      fakeLedger.bills.add(
        bill(id: 's1', receiptNumber: 'BF-000001', totalPaise: 15000),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      await scrollDetailTo(
        tester,
        find.widgetWithText(PrimaryButton, 'Record Payment'),
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Record Payment'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'UPI on bill');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Payment'));
      await pumpAsync(tester);

      expect(fakeLedger.storedPayments.single.paymentMethod, PaymentMethod.upi);
      expect(fakeLedger.storedPayments.single.note, 'UPI on bill');
      expect(find.text('Payment recorded.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('rejects an overpayment inline and recovers on retry', (
      tester,
    ) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      fakeLedger.bills.add(
        bill(id: 's1', receiptNumber: 'BF-000001', totalPaise: 15000),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      await scrollDetailTo(
        tester,
        find.widgetWithText(PrimaryButton, 'Record Payment'),
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Record Payment'));
      await tester.pumpAndSettle();

      fakeLedger.recordPaymentError = const PaymentExceedsDueFailure();
      await tester.enterText(find.byType(TextFormField).first, '999');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Payment'));
      await pumpAsync(tester);

      expect(
        find.text('This payment is more than the remaining balance.'),
        findsOneWidget,
      );
      expect(find.text('Save Payment'), findsOneWidget, reason: 'dialog stays');
      expect(fakeLedger.storedPayments, isEmpty);

      fakeLedger.recordPaymentError = null;
      await tester.enterText(find.byType(TextFormField).first, '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Payment'));
      await pumpAsync(tester);

      expect(fakeLedger.storedPayments.single.amountPaise, 10000);
      expect(find.text('Payment recorded.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('invalid amounts are rejected before saving', (tester) async {
      fakeCustomers.storedCustomers.add(customer('c1', 'Priya'));
      fakeLedger.bills.add(
        bill(id: 's1', receiptNumber: 'BF-000001', totalPaise: 15000),
      );
      await pumpAuthenticated(tester);
      await openDetail(tester, 'Priya');

      await scrollDetailTo(
        tester,
        find.widgetWithText(PrimaryButton, 'Record Payment'),
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Record Payment'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Save Payment'));
      await pumpAsync(tester);

      expect(find.text('Enter a valid amount (e.g. 149.50)'), findsOneWidget);
      expect(fakeLedger.storedPayments, isEmpty);

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
      fakeCustomers.storedCustomers.add(
        customer('c1', 'Priya', phone: '9845012345'),
      );

      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpAuthenticated(tester);
      await openCustomers(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Priya'), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
    });
  });
}
