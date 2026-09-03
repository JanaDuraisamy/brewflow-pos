import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/domain/reports_models.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reports State (Riverpod)
///
/// Composition:
/// - [reportsRangeProvider]    → the reporting window (preset + UTC bounds,
///                               reusing orders preset semantics; defaults to
///                               the last 30 days — never unbounded).
/// - [reportsControllerProvider] → [ReportsSnapshot] computed from the three
///                               existing read repositories (orders,
///                               expenses, inventory) — no reports-specific
///                               database access, no new tables.
///
/// The controller mirrors the Dashboard aggregation conventions: paged window
/// scans with a safety cap, per-order detail reads (N+1, bounded ranges only),
/// current-cost profit resolution with honest nullability, and integer paise
/// arithmetic everywhere.
/// ---------------------------------------------------------------------------

/// One reporting window; changes rebuild [reportsControllerProvider].
final reportsRangeProvider =
    NotifierProvider<ReportsRangeController, ReportRange>(
      ReportsRangeController.new,
    );

final class ReportsRangeController extends Notifier<ReportRange> {
  @override
  ReportRange build() => _boundsFor(OrdersDatePreset.last30, DateTime.now());

  /// Applies a named preset computed from the current time. Presets that do
  /// not describe a window ([custom], [all]) are ignored here.
  void setPreset(OrdersDatePreset preset) {
    if (preset == OrdersDatePreset.custom || preset == OrdersDatePreset.all) {
      return;
    }
    state = _boundsFor(preset, DateTime.now());
  }

  /// Sets a custom inclusive local date range (picker dates, local timezone),
  /// following the orders/expenses picker convention.
  void setCustomRange(DateTime fromLocal, DateTime toLocal) {
    if (!toLocal.isAfter(fromLocal)) return;
    final toDay = _localDay(toLocal);
    state = ReportRange(
      datePreset: OrdersDatePreset.custom,
      fromUtc: _localDay(fromLocal).toUtc(),
      toUtc: _endOfDayUtc(toDay),
    );
  }

  static ReportRange _boundsFor(OrdersDatePreset preset, DateTime now) {
    final offsetDays = switch (preset) {
      OrdersDatePreset.today => 0,
      OrdersDatePreset.last7 => 6,
      OrdersDatePreset.last30 => 29,
      OrdersDatePreset.last90 => 89,
      _ => 29,
    };
    final fromDay = _localDay(now.subtract(Duration(days: offsetDays)));
    final toDay = _localDay(now);
    return ReportRange(
      datePreset: preset,
      fromUtc: fromDay.toUtc(),
      toUtc: _endOfDayUtc(toDay),
    );
  }

  static DateTime _endOfDayUtc(DateTime localDay) =>
      DateTime(localDay.year, localDay.month, localDay.day)
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1))
          .toUtc();

  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Aggregated reports state over the real orders + expenses + inventory
/// repositories.
final reportsControllerProvider =
    AsyncNotifierProvider<ReportsController, ReportsSnapshot>(
      ReportsController.new,
    );

final class ReportsController extends AsyncNotifier<ReportsSnapshot> {
  static const String tag = 'Reports';

  /// Rows fetched per repository page while scanning reporting windows.
  static const int _pageSize = 500;

  /// Safety cap for one reporting scan (matches the Dashboard ceiling; a
  /// single window past this count is beyond anything a counter needs).
  static const int _maxScannedOrders = 5000;

  /// Top-products list cap.
  static const int _topProductsLimit = 5;

