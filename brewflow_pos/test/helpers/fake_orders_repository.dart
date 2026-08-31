import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';

/// In-memory [OrdersRepository] for tests.
///
/// Mirrors the Drift repository semantics relevant to state and UI: rows are
/// sorted newest first, filtering happens against the same dimensions
/// (receipt number, product-name snapshot, payment method, UTC range) and
/// pagination bounds the returned page. Can fail or stall on demand.
final class FakeOrdersRepository implements OrdersRepository {
  final List<OrderSummary> storedSummaries = [];
  final Map<String, Order> _storedOrders = {};

  /// Thrown by [orders] when set (list-load failures).
  Object? ordersError;

  /// Thrown by [orderById] when set (detail-load failures).
  Object? detailError;

  /// When set, list loads wait until released (in-flight state tests).
  Completer<void>? ordersGate;

  /// Records the (limit, offset) of every paged call.
  final List<(int limit, int offset)> pageRequests = [];

  /// Seeds one order (summary + detail) directly from checkout-style data.
  void add({
    required String receiptNumber,
    required DateTime createdAt,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    PaymentMethod? paymentMethod,
    required int totalPaise,
    required List<OrderItem> items,
    String? customerName,
    bool isVoided = false,
    DateTime? voidedAt,
  }) {
    final summary = OrderSummary(
      id: 'order-${storedSummaries.length + 1}',
      receiptNumber: receiptNumber,
      itemCount: items.fold(0, (sum, item) => sum + item.quantity),
      totalPaise: totalPaise,
      paymentStatus: paymentStatus,
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : paymentMethod,
      createdAt: createdAt,
      customerName: customerName,
      isVoided: isVoided,
      voidedAt: voidedAt,
    );
    storedSummaries.add(summary);
    _storedOrders[summary.id] = Order(
      id: summary.id,
      receiptNumber: receiptNumber,
      subtotalPaise: totalPaise,
      totalPaise: totalPaise,
      paymentStatus: paymentStatus,
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : paymentMethod,
      createdAt: createdAt,
      items: items,
      customerName: customerName,
      isVoided: isVoided,
      voidedAt: voidedAt,
    );
  }

  bool _matches(OrderSummary order, OrdersFilter filter) {
    final query = filter.query.trim();
    if (query.isNotEmpty) {
      final detail = _storedOrders[order.id];
      final byReceipt = order.receiptNumber.toLowerCase().contains(
        query.toLowerCase(),
      );
      final byProduct =
          detail?.items.any(
            (item) =>
                item.productName.toLowerCase().contains(query.toLowerCase()),
          ) ??
          false;
      if (!byReceipt && !byProduct) return false;
    }
    if (filter.paymentMethod != null &&
        order.paymentMethod != filter.paymentMethod) {
      return false;
    }
    if (filter.fromUtc != null && order.createdAt.isBefore(filter.fromUtc!)) {
      return false;
    }
    if (filter.toUtc != null && order.createdAt.isAfter(filter.toUtc!)) {
      return false;
    }
    return true;
  }

  @override
  Future<OrdersPageResult> orders({
    OrdersFilter filter = const OrdersFilter(),
    int limit = 50,
    int offset = 0,
  }) async {
    pageRequests.add((limit, offset));
    final error = ordersError;
    if (error != null) {
      throw error;
    }
    final gate = ordersGate;
    if (gate != null) {
      await gate.future;
    }
    final matching = [
      for (final order in storedSummaries)
        if (_matches(order, filter)) order,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final end = (offset + limit).clamp(0, matching.length);
    final page = offset >= matching.length
        ? <OrderSummary>[]
        : matching.sublist(offset, end);
    return OrdersPageResult(items: page, hasMore: end < matching.length);
  }

  @override
  Future<Order> orderById(String id) async {
    final error = detailError;
    if (error != null) {
      throw error;
    }
    final order = _storedOrders[id];
    if (order == null) {
      throw const MissingOrderFailure();
    }
    return order;
  }
}
