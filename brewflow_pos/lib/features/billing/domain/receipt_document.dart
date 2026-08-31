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
  });

  final String label;
  final int unitPricePaise;
  final int quantity;
  final int lineTotalPaise;
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
  });

  /// Configured business identity (Settings → Business Name).
  final String shopName;
  final String receiptNumber;
  final DateTime createdAt;
  final int totalPaise;
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
    }

    buffer
      ..writeln('--------------------------------')
      ..writeln(
        'Total: ${Money.formatPaise(totalPaise)} (${paymentStatus.label})',
      );
    if (paymentMethod != null) {
      buffer.writeln('Paid via ${paymentMethod!.name.toUpperCase()}');
    }
    return buffer.toString();
  }
}