  @override
  Future<ReportsSnapshot> build() async {
    requirePermission(ref, Permission.reports);
    final range = ref.watch(reportsRangeProvider);
    final orders = ref.watch(ordersRepositoryProvider);
    final expenses = ref.watch(expensesRepositoryProvider);
    final inventory = ref.watch(inventoryRepositoryProvider);
    final businessContext = ref.watch(businessSwitcherProvider);
    // Read scope from the business context (owner phone). This is read-only;
    // reports never write.
    final shopIds = await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(businessContext);
    final showBreakdown = businessContext == BusinessContext.all;
    final labelsById = await _businessLabels();
    try {
      final fromUtc = range.fromUtc;
      final toUtc = range.toUtc;
      final window = fromUtc != null && toUtc != null
          ? await _fetchWindow(orders, fromUtc, toUtc, shopIds: shopIds)
          : <OrderSummary>[];

      final products = await inventory.products(shopIds: shopIds);
      final categories = await inventory.categories(shopIds: shopIds);
      final recorded = await expenses.expenses(
        fromUtc: fromUtc,
        toUtc: toUtc,
        status: ExpenseStatusFilter.active,
        shopIds: shopIds,
      );

      final productById = <String, Product>{
        for (final product in products) product.id: product,
      };
      final variantCostById = <String, int?>{
        for (final product in products)
          for (final variant in product.variants)
            variant.id: variant.costPricePaise,
      };
      final categoryById = <String, Category>{
        for (final category in categories) category.id: category,
      };

      final daily = _dailySales(range, window);
      var salesTotal = 0;
      var itemTotal = 0;
      final paymentSplit = <PaymentMethod, int>{};
      for (final order in window) {
        salesTotal += order.totalPaise;
        itemTotal += order.itemCount;
        // NOT_PAID credit sales carry no method; they still count in revenue
        // and profit, just not in the method breakdown.
        final method = order.paymentMethod;
        if (method == null) continue;
        paymentSplit.update(
          method,
          (total) => total + order.totalPaise,
          ifAbsent: () => order.totalPaise,
        );
      }

      final byProduct = <(String, String?), List<int>>{};
      final byCategory = <String, int>{};
      var cogs = 0;
      var resolvedLines = 0;
      var unresolvedLines = 0;
      for (final order in window) {
        final detail = await orders.orderById(order.id);
        for (final item in detail.items) {
          // Variant lines stay distinguishable from plain lines and from
          // other variants of the same product: the aggregation key is the
          // snapshot name pair, never the product name alone.
          final aggregation = byProduct.putIfAbsent((
            item.productName,
            item.variantName,
          ), () => [0, 0]);
          aggregation[0] += item.quantity;
          aggregation[1] += item.lineTotalPaise;

          final product = item.productId == null
              ? null
              : productById[item.productId];
          final cost = item.variantId != null
              ? variantCostById[item.variantId]
              : product?.costPricePaise;
          if (cost != null) {
            cogs += cost * item.quantity;
            resolvedLines += 1;
          } else {
            unresolvedLines += 1;
          }

          final categoryId = product?.categoryId;
          final categoryName = categoryId == null
              ? null
              : categoryById[categoryId]?.name;
          if (categoryName != null) {
            byCategory.update(
              categoryName,
              (total) => total + item.lineTotalPaise,
              ifAbsent: () => item.lineTotalPaise,
            );
          }
        }
      }

      final topProducts = [
        for (final entry in byProduct.entries)
          ProductPerformanceRow(
            productName: entry.key.$1,
            variantName: entry.key.$2,
            unitsSold: entry.value[0],
            revenuePaise: entry.value[1],
          ),
      ]..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));
      if (topProducts.length > _topProductsLimit) {
        topProducts.removeRange(_topProductsLimit, topProducts.length);
      }

