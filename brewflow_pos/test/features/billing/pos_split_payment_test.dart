import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// POS split-payment flow, end to end through the widget tree.
///
/// The regression this file locks: entering a valid split left the bill
/// uncompletable. Turning split mode on nulls the single-method picker
/// (`_payment = null`, correct — a split has no single method), but the
/// Complete Sale gate keyed on `payment != null` and ignored `splitMode`, so
/// the button stayed disabled forever. The cashier saw a sheet that said
/// "Exact — ready to complete" and a dead button underneath it.
///
/// The rule under test, verbatim from the brief: ₹200 CASH + ₹78 UPI = ₹278.
/// ---------------------------------------------------------------------------
void main() {
  // ₹278 exactly, so the business-rule amounts are the real ones.
  const totalPaise = 27800;

  Category category(String id, String name) => Category(
    id: id,
    name: name,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  Future<
    (FakeInventoryRepository, FakeBillingRepository, FakeCustomersRepository)
  >
  pumpPos(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final inventory = FakeInventoryRepository();
    inventory.storedCategories.add(category('c1', 'Beverages'));
    inventory.storedProducts.add(
      Product(
        id: 'p-ride',
        categoryId: 'c1',
        name: 'Combo Ride',
        sku: 'CR-278',
        sellingPricePaise: totalPaise,
        costPricePaise: null,
        stockQuantity: 5,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        // The Cafe shop id FakeStaffRepository.ensureShop() hands out.
        shopId: 'shop-1',
      ),
    );
    final billing = FakeBillingRepository(inventory);
    final customers = FakeCustomersRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...businessScopeOverrides(),
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

  Finder addCombo() => find.descendant(
    of: find.ancestor(of: find.text('Combo Ride'), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  Finder completeButton() => find.widgetWithText(FilledButton, 'Complete Sale');
  Finder confirmSplitButton() =>
      find.widgetWithText(FilledButton, 'Confirm Split');

  /// Scoped to the modal sheet: the POS page behind it has its own text fields
  /// (customer search), so an unscoped `find.byType(TextField)` would type into
  /// the wrong widget.
  Finder sheetFields() => find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextField),
  );

  bool completeEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(completeButton()).onPressed != null;

  /// Opens split mode, types [cash]/[upi] rupees and confirms.
  Future<void> enterSplit(WidgetTester tester, String cash, String upi) async {
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(find.text('Split Payment'), findsOneWidget);
    expect(find.text('Total: ₹278.00'), findsOneWidget);

    await tester.enterText(sheetFields().at(0), cash);
    await tester.pumpAndSettle();
    await tester.enterText(sheetFields().at(1), upi);
    await tester.pumpAndSettle();

    await tester.tap(confirmSplitButton());
    await tester.pumpAndSettle();
  }

  Future<void> flushSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('split payment completes the bill', () {
    testWidgets('₹200 CASH + ₹78 UPI = ₹278 is enabled and completes', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      // No single method chosen yet.
      expect(completeEnabled(tester), isFalse);

      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      // The reported dead end: a valid split left the button disabled.
      await tester.enterText(sheetFields().at(0), '200');
      await tester.pumpAndSettle();
      await tester.enterText(sheetFields().at(1), '78');
      await tester.pumpAndSettle();

      expect(find.text('Exact — ready to complete'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirmSplitButton()).onPressed,
        isNotNull,
      );
      // Before confirming, still disabled.
      expect(completeEnabled(tester), isFalse);

      await tester.tap(confirmSplitButton());
      await tester.pumpAndSettle();

      expect(
        completeEnabled(tester),
        isTrue,
        reason:
            'a confirmed exact split is the payment proof; the single-method '
            'picker is null by design in split mode',
      );

      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      expect(billing.storedSales, hasLength(1));
      final sale = billing.storedSales.single;
      expect(sale.totalPaise, totalPaise);
      expect(
        sale.paymentMethod,
        isNull,
        reason: 'a split sale has no single method on the header',
      );
      expect(sale.payments, hasLength(2));
      expect(sale.payments[0].paymentMethod, PaymentMethod.cash);
      expect(sale.payments[0].amountPaise, 20000);
      expect(sale.payments[1].paymentMethod, PaymentMethod.upi);
      expect(sale.payments[1].amountPaise, 7800);

      await flushSnackBars(tester);
    });

    testWidgets('₹100 CASH + ₹178 UPI = ₹278 also completes', (tester) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await enterSplit(tester, '100', '178');
      expect(completeEnabled(tester), isTrue);

      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      expect(billing.storedSales, hasLength(1));
      final sale = billing.storedSales.single;
      expect(sale.payments, hasLength(2));
      expect(sale.payments[0].amountPaise, 10000);
      expect(sale.payments[1].amountPaise, 17800);
      expect(
        sale.payments.fold<int>(0, (a, p) => a + p.amountPaise),
        totalPaise,
      );

      await flushSnackBars(tester);
    });

    testWidgets('decimal rupees are exact: ₹200.50 + ₹77.50', (tester) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await enterSplit(tester, '200.50', '77.50');
      expect(completeEnabled(tester), isTrue);

      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      expect(billing.storedSales, hasLength(1));
      final sale = billing.storedSales.single;
      expect(sale.payments[0].amountPaise, 20050);
      expect(sale.payments[1].amountPaise, 7750);
      expect(sale.totalPaise, totalPaise);

      await flushSnackBars(tester);
    });
  });

  group('split payment is rejected before checkout', () {
    testWidgets('incomplete split cannot be confirmed', (tester) async {
      await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      await tester.enterText(sheetFields().at(0), '200');
      await tester.enterText(sheetFields().at(1), '70');
      await tester.pumpAndSettle();

      expect(find.text('Remaining: ₹8.00'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirmSplitButton()).onPressed,
        isNull,
      );
      expect(completeEnabled(tester), isFalse);

      await flushSnackBars(tester);
    });

    testWidgets('overpayment cannot be confirmed', (tester) async {
      await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      await tester.enterText(sheetFields().at(0), '200');
      await tester.enterText(sheetFields().at(1), '100');
      await tester.pumpAndSettle();

      expect(find.text('Overpaid: ₹22.00'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirmSplitButton()).onPressed,
        isNull,
      );

      await flushSnackBars(tester);
    });

    testWidgets('leaving split mode re-arms the single-method gate', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await enterSplit(tester, '200', '78');
      expect(completeEnabled(tester), isTrue);

      // Toggling Split off must discard the confirmed draft, not leave a stale
      // one gating the button.
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      expect(
        completeEnabled(tester),
        isFalse,
        reason: 'no payment method chosen after leaving split mode',
      );

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      expect(completeEnabled(tester), isTrue);

      await tester.tap(completeButton());
      await tester.pumpAndSettle();
      expect(billing.storedSales, hasLength(1));

      await flushSnackBars(tester);
    });
  });

  group('single-payment checkout is preserved', () {
    testWidgets('single CASH still completes', (tester) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      expect(completeEnabled(tester), isTrue);

      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      expect(billing.storedSales, hasLength(1));
      final sale = billing.storedSales.single;
      expect(sale.paymentMethod, PaymentMethod.cash);
      expect(sale.totalPaise, totalPaise);

      await flushSnackBars(tester);
    });

    testWidgets('single UPI still completes', (tester) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      expect(completeEnabled(tester), isTrue);

      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      expect(billing.storedSales, hasLength(1));
      expect(billing.storedSales.single.paymentMethod, PaymentMethod.upi);

      await flushSnackBars(tester);
    });
  });

  group('input is rupees, never paise', () {
    testWidgets('typing 200 means ₹200, not 200 paise', (tester) async {
      await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      // A single ₹200 leg against a ₹278 total leaves ₹78 remaining — which
      // is only true if 200 was read as 200 rupees. Read as paise it would
      // leave ₹276 remaining.
      await tester.enterText(sheetFields().at(0), '200');
      await tester.pumpAndSettle();
      expect(find.text('Remaining: ₹78.00'), findsOneWidget);

      // The labels must not leak the internal unit.
      expect(find.text('Cash amount (₹)'), findsOneWidget);
      expect(find.text('UPI amount (₹)'), findsOneWidget);
      expect(find.textContaining('paise'), findsNothing);

      await flushSnackBars(tester);
    });

    testWidgets('a total in rupees is shown with a single ₹ symbol', (
      tester,
    ) async {
      await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      expect(find.text('Total: ₹278.00'), findsOneWidget);
      expect(find.text('₹₹278.00'), findsNothing);
      expect(
        RegExp('₹')
            .allMatches(
              find.text('Total: ₹278.00').evaluate().single.toString(),
            )
            .length,
        lessThanOrEqualTo(1),
      );

      await flushSnackBars(tester);
    });
  });

  group('receipt renders the split', () {
    testWidgets('a completed split sale shows each leg on the receipt', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await enterSplit(tester, '200', '78');
      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      // The success screen is part of "completing the bill": a split sale has
      // no single method on the header, so this used to throw a null-check
      // error here instead of confirming the sale to the cashier.
      expect(find.text('Sale Complete'), findsOneWidget);
      expect(
        find.textContaining('Split: Cash ₹200.00 + UPI ₹78.00'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(billing.storedSales, hasLength(1));

      await flushSnackBars(tester);
    });

    testWidgets('a single-method sale still names one method', (tester) async {
      await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await tester.tap(completeButton());
      await tester.pumpAndSettle();

      expect(find.text('Sale Complete'), findsOneWidget);
      expect(find.textContaining('· Cash'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await flushSnackBars(tester);
    });
  });

  group('cart is not consumed by a rejected split', () {
    testWidgets('leaving the cart intact when the split is incomplete', (
      tester,
    ) async {
      final (_, billing, _) = await pumpPos(tester);
      await tester.tap(addCombo());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();
      await tester.enterText(sheetFields().at(0), '10');
      await tester.enterText(sheetFields().at(1), '10');
      await tester.pumpAndSettle();

      // Dismiss the sheet without confirming.
      await tester.tapAt(const Offset(100, 60));
      await tester.pumpAndSettle();

      expect(billing.storedSales, isEmpty);
      expect(find.text('1 in cart'), findsOneWidget);
      expect(find.text('Combo Ride'), findsWidgets);

      await flushSnackBars(tester);
    });
  });
}
