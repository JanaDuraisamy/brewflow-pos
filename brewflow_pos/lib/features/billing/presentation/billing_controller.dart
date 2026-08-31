import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Billing State (Riverpod)
///
/// Composition:
/// - [billingRepositoryProvider] → Drift-backed repository (override in
///                                 tests with a fake).
/// - [posFilterProvider]         → POS product search/category filter.
/// - [posProductsProvider]       → sellable products (active, in stock).
/// - [cartProvider]              → the current checkout cart.
///
/// Cart rules enforced here: unique lines, quantity within [1, stock],
/// no unavailable or zero-stock products, payment required at checkout.
/// Checkout failures leave the cart untouched so the counter can retry or
/// adjust quantity and try again.
/// ---------------------------------------------------------------------------

/// Owns the single billing repository for the application scope.
final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return DriftBillingRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// Holds the POS product filter; changes rebuild [posProductsProvider].
final class PosFilter {
  const PosFilter({this.query = '', this.categoryId});

  /// Search text matched against product name and SKU.
  final String query;

  /// Restricts the shelf to one category when set.
  final String? categoryId;

  PosFilter withQuery(String query) =>
      PosFilter(query: query, categoryId: categoryId);

  PosFilter withCategory(String? categoryId) =>
      PosFilter(query: query, categoryId: categoryId);
}

/// Holds the current POS filter state.
final posFilterProvider = NotifierProvider<PosFilterController, PosFilter>(
  PosFilterController.new,
);

final class PosFilterController extends Notifier<PosFilter> {
  @override
  PosFilter build() => const PosFilter();

  void setQuery(String query) => state = state.withQuery(query);

  void setCategory(String? categoryId) =>
      state = state.withCategory(categoryId);
}

/// POS shelf products: the active products matching the POS filter.
///
/// Reuses the inventory repository's SQL filtering. Zero-stock and
/// made-to-order (untracked) active products are deliberately kept visible so
/// staff can see the full shelf; the POS card renders them as sold out and the
/// cart guard (`InsufficientStockFailure`) plus the checkout `stock_quantity
/// >= ?` SQL guard prevent any sale of a zero-stock line.
final posProductsProvider =
    AsyncNotifierProvider<PosProductsController, List<Product>>(
      PosProductsController.new,
    );

final class PosProductsController extends AsyncNotifier<List<Product>> {
  static const String tag = 'Billing';

  @override
  Future<List<Product>> build() async {
    final filter = ref.watch(posFilterProvider);
    final repository = ref.watch(inventoryRepositoryProvider);
    try {
      return await repository.products(
        search: filter.query,
        categoryId: filter.categoryId,
        status: ProductStatusFilter.active,
      );
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load POS products',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }
}

/// The current checkout cart. Mutations are synchronous (pure state); only
/// [CartController.checkout] touches the repository.
final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

/// Active customers offered by the POS customer picker.
///
/// Independent of the Customers page filter; always returns the active set so
/// the counter can only link sales to customers that can still be billed.
final posCustomersProvider =
    AsyncNotifierProvider<PosCustomersController, List<Customer>>(
      PosCustomersController.new,
    );

final class PosCustomersController extends AsyncNotifier<List<Customer>> {
  static const String tag = 'Billing';

  @override
  Future<List<Customer>> build() async {
    final repository = ref.watch(customersRepositoryProvider);
    try {
      return await repository.customers(status: CustomerStatusFilter.active);
    } on CustomersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load POS customer choices',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedCustomersFailure();
    }
  }
}

final class CartController extends Notifier<Cart> {
  static const String tag = 'Billing';

  @override
  Cart build() => Cart.empty;

  /// Whether membership pricing may operate at all (global Settings switch).
  /// Read lazily — never watched — so a settings change can never reset an
  /// in-progress cart.
  bool _membershipEnabled() =>
      ref.read(shopSettingsProvider).value?.membershipEnabled ??
      ShopSettings.defaultMembershipEnabled;