      final categoryPerformance = [
        for (final entry in byCategory.entries)
          CategoryPerformanceRow(
            categoryName: entry.key,
            revenuePaise: entry.value,
          ),
      ]..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));

      var expenseTotal = 0;
      final byExpenseCategory = <ExpenseCategory, int>{};
      final byExpensePayment = <PaymentMethod, int>{};
      for (final expense in recorded) {
        expenseTotal += expense.amountPaise;
        byExpenseCategory.update(
          expense.category,
          (total) => total + expense.amountPaise,
          ifAbsent: () => expense.amountPaise,
        );
        byExpensePayment.update(
          expense.paymentMethod,
          (total) => total + expense.amountPaise,
          ifAbsent: () => expense.amountPaise,
        );
      }

      final hasSales = window.isNotEmpty;
      final int? cogsPaise;
      final bool partialCosts;
      if (hasSales) {
        cogsPaise = resolvedLines > 0 ? cogs : null;
        partialCosts = resolvedLines > 0 && unresolvedLines > 0;
      } else {
        cogsPaise = 0;
        partialCosts = false;
      }

      return ReportsSnapshot(
        range: range,
        sales: SalesSummary(
          totalPaise: salesTotal,
          orderCount: window.length,
          itemCount: itemTotal,
          dailySalesPaise: daily,
        ),
        payments: PaymentBreakdown(
          byMethodPaise: paymentSplit,
          totalPaise: salesTotal,
        ),
        expenses: ExpenseSummary(
          totalPaise: expenseTotal,
          count: recorded.length,
          byCategoryPaise: byExpenseCategory,
          byPaymentPaise: byExpensePayment,
        ),
        profitLoss: ProfitLossSummary(
          salesPaise: salesTotal,
          expensesPaise: expenseTotal,
          cogsPaise: cogsPaise,
          netProfitPaise: cogsPaise == null
              ? null
              : salesTotal - cogsPaise - expenseTotal,
          hasSales: hasSales,
          hasExpenses: recorded.isNotEmpty,
          partialCosts: partialCosts,
        ),
        topProducts: topProducts,
        categoryPerformance: categoryPerformance,
        businessBreakdown: showBreakdown
            ? _businessBreakdown(window, labelsById)
            : const [],
      );
    } on OrdersFailure {
      rethrow;
    } on ExpensesFailure {
      rethrow;
    } on InventoryFailure {
      rethrow;
    } on PermissionDeniedFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load reports',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedReportsFailure();
    }
  }

  /// Loads every sale inside [fromUtc]..[toUtc] (inclusive), paging the
  /// repository and stopping at the safety cap.
  Future<List<OrderSummary>> _fetchWindow(
    OrdersRepository orders,
    DateTime fromUtc,
    DateTime toUtc, {
    List<String>? shopIds,
  }) async {
    final filter = OrdersFilter(fromUtc: fromUtc, toUtc: toUtc);
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
      if (!page.hasMore || fetched >= _maxScannedOrders) break;
      offset += _pageSize;
    }
    return results;
  }

  /// Maps shop ids to user-facing business labels for the Combined breakdown.
  Future<Map<String, String>> _businessLabels() async {
    final switcher = ref.read(businessSwitcherProvider.notifier);
    final labels = <String, String>{};
    try {
      final cafeId = await switcher.shopIdFor(BusinessContext.cafe);
      labels[cafeId] = BusinessContext.cafe.label;
      final ftId = await switcher.shopIdFor(BusinessContext.foodTruck);
      if (ftId != cafeId) labels[ftId] = BusinessContext.foodTruck.label;
    } catch (_) {}
    return labels;
  }

  /// Groups the window's orders by shop into per-business slices. Shops are
  /// never merged; each keeps its own label and totals.
  List<ReportsBusinessBreakdown> _businessBreakdown(
    List<OrderSummary> orders,
    Map<String, String> labelsById,
  ) {
    final byShop = <String, List<OrderSummary>>{};
    for (final order in orders) {
      byShop.putIfAbsent(order.shopId ?? '', () => []).add(order);
    }
    final result = <ReportsBusinessBreakdown>[
      for (final entry in byShop.entries)
        ReportsBusinessBreakdown(
          label: labelsById[entry.key] ?? 'Business',
          salesPaise: entry.value.fold(0, (sum, o) => sum + o.totalPaise),
          orderCount: entry.value.length,
          itemCount: entry.value.fold(0, (sum, o) => sum + o.itemCount),
        ),
    ]..sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  /// Buckets the window's receipts into one total per local day, oldest day
  /// first. [range] supplies the local-day span; orders outside it are
  /// ignored defensively.
  static List<int> _dailySales(ReportRange range, List<OrderSummary> orders) {
    final fromUtc = range.fromUtc;
    final toUtc = range.toUtc;
    if (fromUtc == null || toUtc == null) return const [];
    final startDay = _localDay(fromUtc.toLocal());
    final endDay = _localDay(toUtc.toLocal());
    final days = endDay.difference(startDay).inDays + 1;
    final buckets = List<int>.filled(days, 0);
    for (final order in orders) {
      final day = _localDay(order.createdAt.toLocal());
      final index = day.difference(startDay).inDays;
      if (index >= 0 && index < buckets.length) {
        buckets[index] += order.totalPaise;
      }
    }
    return buckets;
  }

  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Maps any thrown object to a user-safe message, following the house
/// failure-mapping convention: reports failures carry their own text, then
/// the composed repositories' display-ready failures, then a generic
/// fallback. Details are always logged, never shown.
String reportsErrorMessage(Object error, {String? fallback}) {
  if (error is ReportsFailure) {
    return error.message;
  }
  if (error is OrdersFailure) {
    return error.message;
  }
  if (error is ExpensesFailure) {
    return error.message;
  }
  if (error is InventoryFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
