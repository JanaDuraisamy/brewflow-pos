import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reusable Bill Document
///
/// The single canonical representation of a completed bill. Every consumer —
/// receipt preview, sharing, printing, reprint from Orders — renders from
/// this document so all channels show the same, consistent bill.
///
/// Pure value object built from already-persisted snapshots; never mutates
/// business state.
/// ---------------------------------------------------------------------------

/// One rendered line of the bill (snapshot values).
final class ReceiptLine {
  const ReceiptLine({
    required this.label,
    required this.unitPricePaise,
    required this.quantity,
    required this.lineTotalPaise,
    this.offerDiscountPaise = 0,
    this.appliedOfferName,
  });

  final String label;
  final int unitPricePaise;
  final int quantity;
  final int lineTotalPaise;
  final int offerDiscountPaise;
  final String? appliedOfferName;
}

final class ReceiptDocument {
  const ReceiptDocument({
    required this.shopName,
    required this.receiptNumber,
    required this.createdAt,
    required this.totalPaise,
    required this.paymentStatus,
    required this.lines,
    this.paymentMethod,
    this.customerName,
    this.subtotalPaise = 0,
    this.offerDiscountPaise = 0,
  });

  /// Configured business identity (Settings → Business Name).
  final String shopName;
  final String receiptNumber;
  final DateTime createdAt;
  final int totalPaise;
  final int subtotalPaise;
  final int offerDiscountPaise;
  final PaymentStatus paymentStatus;
  final PaymentMethod? paymentMethod;

  /// Display name of the customer the bill was raised for; null when the
  /// sale was a walk-in (no customer selected).
  final String? customerName;
  final List<ReceiptLine> lines;

  /// From a checkout result (post-sale receipt dialog / reprint flow).
  factory ReceiptDocument.fromSale({
    required String shopName,
    required Sale sale,
    required List<SaleItem> items,
    String? customerName,
  }) => ReceiptDocument(
    shopName: shopName,
    receiptNumber: sale.receiptNumber,
    createdAt: sale.createdAt,
    totalPaise: sale.totalPaise,
    subtotalPaise: sale.subtotalPaise,
    offerDiscountPaise: sale.offerDiscountPaise,
    paymentStatus: sale.paymentStatus,
    paymentMethod: sale.paymentMethod,
    customerName: customerName,
    lines: [
      for (final item in items)
        ReceiptLine(
          label: item.variantName == null
              ? item.productName
              : '${item.productName} — ${item.variantName}',
          unitPricePaise: item.unitPricePaise,
          quantity: item.quantity,
          lineTotalPaise: item.lineTotalPaise,
          offerDiscountPaise: item.offerDiscountPaise,
          appliedOfferName: item.appliedOfferName,
        ),
    ],
  );

  /// From an orders-history entry (re-share/reprint surface).
  factory ReceiptDocument.fromOrder({
    required String shopName,
    required Order order,
  }) => ReceiptDocument(
    shopName: shopName,
    receiptNumber: order.receiptNumber,
    createdAt: order.createdAt,
    totalPaise: order.totalPaise,
    subtotalPaise: order.subtotalPaise,
    offerDiscountPaise: order.items.fold(
      0,
      (sum, item) => sum + item.offerDiscountPaise,
    ),
    paymentStatus: order.paymentStatus,
    paymentMethod: order.paymentMethod,
    customerName: order.customerName,
    lines: [
      for (final item in order.items)
        ReceiptLine(
          label: item.variantName == null
              ? item.productName
              : '${item.productName} — ${item.variantName}',
          unitPricePaise: item.unitPricePaise,
          quantity: item.quantity,
          lineTotalPaise: item.lineTotalPaise,
          offerDiscountPaise: item.offerDiscountPaise,
          appliedOfferName: item.appliedOfferName,
        ),
    ],
  );

  /// Stable, human-readable rendering shared by share/print channels.
  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln(shopName)
      ..writeln('Receipt $receiptNumber')
      ..writeln(formatDateTime(createdAt));
    if (customerName != null) {
      buffer.writeln('Customer: $customerName');
    }
    buffer.writeln('--------------------------------');

    for (final line in lines) {
      buffer.writeln(
        '${line.label}\n'
        '  ${Money.formatPaise(line.unitPricePaise)} x ${line.quantity}   '
        '${Money.formatPaise(line.lineTotalPaise)}',
      );
      if (line.offerDiscountPaise > 0 && line.appliedOfferName != null) {
        buffer.writeln(
          '  Offer: ${line.appliedOfferName} -${Money.formatPaise(line.offerDiscountPaise)}',
        );
      }
    }

    if (offerDiscountPaise > 0) {
      buffer
        ..writeln('--------------------------------')
        ..writeln('Subtotal: ${Money.formatPaise(subtotalPaise)}')
        ..writeln('Offer Discount: -${Money.formatPaise(offerDiscountPaise)}')
        ..writeln('--------------------------------')
        ..writeln(
          'Total: ${Money.formatPaise(totalPaise)} (${paymentStatus.label})',
        );
    } else {
      buffer
        ..writeln('--------------------------------')
        ..writeln(
          'Total: ${Money.formatPaise(totalPaise)} (${paymentStatus.label})',
        );
    }
    if (paymentMethod != null) {
      buffer.writeln('Paid via ${paymentMethod!.name.toUpperCase()}');
    }
    return buffer.toString();
  }
}
