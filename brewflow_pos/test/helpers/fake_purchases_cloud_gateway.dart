import 'package:brewflow_pos/features/purchases/data/purchases_cloud_gateway.dart';

class FakePurchasesCloudGateway implements PurchasesCloudGateway {
  int _purchaseCounter = 0;
  Object? nextError;

  @override
  Future<Map<String, dynamic>> receivePurchaseAtomic({
    required String shopId,
    String? supplierId,
    String? notes,
    required List<Map<String, dynamic>> lines,
  }) async {
    if (nextError != null) {
      final e = nextError;
      nextError = null;
      throw e!;
    }
    if (shopId == 'forbidden-shop') throw Exception('FORBIDDEN');
    _purchaseCounter += 1;
    return {
      'id': 'pur-${_purchaseCounter}',
      'purchase_number': 'PUR-${_purchaseCounter.toString().padLeft(6, '0')}',
      'subtotal': 10000,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
