import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchases State (Riverpod)
///
/// Composition:
/// - [purchasesRepositoryProvider] → Drift-backed repository (override in
///                                    tests with a fake).
/// - [purchasesProvider]           → purchase history rows (header + supplier
///                                    label) filtered by the search query.
/// - [activeSuppliersProvider]     → active suppliers for the receiving form.
/// - [purchaseProductsProvider]    → active products for the receiving form.
/// - [purchaseFormProvider]        → the receiving draft: supplier, cart
///                                    lines, submitting flag.
/// - [purchaseItemsProvider]       → snapshot lines of one purchase.
///
/// The form controller is a pure presentation layer: it never touches Drift,
/// DAOs or stock arithmetic. [PurchaseFormController.submit] validates the
/// obvious, delegates the authoritative atomic write to
/// [PurchaseRepository.receivePurchase] and refreshes the affected providers
/// (purchases, products, movement history, dashboard) on success only.
/// ---------------------------------------------------------------------------

/// Owns the single purchase repository for the application scope.
final purchasesRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return DriftPurchaseRepository(ref.watch(appDatabaseProvider));
});

/// One purchase-history row: the persisted header plus the supplier display
/// label resolved from the supplier profiles at load time. Presentation-only;
/// the persisted purchase never stores the supplier name.
final class PurchaseRow {
  const PurchaseRow({required this.purchase, required this.supplierName});

  final Purchase purchase;

  /// Supplier display name; null means walk-in (or an unresolvable profile).
  final String? supplierName;
}

/// Immutable purchase-history search state (client-side by number/supplier).
final class PurchasesFilter {
  const PurchasesFilter({this.query = ''});

  /// Search text matched against purchase number and supplier label.
  final String query;

  PurchasesFilter withQuery(String query) => PurchasesFilter(query: query);
}

/// Holds the purchase-history search text; changes rebuild [purchasesProvider].
final purchasesFilterProvider =
    NotifierProvider<PurchasesFilterController, PurchasesFilter>(
      PurchasesFilterController.new,
    );

final class PurchasesFilterController extends Notifier<PurchasesFilter> {
  @override
  PurchasesFilter build() => const PurchasesFilter();

  void setQuery(String query) => state = state.withQuery(query);

  void clear() => state = const PurchasesFilter();
}

/// Purchase history, newest first, with supplier labels resolved and the
/// current search query applied.
final purchasesProvider =
    AsyncNotifierProvider<PurchasesController, List<PurchaseRow>>(
      PurchasesController.new,
    );

final class PurchasesController extends AsyncNotifier<List<PurchaseRow>> {
  static const String tag = 'Purchases';

  @override
  Future<List<PurchaseRow>> build() async {
    final filter = ref.watch(purchasesFilterProvider);
    final repository = ref.watch(purchasesRepositoryProvider);
    final suppliers = ref.watch(suppliersRepositoryProvider);
    try {
      final purchases = await repository.purchases();
      final supplierNames = <String, String>{
        for (final supplier in await suppliers.suppliers())
          supplier.id: supplier.name,
      };
      var rows = [
        for (final purchase in purchases)
          PurchaseRow(
            purchase: purchase,
            supplierName: purchase.supplierId == null
                ? null
                : supplierNames[purchase.supplierId],
          ),
      ];
      final query = filter.query.trim().toLowerCase();
      if (query.isNotEmpty) {
        rows = [
          for (final row in rows)
            if (row.purchase.purchaseNumber.toLowerCase().contains(query) ||
                (row.supplierName?.toLowerCase().contains(query) ?? false))
              row,
        ];
      }
      return rows;
    } on PurchasesFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load purchases',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedPurchasesFailure();
    }
  }

  Future<void> voidPurchase(String id) async {
    requireOwner(ref);
    try {
      await ref.read(purchasesRepositoryProvider).voidPurchase(id);
      ref.invalidateSelf();
    } on PurchasesFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to void purchase',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedPurchasesFailure();
    }
  }
}

/// One line of the receiving cart.
///
/// UI-local draft only: the product/variant name/SKU/stock are advisory
/// context from selection time; on submit the authoritative repository
/// re-reads the database, validates, and snapshots the persisted line.
final class PurchaseDraftLine {
  const PurchaseDraftLine({
    required this.productId,
    required this.productName,
    this.variantId,
    this.variantName,
    this.sku,
    required this.stockQuantity,
    required this.quantity,
    required this.unitCostPaise,
  });

