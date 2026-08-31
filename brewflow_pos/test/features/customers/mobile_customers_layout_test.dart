import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
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
    bool isActive = true,
  }) => Customer(
    id: id,
    name: name,
    phone: phone,
    email: email,
    isActive: isActive,
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

  group('mobile customers layout', () {
    setUp(() {
      fakeCustomers.storedCustomers.addAll([
        customer(
          'c4',
          'A Very Long Customer Name To Exercise Ellipsis Handling',
          phone: '9845556666',
        ),
        customer('c5', 'Anand', isActive: false),
        customer('c2', 'Karthik', phone: '9000012345'),
        customer('c3', 'Meena', isActive: false),
      ]);
      // The first-sorted (and tallest) card carries an outstanding balance so
      // the due row renders on screen at every width.
      fakeLedger.bills.add(
        FakeLedgerBill(
          id: 's1',
          customerId: 'c4',
          receiptNumber: 'BF-000001',
          createdAt: now,
          totalPaise: 15000,
        ),
      );
    });

    const widths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

    for (final width in widths) {
      testWidgets('renders phone cards without overflow at ${width}dp', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);

        await pumpAuthenticated(tester);
        await openCustomers(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(CustomersPage), findsOneWidget);
        // No desktop-style tables on phone.
        expect(find.byType(DataTable), findsNothing);
        // Card hierarchy: Name, Phone, Outstanding/Due, Status.
        expect(
          find.text('A Very Long Customer Name To Exercise Ellipsis Handling'),
          findsOneWidget,
        );
        expect(find.text('9845556666'), findsOneWidget);
        expect(find.text('Due ₹150.00'), findsOneWidget);
        expect(find.text('9000012345'), findsOneWidget);
        expect(find.text('No dues'), findsNWidgets(3));
      });
    }

    testWidgets('long-press on phone customer card opens sheet and activate '
        'needs no destructive confirm', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetPhysicalSize);

      await pumpAuthenticated(tester);
      await openCustomers(tester);

      final card = find.ancestor(
        of: find.text('Anand'),
        matching: find.byType(AppCard),
      );
      expect(card, findsOneWidget);
      await tester.longPress(card);
      await tester.pumpAndSettle();

      expect(find.text('View'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      // Anand is inactive, so the sheet offers Activate (non-destructive).
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);

      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final anand = fakeCustomers.storedCustomers.firstWhere(
        (customer) => customer.id == 'c5',
      );
      expect(anand.isActive, isTrue);
    });

    testWidgets('long-press on tablet customer card opens sheet and deactivate '
        'confirms', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(700, 900);
      addTearDown(tester.view.resetPhysicalSize);

      await pumpAuthenticated(tester);
      await openCustomers(tester);

      // Tablet (600-799dp) renders the wider _CustomerCard, not the table.
      expect(find.byType(DataTable), findsNothing);

      final card = find.ancestor(
        of: find.text('Karthik'),
        matching: find.byType(AppCard),
      );
      expect(card, findsOneWidget);
      await tester.longPress(card);
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Deactivate'), findsOneWidget);

      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(find.text('Deactivate customer'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await tester.pumpAndSettle();

      final karthik = fakeCustomers.storedCustomers.firstWhere(
        (customer) => customer.id == 'c2',
      );
      expect(karthik.isActive, isFalse);
    });
  });
}
