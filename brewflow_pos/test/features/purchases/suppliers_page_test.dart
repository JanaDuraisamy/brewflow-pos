import 'dart:async';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/supplier_form_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeSuppliersRepository fakeSuppliers;

  final now = DateTime.now().toUtc();

  Supplier supplier(
    String id,
    String name, {
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool isActive = true,
  }) => Supplier(
    id: id,
    name: name,
    phone: phone,
    email: email,
    address: address,
    notes: notes,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeSuppliers = FakeSuppliersRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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

  Future<void> openSuppliers(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.suppliers);
    await pumpAsync(tester);
  }

  /// The form is a scrollable column, so its action buttons only exist in the
  /// tree once scrolled into view.
  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.descendant(
      of: find.byType(SupplierFormPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(finder, 120, scrollable: scrollable.first);
    await tester.pump();
  }

  group('suppliers landing page', () {
    testWidgets('shows the empty state when there are no suppliers', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      expect(find.byType(SuppliersPage), findsOneWidget);
      expect(find.text('No suppliers yet'), findsOneWidget);
      expect(
        find.text('Add your first supplier to start building profiles.'),
        findsOneWidget,
      );
    });

    testWidgets('lists suppliers with contact details and status', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.addAll([
        supplier(
          's1',
          'Acme Supplies',
          phone: '9845012345',
          email: 'acme@example.com',
        ),
        supplier('s2', 'Brew Traders', phone: '9000012345'),
        supplier('s3', 'Old Mills', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Brew Traders'), findsOneWidget);
      expect(find.text('Old Mills'), findsOneWidget);
      expect(find.text('9845012345'), findsOneWidget);
      expect(find.text('acme@example.com'), findsOneWidget);
      // One filter chip label plus one badge per matching supplier.
      expect(find.text('Active'), findsNWidgets(3));
      expect(find.text('Inactive'), findsNWidgets(2));
    });

    testWidgets('search narrows the list by name, phone and email', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.addAll([
        supplier('s1', 'Acme Supplies', phone: '9845012345'),
        supplier('s2', 'Brew Traders', phone: '9000012345'),
        supplier('s3', 'Old Mills', email: 'mills@example.com'),
      ]);
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      await tester.enterText(find.byType(TextField), 'acme');
      await pumpAsync(tester);
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Brew Traders'), findsNothing);

      await tester.enterText(find.byType(TextField), '900001');
      await pumpAsync(tester);
      expect(find.text('Brew Traders'), findsOneWidget);
      expect(find.text('Acme Supplies'), findsNothing);

      await tester.enterText(find.byType(TextField), 'mills@example');
      await pumpAsync(tester);
      expect(find.text('Old Mills'), findsOneWidget);
      expect(find.text('Brew Traders'), findsNothing);
    });

    testWidgets('status filter narrows the list', (tester) async {
      fakeSuppliers.storedSuppliers.addAll([
        supplier('s1', 'Acme Supplies', isActive: true),
        supplier('s2', 'Old Mills', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      await tester.tap(find.widgetWithText(AppFilterChip, 'Inactive'));
      await pumpAsync(tester);

      expect(find.text('Old Mills'), findsOneWidget);
      expect(find.text('Acme Supplies'), findsNothing);
    });

    testWidgets('clearing a dead-end filter restores the full list', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await pumpAsync(tester);

      expect(find.text('No suppliers match your filters'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await pumpAsync(tester);

      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('No suppliers match your filters'), findsNothing);
    });

    testWidgets('stays in a loading state while suppliers load', (
      tester,
    ) async {
      final gate = Completer<void>();
      fakeSuppliers.loadGate = gate;
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      await pumpAuthenticated(tester);

      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.suppliers);
      await tester.pump();
      await tester.pump();

      expect(find.text('Loading suppliers…'), findsOneWidget);

      gate.complete();
      await pumpAsync(tester);

      expect(find.text('Acme Supplies'), findsOneWidget);
    });

    testWidgets('load failures show a safe error state that can retry', (
      tester,
    ) async {
      fakeSuppliers.loadError = const UnexpectedSuppliersFailure();
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      fakeSuppliers.loadError = null;
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);

      expect(find.text('No suppliers yet'), findsOneWidget);
    });

    testWidgets('deactivating a supplier flips the status in place', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      expect(fakeSuppliers.storedSuppliers.single.isActive, isTrue);

      await tester.tap(find.byTooltip('Deactivate supplier'));
      await pumpAsync(tester);

      expect(fakeSuppliers.storedSuppliers.single.isActive, isFalse);
      // Chip label plus the supplier badge.
      expect(find.text('Inactive'), findsNWidgets(2));
      expect(find.byTooltip('Activate supplier'), findsOneWidget);
    });

    testWidgets('activating a supplier flips the status back', (tester) async {
      fakeSuppliers.storedSuppliers.add(
        supplier('s1', 'Acme Supplies', isActive: false),
      );
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      expect(fakeSuppliers.storedSuppliers.single.isActive, isFalse);

      await tester.tap(find.byTooltip('Activate supplier'));
      await pumpAsync(tester);

      expect(fakeSuppliers.storedSuppliers.single.isActive, isTrue);
      // Chip label plus the supplier badge.
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.byTooltip('Deactivate supplier'), findsOneWidget);
    });
  });

  group('supplier form', () {
    Future<void> openNewSupplierForm(WidgetTester tester) async {
      await openSuppliers(tester);
      await tester.tap(find.text('Add Supplier').first);
      await pumpAsync(tester);
      expect(find.byType(SupplierFormPage), findsOneWidget);
    }

    testWidgets('add supplier button opens the form and cancel returns', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewSupplierForm(tester);

      expect(find.text('New Supplier'), findsOneWidget);

      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await scrollFormTo(tester, cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(SupplierFormPage), findsNothing);
      expect(find.byType(SuppliersPage), findsOneWidget);
    });

    testWidgets('saves a new supplier and returns to a refreshed list', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openNewSupplierForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Acme Supplies');
      await tester.enterText(find.byType(TextFormField).at(1), '9845012345');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'acme@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(3), 'Anna Nagar');
      await tester.enterText(find.byType(TextFormField).at(4), 'Coffee beans');

      final save = find.widgetWithText(FilledButton, 'Save Supplier');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(SupplierFormPage), findsNothing);
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Supplier added.'), findsOneWidget);

      final saved = fakeSuppliers.storedSuppliers.single;
      expect(saved.name, 'Acme Supplies');
      expect(saved.phone, '9845012345');
      expect(saved.email, 'acme@example.com');
      expect(saved.address, 'Anna Nagar');
      expect(saved.notes, 'Coffee beans');
      expect(saved.isActive, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('validates the required name before saving', (tester) async {
      await pumpAuthenticated(tester);
      await openNewSupplierForm(tester);

      final save = find.widgetWithText(FilledButton, 'Save Supplier');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await tester.pump();

      expect(find.text('Supplier name is required.'), findsOneWidget);
      expect(find.byType(SupplierFormPage), findsOneWidget);
      expect(fakeSuppliers.storedSuppliers, isEmpty);
    });

    testWidgets('rejects a duplicate phone inline without leaving the form', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(
        supplier('s1', 'Acme Supplies', phone: '9845012345'),
      );
      await pumpAuthenticated(tester);
      await openNewSupplierForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Brew Traders');
      await tester.enterText(find.byType(TextFormField).at(1), '9845012345');

      final save = find.widgetWithText(FilledButton, 'Save Supplier');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(
        find.text('A supplier with this phone already exists.'),
        findsOneWidget,
      );
      expect(find.byType(SupplierFormPage), findsOneWidget);
      expect(fakeSuppliers.storedSuppliers, hasLength(1));
    });

    testWidgets('edit prefills the form and saves changes', (tester) async {
      fakeSuppliers.storedSuppliers.add(
        supplier(
          's1',
          'Acme Supplies',
          phone: '9845012345',
          email: 'acme@example.com',
          address: 'Anna Nagar',
          notes: 'Coffee beans',
        ),
      );
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      await tester.tap(find.byTooltip('Edit supplier'));
      await pumpAsync(tester);
      expect(find.byType(SupplierFormPage), findsOneWidget);
      expect(find.text('Edit Supplier'), findsOneWidget);

      expect(
        find.widgetWithText(TextFormField, 'Acme Supplies'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '9845012345'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'acme@example.com'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Coffee beans'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'Acme Co');
      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(SupplierFormPage), findsNothing);
      expect(find.text('Acme Co'), findsOneWidget);
      expect(find.text('Supplier updated.'), findsOneWidget);
      expect(fakeSuppliers.storedSuppliers.single.name, 'Acme Co');
      expect(fakeSuppliers.storedSuppliers.single.phone, '9845012345');

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('responsive layout', () {
    testWidgets('renders cards on mobile and a data table when wide', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(
        supplier('s1', 'Acme Supplies', phone: '9845012345'),
      );
      await pumpAuthenticated(tester);
      await openSuppliers(tester);

      tester.view.physicalSize = const Size(360, 640);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Acme Supplies'), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Acme Supplies'), findsOneWidget);
    });
  });
}
