import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';
import 'package:flutter_test/flutter_test.dart';

Sale _sale({PaymentStatus status = PaymentStatus.paid}) => Sale(
  id: 's1',
  receiptNumber: 'BF-000001',
  subtotalPaise: 32000,
  totalPaise: 32000,
  paymentStatus: status,
  paymentMethod: status == PaymentStatus.paid ? PaymentMethod.upi : null,
  createdAt: DateTime.utc(2026, 8, 24, 9, 30),
  updatedAt: DateTime.utc(2026, 8, 24, 9, 30),
);

void main() {
  group('ReceiptDocument', () {
    test('renders shop name, receipt number, items and paid total', () {
      final document = ReceiptDocument.fromSale(
        shopName: 'Sri Murugan Tea & Jigarthanda',
        sale: _sale(),
        items: const [
          SaleItem(
            id: 'i1',
            saleId: 's1',
            productId: 'p1',
            productName: 'Filter Coffee',
            sku: 'FC-01',
            unitPricePaise: 12000,
            quantity: 2,
            lineTotalPaise: 24000,
          ),
          SaleItem(
            id: 'i2',
            saleId: 's1',
            productId: 'p2',
            productName: 'Green Tea',
            variantName: 'Large',
            unitPricePaise: 8000,
            quantity: 1,
            lineTotalPaise: 8000,
          ),
        ],
      );

      final text = document.toPlainText();

      expect(text, contains('Sri Murugan Tea & Jigarthanda'));
      expect(text, contains('Receipt BF-000001'));
      expect(text, contains('Filter Coffee'));
      expect(text, contains('₹120.00 x 2   ₹240.00'));
      expect(text, contains('Green Tea — Large'));
      expect(text, contains('Total: ₹320.00 (Paid)'));
      expect(text, contains('Paid via UPI'));
    });

    test('credit bill renders Not paid and no payment method', () {
      final document = ReceiptDocument.fromSale(
        shopName: 'Shop',
        sale: _sale(status: PaymentStatus.notPaid),
        items: const [],
      );

      final text = document.toPlainText();
      expect(text, contains('(Not paid)'));
      expect(text, isNot(contains('Paid via')));
    });

    test('builds identically from an orders-history entry', () {
      final singleItemSale = Sale(
        id: 's1',
        receiptNumber: 'BF-000001',
        subtotalPaise: 24000,
        totalPaise: 24000,
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.upi,
        createdAt: DateTime.utc(2026, 8, 24, 9, 30),
        updatedAt: DateTime.utc(2026, 8, 24, 9, 30),
      );
      final fromSaleDoc = ReceiptDocument.fromSale(
        shopName: 'Shop',
        sale: singleItemSale,
        items: const [
          SaleItem(
            id: 'i1',
            saleId: 's1',
            productId: 'p1',
            productName: 'Filter Coffee',
            sku: 'FC-01',
            unitPricePaise: 12000,
            quantity: 2,
            lineTotalPaise: 24000,
          ),
        ],
      );
      final fromOrderDoc = ReceiptDocument.fromOrder(
        shopName: 'Shop',
        order: Order(
          id: 's1',
          receiptNumber: 'BF-000001',
          subtotalPaise: 24000,
          totalPaise: 24000,
          paymentStatus: PaymentStatus.paid,
          createdAt: DateTime.utc(2026, 8, 24, 9, 30),
          paymentMethod: PaymentMethod.upi,
          items: [
            OrderItem(
              productName: 'Filter Coffee',
              sku: 'FC-01',
              unitPricePaise: 12000,
              quantity: 2,
              lineTotalPaise: 24000,
            ),
          ],
        ),
      );

      expect(fromOrderDoc.toPlainText(), fromSaleDoc.toPlainText());
    });
  });
}
