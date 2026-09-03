import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/printing/data/esc_pos_receipt_encoder.dart';
import 'package:brewflow_pos/features/printing/data/unverified_printer_service.dart';
import 'package:brewflow_pos/features/printing/domain/printer_service.dart';
import 'package:flutter_test/flutter_test.dart';

Sale _sale() => Sale(
  id: 's1',
  receiptNumber: 'BF-000001',
  subtotalPaise: 12000,
  totalPaise: 12000,
  offerDiscountPaise: 0,
  paymentStatus: PaymentStatus.paid,
  paymentMethod: PaymentMethod.cash,
  createdAt: DateTime.utc(2026, 8, 24, 9, 30),
  updatedAt: DateTime.utc(2026, 8, 24, 9, 30),
);

ReceiptDocument _document() => ReceiptDocument.fromSale(
  shopName: 'Sri Murugan Tea & Jigarthanda',
  sale: _sale(),
  items: [
    SaleItem(
      id: 'i1',
      saleId: 's1',
      productId: 'p1',
      productName: 'Filter Coffee',
      sku: null,
      unitPricePaise: 12000,
      quantity: 1,
      lineTotalPaise: 12000,
      offerDiscountPaise: 0,
    ),
  ],
);

/// Decodes the printer payload, skipping ESC/POS control sequences so only the
/// actual receipt text lines remain (`ESC @` = 2 bytes, `ESC <opcode> <param>` =
/// 3 bytes, `GS V <param> <param>` = 4 bytes).
String _printableText(String raw) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final unit = raw.codeUnitAt(i);
    if (unit == 0x1B) {
      i += i + 1 < raw.length && raw.codeUnitAt(i + 1) == 0x40 ? 2 : 3;
    } else if (unit == 0x1D) {
      i += 4;
    } else if (unit == 0x0A) {
      buffer.write('\n');
      i += 1;
    } else {
      buffer.writeCharCode(unit);
      i += 1;
    }
  }
  return buffer.toString();
}

void main() {
  group('ESC/POS encoder', () {
    test('emits init, header, item line, bold total and cut', () {
      final bytes = EscPosReceiptEncoder.encode(_document());

      expect(bytes.length, greaterThan(40));
      // ESC @ — initialize.
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
      final stream = String.fromCharCodes(bytes);

      // ASCII-safe header + receipt identity.
      expect(stream, contains('Sri Murugan Tea & Jigarthanda'));
      expect(stream, contains('Receipt BF-000001'));
      expect(stream, contains('Filter Coffee'));
      expect(stream, contains('TOTAL'));

      // GS V 42 0 — partial cut terminator.
      expect(bytes[bytes.length - 4], 0x1D);
      expect(bytes[bytes.length - 3], 0x56);
    });

    test('non-ASCII characters degrade to printable fallbacks', () {
      final document = ReceiptDocument.fromOrder(
        shopName: 'Café — Em dash',
        order: Order(
          id: 's2',
          receiptNumber: 'BF-000002',
          subtotalPaise: 1000,
          totalPaise: 1000,
          paymentStatus: PaymentStatus.paid,
          createdAt: DateTime.utc(2026, 8, 24),
          items: const [],
        ),
      );

      final bytes = EscPosReceiptEncoder.encode(document);
      final text = String.fromCharCodes(bytes);
      expect(text, contains('Caf? - Em dash'));
      expect(RegExp(r'[^\x00-\x7F]').hasMatch(text), isFalse);
    });

    test('money, payment method and customer print in readable ASCII', () {
      final document = ReceiptDocument.fromSale(
        shopName: 'Sri Murugan Tea & Jigarthanda',
        sale: _sale(),
        items: [
          SaleItem(
            id: 'i1',
            saleId: 's1',
            productId: 'p1',
            productName: 'Filter Coffee',
            sku: null,
            unitPricePaise: 12000,
            quantity: 1,
            lineTotalPaise: 12000,
            offerDiscountPaise: 0,
          ),
        ],
        customerName: 'Ramesh',
      );

      final text = String.fromCharCodes(EscPosReceiptEncoder.encode(document));
      expect(text, contains('Rs.120.00'));
      expect(
        text,
        isNot(contains('?120.00')),
        reason: 'the ₹ glyph must not degrade to an unreadable ?',
      );
      expect(text, contains('Paid via CASH'));
      expect(text, contains('Customer: Ramesh'));
      expect(RegExp(r'[^\x00-\x7F]').hasMatch(text), isFalse);
    });

    test(
      'fromOrder carries the customer snapshot into print and share text',
      () {
        final order = Order(
          id: 's3',
          receiptNumber: 'BF-000003',
          subtotalPaise: 4000,
          totalPaise: 4000,
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.upi,
          createdAt: DateTime.utc(2026, 8, 24),
          customerName: 'Meena',
          items: [
            OrderItem(
              productName: 'Masala Chai',
              unitPricePaise: 2000,
              quantity: 2,
              lineTotalPaise: 4000,
            ),
          ],
        );
        final document = ReceiptDocument.fromOrder(
          shopName: 'Cafe',
          order: order,
        );

        expect(document.customerName, 'Meena');
        expect(document.toPlainText(), contains('Customer: Meena'));

        final text = String.fromCharCodes(
          EscPosReceiptEncoder.encode(document),
        );
        expect(text, contains('Customer: Meena'));
        expect(text, contains('Paid via UPI'));
        expect(text, contains('Rs.40.00'));
      },
    );

    test('long product names wrap to the 32-column receipt width', () {
      const longName = 'Extra Large Filter Coffee with Double Cream Foam';
      final document = ReceiptDocument.fromSale(
        shopName: 'S',
        sale: _sale(),
        items: [
          SaleItem(
            id: 'i1',
            saleId: 's1',
            productId: 'p1',
            productName: longName,
            sku: null,
            unitPricePaise: 15000,
            quantity: 1,
            lineTotalPaise: 15000,
            offerDiscountPaise: 0,
          ),
        ],
      );

      final text = _printableText(
        String.fromCharCodes(EscPosReceiptEncoder.encode(document)),
      );

      // Every printable line fits the narrow 58mm column.
      for (final line in text.split('\n')) {
        expect(
          line.runes.length,
          lessThanOrEqualTo(32),
          reason: 'line "$line" exceeds the receipt width',
        );
      }

      // Wrapping never truncates: the full label survives across lines.
      expect(text.replaceAll('\n', ''), contains(longName));
    });
  });

  group('unverified hardware binding', () {
    test('reports honest unavailability and never fakes success', () async {
      final service = const UnverifiedPrinterService();

      expect(service.statusLabel, contains('not yet verified'));

      final printResult = await service.print(_document());
      expect(printResult, isA<PrintUnavailable>());
      expect(printResult.isFailure, isTrue);

      final testResult = await service.testPrint();
      expect(testResult, isA<PrintUnavailable>());
    });
  });
}