  /// Adds [product] (or its [variant] line) at one unit.
  ///
  /// Throws [UnavailableProductFailure] for inactive products/variants and
  /// [InsufficientStockFailure] once the stock cap is reached. Products with
  /// [StockUnit.none] are made-to-order: they carry no inventory, so stock is
  /// never checked and the line gets the untracked ceiling instead.
  void add(Product product, {ProductVariant? variant}) {
    if (!product.isActive) {
      throw UnavailableProductFailure(product.name);
    }
    final untracked = product.stockUnit == StockUnit.none;
    final stock = variant?.stockQuantity ?? product.stockQuantity;
    if (!untracked && stock <= 0) {
      throw InsufficientStockFailure(product.name);
    }
    final line = CartLine(
      productId: product.id,
      productName: product.name,
      sku: variant?.sku ?? product.sku,
      variantId: variant?.id,
      variantName: variant?.name,
      unitPricePaise: variant?.sellingPricePaise ?? product.sellingPricePaise,
      memberPricePaise: variant?.memberPricePaise ?? product.memberPricePaise,
      quantity: 1,
      maxQuantity: untracked ? untrackedStockCap : stock,
    );
    final existing = state.lineFor(line.keyId);
    if (existing == null) {
      state = state.withAdded(line);
      return;
    }
    if (existing.quantity >= existing.maxQuantity) {
      throw InsufficientStockFailure(line.productName);
    }
    state = state.withLineQuantity(line.keyId, existing.quantity + 1);
  }

  /// Adds one more unit of an existing line (by its stock-entity key);
  /// throwing [InsufficientStockFailure] when the stock cap is reached.
  void increment(String keyId) {
    final line = state.lineFor(keyId);
    if (line == null) {
      throw const InvalidQuantityFailure('Item is not in the cart.');
    }
    if (line.quantity >= line.maxQuantity) {
      throw InsufficientStockFailure(line.productName);
    }
    state = state.withLineQuantity(keyId, line.quantity + 1);
  }

  /// Removes one unit; the line disappears when it would drop to zero.
  void decrement(String keyId) {
    final line = state.lineFor(keyId);
    if (line == null) return;
    if (line.quantity == 1) {
      state = state.without(keyId);
      return;
    }
    state = state.withLineQuantity(keyId, line.quantity - 1);
  }

  /// Sets an exact quantity, within [1, stock cap]. Throws
  /// [InvalidQuantityFailure] for zero/negative and [InsufficientStockFailure]
  /// above the cap.
  void setQuantity(String keyId, int quantity) {
    if (quantity <= 0) {
      throw const InvalidQuantityFailure();
    }
    final line = state.lineFor(keyId);
    if (line == null) return;
    if (quantity > line.maxQuantity) {
      throw InsufficientStockFailure(line.productName);
    }
    state = state.withLineQuantity(keyId, quantity);
  }

  /// Removes a line by its stock-entity key; a no-op when not in the cart.
  void remove(String keyId) => state = state.without(keyId);

  /// Restores a previously removed line (undo).
  void restoreLine(CartLine line) => state = state.withAdded(line);

  /// Empties the cart (and with it any selected customer).
  void clear() => state = Cart.empty;

  /// Replaces the entire cart with [bill]'s snapshot (a resumed held bill),
  /// including its selected customer and member-pricing switch. The UI
  /// confirms before calling when the current cart is not empty.
  void restore(HeldBill bill) => state = bill.toCart();

  /// Links the current sale to [customerId] (null returns it to a walk-in)
  /// and recalculates member pricing: an active member customer pays member
  /// prices while membership pricing is enabled globally; anyone else —
  /// including a deactivated member — pays normal selling prices. For a
  /// walk-in the counter's manual member-pricing switch keeps governing the
  /// cart, exactly as before. Existing lines recalculate immediately because
  /// the charged price is derived from the cart's member-pricing flag at
  /// display/checkout time.
  Future<void> selectCustomer(String? customerId) async {
    if (!_membershipEnabled()) {
      state = state.withCustomer(customerId).withMemberPricing(false);
      return;
    }
    var memberPricing = state.memberPricing;
    if (customerId != null) {
      try {
        final customer = await ref
            .read(customersRepositoryProvider)
            .customerById(customerId);
        memberPricing =
            customer != null && customer.isActive && customer.membershipActive;
      } on Exception {
        // Profile lookup failed: fall back to normal prices rather than
        // guessing a benefit the counter cannot verify.
        memberPricing = false;
      }
    }
    state = state.withCustomer(customerId).withMemberPricing(memberPricing);
  }

  /// Toggles member pricing for this cart. Membership pricing is a global
  /// capability: when the Settings switch is off this is a no-op so no cart
  /// can ever charge member prices against the owner's choice.
  void toggleMemberPricing() {
    if (!_membershipEnabled()) return;
    state = state.withMemberPricing(!state.memberPricing);
  }

