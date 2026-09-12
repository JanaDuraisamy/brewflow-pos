import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PurchasesCloudGateway {
  Future<Map<String, dynamic>> receivePurchaseAtomic({
    required String shopId,
    String? supplierId,
    String? notes,
    required List<Map<String, dynamic>> lines,
  });
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
    final res = await _client.rpc<dynamic>(
      'receive_purchase_atomic',
      params: {
        'p_shop_id': shopId,
        'p_supplier_id': supplierId,
        'p_notes': notes,
        'p_lines': lines,
      },
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    throw StateError('Unexpected RPC response: $res');
  }
}
