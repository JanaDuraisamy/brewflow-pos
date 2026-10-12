import 'dart:async';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/domain/payment_attribution.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Dashboard State (Riverpod)
///
/// Composition:
/// - [dashboardDateProvider]       → the local date selected on the dashboard
///                                   (defaults to today).
/// - [connectivityStatusProvider]  → live connectivity state for the
///                                   sync-status surface.
/// - [dashboardControllerProvider] → the aggregated [DashboardSnapshot].
///
/// Everything is computed from real repositories — completed sales (orders),
/// products/categories (inventory) and the connectivity service (surfaced
/// through [connectivityStatusProvider] by the page, live). Nothing on the
/// dashboard is invented: absent data renders as explicit empty states in
/// the page, never as placeholder numbers. The controller rebuilds whenever
/// the selected date or a watched repository changes; billing/inventory
/// mutations explicitly invalidate it so the day's numbers stay fresh.
/// ---------------------------------------------------------------------------

/// Stock-level threshold at/below which an active product counts as low on
/// stock for dashboard alerts.
const int dashboardLowStockThreshold = 5;

/// Per-business sales totals for the selected day, used by the Combined
/// (owner phone) view to show each shop's contribution without ever merging
/// them. Named so the UI can label each slice; null sale/order values are 0.
final class BusinessSalesSummary {
  const BusinessSalesSummary({
    required this.label,
    required this.salesPaise,
    required this.orderCount,
    required this.itemCount,
  });

  final String label;
  final int salesPaise;
  final int orderCount;
  final int itemCount;

  @override
  bool operator ==(Object other) =>
      other is BusinessSalesSummary &&
      other.label == label &&
      other.salesPaise == salesPaise &&
      other.orderCount == orderCount &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(label, salesPaise, orderCount, itemCount);
}

/// One immutable dashboard state, computed entirely from real data.
final class DashboardSnapshot {
  const DashboardSnapshot({
    required this.daySalesPaise,
    required this.totalBills,
    required this.dayOrderCount,
    required this.dayItemCount,
    required this.paymentSplitPaise,
    required this.dayNotPaidPaise,
    required this.weeklySalesPaise,
    required this.recentBills,
    required this.productCount,
    required this.lowStockCount,
    required this.lowStockThreshold,
    required this.outOfStockCount,
    required this.categoryCount,
    required this.dueCustomers,
    this.businessBreakdown = const [],
    this.dayDueCollectedPaise = 0,
    this.dayDueCollections = const [],
    this.dayBills = const [],
    this.shopLabels = const {},
  });

  /// Total counter receipts on the selected day.
  final int daySalesPaise;

  /// All-time bill count. Paged fetch, capped for safety; never negative.
  final int totalBills;

  /// Number of completed sales on the selected day.
  final int dayOrderCount;

  /// Total pieces sold on the selected day.
  final int dayItemCount;

  /// Selected-day settled money per payment method; methods without sales are
  /// absent from the map. BANK is never a current category: a retired till
  /// method's historical money is folded into Cash (see
  /// [PaymentAttribution]).
  final Map<PaymentMethod, int> paymentSplitPaise;

  /// Selected-day credit money still owed — the total of every NOT_PAID sale
  /// on the selected day. This is the "Not Paid" row of the Payment Summary,
  /// and it is what makes Cash + UPI + Not Paid reconcile with [daySalesPaise].
  final int dayNotPaidPaise;

  /// Sales totals for the seven-day window ending on the selected date,
  /// oldest day first (index 0 = selected minus 6 days).
  final List<int> weeklySalesPaise;

  /// The most recent completed sales, newest first (display cap only).
  final List<OrderSummary> recentBills;

  /// Active product count (all statuses as stored).
  final int productCount;

  /// Stock entities low on stock: active products without variants judged
  /// by their effective product policy, plus active variants of variant
  /// products judged by their own effective policy. Entities with the
  /// OFF low-stock mode are excluded.
  final int lowStockCount;