  /// Completes the sale with [paymentStatus] and, for PAID sales,
  /// [paymentMethod] (must be non-null); clears the cart on success and
  /// refreshes the POS shelf plus any customer-ledger surface touched by the
  /// sale.
  ///
  /// A NOT_PAID (credit) sale requires a selected customer — the unpaid
  /// total becomes the customer's ledger debt. Throws [EmptyCartFailure] /
  /// [MissingCustomerForCreditSaleFailure] / [InvalidPaymentFailure] / any
  /// repository [BillingFailure]. Failures preserve the cart exactly as it
  /// was, including the selected customer.
  Future<CompletedSale> checkout(
    PaymentMethod? paymentMethod, {
    PaymentStatus paymentStatus = PaymentStatus.paid,
  }) async {
    requirePermission(ref, Permission.billing);
    if (state.isEmpty) {
      throw const EmptyCartFailure();
    }
    if (paymentStatus == PaymentStatus.notPaid &&
        state.selectedCustomerId == null) {
      throw const MissingCustomerForCreditSaleFailure();
    }
    if (paymentStatus == PaymentStatus.paid && paymentMethod == null) {
      throw const InvalidPaymentFailure();
    }
    final total = state.chargedTotalPaise;
    if (total == null) {
      throw const UnexpectedBillingFailure(
        'Cart total exceeds the safe ceiling.',
      );
    }
    try {
      final completed = await ref
          .read(billingRepositoryProvider)
          .completeSale(
            lines: state.resolvedLines,
            paymentStatus: paymentStatus,
            paymentMethod: paymentStatus == PaymentStatus.notPaid
                ? null
                : paymentMethod,
            customerId: state.selectedCustomerId,
          );
      state = Cart.empty;
      ref.invalidate(posProductsProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(productMovementsProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
      // Customer-linked sales land in the customer ledger (a NOT_PAID sale
      // as debt, a PAID sale as paid history); refresh it immediately.
      final customerId = completed.sale.customerId;
      if (customerId != null) {
        ref.invalidate(customerLedgerProvider(customerId));
      }
      return completed;
    } on BillingFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Checkout failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedBillingFailure();
    }
  }
}

/// Bills parked at the counter (Hold Bill). Pure in-memory state — holding a
/// bill writes nothing to the database and creates no Sale, stock movement,
/// receipt number or debt. The collection is session-scoped: it starts empty
/// and is cleared on logout, so one cashier's held bills never leak into the
/// next session. Holding never reserves stock; checkout after resume
/// re-validates against the live repository and fails safely when stock has
/// changed.
final heldBillsProvider = NotifierProvider<HeldBillsController, List<HeldBill>>(
  HeldBillsController.new,
);

final class HeldBillsController extends Notifier<List<HeldBill>> {
  static const String tag = 'Billing';

  int _nextHoldNumber = 1;

  @override
  List<HeldBill> build() => const [];

  /// Moves the current cart into the held-bill collection and empties the
  /// cart. A no-op (returns null) when the cart is empty. Pure state move:
  /// nothing touches the repository — no Sale row, no stock movement, no
  /// receipt number consumed, no debt recorded. The payment choices are
  /// snapshotted so resuming restores exactly what the counter had chosen.
  HeldBill? holdCurrentBill({
    required PaymentStatus paymentStatus,
    PaymentMethod? paymentMethod,
  }) {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return null;
    final bill = HeldBill(
      id: 'hold-$_nextHoldNumber',
      lines: cart.lines,
      selectedCustomerId: cart.selectedCustomerId,
      memberPricing: cart.memberPricing,
      paymentStatus: paymentStatus,
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : paymentMethod,
      heldAt: DateTime.now().toUtc(),
    );
    _nextHoldNumber += 1;
    state = [...state, bill];
    ref.read(cartProvider.notifier).clear();
    return bill;
  }

  /// Restores the held bill [id] into the cart, replacing any current cart
  /// content (the UI confirms this first) and removing it from the
  /// collection. Returns the resumed bill, or null when the id is unknown
  /// (a no-op that leaves the cart and collection untouched).
  HeldBill? resumeHeldBill(String id) {
    final index = state.indexWhere((bill) => bill.id == id);
    if (index == -1) return null;
    final bill = state[index];
    final remaining = [...state]..removeAt(index);
    state = remaining;
    ref.read(cartProvider.notifier).restore(bill);
    return bill;
  }

  /// Removes only the held bill [id]; a no-op for unknown ids. The bill is
  /// simply discarded — nothing was reserved, so nothing needs releasing.
  void deleteHeldBill(String id) {
    final remaining = [
      for (final bill in state)
        if (bill.id != id) bill,
    ];
    if (remaining.length != state.length) {
      state = remaining;
    }
  }
}

/// Maps any thrown object to a user-safe message.
///
/// [BillingFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String billingErrorMessage(Object error, {String? fallback}) {
  if (error is BillingFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
