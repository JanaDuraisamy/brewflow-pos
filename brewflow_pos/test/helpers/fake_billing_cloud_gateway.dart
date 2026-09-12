import 'package:brewflow_pos/features/billing/data/billing_cloud_gateway.dart';

class FakeBillingCloudGateway implements BillingCloudGateway {
  int _receiptCounter = 0;
  final List<Map<String, dynamic>> calls = [];
  Object? nextError;

  /// If set, createSaleAtomic will check stock via this callback and throw.
  Future<void> Function(List<Map<String, dynamic>> lines)? stockCheck;

  String _receipt() {
    _receiptCounter += 1;
    return 'BF-${_receiptCounter.toString().padLeft(6, '0')}';
  }

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
  }) async {
    calls.add({'shopId': shopId, 'lines': lines});
    if (nextError != null) {
      final e = nextError;
      nextError = null;
      throw e!;
    }
    if (stockCheck != null) await stockCheck!(lines);
    // Simulate shop isolation: if shopId == forbidden, throw FORBIDDEN
    if (shopId == 'forbidden-shop') throw Exception('FORBIDDEN');
    final receipt = _receipt();
    return {
      'id': 'sale-$_receiptCounter',
      'receipt_number': receipt,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> voidSaleAtomic(String saleId) async {
    if (nextError != null) {
      final e = nextError;
      nextError = null;
      throw e!;
    }
    if (saleId == 'already-voided') throw Exception('ALREADY_VOIDED');
    if (saleId == 'not-found') throw Exception('SALE_NOT_FOUND');
    if (saleId == 'forbidden-shop') throw Exception('FORBIDDEN');
    return {
      'id': saleId,
      'voided_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