  final String productId;
  final String productName;

  /// Variant being received; null for plain product lines.
  final String? variantId;

  /// Variant name at selection time (advisory display only).
  final String? variantName;

  /// SKU of the stock entity at selection time (advisory display only).
  final String? sku;

  /// Stock of the stock entity at selection time (advisory 'after receive'
  /// preview only; the repository remains authoritative).
  final int stockQuantity;
  final int quantity;
  final int unitCostPaise;

  /// Identity of the stock entity this line receives into.
  String get keyId => variantId ?? productId;

  PurchaseDraftLine copyWith({int? quantity, int? unitCostPaise}) =>
      PurchaseDraftLine(
        productId: productId,
        productName: productName,
        variantId: variantId,
        variantName: variantName,
        sku: sku,
        stockQuantity: stockQuantity,
        quantity: quantity ?? this.quantity,
        unitCostPaise: unitCostPaise ?? this.unitCostPaise,
      );
}

/// Immutable receiving-form state.
final class PurchaseFormState {
  const PurchaseFormState({
    this.supplierId,
    this.lines = const [],
    this.submitting = false,
  });

  /// Selected supplier profile; null means walk-in / no supplier.
  final String? supplierId;

  /// Receiving cart, one line per product.
  final List<PurchaseDraftLine> lines;

  /// True while a receive is in flight (blocks all form actions).
  final bool submitting;

  PurchaseFormState copyWith({
    Object? supplierId = _unset,
    List<PurchaseDraftLine>? lines,
    bool? submitting,
  }) => PurchaseFormState(
    supplierId: identical(supplierId, _unset)
        ? this.supplierId
        : supplierId as String?,
    lines: lines ?? this.lines,
    submitting: submitting ?? this.submitting,
  );

  static const Object _unset = Object();
}

/// The receiving draft: supplier selection, cart lines and submission state.
final purchaseFormProvider =
    NotifierProvider<PurchaseFormController, PurchaseFormState>(
      PurchaseFormController.new,
    );

final class PurchaseFormController extends Notifier<PurchaseFormState> {
  static const String tag = 'Purchases';

  @override
  PurchaseFormState build() => const PurchaseFormState();

  /// Selects the purchase supplier; null selects walk-in.
  void setSupplier(String? supplierId) {
    if (state.submitting) return;
    state = state.copyWith(supplierId: supplierId);
  }

  /// Adds one cart line for [product] (or its [variant]) with the default
  /// quantity and unit cost. Returns false (and changes nothing) when the
  /// stock entity is already in the cart or the line is invalid; the same
  /// stock entity may appear once.
  bool addLine({
    required Product product,
    ProductVariant? variant,
    required int quantity,
    required int unitCostPaise,
  }) {
    if (state.submitting) return false;
    if (quantity < 1 || unitCostPaise < 0) return false;
    final keyId = variant?.id ?? product.id;
    if (state.lines.any((line) => line.keyId == keyId)) return false;
    state = state.copyWith(
      lines: [
        ...state.lines,
        PurchaseDraftLine(
          productId: product.id,
          productName: product.name,
          variantId: variant?.id,
          variantName: variant?.name,
          sku: variant?.sku ?? product.sku,
          stockQuantity: variant?.stockQuantity ?? product.stockQuantity,
          quantity: quantity,
          unitCostPaise: unitCostPaise,
        ),
      ],
    );
    return true;
  }

  /// Updates the received quantity of one line (transient zero/empty input is
  /// allowed while typing; validation happens on submit).
  void updateQuantity(String keyId, int quantity) {
    if (state.submitting) return;
    state = state.copyWith(
      lines: [
        for (final line in state.lines)
          if (line.keyId == keyId) line.copyWith(quantity: quantity) else line,
      ],
    );
  }

  /// Updates the unit cost (paise) of one line.
  void updateCost(String keyId, int unitCostPaise) {
    if (state.submitting) return;
    state = state.copyWith(
      lines: [
        for (final line in state.lines)
          if (line.keyId == keyId)
            line.copyWith(unitCostPaise: unitCostPaise)
          else
            line,
      ],
    );
  }

  /// Removes one line from the cart.
  void removeLine(String keyId) {
    if (state.submitting) return;
    state = state.copyWith(
      lines: [
        for (final line in state.lines)
          if (line.keyId != keyId) line,
      ],
    );
  }

  /// Clears the cart (after a successful receive).
  void clearCart() {
    state = state.copyWith(lines: const []);
  }

