import 'package:brewflow_pos/core/network/rpc_timeout.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PurchasesCloudGateway {
  Future<Map<String, dynamic>> receivePurchaseAtomic({
    required String shopId,
    String? supplierId,
    String? notes,
    required List<Map<String, dynamic>> lines,
  });

  /// Voids a received purchase on the server: reverses the stock each line
  /// added and deletes the purchase + its item/movement history atomically.
  Future<Map<String, dynamic>> voidPurchaseAtomic({required String purchaseId});
}

final class SupabasePurchasesGateway implements PurchasesCloudGateway {
  SupabasePurchasesGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> receivePurchaseAtomic({
    required String shopId,
    String? supplierId,
    String? notes,
    required List<Map<String, dynamic>> lines,
  }) async {
    final res = await rpcWithTimeout(
      () => _client.rpc<dynamic>(
        'receive_purchase_atomic',
        params: {
          'p_shop_id': shopId,
          'p_supplier_id': supplierId,
          'p_notes': notes,
          'p_lines': lines,
        },
      ),
      name: 'receive_purchase_atomic',
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw StateError('Unexpected RPC response: $res');
  }

  @override
  Future<Map<String, dynamic>> voidPurchaseAtomic({
    required String purchaseId,
  }) async {
    final res = await rpcWithTimeout(
      () => _client.rpc<dynamic>(
        'void_purchase_atomic',
        params: {'p_purchase_id': purchaseId},
      ),
      name: 'void_purchase_atomic',
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw StateError('Unexpected RPC response: $res');
  }
}
