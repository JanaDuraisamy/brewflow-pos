/// ---------------------------------------------------------------------------
/// BrewFlow POS — Orders Domain Models
///
/// Read models for completed sales history. Every value comes from the
/// snapshots persisted by the Billing module (sale headers + sale items);
/// nothing here is recomputed from current product records.
///
/// Money is always integer paise (see core/utils/money.dart); timestamps are
/// UTC instants, converted to local time only for display.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

/// One row of the completed-sales list.
///
/// [id] is the internal identifier only — it is never rendered. Everything
/// shown to the user ([receiptNumber], totals, timestamps) is persisted
/// history data.
final class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.receiptNumber,
    required this.itemCount,
    required this.totalPaise,
    required this.paymentStatus,
    required this.createdAt,
    this.paymentMethod,
    this.customerName,
    this.isVoided = false,
    this.voidedAt,
  });

  final String id;
  final String receiptNumber;

  /// Total pieces sold across all lines.
  final int itemCount;
  final int totalPaise;

  /// Collection status at the counter: paid or not paid (credit).
  final PaymentStatus paymentStatus;

  /// Method the counter accepted; null for NOT_PAID credit sales.
  final PaymentMethod? paymentMethod;
  final DateTime createdAt;

  /// Display name of the customer the sale was linked to at checkout;
  /// null when the sale was a walk-in (no customer selected).
  final String? customerName;

  /// Whether this sale has been voided (its line items and payment reversed).
  final bool isVoided;

  /// When the sale was voided; null when the sale is still active.
  final DateTime? voidedAt;
}

/// A fully loaded order (header + snapshot line items).
final class Order {
  const Order({
    required this.id,
    required this.receiptNumber,
    required this.subtotalPaise,
    required this.totalPaise,
    required this.paymentStatus,
    required this.createdAt,
    required this.items,
    this.paymentMethod,
    this.customerName,
    this.isVoided = false,
    this.voidedAt,
  });

  final String id;
  final String receiptNumber;
  final int subtotalPaise;
  final int totalPaise;

  /// Collection status at the counter: paid or not paid (credit).
  final PaymentStatus paymentStatus;

  /// Method the counter accepted; null for NOT_PAID credit sales.
  final PaymentMethod? paymentMethod;
  final DateTime createdAt;
  final List<OrderItem> items;

  /// Display name of the customer the sale was linked to at checkout;
  /// null when the sale was a walk-in (no customer selected).
  final String? customerName;

  /// Whether this sale has been voided (its line items and payment reversed).
  final bool isVoided;

  /// When the sale was voided; null when the sale is still active.
  final DateTime? voidedAt;
}

/// User-facing customer label for an order: the customer's name, or the
/// standard walk-in label when the sale was not linked to a customer.
String orderCustomerLabel(String? customerName) => customerName ?? 'Walk-in';

/// One persisted line of a completed sale — historical snapshot values.
final class OrderItem {
  const OrderItem({
    required this.productName,
    this.sku,
    required this.unitPricePaise,
    required this.quantity,
    required this.lineTotalPaise,
    this.productId,
    this.variantId,
    this.variantName,
  });

  final String productName;
  final String? sku;
  final int unitPricePaise;
  final int quantity;
  final int lineTotalPaise;

  /// Product the line was sold from; lets analytics (e.g. dashboard profit)
  /// join the sale snapshot against the product's recorded cost price.
  /// Absent only for rows persisted before this field was mapped.
  final String? productId;

  /// Variant sold; null for plain product lines.
  final String? variantId;

  /// Variant name snapshot; null for plain product lines.
  final String? variantName;
}

/// Date-range presets offered by the orders filter bar. Custom ranges picked
/// through the date range picker collapse to [custom].
enum OrdersDatePreset { all, today, last7, last30, last90, custom }

/// Immutable filter state for the completed-sales list.
///
/// [fromUtc]/[toUtc] bound the sale timestamp (inclusive, UTC). [query] is
/// matched against receipt numbers and product-name snapshots; [paymentMethod]
/// restricts to one payment method.
final class OrdersFilter {
  const OrdersFilter({
    this.query = '',
    this.paymentMethod,
    this.datePreset = OrdersDatePreset.all,
    this.fromUtc,
    this.toUtc,
  });

  final String query;
  final PaymentMethod? paymentMethod;
  final OrdersDatePreset datePreset;

  /// Inclusive UTC range bounds; both null for "all time".
  final DateTime? fromUtc;
  final DateTime? toUtc;

  /// Whether anything restricts the list beyond the default state.
  bool get isActive =>
      query.trim().isNotEmpty || paymentMethod != null || fromUtc != null;

  OrdersFilter copyWith({
    String? query,
    PaymentMethod? paymentMethod,
    OrdersDatePreset? datePreset,
    DateTime? fromUtc,
    DateTime? toUtc,
  }) => OrdersFilter(
    query: query ?? this.query,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    datePreset: datePreset ?? this.datePreset,
    fromUtc: fromUtc ?? this.fromUtc,
    toUtc: toUtc ?? this.toUtc,
  );

  @override
  bool operator ==(Object other) =>
      other is OrdersFilter &&
      other.query == query &&
      other.paymentMethod == paymentMethod &&
      other.datePreset == datePreset &&
      other.fromUtc == fromUtc &&
      other.toUtc == toUtc;

  @override
  int get hashCode =>
      Object.hash(query, paymentMethod, datePreset, fromUtc, toUtc);
}

/// One page of the completed-sales list.
final class OrdersPageResult {
  const OrdersPageResult({required this.items, required this.hasMore});

  final List<OrderSummary> items;

  /// Whether more rows exist after this page.
  final bool hasMore;
}
