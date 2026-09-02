/// ---------------------------------------------------------------------------
/// BrewFlow POS — Orders Repository Contract
///
/// The single boundary between orders state/UI and the local Drift database.
/// It reads the sales / sale_items tables written by the Billing module; it
/// never mutates completed sales, inventory or anything else. Failures are
/// always safe-to-display [OrdersFailure] values.
/// ---------------------------------------------------------------------------
library;

import 'orders_models.dart';

/// Base for all orders failures. Every subtype carries a user-safe message.
sealed class OrdersFailure implements Exception {
  const OrdersFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The requested order does not exist (or its sale was never persisted).
final class MissingOrderFailure extends OrdersFailure {
  const MissingOrderFailure() : super('Order not found.');
}

/// Database-level surprise; details are logged, never shown to the user.
final class UnexpectedOrdersFailure extends OrdersFailure {
  const UnexpectedOrdersFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first completed-sales history contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class OrdersRepository {
  /// One page of completed sales, newest first, matching [filter].
  ///
  /// Implementation note: filtering happens in the database, never in memory,
  /// so the history can scale without loading the full dataset.
  Future<OrdersPageResult> orders({
    OrdersFilter filter = const OrdersFilter(),
    int limit = 50,
    int offset = 0,
    List<String>? shopIds,
  });

  /// Full details (header + snapshot items) of one completed sale; throws
  /// [MissingOrderFailure] when the sale does not exist.
  Future<Order> orderById(String id);
}