  /// Validates the obvious draft problems and receives the purchase through
  /// the authoritative repository (which re-validates atomically).
  ///
  /// Returns null when another submission is already in flight (the
  /// double-submission guard — only one [receivePurchase] call may happen).
  /// On success the cart is cleared and the affected providers (purchase
  /// history, products, movement history, dashboard) are invalidated so every
  /// visible surface refreshes without a restart. On failure the form state
  /// (supplier + cart) is preserved so the user can correct and retry.
  Future<Purchase?> submit({String? notes}) async {
    requirePermission(ref, Permission.purchases);
    final current = state;
    if (current.submitting) return null;
    if (current.lines.isEmpty) {
      throw const EmptyPurchaseFailure();
    }
    for (final line in current.lines) {
      if (line.quantity < 1) {
        throw const InvalidPurchaseQuantityFailure();
      }
      if (line.unitCostPaise < 0) {
        throw const InvalidPurchaseCostFailure();
      }
    }
    state = state.copyWith(submitting: true);
    try {
      final purchase = await ref
          .read(purchasesRepositoryProvider)
          .receivePurchase(
            lines: [
              for (final line in current.lines)
                PurchaseLine(
                  productId: line.productId,
                  variantId: line.variantId,
                  quantity: line.quantity,
                  unitCostPaise: line.unitCostPaise,
                ),
            ],
            supplierId: current.supplierId,
            notes: notes,
          );
      state = state.copyWith(submitting: false, lines: const []);
      ref.invalidate(purchasesProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(posProductsProvider);
      ref.invalidate(productMovementsProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
      return purchase;
    } on PurchasesFailure {
      state = state.copyWith(submitting: false);
      rethrow;
    } catch (error, stackTrace) {
      state = state.copyWith(submitting: false);
      AppLog.error(
        'Failed to receive purchase',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedPurchasesFailure();
    }
  }
}

/// Active suppliers for the receiving form; inactive ones cannot be chosen.
final activeSuppliersProvider =
    AsyncNotifierProvider<ActiveSuppliersController, List<Supplier>>(
      ActiveSuppliersController.new,
    );

final class ActiveSuppliersController extends AsyncNotifier<List<Supplier>> {
  static const String tag = 'Purchases';

  @override
  Future<List<Supplier>> build() async {
    final repository = ref.watch(suppliersRepositoryProvider);
    try {
      return await repository.suppliers(status: SupplierStatusFilter.active);
    } on SuppliersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load active suppliers',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSuppliersFailure();
    }
  }
}

/// Active products for the receiving form; inactive ones cannot receive.
final purchaseProductsProvider =
    AsyncNotifierProvider<PurchaseProductsController, List<Product>>(
      PurchaseProductsController.new,
    );

final class PurchaseProductsController extends AsyncNotifier<List<Product>> {
  static const String tag = 'Purchases';

  @override
  Future<List<Product>> build() async {
    final repository = ref.watch(inventoryRepositoryProvider);
    try {
      return await repository.products(status: ProductStatusFilter.active);
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load products for purchase',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }
}

/// Snapshot line items of one purchase — the authoritative historical record
/// (never re-read from current product data).
final purchaseItemsProvider =
    AsyncNotifierProvider.family<
      PurchaseItemsController,
      List<PurchaseItem>,
      String
    >(PurchaseItemsController.new);

final class PurchaseItemsController extends AsyncNotifier<List<PurchaseItem>> {
  PurchaseItemsController(this.purchaseId);

  /// The purchase whose snapshot lines this controller holds.
  final String purchaseId;

  static const String tag = 'Purchases';

  @override
  Future<List<PurchaseItem>> build() async {
    final repository = ref.watch(purchasesRepositoryProvider);
    try {
      return await repository.purchaseItems(purchaseId);
    } on PurchasesFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load purchase items',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedPurchasesFailure();
    }
  }
}

/// Supplier display name for a purchase detail page; null when the profile
/// cannot be resolved.
final purchaseSupplierNameProvider = FutureProvider.family<String?, String>((
  ref,
  supplierId,
) async {
  final repository = ref.watch(suppliersRepositoryProvider);
  final supplier = await repository.supplierById(supplierId);
  return supplier?.name;
});

/// Maps any thrown object to a user-safe message.
///
/// [PurchasesFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String purchasesErrorMessage(Object error, {String? fallback}) {
  if (error is PurchasesFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
