import 'package:brewflow_pos/core/network/rpc_timeout.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-authoritative billing gateway (online-only).
/// Implemented via Supabase RPCs defined in 0011 migration.
abstract interface class BillingCloudGateway {
  /// Calls create_sale_atomic and returns {id, receipt_number, created_at}
  Future<Map<String, dynamic>> createSaleAtomic({
    required String shopId,
    String? customerId,
    required int subtotalPaise,
    required int totalPaise,
    required int offerDiscountPaise,
    String? paymentMethod,
    required String paymentStatus,
    required List<Map<String, dynamic>> lines,
    List<Map<String, dynamic>>? payments,
  });

  Future<Map<String, dynamic>> voidSaleAtomic(String saleId);
}

final class SupabaseBillingGateway implements BillingCloudGateway {
  SupabaseBillingGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> createSaleAtomic({
    required String shopId,
    String? customerId,
    required int subtotalPaise,
    required int totalPaise,
    required int offerDiscountPaise,
    String? paymentMethod,
    required String paymentStatus,
    required List<Map<String, dynamic>> lines,
    List<Map<String, dynamic>>? payments,
  }) async {
    final res = await rpcWithTimeout(
      () => _client.rpc<dynamic>(
        'create_sale_atomic',
        params: {
          'p_shop_id': shopId,
          'p_customer_id': customerId,
          'p_subtotal_paise': subtotalPaise,
          'p_total_paise': totalPaise,
          'p_offer_discount_paise': offerDiscountPaise,
          'p_payment_method': paymentMethod,
          'p_payment_status': paymentStatus,
          'p_lines': lines,
          'p_payments': payments,
        },
      ),
      name: 'create_sale_atomic',
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw StateError('Unexpected RPC response: $res');
  }

  @override
  Future<Map<String, dynamic>> voidSaleAtomic(String saleId) async {
    final res = await rpcWithTimeout(
      () => _client.rpc<dynamic>(
        'void_sale_atomic',
        params: {'p_sale_id': saleId},
      ),
      name: 'void_sale_atomic',
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'id': saleId};
  }
}