  /// The global threshold used for the USE_DEFAULT fallback in
  /// [lowStockCount], taken from the saved shop settings (falls back to
  /// [dashboardLowStockThreshold]).
  final int lowStockThreshold;

  /// Stock entities with no stock left (same entity rules as
  /// [lowStockCount], excluding OFF entities).
  final int outOfStockCount;

  /// Category count.
  final int categoryCount;

  /// Customers with outstanding dues and their total, derived from the
  /// customer ledger (never stored).
  final DueCustomersSummary dueCustomers;

  /// Per-business sales for the selected day. Empty unless the owner is in
  /// the Combined view. Shops are never aggregated together; each entry
  /// keeps its own identity so the UI can label it.
  final List<BusinessSalesSummary> businessBreakdown;

  /// Money collected from customer dues on the selected day: the sum of
  /// every valid (non-reversed) ledger payment whose `paidAt` falls inside
  /// the selected local day. New-sale receipts are never included — they
  /// live in [daySalesPaise].
  final int dayDueCollectedPaise;

  /// The day's due-collection payments, newest first, backing the Due
  /// Collected card's drill-down. Each row carries its customer, amount,
  /// method, timestamp and (in the Combined view) business label.
  final List<DueCollection> dayDueCollections;

  /// Completed sales on the selected day, newest first, backing the Bills
  /// card's drill-down. Already loaded for the day KPIs — tapping the card
  /// adds no database reads.
  final List<OrderSummary> dayBills;

  /// Business labels by shop id, non-empty only in the Combined view. The
  /// Bills drill-down tags each row through this map; single-shop reads
  /// render no shop text.
  final Map<String, String> shopLabels;
}

/// Item-wise sales for the dashboard's selected day and shop scope, loaded
/// lazily when the Items drill-down opens — never on the dashboard build
/// itself, so the day's N+1 detail reads happen only on an explicit tap.
/// Auto-disposed with the sheet; rebuilds when the selected date or the
/// business context changes.
final dashboardDayItemsProvider =
    FutureProvider.autoDispose<List<ItemSalesRow>>((ref) async {
      ref.watch(dashboardDateProvider);
      ref.watch(businessSwitcherProvider);
      return ref.read(dashboardControllerProvider.notifier).dayItemBreakdown();
    });

/// Holds the dashboard's selected local date; defaults to today.
final dashboardDateProvider =
    NotifierProvider<DashboardDateController, DateTime>(
      DashboardDateController.new,
    );

final class DashboardDateController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Selects a local date (normalized to midnight). Past dates are allowed;
  /// the picker already restricts to no later than today.
  void select(DateTime localDate) {
    state = DateTime(localDate.year, localDate.month, localDate.day);
  }
}

/// Live application connectivity, kept in sync with the service's snapshot
/// stream (the service itself is initialized lazily on first watch).
final connectivityStatusProvider =
    NotifierProvider<ConnectivityStatusController, ConnectivityStatus>(
      ConnectivityStatusController.new,
    );

final class ConnectivityStatusController extends Notifier<ConnectivityStatus> {
  static const String tag = 'Dashboard';

  StreamSubscription<ConnectivitySnapshot>? _subscription;

  @override
  ConnectivityStatus build() {
    final service = ref.watch(connectivityServiceProvider);
    unawaited(service.init());
    _subscription = service.snapshots.listen((snapshot) {
      state = snapshot.status;
    });
    ref.onDispose(() => _subscription?.cancel());
    return service.status;
  }
}

/// Aggregated dashboard state over the real orders + inventory repositories.
final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardSnapshot>(
      DashboardController.new,
    );

final class DashboardController extends AsyncNotifier<DashboardSnapshot> {
  static const String tag = 'Dashboard';

  /// Rows fetched per repository page while scanning windows/totals.
  static const int _pageSize = 500;

  /// Hard safety cap for the all-time bill scan (a counter reaching this
  /// count in a single day is beyond anything the dashboard needs).
  static const int _totalBillsCap = 5000;

