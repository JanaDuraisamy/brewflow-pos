import 'package:brewflow_pos/features/inventory/data/stock_adjustment_cloud_gateway.dart';

/// Hermetic [StockAdjustmentCloudGateway] for tests: mimics the
/// `adjust_stock_atomic` RPC (rejects results that would drive stock below
/// zero with `INSUFFICIENT_STOCK`) and records every call for assertions.
class FakeStockAdjustmentCloudGateway implements StockAdjustmentCloudGateway {
  /// The server's current stock level for the adjusted entity. Starts at 10;
  /// tests can lower it to simulate a divergent (server-authoritative) value.
  int stockBefore = 10;

  Object? nextError;

  final List<Map<String, dynamic>> calls = [];

  @override
  Future<Map<String, dynamic>> adjustStockAtomic({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
    required String reason,
    String? note,
  }) async {
    calls.add({
      'shop_id': shopId,
      'product_id': productId,
      'variant_id': variantId,
      'delta': delta,
      'reason': reason,
      'note': note,
    });
    if (nextError != null) {
      final error = nextError;
      nextError = null;
      throw error!;
    }
    final stockAfter = stockBefore + delta;
    if (stockAfter < 0) {
      throw Exception('INSUFFICIENT_STOCK');
    }
    final before = stockBefore;
    stockBefore = stockAfter;
    return {
      'id': 'mov-${calls.length}',
      'stock_before': before,
      'stock_after': stockAfter,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
