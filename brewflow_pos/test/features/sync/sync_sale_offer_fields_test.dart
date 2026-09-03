import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncSale offer fields', () {
    test('round-trip preserves the offer discount', () {
      final sale = SyncSale(
        id: 'sale-1',
        shopId: 'shop-1',
        receiptNumber: 'BF-1',
        subtotalPaise: 30000,
        totalPaise: 25000,
        paymentStatus: 'PAID',
        createdAt: DateTime.utc(2026, 1, 1),
        offerDiscountPaise: 5000,
      );

      final restored = SyncSale.fromJson(sale.toJson());

      expect(restored.offerDiscountPaise, 5000);
      expect(restored.totalPaise, 25000);
    });

    test('legacy payloads without offer fields default to zero', () {
      final restored = SyncSale.fromJson({
        'id': 'sale-1',
        'shopId': 'shop-1',
        'receiptNumber': 'BF-1',
        'subtotalPaise': 30000,
        'totalPaise': 30000,
        'paymentStatus': 'PAID',
        'createdAt': '2026-01-01T00:00:00.000Z',
      });

      expect(restored.offerDiscountPaise, 0);
    });
  });
  group('SyncSaleItem offer fields', () {
    test('round-trip preserves line discount and offer identity', () {
      final item = SyncSaleItem(
        id: 'item-1',
        shopId: 'shop-1',
        saleId: 'sale-1',
        productId: 'p1',
        productName: 'Filter Coffee',
        unitPricePaise: 12000,
        quantity: 2,
        lineTotalPaise: 24000,
        offerDiscountPaise: 2400,
        appliedOfferId: 'off-pct-1',
        appliedOfferName: 'Monsoon 10%',
        appliedOfferType: 'PERCENTAGE',
      );

      final restored = SyncSaleItem.fromJson(item.toJson());

      expect(restored.offerDiscountPaise, 2400);
      expect(restored.appliedOfferId, 'off-pct-1');
      expect(restored.appliedOfferName, 'Monsoon 10%');
      expect(restored.appliedOfferType, 'PERCENTAGE');
    });

    test('legacy payloads without offer fields default to none', () {
      final restored = SyncSaleItem.fromJson({
        'id': 'item-1',
        'shopId': 'shop-1',
        'saleId': 'sale-1',
        'productId': 'p1',
        'productName': 'Filter Coffee',
        'unitPricePaise': 12000,
        'quantity': 2,
        'lineTotalPaise': 24000,
      });

      expect(restored.offerDiscountPaise, 0);
      expect(restored.appliedOfferId, isNull);
      expect(restored.appliedOfferName, isNull);
      expect(restored.appliedOfferType, isNull);
    });
  });
}
