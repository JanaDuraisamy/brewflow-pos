import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_preferences_storage.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// POS payment hardening: the business rules from the brief, locked for both
/// the Cafe and the Food Truck counter.
///
/// The regression class this file guards is a cashier-facing one. Split tender
/// shipped with two holes: a one-instrument "split" (one Cash row, nothing
/// else) was accepted everywhere and read back as split tender, and a leg
/// could carry a method the counter does not accept. Single-method sales also
/// accepted BANK for new bills even though BANK is history-only, and a switch
/// of business left the previous shop's payment selection and cart on screen.
///
/// Each test below is one numbered rule from the brief.
/// ---------------------------------------------------------------------------
/// In-memory [SecureStorage] so AppStorage.init is safe inside a test.
class _FakeSecure implements SecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      _values[key] == 'true';

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value.toString();
  }

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async =>
      int.tryParse(_values[key] ?? '') ?? defaultValue;

  @override
  Future<void> writeInt(String key, int value) async {
    _values[key] = value.toString();
  }

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}

/// Pumps until no transient callbacks remain. The POS page kicks off async
/// provider reads (shop id, shelf, cart), so a bare pumpAndSettle can return
/// mid-flight.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.binding.transientCallbackCount == 0) return;
  }
}

void main() {
  // ₹278, so the split amounts in the brief (₹200 + ₹78) are the real ones.
  const totalPaise = 27800;
  const cafeId = 'shop-1'; // FakeStaffRepository.ensureShop() mints this.
  const truckId = 'shop-truck';

  // AppStorage.init is a no-op once it has run, so the backing store is bound
  // once for the whole file. Each test rewrites the key it needs.
  final prefs = FakePreferencesStorage();

  setUpAll(() async {
    await AppStorage.init(secure: _FakeSecure(), preferences: prefs);
  });

  Category category() => Category(
    id: 'c1',
    name: 'Beverages',
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  );

  Product product(String shopId, String name) => Product(
    id: 'p-$shopId',
    categoryId: 'c1',
    name: name,
    sku: 'CR-278-$shopId',
    sellingPricePaise: totalPaise,
    costPricePaise: null,
    stockQuantity: 5,
    isActive: true,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    shopId: shopId,
  );

  /// Pumps the POS shelf for [business] against fake repositories and returns
  /// the container, so a test can switch business mid-cart.
  Future<
    ({
      ProviderContainer container,
      FakeInventoryRepository inventory,
      FakeBillingRepository billing,
      FakeCustomersRepository customers,
      String shopId,
      String productName,
    })
  >
  pumpPos(WidgetTester tester, {required BusinessContext business}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    // Pin the truck id so browsing it never mints a shop as a side effect.
    await prefs.writeString(
      BusinessSwitcherController.foodTruckShopIdKey,
      truckId,
    );

    final shopId = business == BusinessContext.cafe ? cafeId : truckId;
    final productName = shopId == cafeId ? 'Cafe Combo' : 'Truck Combo';

    final inventory = FakeInventoryRepository();
    inventory.storedCategories.add(category());
    // Only the active business is seeded. The Cafe shelf is loaded unscoped and
    // relies on the real repository to scope by session shop, which the fake
    // cannot do, so seeding both would show two rows and prove nothing.
    inventory.storedProducts.add(product(shopId, productName));

    final billing = FakeBillingRepository(inventory);
    final customers = FakeCustomersRepository();
    // Seeded before the pump: posCustomersProvider resolves a cart's
    // selectedCustomerId against its cached list, so a customer added after
    // the first build would never be found.
    customers.storedCustomers.add(
      Customer(
        id: 'cust-1',
        name: 'Anand',
        phone: '9845012345',
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        billingRepositoryProvider.overrideWithValue(billing),
        customersRepositoryProvider.overrideWithValue(customers),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(FakeCloudShopResolver()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(businessSwitcherProvider.notifier).select(business);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PosPage())),
      ),
    );
    await settle(tester);
    expect(find.text(productName), findsOneWidget);
    return (
      container: container,
      inventory: inventory,
      billing: billing,
      customers: customers,
      shopId: shopId,
      productName: productName,
    );
  }

  Finder addButton(String productName) => find.descendant(
    of: find.ancestor(of: find.text(productName), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  Finder completeButton() => find.widgetWithText(FilledButton, 'Complete Sale');
  Finder confirmSplitButton() =>
      find.widgetWithText(FilledButton, 'Confirm Split');

  /// Scoped to the sheet: the page behind it has its own text fields.
  Finder sheetFields() => find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextField),
  );

  bool completeEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(completeButton()).onPressed != null;

  Future<void> addCombo(WidgetTester tester, String productName) async {
    await tester.tap(addButton(productName));
    await settle(tester);
    expect(completeButton(), findsOneWidget);
  }

  /// Taps the single-method choice and confirms the Complete Sale gate opens.
  Future<void> pickMethod(WidgetTester tester, String method) async {
    await tester.tap(find.text(method).last);
    await settle(tester);
  }

  /// Closes the post-sale receipt so the next cart can be rung up.
  Future<void> dismissReceipt(WidgetTester tester) async {
    await tester.tap(find.text('New Sale'));
    await settle(tester);
    expect(find.text('Sale Complete'), findsNothing);
  }

  Future<void> openSplit(WidgetTester tester) async {
    await tester.tap(find.text('Split'));
    await settle(tester);
    expect(find.text('Split Payment'), findsOneWidget);
  }

  Future<void> typeSplit(WidgetTester tester, String cash, String upi) async {
    await tester.enterText(sheetFields().at(0), cash);
    await settle(tester);
    await tester.enterText(sheetFields().at(1), upi);
    await settle(tester);
  }

  Future<void> confirmSplit(WidgetTester tester) async {
    await tester.tap(confirmSplitButton());
    await settle(tester);
  }

  /// Dismisses the split sheet without confirming, by tapping the modal
  /// barrier just above the sheet. The point is derived from the sheet's own
  /// top edge so it stays on the barrier for any sheet height.
  Future<void> cancelSplit(WidgetTester tester) async {
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final top = tester.getTopLeft(sheet).dy;
    expect(
      top,
      greaterThan(20),
      reason: 'the sheet must leave a tappable barrier above it',
    );
    await tester.tapAt(Offset(tester.view.physicalSize.width / 2, top - 12));
    await settle(tester);
    expect(find.text('Split Payment'), findsNothing);
  }

  int stockOf(FakeInventoryRepository inventory, String shopId) => inventory
      .storedProducts
      .firstWhere((p) => p.shopId == shopId)
      .stockQuantity;

  for (final entry in <(String, BusinessContext)>[
    ('Cafe', BusinessContext.cafe),
    ('Food Truck', BusinessContext.foodTruck),
  ]) {
    final (label, business) = entry;

    group('$label counter', () {
      // Rule: a paid single sale is completed with exactly one method, and the
      // persisted sale records that one method and no legs.
      for (final method in ['Cash', 'UPI']) {
        testWidgets('$method completes the sale with one recorded payment', (
          tester,
        ) async {
          final env = await pumpPos(tester, business: business);
          final billing = env.billing;
          await addCombo(tester, env.productName);
          expect(
            completeEnabled(tester),
            isFalse,
            reason: 'a cart with no method must not be completable',
          );

          await pickMethod(tester, method);
          expect(completeEnabled(tester), isTrue);

          await tester.tap(completeButton());
          await settle(tester);

          expect(billing.storedSales, hasLength(1));
          final sale = billing.storedSales.single;
          expect(sale.totalPaise, totalPaise);
          expect(
            sale.paymentMethod,
            method == 'Cash' ? PaymentMethod.cash : PaymentMethod.upi,
          );
          expect(sale.payments, isEmpty);
        });
      }

      // Rule: with no method chosen, Complete Sale stays disabled and tapping
      // the disabled button cannot create a sale.
      testWidgets('no method selected blocks completion', (tester) async {
        final env = await pumpPos(tester, business: business);
        final billing = env.billing;
        await addCombo(tester, env.productName);

        expect(completeEnabled(tester), isFalse);
        // Payment status must default to paid, so a customer is not demanded
        // and no method is demanded either.
        expect(find.text('Complete Sale'), findsOneWidget);

        await tester.tap(completeButton());
        await settle(tester);
        expect(billing.storedSales, isEmpty);
      });

      // Rule: a confirmed split completes the sale with no single method, and
      // the sale records legs rather than a single payment method.
      testWidgets('a confirmed split completes with legs, not a method', (
        tester,
      ) async {
        final env = await pumpPos(tester, business: business);
        final billing = env.billing;
        await addCombo(tester, env.productName);
        await openSplit(tester);
        expect(find.text('Total: ₹278.00'), findsOneWidget);
        await typeSplit(tester, '200', '78');
        await confirmSplit(tester);

        // Split mode is on, so no single method is selected, yet the gate is
        // open: this is the bug that made valid splits dead on arrival.
        expect(completeEnabled(tester), isTrue);

        await tester.tap(completeButton());
        await settle(tester);

        expect(billing.storedSales, hasLength(1));
        final sale = billing.storedSales.single;
        expect(sale.paymentMethod, isNull);
        expect(sale.payments, hasLength(2));
        expect(sale.payments.map((p) => p.paymentMethod), [
          PaymentMethod.cash,
          PaymentMethod.upi,
        ]);
        expect(
          sale.payments.fold<int>(0, (a, p) => a + p.amountPaise),
          totalPaise,
        );
      });

      // Rule: a successful checkout creates exactly one sale and decrements
      // stock once - not once per leg and not twice per render.
      testWidgets('one sale and one stock decrement per checkout', (
        tester,
      ) async {
        final env = await pumpPos(tester, business: business);
        final billing = env.billing;
        final before = stockOf(env.inventory, env.shopId);
        await addCombo(tester, env.productName);
        await openSplit(tester);
        await typeSplit(tester, '200', '78');
        await confirmSplit(tester);
        await tester.tap(completeButton());
        await settle(tester);

        expect(billing.storedSales, hasLength(1));
        expect(stockOf(env.inventory, env.shopId), before - 1);
      });
    });
  }

  group('split validation', () {
    // Rule: a split that does not add up to the total cannot be confirmed.
    testWidgets('an incomplete split is refused', (tester) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);

      final billing = env.billing;

      await addCombo(tester, env.productName);
      await openSplit(tester);
      await typeSplit(tester, '200', '78');
      // Clear the UPI leg: one instrument is not a split.
      await tester.enterText(sheetFields().at(1), '');
      await settle(tester);

      expect(confirmSplitButton(), findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirmSplitButton()).onPressed,
        isNull,
        reason: 'a single Cash leg must not be confirmable as a split',
      );
      // A partial leg still owes money, so the sheet names the shortfall.
      expect(find.textContaining('Remaining: ₹78.00'), findsOneWidget);
      expect(completeEnabled(tester), isFalse);

      await tester.tap(confirmSplitButton());
      await settle(tester);
      expect(billing.storedSales, isEmpty);
    });

    // The nastier one-leg case: the sum is already exact, so "remaining" would
    // be a lie. The sheet has to name the missing instrument instead, and the
    // confirm button must stay dead.
    testWidgets('a lone leg covering the whole total is not a split', (
      tester,
    ) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);
      await addCombo(tester, env.productName);
      await openSplit(tester);
      await typeSplit(tester, '278', '');

      expect(find.text('A split needs both Cash and UPI'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(confirmSplitButton()).onPressed,
        isNull,
      );
      expect(completeEnabled(tester), isFalse);
      expect(env.billing.storedSales, isEmpty);
    });

    // Rule: split legs must equal the total exactly, from both directions.
    for (final entry in <(String, String, String)>[
      ('under', '100', '78'),
      ('over', '300', '78'),
    ]) {
      final (direction, cash, upi) = entry;
      testWidgets('a split $direction the total is refused', (tester) async {
        final env = await pumpPos(tester, business: BusinessContext.cafe);

        final billing = env.billing;

        await addCombo(tester, env.productName);
        await openSplit(tester);
        await typeSplit(tester, cash, upi);

        expect(
          tester.widget<FilledButton>(confirmSplitButton()).onPressed,
          isNull,
        );
        await tester.tap(confirmSplitButton());
        await settle(tester);
        expect(billing.storedSales, isEmpty);
        // Still on the POS page with the cart intact, ready for a retry.
        expect(find.text('Complete Sale'), findsOneWidget);
      });
    }

    // Rule: leaving split mode must not hand back a payment the cashier never
    // chose. Cancelling the sheet, or toggling split off, both clear it.
    testWidgets('cancelling a split still requires an explicit method', (
      tester,
    ) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);

      await addCombo(tester, env.productName);

      // Path 1: open the sheet, type, then dismiss without confirming.
      await openSplit(tester);
      await typeSplit(tester, '200', '78');
      await cancelSplit(tester);
      expect(
        completeEnabled(tester),
        isFalse,
        reason: 'a cancelled split must not leave a completable bill',
      );

      // Path 2: confirm a split, then toggle split mode back off.
      await openSplit(tester);
      await typeSplit(tester, '200', '78');
      await confirmSplit(tester);
      expect(completeEnabled(tester), isTrue);

      await tester.tap(find.text('Split'));
      await settle(tester);
      expect(
        completeEnabled(tester),
        isFalse,
        reason: 'leaving split mode must not hand back a chosen method',
      );

      // And an explicit choice is what re-opens the gate.
      await pickMethod(tester, 'UPI');
      expect(completeEnabled(tester), isTrue);
    });
  });

  group('business scope', () {
    // Rule: payment and cart state must not leak between shops. Switching from
    // the Cafe to the Food Truck mid-cart drops the previous shop's selection
    // and its cart, and a switch back starts clean rather than half-paid.
    testWidgets('switching shops clears the previous shop payment state', (
      tester,
    ) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);

      final container = env.container;
      final billing = env.billing;
      final cafeProduct = env.productName;

      await addCombo(tester, cafeProduct);
      await pickMethod(tester, 'UPI');
      expect(completeEnabled(tester), isTrue);

      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.foodTruck);
      await settle(tester);

      // The Cafe cart is gone and the till is parked on the truck. The pinned
      // Complete Sale button stays on screen, but disabled: no cart, and no
      // method carried over from the shop that was left.
      expect(container.read(cartProvider).lines, isEmpty);
      expect(completeEnabled(tester), isFalse);

      // A switch back to the Cafe is clean too: cart empty, no method chosen.
      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.cafe);
      await settle(tester);
      expect(find.text(cafeProduct), findsOneWidget);
      expect(completeEnabled(tester), isFalse);
      expect(billing.storedSales, isEmpty);
    });

    // The other half of the leak rule: a confirmed split is a payment decision
    // about specific products in the shop that was left. It must not come back
    // when the cashier returns, because the cart that justified it is gone.
    testWidgets('a confirmed split does not survive a shop switch', (
      tester,
    ) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);
      final container = env.container;
      await addCombo(tester, env.productName);
      await openSplit(tester);
      await typeSplit(tester, '200', '78');
      await confirmSplit(tester);
      expect(completeEnabled(tester), isTrue);

      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.foodTruck);
      await settle(tester);
      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.cafe);
      await settle(tester);

      // Back on the Cafe shelf with an empty cart: still not completable, so a
      // stale split can never be confirmed against a different cart.
      expect(find.text(env.productName), findsOneWidget);
      expect(container.read(cartProvider).lines, isEmpty);
      expect(completeEnabled(tester), isFalse);
      expect(env.billing.storedSales, isEmpty);
    });

    // "Not Paid" is a decision about one cart. A credit sale must not push the
    // next cart into credit, and must not follow the cashier to another shop.
    testWidgets('a credit sale does not leave Not Paid latched', (
      tester,
    ) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);
      final container = env.container;
      // A credit sale needs a customer before it can be completed, so link one
      // the way the picker would.
      container.read(cartProvider.notifier).selectCustomer('cust-1');

      await addCombo(tester, env.productName);
      await tester.tap(find.text('Not Paid').last);
      await settle(tester);
      expect(completeEnabled(tester), isTrue);

      await tester.tap(completeButton());
      await settle(tester);
      expect(env.billing.storedSales, hasLength(1));
      expect(
        env.billing.storedSales.single.paymentStatus,
        PaymentStatus.notPaid,
      );
      expect(env.billing.storedSales.single.paymentMethod, isNull);
      await dismissReceipt(tester);

      // The next bill starts on a paid till again, not silently in credit.
      await addCombo(tester, env.productName);
      expect(
        completeEnabled(tester),
        isFalse,
        reason: 'the next cart must not inherit the credit decision',
      );
      // A method is demanded for it, exactly like any other paid sale.
      await pickMethod(tester, 'Cash');
      expect(completeEnabled(tester), isTrue);
    });

    // The cart is app-global but the POS page is not always mounted, so the
    // rule cannot live in the page. Here the switch happens with no counter on
    // screen at all, which is what a switch made from another page looks like.
    testWidgets('a switch made off the counter still drops the cart', (
      tester,
    ) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);
      final container = env.container;
      await addCombo(tester, env.productName);
      expect(container.read(cartProvider).lines, hasLength(1));

      // Leave the counter entirely, then move the till.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
        ),
      );
      await settle(tester);
      expect(find.byType(PosPage), findsNothing);

      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.foodTruck);
      await settle(tester);

      expect(
        container.read(cartProvider).lines,
        isEmpty,
        reason: 'a Cafe cart must not reach the Food Truck counter',
      );
    });
  });

  group('controller guards', () {
    // Rules at the boundary below the UI: a split is CASH/UPI only, needs at
    // least two legs, and is never confused with a single-method sale. These
    // drive CartController directly, skipping the editor, because a caller can
    // reach the controller with any leg list. FakeBillingRepository accepts
    // anything, so a failure here proves the guard is the controller's own.
    Future<CartController> cartWithOneLine(WidgetTester tester) async {
      final env = await pumpPos(tester, business: BusinessContext.cafe);
      final cart = env.container.read(cartProvider.notifier);
      cart.add(product(env.shopId, env.productName));
      return cart;
    }

    testWidgets('a one-leg payment list is not a split', (tester) async {
      final cart = await cartWithOneLine(tester);
      await expectLater(
        cart.checkout(
          null,
          payments: [
            SalePayment(
              paymentMethod: PaymentMethod.cash,
              amountPaise: totalPaise,
            ),
          ],
        ),
        throwsA(isA<InvalidPaymentFailure>()),
      );
    });

    testWidgets('a BANK leg is not a split instrument', (tester) async {
      final cart = await cartWithOneLine(tester);
      await expectLater(
        cart.checkout(
          null,
          payments: [
            SalePayment(paymentMethod: PaymentMethod.cash, amountPaise: 20000),
            SalePayment(paymentMethod: PaymentMethod.bank, amountPaise: 7800),
          ],
        ),
        throwsA(isA<InvalidPaymentFailure>()),
      );
    });

    testWidgets('a valid two-leg split is accepted', (tester) async {
      final cart = await cartWithOneLine(tester);
      final completed = await cart.checkout(
        null,
        payments: [
          SalePayment(paymentMethod: PaymentMethod.cash, amountPaise: 20000),
          SalePayment(paymentMethod: PaymentMethod.upi, amountPaise: 7800),
        ],
      );
      expect(completed.sale.payments, hasLength(2));
      expect(completed.sale.paymentMethod, isNull);
    });
  });
}