  /// Recent-bills list cap.
  static const int _recentBillsLimit = 5;

  /// Window length behind the selected day (7 daily points total).
  static const int _windowDays = 7;

  @override
  Future<DashboardSnapshot> build() async {
    final selected = ref.watch(dashboardDateProvider);
    final orders = ref.watch(ordersRepositoryProvider);
    final inventory = ref.watch(inventoryRepositoryProvider);
    final ledger = ref.watch(customerLedgerRepositoryProvider);
    final settingsRepository = ref.watch(settingsRepositoryProvider);
    final businessContext = ref.watch(businessSwitcherProvider);
    // Read scope from the business context (owner phone). All (Combined)
    // resolves to every shop; a single business resolves to that shop. This
    // is a read-only scope — never used for writes.
    final shopIds = await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(businessContext);
    final showBreakdown = businessContext == BusinessContext.all;
    final labelsById = await _businessLabels();
    try {
      // The low-stock threshold comes from the saved shop settings. Settings
      // are best-effort here: when they are unavailable, the dashboard keeps
      // its built-in default instead of failing.
      var lowStockThreshold = dashboardLowStockThreshold;
      try {
        lowStockThreshold = (await settingsRepository.load()).lowStockThreshold;
      } on Object {
        AppLog.info('Low-stock threshold fell back to the default', tag: tag);
      }
      final windowStart = _localDay(
        selected.subtract(Duration(days: _windowDays - 1)),
      );
      final windowOrders = await _fetchWindow(
        orders,
        windowStart,
        selected,
        shopIds: shopIds,
      );
      final selectedDayOrders = [
        for (final order in windowOrders)
          if (_localDay(order.createdAt) == selected) order,
      ];

      final products = await inventory.products(shopIds: shopIds);
      final categories = await inventory.categories(shopIds: shopIds);

      final weekly = List<int>.filled(_windowDays, 0);
      for (final order in windowOrders) {
        final index = _localDay(order.createdAt).difference(windowStart).inDays;
        if (index >= 0 && index < _windowDays) {
          weekly[index] += order.totalPaise;
        }
      }

      final paymentSplit = attributePayments(
        selectedDayOrders,
        legsBySaleId: await orders.paymentLegsFor(
          selectedDayOrders.map((order) => order.id),
        ),
      );

      // Due collections follow the SELECTED local day (not hard-coded
      // today), using the same UTC-bounds convention as the sales window:
      // the collection instant (`paidAt`) decides the day, never the bill's
      // `createdAt`.
      final dueCollections = await ledger.dueCollections(
        shopIds: shopIds,
        fromUtc: selected.toUtc(),
        toUtc: _endOfDayUtc(selected),
      );

      final recentBills = await orders.orders(
        limit: _recentBillsLimit,
        shopIds: shopIds,
      );

      final active = [
        for (final p in products)
          if (p.isActive) p,
      ];

      // Stock-alert counts are entity-based: a product without variants is
      // judged by its own effective policy; a product with variants is judged
      // by each active variant's effective policy (USE_DEFAULT falls back to
      // the product policy, then the global threshold; OFF excludes the
      // entity from both counts).
      var lowStockCount = 0;
      var outOfStockCount = 0;
      for (final product in active) {
        // stockUnit NONE = made-to-order / untracked: it can never be "low
        // on stock" and its zero quantity is not an out-of-stock state, so
        // untracked menu items never pollute the dashboard alerts.
        if (product.stockUnit == StockUnit.none) continue;
        if (product.variants.isNotEmpty) {
          for (final variant in product.variants) {
            if (!variant.isActive) continue;
            final threshold = effectiveVariantLowStockThreshold(
              variant,
              product,
              lowStockThreshold,
            );
            if (threshold == null) continue;
            if (isLowStock(
              stock: variant.stockQuantity,
              threshold: threshold,
            )) {
              lowStockCount += 1;
            } else if (variant.stockQuantity <= 0) {
              outOfStockCount += 1;
            }
          }
        } else {
          final threshold = effectiveLowStockThreshold(
            product,
            lowStockThreshold,
          );
          if (threshold == null) continue;
          if (isLowStock(stock: product.stockQuantity, threshold: threshold)) {
            lowStockCount += 1;
          } else if (product.stockQuantity <= 0) {
            outOfStockCount += 1;
          }
        }
      }

      return DashboardSnapshot(
        daySalesPaise: selectedDayOrders.fold(
          0,
          (sum, order) => sum + order.totalPaise,
        ),
        totalBills: await _fetchTotalBills(orders, shopIds: shopIds),
        dayOrderCount: selectedDayOrders.length,
        dayItemCount: selectedDayOrders.fold(
          0,
          (sum, order) => sum + order.itemCount,
        ),
        paymentSplitPaise: {
          if (paymentSplit.cashPaise > 0)
            PaymentMethod.cash: paymentSplit.cashPaise,
          if (paymentSplit.upiPaise > 0)
            PaymentMethod.upi: paymentSplit.upiPaise,
        },
        dayNotPaidPaise: paymentSplit.notPaidPaise,
        weeklySalesPaise: weekly,
        recentBills: recentBills.items,
        productCount: products.length,
        lowStockCount: lowStockCount,
        lowStockThreshold: lowStockThreshold,
        outOfStockCount: outOfStockCount,
        categoryCount: categories.length,
        dueCustomers: await ledger.dueCustomersSummary(shopIds: shopIds),
        businessBreakdown: showBreakdown
            ? _businessBreakdown(selectedDayOrders, labelsById)
            : const [],
        dayDueCollectedPaise: dueCollections.fold(
          0,
          (sum, collection) => sum + collection.amountPaise,
        ),
        dayDueCollections: showBreakdown
            ? [
                for (final collection in dueCollections)
                  collection.copyWith(
                    shopLabel: _shopLabel(collection.shopId, labelsById),
                  ),
              ]
            : dueCollections,
        dayBills: selectedDayOrders,
        shopLabels: showBreakdown ? labelsById : const {},
      );
    } on OrdersFailure {
      rethrow;
    } on InventoryFailure {
      rethrow;
    } on CustomerLedgerFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load dashboard',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedOrdersFailure();
    }
  }

  /// Loads every sale inside [windowStart]..[selected] (inclusive local
  /// days), paging the repository and stopping at the safety cap.
  Future<List<OrderSummary>> _fetchWindow(
    OrdersRepository orders,
    DateTime windowStart,
    DateTime selected, {
    List<String>? shopIds,
  }) async {
    final filter = OrdersFilter(
      fromUtc: windowStart.toUtc(),
      toUtc: _endOfDayUtc(selected),
    );
    final results = <OrderSummary>[];
    var offset = 0;
    var fetched = 0;
    while (true) {
      final page = await orders.orders(
        filter: filter,
        limit: _pageSize,
        offset: offset,
        shopIds: shopIds,
      );
      results.addAll(page.items);
      fetched += page.items.length;
      if (!page.hasMore || fetched >= _totalBillsCap) break;
      offset += _pageSize;
    }
    return results;
  }

  /// All-time completed-sale count, paged up to [_totalBillsCap].
  Future<int> _fetchTotalBills(
    OrdersRepository orders, {
    List<String>? shopIds,
  }) async {
    var total = 0;
    var offset = 0;
    while (true) {
      final page = await orders.orders(
        limit: _pageSize,
        offset: offset,
        shopIds: shopIds,
      );
      total += page.items.length;
      if (!page.hasMore || total >= _totalBillsCap) break;
      offset += _pageSize;
    }
    return total;
  }

  /// Item-wise sales for the currently selected day and shop scope.
  ///
  /// Aggregates the persisted line snapshots of the day's bills by
  /// (product, variant) — variants of one product stay distinguishable from
  /// each other and from the plain product row, mirroring the Reports
  /// aggregation. Opening-balance entries never appear (the orders window
  /// excludes them). Rows sort by revenue, highest first.
  ///
  /// Runs only when the Items drill-down opens ([dashboardDayItemsProvider]),
  /// so a day with many bills costs one batched detail pass on tap instead
  /// of on every dashboard build.
  Future<List<ItemSalesRow>> dayItemBreakdown() async {
    final selected = ref.read(dashboardDateProvider);
    final orders = ref.read(ordersRepositoryProvider);
    final businessContext = ref.read(businessSwitcherProvider);
    final shopIds = await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(businessContext);
    try {
      final dayOrders = await _fetchWindow(
        orders,
        selected,
        selected,
        shopIds: shopIds,
      );
      final byProduct = <(String, String?), List<int>>{};
      for (final order in dayOrders) {
        final detail = await orders.orderById(order.id);
        for (final item in detail.items) {
          final aggregation = byProduct.putIfAbsent((
            item.productName,
            item.variantName,
          ), () => [0, 0]);
          aggregation[0] += item.quantity;
          aggregation[1] += item.lineTotalPaise;
        }
      }
      final rows = [
        for (final entry in byProduct.entries)
          ItemSalesRow(
            productName: entry.key.$1,
            variantName: entry.key.$2,
            unitsSold: entry.value[0],
            revenuePaise: entry.value[1],
          ),
      ]..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));
      return rows;
    } on OrdersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load day item breakdown',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedOrdersFailure();
    }
  }

  /// Resolves one payment row's shop to its user-facing business label.
  /// Unknown or legacy (null-shop) rows read as a plain 'Business', mirroring
  /// [_businessBreakdown].
  static String _shopLabel(String? shopId, Map<String, String> labelsById) =>
      shopId == null ? 'Business' : (labelsById[shopId] ?? 'Business');

  /// Maps shop ids to user-facing business labels for the Combined breakdown.
  /// CAFE is the primary (legacy) shop; FOOD TRUCK the second business.
  Future<Map<String, String>> _businessLabels() async {
    final switcher = ref.read(businessSwitcherProvider.notifier);
    final labels = <String, String>{};
    try {
      final cafeId = await switcher.shopIdFor(BusinessContext.cafe);
      labels[cafeId] = BusinessContext.cafe.label;
      final ftId = await switcher.existingFoodTruckShopId();
      if (ftId != null && ftId != cafeId) {
        labels[ftId] = BusinessContext.foodTruck.label;
      }
    } catch (_) {
      // Non-fatal: the breakdown just falls back to whatever ids resolve.
    }
    return labels;
  }

  /// Groups the selected day's orders by shop into per-business slices. Shops
  /// are never merged; each keeps its own label and totals.
  List<BusinessSalesSummary> _businessBreakdown(
    List<OrderSummary> orders,
    Map<String, String> labelsById,
  ) {
    final byShop = <String, List<OrderSummary>>{};
    for (final order in orders) {
      byShop.putIfAbsent(order.shopId ?? '', () => []).add(order);
    }
    final result = <BusinessSalesSummary>[
      for (final entry in byShop.entries)
        BusinessSalesSummary(
          label: labelsById[entry.key] ?? 'Business',
          salesPaise: entry.value.fold(
            0,
            (sum, order) => sum + order.totalPaise,
          ),
          orderCount: entry.value.length,
          itemCount: entry.value.fold(0, (sum, order) => sum + order.itemCount),
        ),
    ]..sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _endOfDayUtc(DateTime localDay) =>
      DateTime(localDay.year, localDay.month, localDay.day)
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1))
          .toUtc();
}

/// Maps any thrown object to a user-safe message, following the house
/// failure-mapping convention (orders/inventory/ledger failures carry
/// display text).
String dashboardErrorMessage(Object error, {String? fallback}) {
  if (error is OrdersFailure) {
    return error.message;
  }
  if (error is InventoryFailure) {
    return error.message;
  }
  if (error is CustomerLedgerFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
