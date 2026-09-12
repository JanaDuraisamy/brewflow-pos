import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud-authoritative adapter for one atomic stock adjustment/opening.
///
/// Wraps the `adjust_stock_atomic` Supabase RPC (migration 0012): it validates
/// the shop/product server-side, applies the signed delta under a row lock so
/// it can never drive stock below zero, and returns the committed
/// `stock_before` / `stock_after` values plus the movement id and timestamp.
abstract interface class StockAdjustmentCloudGateway {
  /// Applies a signed [delta] to a product (or one of its variants) and
  /// returns the committed server values.
  ///
  /// [reason] is the wire movement reason (`OPENING`, `DAMAGE`, ...); [note]
  /// is optional free-form text. Server errors surface as exceptions whose
  /// message carries a stable code (`INSUFFICIENT_STOCK`, `PRODUCT_NOT_FOUND`,
  /// `INACTIVE_PRODUCT`, `FORBIDDEN`).
  Future<Map<String, dynamic>> adjustStockAtomic({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
    required String reason,
    String? note,
  });
}

final class SupabaseStockAdjustmentGateway
    implements StockAdjustmentCloudGateway {
  SupabaseStockAdjustmentGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> adjustStockAtomic({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
    required String reason,
    String? note,
  }) async {
    final res = await _client.rpc<dynamic>(
      'adjust_stock_atomic',
      params: {
        'p_shop_id': shopId,
        'p_product_id': productId,
        'p_variant_id': variantId,
        'p_delta': delta,
        'p_reason': reason,
        'p_note': note,
      },
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw StateError('Unexpected RPC response: $res');
  }
}
