import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/orders/data/drift_orders_repository.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Orders State (Riverpod)
///
/// Composition:
/// - [ordersRepositoryProvider] → Drift-backed read-only repository.
/// - [ordersFilterProvider]     → search / payment / date-range filter state.
/// - [ordersListProvider]       → paged completed-sales feed; filter changes
///                                reset it to the first page, [loadMore]
///                                appends the next page without touching the
///                                repository state shape.
/// - [orderDetailProvider]      → full snapshot details of one sale.
///
/// Orders never mutate data: the repository is read-only and watching the
/// history never touches stock, sales or inventory.
/// ---------------------------------------------------------------------------

/// Owns the single orders repository for the application scope.
final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return DriftOrdersRepository(ref.watch(appDatabaseProvider));
});

/// Holds the current completed-sales filter state.
final ordersFilterProvider =
    NotifierProvider<OrdersFilterController, OrdersFilter>(
      OrdersFilterController.new,
    );

/// Bounds for a whole "local day" converted to UTC instants.
final class _DayBound {
  const _DayBound(this.fromUtc, this.toUtc);

  final DateTime fromUtc;
  final DateTime toUtc;
}

final class OrdersFilterController extends Notifier<OrdersFilter> {
  @override
  OrdersFilter build() => const OrdersFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setPaymentMethod(PaymentMethod? paymentMethod) =>
      state = state.copyWith(paymentMethod: paymentMethod);

  /// Applies a named date-range preset, computed from the current time.
  void setPreset(OrdersDatePreset preset) {
    if (preset == OrdersDatePreset.custom) {
      return;
    }
    if (preset == OrdersDatePreset.all) {
      state = OrdersFilter(
        query: state.query,
        paymentMethod: state.paymentMethod,
      );
      return;
    }
    final now = DateTime.now();
    final offsetDays = switch (preset) {
      OrdersDatePreset.today => 0,
      OrdersDatePreset.last7 => 6,
      OrdersDatePreset.last30 => 29,
      OrdersDatePreset.last90 => 89,
      _ => 0,
    };
    final fromDay = _localDay(now.subtract(Duration(days: offsetDays)));
    final toDay = _localDay(now);
    state = state.copyWith(
      datePreset: preset,
      fromUtc: fromDay.toUtc(),
      toUtc: toDay
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1))
          .toUtc(),
    );
  }

  /// Sets a custom inclusive local date range (picker dates, local timezone).
  void setCustomRange(DateTime fromLocal, DateTime toLocal) {
    if (!toLocal.isAfter(fromLocal)) return;
    final bounds = _boundsOf(_localDay(toLocal));
    state = state.copyWith(
      datePreset: OrdersDatePreset.custom,
      fromUtc: _localDay(fromLocal).toUtc(),
      toUtc: bounds.toUtc,
    );
  }

  void clear() => state = const OrdersFilter();

  static _DayBound _boundsOf(DateTime startOfDay) => _DayBound(
    startOfDay.toUtc(),
    startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1))
        .toUtc(),
  );

  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// One loaded page of the completed-sales feed.
final class OrdersFeed {
  const OrdersFeed({required this.items, required this.hasMore});

  final List<OrderSummary> items;
  final bool hasMore;
}

/// Paged completed-sales list, newest first, driven by [ordersFilterProvider].
final ordersListProvider =
    AsyncNotifierProvider<OrdersListController, OrdersFeed>(
      OrdersListController.new,
    );

final class OrdersListController extends AsyncNotifier<OrdersFeed> {
  static const String tag = 'Orders';

  /// Rows fetched per page; keeps history navigable without loading it all.
  static const int pageSize = 50;

  bool _loadingMore = false;

  @override
  Future<OrdersFeed> build() async {
    final filter = ref.watch(ordersFilterProvider);
    final repository = ref.watch(ordersRepositoryProvider);
    final businessContext = ref.watch(businessSwitcherProvider);
    final shopIds = await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(businessContext);
    try {
      final page = await repository.orders(
        filter: filter,
        limit: pageSize,
        shopIds: shopIds,
      );
      return OrdersFeed(items: page.items, hasMore: page.hasMore);
    } on OrdersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load orders',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedOrdersFailure();
    }
  }

  /// Appends the next page. Stale results (filter changed mid-flight) are
  /// discarded; failures surface as [OrdersFailure] for the UI to show while
  /// the already-loaded rows stay visible.
  Future<void> loadMore() async {
    if (_loadingMore || state.value == null) return;
    final accumulated = state.value!;
    if (!accumulated.hasMore) return;
    final filterAtStart = ref.read(ordersFilterProvider);
    final repository = ref.read(ordersRepositoryProvider);
    final businessContext = ref.read(businessSwitcherProvider);
    final shopIds = await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(businessContext);
    _loadingMore = true;
    try {
      final page = await repository.orders(
        filter: filterAtStart,
        limit: pageSize,
        offset: accumulated.items.length,
        shopIds: shopIds,
      );
      if (ref.read(ordersFilterProvider) != filterAtStart) {
        return;
      }
      state = AsyncData(
        OrdersFeed(
          items: [...accumulated.items, ...page.items],
          hasMore: page.hasMore,
        ),
      );
    } on OrdersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load more orders',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedOrdersFailure();
    } finally {
      _loadingMore = false;
    }
  }

  /// Marks a sale as voided (owner-only). Restores stock and reverses
  /// payments atomically through the billing repository.
  Future<void> voidOrder(String saleId) async {
    requireOwner(ref);
    try {
      await ref.read(billingRepositoryProvider).voidSale(saleId);
      ref.invalidateSelf();
      ref.invalidate(orderDetailProvider);
    } on BillingFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to void order',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedOrdersFailure();
    }
  }
}

/// Full snapshot details of one completed sale.
final orderDetailProvider = FutureProvider.family<Order, String>((
  ref,
  saleId,
) async {
  final repository = ref.watch(ordersRepositoryProvider);
  try {
    return await repository.orderById(saleId);
  } on OrdersFailure {
    rethrow;
  } catch (error, stackTrace) {
    AppLog.error(
      'Failed to load order details',
      tag: 'Orders',
      error: error,
      stackTrace: stackTrace,
    );
    throw const UnexpectedOrdersFailure();
  }
});

/// Maps any thrown object to a user-safe message.
///
/// [OrdersFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String ordersErrorMessage(Object error, {String? fallback}) {
  if (error is OrdersFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}

/// Display label for a payment method, e.g. 'Cash', 'UPI', 'Bank'.
String paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.upi => 'UPI',
  PaymentMethod.bank => 'Bank',
};

/// Pluralized pieces label, e.g. '1 item' / '3 items'.
String itemsLabel(int count) => '$count item${count == 1 ? '' : 's'}';
