import 'package:brewflow_pos/features/billing/data/billing_cloud_gateway.dart';

/// Captured arguments of one `createSaleAtomic` call.
final class CreateSaleArgs {
  CreateSaleArgs({
    required this.shopId,
    required this.customerId,
    required this.subtotalPaise,
    required this.totalPaise,
    required this.offerDiscountPaise,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.lines,
    required this.payments,
  });

  final String shopId;
  final String? customerId;
  final int subtotalPaise;
  final int totalPaise;
  final int offerDiscountPaise;
  final String? paymentMethod;
  final String paymentStatus;
  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>>? payments;
}

class FakeBillingCloudGateway implements BillingCloudGateway {
  int _receiptCounter = 0;
  final List<Map<String, dynamic>> calls = [];

  /// Every `createSaleAtomic` argument set, so split-payment tests can assert
  /// the legs actually reached the RPC rather than only that it was called.
  final List<CreateSaleArgs> createSaleArgs = [];
  Object? nextError;

  CreateSaleArgs? get lastCreateSale =>
      createSaleArgs.isEmpty ? null : createSaleArgs.last;

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
    List<Map<String, dynamic>>? payments,
  }) async {
    calls.add({'shopId': shopId, 'lines': lines});
    createSaleArgs.add(
      CreateSaleArgs(
        shopId: shopId,
        customerId: customerId,
        subtotalPaise: subtotalPaise,
        totalPaise: totalPaise,
        offerDiscountPaise: offerDiscountPaise,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        lines: lines,
        payments: payments,
      ),
    );
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
