/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reports Domain Models
///
/// Read-only aggregation models for the Reports module. Every value is
/// computed by the reports controller from existing repositories (orders,
/// expenses, inventory); nothing here mutates data and no database rows leak
/// past the controller boundary.
///
/// Money is always integer paise (see core/utils/money.dart); timestamps are
/// UTC instants, converted to local time only for display and day bucketing,
/// following the exact convention used by orders/expenses filters.
///
/// The sealed [ReportsFailure] contract also lives here: the Report module
/// composes repositories instead of owning one, so its failures share this
/// domain file rather than a dedicated repository file.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';

/// Bounds of one reporting window, reusing the established preset semantics.
final class ReportRange {
  const ReportRange({
    this.datePreset = OrdersDatePreset.last30,
    this.fromUtc,
    this.toUtc,
  });

  /// Named preset driving [fromUtc]/[toUtc]; [custom] for picked ranges.
  final OrdersDatePreset datePreset;

  /// Inclusive UTC bounds; both null only when the range is "all time"
  /// (never the default — reports always default to a bounded range).
  final DateTime? fromUtc;
  final DateTime? toUtc;

  bool get isCustom => datePreset == OrdersDatePreset.custom;

  @override
  bool operator ==(Object other) =>
      other is ReportRange &&
      other.datePreset == datePreset &&
      other.fromUtc == fromUtc &&
      other.toUtc == toUtc;

  @override
  int get hashCode => Object.hash(datePreset, fromUtc, toUtc);
}

/// Sales totals over one reporting window.
final class SalesSummary {
  const SalesSummary({
    required this.totalPaise,
    required this.orderCount,
    required this.itemCount,
    required this.dailySalesPaise,
  });

  /// Total receipts in the window.
  final int totalPaise;

  /// Completed-sale count in the window.
  final int orderCount;

  /// Pieces sold in the window.
  final int itemCount;

  /// Total receipts per local day across the range, oldest day first.
  final List<int> dailySalesPaise;

  /// Average order value; null when nothing was sold (UI shows '—', never
  /// an invented figure).
  int? get averageSalePaise =>
      orderCount == 0 ? null : totalPaise ~/ orderCount;
}

/// Receipt totals split by payment method.
final class PaymentBreakdown {
  const PaymentBreakdown({
    required this.byMethodPaise,
    required this.totalPaise,
  });

  /// Totals per payment method; methods without sales are absent.
  final Map<PaymentMethod, int> byMethodPaise;

  /// Same as the sales total, kept here so shares never divide by zero.
  final int totalPaise;

  int paiseOf(PaymentMethod method) => byMethodPaise[method] ?? 0;

  /// Whole-percent share of the window total; null when there is no sales
  /// total (the UI then shows '—').
  int? shareOf(PaymentMethod method) {
    if (totalPaise <= 0) return null;
    return (paiseOf(method) * 100) ~/ totalPaise;
  }
}

/// Active-expense totals over one reporting window.
final class ExpenseSummary {
  const ExpenseSummary({
    required this.totalPaise,
    required this.count,
    required this.byCategoryPaise,
    required this.byPaymentPaise,
  });

  /// Sum of the window's active expenses.
  final int totalPaise;

  /// Number of active expenses in the window.
  final int count;

  /// Totals per fixed [ExpenseCategory]; zero entries are absent.
  final Map<ExpenseCategory, int> byCategoryPaise;

  /// Totals per payment method; zero entries are absent.
  final Map<PaymentMethod, int> byPaymentPaise;
}

/// Profit & loss over one reporting window.
///
/// Cost of goods resolves each sold line against the product's CURRENT cost
/// price (no historical cost snapshot exists in the schema). [cogsPaise] is
/// null whenever sales exist but no line resolves to a cost price, and
/// [netProfitPaise] is null then too — unknown profit is never replaced by a
/// fabricated figure (₹0.00 or otherwise).
final class ProfitLossSummary {
  const ProfitLossSummary({
    required this.salesPaise,
    required this.expensesPaise,
    required this.cogsPaise,
    required this.netProfitPaise,
    required this.hasSales,
    required this.hasExpenses,
    required this.partialCosts,
  });

  final int salesPaise;
  final int expensesPaise;

  /// Cost of goods over resolved lines; null when sales exist but nothing
  /// resolved, 0 when nothing was sold.
  final int? cogsPaise;

  /// sales − cogs − expenses; null whenever [cogsPaise] is null.
  final int? netProfitPaise;

  final bool hasSales;
  final bool hasExpenses;

  /// Whether some lines resolved to a current cost while others did not
  /// (profit then covers only the resolvable lines).
  final bool partialCosts;
}

/// One row of the top-products list (name snapshots from the sale).
final class ProductPerformanceRow {
  const ProductPerformanceRow({
    required this.productName,
    this.variantName,
    required this.unitsSold,
    required this.revenuePaise,
  });

  /// Product name snapshot stored on the sale items — historical display
  /// never depends on the current product record.
  final String productName;

  /// Variant name snapshot stored on the sale items; null for plain lines.
  /// Variants of the same product aggregate into their own rows, never into
  /// the plain-product row or into each other.
  final String? variantName;
  final int unitsSold;
  final int revenuePaise;
}

/// One row of the category performance list.
final class CategoryPerformanceRow {
  const CategoryPerformanceRow({
    required this.categoryName,
    required this.revenuePaise,
  });

  /// Current category name joined through the product (categories are not
  /// snapshotted on sale items; attribution is current, not historical).
  final String categoryName;
  final int revenuePaise;
}

/// Everything the Reports page renders for one window.
final class ReportsSnapshot {
  const ReportsSnapshot({
    required this.range,
    required this.sales,
    required this.payments,
    required this.expenses,
    required this.profitLoss,
    required this.topProducts,
    required this.categoryPerformance,
  });

  final ReportRange range;
  final SalesSummary sales;
  final PaymentBreakdown payments;
  final ExpenseSummary expenses;
  final ProfitLossSummary profitLoss;
  final List<ProductPerformanceRow> topProducts;
  final List<CategoryPerformanceRow> categoryPerformance;
}

/// Base for all reports failures. Every subtype carries a user-safe message.
sealed class ReportsFailure implements Exception {
  const ReportsFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Unexpected error while building reports; details are logged, never shown.
final class UnexpectedReportsFailure extends ReportsFailure {
  const UnexpectedReportsFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}
