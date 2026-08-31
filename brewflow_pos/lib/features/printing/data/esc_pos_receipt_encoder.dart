import 'dart:typed_data';

import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';

/// ---------------------------------------------------------------------------
/// ESC/POS Receipt Encoder (printer-independent)
///
/// Produces standard ESC/POS byte streams (init, alignment, bold, codepage
/// text, feed, cut) accepted by the overwhelming majority of 58mm thermal
/// receipt printers. This is a *formatting* concern only — it knows nothing
/// about transports (Bluetooth/USB/Wi-Fi), which live in hardware adapters.
///
/// Layout targets the standard 58mm default font ('Font A', 32 columns):
/// long product names wrap to the column width instead of overflowing the
/// paper; money renders as ASCII 'Rs.' (the ₹ glyph is outside standard
/// legacy codepages, so transliterating it guarantees the amount is readable
/// on paper); the payment method and customer (when present) are included so
/// the printed receipt matches the shared plain-text bill.
/// ---------------------------------------------------------------------------

final class EscPosReceiptEncoder {
  const EscPosReceiptEncoder._();

  // Standard ESC/POS control bytes.
  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  /// Printable column width of a 58mm receipt at the default Font A.
  static const int _columnWidth = 32;

  /// Encodes the bill document into a printable byte stream.
  static Uint8List encode(ReceiptDocument document) {
    final bytes = BytesBuilder();

    // Initialize printer + center the header.
    bytes.add([_esc, 0x40]);
    bytes.add([_esc, 0x61, 0x01]);
    for (final segment in _wrap(_ascii(document.shopName), _columnWidth)) {
      _line(bytes, _centered(segment, _columnWidth), bold: true);
    }
    _line(
      bytes,
      _centered(_ascii('Receipt ${document.receiptNumber}'), _columnWidth),
    );
    _line(bytes, _centered(_formatDate(document.createdAt), _columnWidth));
    if (document.customerName != null) {
      _line(
        bytes,
        _centered(_ascii('Customer: ${document.customerName}'), _columnWidth),
      );
    }
    bytes.add([_lf]);

    // Left-aligned item block: label wraps to the column width, and each
    // line's total is right-aligned within the same width.
    bytes.add([_esc, 0x61, 0x00]);
    for (final line in document.lines) {
      for (final segment in _wrap(_ascii(line.label), _columnWidth)) {
        _line(bytes, segment);
      }
      _line(
        bytes,
        _quantityRow(
          _ascii(Money.formatPaise(line.unitPricePaise)),
          line.quantity,
          _ascii(Money.formatPaise(line.lineTotalPaise)),
        ),
      );
    }
    bytes.add([_lf]);

    // Emphasized total.
    _line(
      bytes,
      _ascii(
        'TOTAL ${Money.formatPaise(document.totalPaise)}'
        ' (${document.paymentStatus.label})',
      ),
      bold: true,
    );
    if (document.paymentMethod != null) {
      _line(
        bytes,
        _ascii('Paid via ${document.paymentMethod!.name.toUpperCase()}'),
      );
    }

    // Feed and partial cut.
    bytes.add([_lf, _lf, _lf]);
    bytes.add([_gs, 0x56, 0x42, 0x00]);

    return bytes.toBytes();
  }

  static void _line(BytesBuilder bytes, String text, {bool bold = false}) {
    if (bold) {
      bytes.add([_esc, 0x45, 0x01]);
    }
    for (final unit in text.codeUnits) {
      bytes.addByte(unit);
    }
    bytes.addByte(_lf);
    if (bold) {
      bytes.add([_esc, 0x45, 0x00]);
    }
  }

  /// Hard-wraps [text] into segments that each fit [width] columns. Long
  /// product names therefore print across multiple lines instead of being
  /// clipped or overflowing the narrow 58mm paper.
  static List<String> _wrap(String text, int width) {
    final segments = <String>[];
    var rest = text;
    while (rest.length > width) {
      segments.add(rest.substring(0, width));
      rest = rest.substring(width);
    }
    if (rest.isNotEmpty) {
      segments.add(rest);
    }
    return segments.isEmpty ? [''] : segments;
  }

  /// Centers [text] within [width] printable columns.
  static String _centered(String text, int width) {
    if (text.length >= width) return text;
    final padding = (width - text.length) ~/ 2;
    return '${' ' * padding}$text';
  }

  /// Right-aligned metric row, e.g. `  Rs.120.00 x 2     Rs.240.00`.
  static String _quantityRow(String unitPrice, int quantity, String lineTotal) {
    final left = '  $unitPrice x $quantity';
    final right = lineTotal;
    final gap = (right.length >= _columnWidth - left.length)
        ? 1
        : _columnWidth - left.length - right.length;
    return '$left${' ' * gap}$right';
  }

  /// Reduces the string to printable ASCII. The ₹ symbol (outside legacy
  /// codepages) becomes the readable 'Rs.'; em-dashes become '-'; unknown
  /// glyphs become '?'.
  static String _ascii(String input) {
    final text = input.replaceAll('₹', 'Rs.');
    return text.replaceAllMapped(
      RegExp(r'[^\x20-\x7E]'),
      (match) => match.group(0) == '\u2014' ? '-' : '?',
    );
  }

  static String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hour:$minute';
  }
}
