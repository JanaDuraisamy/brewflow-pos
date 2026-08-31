import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';

void main() {
  Category category(String id, String name) => Category(
    id: id,
    name: name,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  Product product({
    String id = 'p1',
    String name = 'Filter Coffee',
    String? sku = 'FC-01',
    int pricePaise = 12000,
    int stock = 5,
    String categoryId = 'c1',
  }) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    sku: sku,
    sellingPricePaise: pricePaise,
    costPricePaise: null,
    stockQuantity: stock,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  FakeInventoryRepository seedInventory() {
    final inventory = FakeInventoryRepository();
    inventory.storedCategories
      ..add(category('c1', 'Beverages'))
      ..add(category('c2', 'Snacks'));
    inventory.storedProducts
      ..add(product(id: 'p1', name: 'Filter Coffee', stock: 5))
      ..add(
        product(
          id: 'p2',
          name: 'Green Tea',
          stock: 3,
          sku: 'GT-02',
          pricePaise: 8000,
        ),
      )
      ..add(product(id: 'p3', name: 'Samosa', stock: 0, categoryId: 'c2'))
      ..add(
        product(
          id: 'p4',
          name: 'Cake',
          stock: 3,
          categoryId: 'c2',
        ).copyWith(isActive: false),
      );
    return inventory;
  }

  Customer customer({
    String id = 'c1',
    String name = 'Anand',
    String? phone = '9845012345',
    bool active = true,
  }) => Customer(
    id: id,
    name: name,
    phone: phone,
    isActive: active,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  FakeCustomersRepository seedCustomers() {
    final customers = FakeCustomersRepository();
    customers.storedCustomers
      ..add(customer(id: 'c1', name: 'Anand', phone: '9845012345'))
      ..add(customer(id: 'c2', name: 'Ravi', phone: '9876543210'))
      ..add(customer(id: 'c3', name: 'Old Joe', active: false));
    return customers;
  }

  Future<
    (FakeInventoryRepository, FakeBillingRepository, FakeCustomersRepository)
  >
  pumpPos(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final inventory = seedInventory();
    final billing = FakeBillingRepository(inventory);
    final customers = seedCustomers();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(billing),
          customersRepositoryProvider.overrideWithValue(customers),
        ],
        child: const MaterialApp(home: Scaffold(body: PosPage())),
      ),
    );
    await tester.pumpAndSettle();
    return (inventory, billing, customers);
  }

  /// Lets any auto-hiding snackbar timer elapse so the test ends cleanly.
  Future<void> flushSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Finder addButtonFor(String productName) => find.descendant(
    of: find.ancestor(of: find.text(productName), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  testWidgets(
    'shelf lists active products and keeps active zero-stock ones visible '
    '(Bug 7.8E-B)',
    (tester) async {
      await pumpPos(tester);

      expect(find.text('Filter Coffee'), findsOneWidget);
      expect(find.text('Green Tea'), findsOneWidget);
      // An active zero-stock product is visible as sold out, not hidden.
      expect(find.text('Samosa'), findsOneWidget);
      expect(find.text('Sold out'), findsOneWidget);
      // Inactive products stay hidden.
      expect(find.text('Cake'), findsNothing);
      expect(find.text('Billing & POS'), findsOneWidget);
    },
  );

  testWidgets('adding a product fills the cart panel', (tester) async {
    await pumpPos(tester);

    expect(find.text('Your cart is empty'), findsOneWidget);

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Filter Coffee'), findsNWidgets(2));
    expect(find.text('1 in cart'), findsOneWidget);
    expect(
      find.text('₹120.00'),
      findsNWidgets(5),
      reason:
          'two shelf cards (Filter Coffee + sold-out Samosa), line total, '
          'subtotal and total',
    );
    expect(find.textContaining('Subtotal'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Complete Sale'),
          )
          .onPressed,
      isNull,
      reason: 'sale disabled until a payment method is chosen',
    );
    await flushSnackBars(tester);
  });

  testWidgets('quantity steppers stop at the stock cap', (tester) async {
    await pumpPos(tester);

    await tester.tap(addButtonFor('Green Tea'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Increase quantity'));
      await tester.pumpAndSettle();
    }
    expect(find.text('₹80.00 × 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();
    expect(find.text('Green Tea does not have enough stock.'), findsOneWidget);
    expect(find.text('₹80.00 × 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Decrease quantity'));
    await tester.pumpAndSettle();
    expect(find.text('₹80.00 × 2'), findsOneWidget);
    await flushSnackBars(tester);
  });

  testWidgets('removing a line restores the empty state', (tester) async {
    await pumpPos(tester);

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart is empty'), findsNothing);

    await tester.tap(find.byTooltip('Remove line'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('1 in cart'), findsNothing);
    await flushSnackBars(tester);
  });

  testWidgets('a successful sale shows the receipt and clears the cart', (
    tester,
  ) async {
    final (inventory, _, _) = await pumpPos(tester);

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('UPI'));
    await tester.tap(find.text('UPI'));
    await tester.pumpAndSettle();

    final complete = find.widgetWithText(FilledButton, 'Complete Sale');
    expect(tester.widget<FilledButton>(complete).onPressed, isNotNull);

    await tester.tap(complete);
    await tester.pumpAndSettle();

    expect(find.text('Sale Complete'), findsOneWidget);
    expect(find.text('Receipt BF-000001'), findsOneWidget);
    expect(find.textContaining('1 item'), findsOneWidget);

    await tester.tap(find.text('New Sale'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(
      find.textContaining('Stock 4'),
      findsOneWidget,
      reason: 'shelf refreshes with deducted stock',
    );
    await flushSnackBars(tester);
    expect(
      inventory.storedProducts.firstWhere((p) => p.id == 'p1').stockQuantity,
      4,
    );
  });

  testWidgets('a failed checkout keeps the cart and shows a safe message', (
    tester,
  ) async {
    final (_, billing, _) = await pumpPos(tester);
    billing.completeSaleError = InsufficientStockFailure('Filter Coffee');

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cash'));
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sale not completed'), findsOneWidget);
    expect(find.text('Your cart is empty'), findsNothing);
    expect(find.text('1 in cart'), findsOneWidget);
    await flushSnackBars(tester);
  });

  testWidgets(
    'checkout disables Complete Sale while in flight and ignores repeats',
    (tester) async {
      final (_, billing, _) = await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('UPI'));
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();

      final gate = Completer<void>();
      billing.completeSaleGate = gate;
      final complete = find.widgetWithText(FilledButton, 'Complete Sale');

      await tester.tap(complete);
      await tester.pump();

      final disabled = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(FilledButton),
      );
      expect(
        disabled,
        findsOneWidget,
        reason: 'Complete Sale shows a progress indicator while in flight',
      );
      expect(
        tester.widget<FilledButton>(disabled).onPressed,
        isNull,
        reason: 'button disabled while checkout is running',
      );

      await tester.tap(disabled, warnIfMissed: false);
      await tester.pump();
      expect(
        billing.checkouts,
        1,
        reason: 'repeated taps must not start a second checkout',
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Sale Complete'), findsOneWidget);
      expect(find.text('Receipt BF-000001'), findsOneWidget);

      await tester.tap(find.text('New Sale'));
      await tester.pumpAndSettle();
      expect(find.text('Your cart is empty'), findsOneWidget);
      await flushSnackBars(tester);
    },
  );

  testWidgets('search narrows the shelf', (tester) async {
    await pumpPos(tester);

    await tester.enterText(find.byType(TextField), 'tea');
    await tester.pumpAndSettle();

    expect(find.text('Green Tea'), findsOneWidget);
    expect(find.text('Filter Coffee'), findsNothing);
  });

  testWidgets('category filter narrows the shelf', (tester) async {
    await pumpPos(tester);

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snacks').last);
    await tester.pumpAndSettle();

    expect(find.text('Filter Coffee'), findsNothing);
    expect(find.text('Green Tea'), findsNothing);
    // Snacks now contains the active zero-stock Samosa (Bug 7.8E-B).
    expect(find.text('Samosa'), findsOneWidget);
  });

  testWidgets('narrow screens switch between shelf and cart without overflow', (
    tester,
  ) async {
    await pumpPos(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Filter Coffee'), findsOneWidget);

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('1 in cart'), findsOneWidget);

    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Current Sale'), findsOneWidget);
    expect(find.text('Complete Sale'), findsOneWidget);
    expect(find.text('Walk-in'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Walk-in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await flushSnackBars(tester);
  });

  testWidgets('wide layout shows shelf and cart side by side', (tester) async {
    await pumpPos(tester, size: const Size(1280, 800));

    expect(find.text('Current Sale'), findsOneWidget);
    expect(find.text('Your cart is empty'), findsOneWidget);

    await tester.tap(addButtonFor('Filter Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('1 in cart'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await flushSnackBars(tester);
  });

  group('customer selection', () {
    testWidgets(
      'cart shows a walk-in and the picker lists active customers only',
      (tester) async {
        await pumpPos(tester);

        expect(find.text('Walk-in'), findsOneWidget);

        await tester.tap(find.text('Walk-in'));
        await tester.pumpAndSettle();

        expect(find.text('Select Customer'), findsOneWidget);
        expect(find.text('Anand'), findsOneWidget);
        expect(find.text('Ravi'), findsOneWidget);
        expect(find.text('Old Joe'), findsNothing);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Select Customer'), findsNothing);
        expect(find.text('Walk-in'), findsOneWidget);
      },
    );

    testWidgets('picker search narrows the customer list', (tester) async {
      await pumpPos(tester);

      await tester.tap(find.text('Walk-in'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'ravi');
      await tester.pumpAndSettle();

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Anand'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);
    });

    testWidgets(
      'selecting a customer links the sale and checkout persists it',
      (tester) async {
        final (_, billing, _) = await pumpPos(tester);

        await tester.tap(addButtonFor('Filter Coffee'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Walk-in'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Anand'));
        await tester.pumpAndSettle();

        expect(find.text('Anand'), findsOneWidget);
        expect(find.text('Walk-in'), findsNothing);

        await tester.ensureVisible(find.text('UPI'));

        await tester.tap(find.text('UPI'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
        await tester.pumpAndSettle();

        expect(billing.lastCustomerId, 'c1');
        expect(billing.storedSales.single.customerId, 'c1');
        expect(find.text('Sale Complete'), findsOneWidget);

        await tester.tap(find.text('New Sale'));
        await tester.pumpAndSettle();
        expect(find.text('Walk-in'), findsOneWidget);
        await flushSnackBars(tester);
      },
    );

    testWidgets('clearing the selection returns to a walk-in sale', (
      tester,
    ) async {
      await pumpPos(tester);

      await tester.tap(find.text('Walk-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ravi'));
      await tester.pumpAndSettle();
      expect(find.text('Ravi'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove customer'));
      await tester.pumpAndSettle();
      expect(find.text('Walk-in'), findsOneWidget);
      expect(find.text('Ravi'), findsNothing);
      await flushSnackBars(tester);
    });
  });

  group('Not Paid credit sales', () {
    testWidgets(
      'Not Paid without a customer shows the hint and disables Complete Sale',
      (tester) async {
        await pumpPos(tester);

        await tester.tap(addButtonFor('Filter Coffee'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Not Paid'));

        await tester.tap(find.text('Not Paid'));
        await tester.pumpAndSettle();

        expect(
          find.text('Select a customer to save this bill as Not Paid.'),
          findsOneWidget,
        );
        expect(find.text('Cash'), findsNothing);
        expect(find.text('UPI'), findsNothing);
        expect(find.text('Bank'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete Sale'),
              )
              .onPressed,
          isNull,
          reason: 'credit sale disabled until a customer is chosen',
        );

        await tester.tap(find.text('Paid'));
        await tester.pumpAndSettle();
        expect(find.text('Cash'), findsOneWidget);
        expect(
          find.text('Select a customer to save this bill as Not Paid.'),
          findsNothing,
        );
        await flushSnackBars(tester);
      },
    );

    testWidgets(
      'Not Paid with a customer previews the due and completes the credit sale',
      (tester) async {
        final (_, billing, _) = await pumpPos(tester);

        await tester.tap(addButtonFor('Filter Coffee'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Walk-in'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Anand'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Not Paid'));

        await tester.tap(find.text('Not Paid'));
        await tester.pumpAndSettle();

        expect(find.text('Due Added'), findsOneWidget);
        // Two shelf cards (Filter Coffee + sold-out Samosa), line total,
        // subtotal, total and the due preview.
        expect(find.text('₹120.00'), findsNWidgets(6));
        final complete = find.widgetWithText(FilledButton, 'Complete Sale');
        expect(tester.widget<FilledButton>(complete).onPressed, isNotNull);

        await tester.tap(complete);
        await tester.pumpAndSettle();

        expect(billing.lastPaymentStatus, PaymentStatus.notPaid);
        expect(billing.lastPaymentMethod, isNull);
        expect(billing.lastCustomerId, 'c1');
        expect(billing.storedSales.single.customerId, 'c1');

        expect(find.text('Sale Complete'), findsOneWidget);
        expect(find.textContaining('Not paid'), findsOneWidget);
        expect(find.text('Added to Customer Due: ₹120.00'), findsOneWidget);

        await tester.tap(find.text('New Sale'));
        await tester.pumpAndSettle();
        expect(find.text('Your cart is empty'), findsOneWidget);
        await flushSnackBars(tester);
      },
    );

    testWidgets('a credit checkout without a customer shows a safe message', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Not Paid'));
      await tester.tap(find.text('Not Paid'));
      await tester.pumpAndSettle();

      expect(billing.checkouts, 0);
      expect(find.text('1 in cart'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('a failed credit checkout keeps the cart and the customer', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);
      billing.completeSaleError = InsufficientStockFailure('Filter Coffee');

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Walk-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anand'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Not Paid'));
      await tester.tap(find.text('Not Paid'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sale not completed'), findsOneWidget);
      expect(find.text('Anand'), findsOneWidget);
      expect(find.text('1 in cart'), findsOneWidget);
      await flushSnackBars(tester);
    });
  });

  group('Hold Bill', () {
    testWidgets('Hold Bill is disabled on an empty cart', (tester) async {
      await pumpPos(tester);

      final hold = find.widgetWithText(OutlinedButton, 'Hold Bill');
      expect(tester.widget<OutlinedButton>(hold).onPressed, isNull);
      expect(find.text('Held Bills'), findsOneWidget);
    });

    testWidgets('holding a bill empties the cart without completing a sale', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();

      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('1 in cart'), findsNothing);
      expect(find.text('Held Bills (1)'), findsOneWidget);
      expect(billing.checkouts, 0);
      expect(billing.storedSales, isEmpty);
      expect(billing.receiptsIssued, 0);
      await flushSnackBars(tester);
    });

    testWidgets('the Held Bills sheet lists bills with customer, items, total '
        'and hold time', (tester) async {
      await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);
      await tester.tap(addButtonFor('Green Tea'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);

      await tester.tap(find.text('Held Bills (2)'));
      await tester.pumpAndSettle();

      expect(find.text('#1 · Walk-in'), findsOneWidget);
      expect(find.text('#2 · Walk-in'), findsOneWidget);
      expect(find.text('1 item · ₹120.00 · held just now'), findsOneWidget);
      expect(find.text('1 item · ₹80.00 · held just now'), findsOneWidget);
      expect(find.text('2 held'), findsOneWidget);
      expect(find.text('Resume'), findsNWidgets(2));
      expect(find.text('Delete'), findsNWidgets(2));
      await flushSnackBars(tester);
    });

    testWidgets('resuming a held bill restores the cart and closes the sheet', (
      tester,
    ) async {
      await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);

      await tester.tap(find.text('Held Bills (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(find.text('1 in cart'), findsOneWidget);
      expect(find.text('₹120.00 × 1'), findsOneWidget);
      expect(find.text('Held Bills'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('resuming restores the payment status and method', (
      tester,
    ) async {
      await pumpPos(tester);

      // Bill #1: paid with UPI.
      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('UPI'));
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);

      // Bill #2: Not Paid for Anand.
      await tester.tap(addButtonFor('Green Tea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Walk-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anand'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Not Paid'));
      await tester.tap(find.text('Not Paid'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);

      await tester.tap(find.text('Held Bills (2)'));
      await tester.pumpAndSettle();

      // Resume bill #1 (cart is empty): UPI must come back.
      await tester.tap(find.text('Resume').first);
      await tester.pumpAndSettle();
      final methodPicker = tester.widget<SegmentedButton<PaymentMethod>>(
        find.byType(SegmentedButton<PaymentMethod>),
      );
      expect(methodPicker.selected, {PaymentMethod.upi});
      expect(find.text('1 in cart'), findsOneWidget);

      // Resume bill #2 with a non-empty cart: confirm replacement, then the
      // Not Paid status and Anand must come back.
      await tester.tap(find.text('Held Bills (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Resume held bill?'), findsOneWidget);
      expect(
        find.text('Current bill will be replaced. Continue?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final statusPicker = tester.widget<SegmentedButton<PaymentStatus>>(
        find.byType(SegmentedButton<PaymentStatus>),
      );
      expect(statusPicker.selected, {PaymentStatus.notPaid});
      expect(find.text('Due Added'), findsOneWidget);
      // Shelf card, line total, subtotal, total and the due preview.
      expect(find.text('₹80.00'), findsNWidgets(5));
      await flushSnackBars(tester);
    });

    testWidgets('resume with a non-empty cart asks for confirmation; cancel '
        'keeps both bills', (tester) async {
      await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);
      await tester.tap(addButtonFor('Green Tea'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Held Bills (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(find.text('Resume held bill?'), findsOneWidget);
      expect(
        find.text('Current bill will be replaced. Continue?'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('#1 · Walk-in'), findsOneWidget);
      expect(find.text('Held Bills (1)'), findsOneWidget);
      expect(find.text('₹80.00 × 1'), findsOneWidget);
      expect(find.text('₹120.00 × 1'), findsNothing);
      expect(find.text('1 in cart'), findsOneWidget);
      await flushSnackBars(tester);
    });

    testWidgets('deleting a held bill asks for confirmation and removes only '
        'that bill', (tester) async {
      await pumpPos(tester);

      await tester.tap(addButtonFor('Filter Coffee'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);
      await tester.tap(addButtonFor('Green Tea'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Hold Bill'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Hold Bill'));
      await tester.pumpAndSettle();
      await flushSnackBars(tester);

      await tester.tap(find.text('Held Bills (2)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete held bill #1?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('#1 · Walk-in'), findsOneWidget);
      expect(find.text('#2 · Walk-in'), findsOneWidget);

      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // The remaining bill is renumbered positionally to #1 (the tea bill).
      expect(find.text('1 item · ₹80.00 · held just now'), findsOneWidget);
      expect(find.text('1 item · ₹120.00 · held just now'), findsNothing);
      expect(find.text('1 held'), findsOneWidget);

      // Close the sheet (tap the barrier); the button label drops the count.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Held Bills (1)'), findsOneWidget);
      await flushSnackBars(tester);
    });
  });
}
