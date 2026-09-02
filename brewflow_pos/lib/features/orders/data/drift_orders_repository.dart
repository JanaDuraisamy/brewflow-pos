import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/data/orders_dao.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Orders Repository
///
/// Read-only view over the sales persisted by the Billing module. All
/// filtering happens in SQLite via [OrdersDao] (the dataset is never loaded
/// wholesale), and database exceptions are translated into safe
/// [OrdersFailure] values (details logged, never shown).
/// ---------------------------------------------------------------------------

final class DriftOrdersRepository implements OrdersRepository {
  DriftOrdersRepository(db.AppDatabase database) : _dao = OrdersDao(database);

  static const String tag = 'Orders';

  final OrdersDao _dao;

  /// Fetches one extra row to learn whether another page exists.
  static const int _probeRow = 1;

  @override
  Future<OrdersPageResult> orders({
    OrdersFilter filter = const OrdersFilter(),
    int limit = 50,
    int offset = 0,
    List<String>? shopIds,
  }) async {
    try {
      final rows = await _dao.salesPage(
        search: filter.query,
        paymentMethod: filter.paymentMethod?.dbValue,
        fromUtc: filter.fromUtc,
        toUtc: filter.toUtc,
        limit: limit + _probeRow,
        offset: offset,
        shopIds: shopIds,
      );
      final hasMore = rows.length > limit;
      final page = hasMore ? rows.sublist(0, limit) : rows;
      final counts = await _dao.itemCountsFor(page.map((row) => row.id));
      final names = await _dao.customerNamesFor([
        for (final row in page)
          if (row.customerId != null) row.customerId!,
      ]);
      return OrdersPageResult(
        items: [
          for (final row in page)
            OrderSummary(
              id: row.id,
              receiptNumber: row.receiptNumber,
              itemCount: counts[row.id] ?? 0,
              totalPaise: row.totalPaise,
              paymentStatus: PaymentStatus.fromDbValue(row.paymentStatus)!,
              paymentMethod: row.paymentMethod == null
                  ? null
                  : PaymentMethod.fromDbValue(row.paymentMethod!),
              createdAt: row.createdAt,
              customerName: row.customerId == null
                  ? null
                  : names[row.customerId],
              isVoided: row.voided,
              voidedAt: row.voidedAt,
              shopId: row.shopId,
            ),
        ],
        hasMore: hasMore,
      );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load orders', error, stackTrace);
    }
  }

  @override
  Future<Order> orderById(String id) async {
    try {
      final row = await _dao.saleById(id);
      if (row == null) {
        throw const MissingOrderFailure();
      }
      final items = await _dao.itemsBySale(id);
      final customerName = row.customerId == null
          ? null
          : await _dao.customerNameFor(row.customerId!);
      return Order(
        id: row.id,
        receiptNumber: row.receiptNumber,
        subtotalPaise: row.subtotalPaise,
        totalPaise: row.totalPaise,
        paymentStatus: PaymentStatus.fromDbValue(row.paymentStatus)!,
        paymentMethod: row.paymentMethod == null
            ? null
            : PaymentMethod.fromDbValue(row.paymentMethod!),
        createdAt: row.createdAt,
        customerName: customerName,
        isVoided: row.voided,
        voidedAt: row.voidedAt,
        items: [
          for (final item in items)
            OrderItem(
              productName: item.productName,
              sku: item.sku,
              unitPricePaise: item.unitPricePaise,
              quantity: item.quantity,
              lineTotalPaise: item.lineTotalPaise,
              productId: item.productId,
              variantId: item.variantId,
              variantName: item.variantName,
            ),
        ],
      );
    } on OrdersFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load order details', error, stackTrace);
    }
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedOrdersFailure();
  }
}
