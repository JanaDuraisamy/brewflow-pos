import 'package:brewflow_pos/features/printing/domain/printer_service.dart';
import 'package:brewflow_pos/features/printing/data/esc_pos_receipt_encoder.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// Default Printer Binding — honest "no verified hardware adapter"
///
/// The HOP-E200 transport is UNVERIFIED (no protocol documentation in the
/// repository; none inferred from photos). Until a verified adapter exists,
/// this service reports unavailability and NEVER pretends to print. It still
/// exercises the full ESC/POS encoding path so the formatter is covered by
/// tests and ready for a real transport.
/// ---------------------------------------------------------------------------

final class UnverifiedPrinterService implements PrinterService {
  const UnverifiedPrinterService();

  static const String _reason =
      'Printer support for this model is not set up yet. '
      'Printing will be available once the printer adapter is configured.';

  @override
  String get statusLabel =>
      'No printer configured (HOP-E200 adapter '
      'not yet verified)';

  @override
  Future<PrintResult> print(ReceiptDocument document) async {
    // Encoding is real and deterministic; only the transport is missing.
    EscPosReceiptEncoder.encode(document);
    return const PrintUnavailable(_reason);
  }

  @override
  Future<PrintResult> testPrint() async {
    return const PrintUnavailable(_reason);
  }
}

/// Composition root. A future hardware adapter replaces this override point
/// without touching billing/UI code.
final printerServiceProvider = Provider<PrinterService>((ref) {
  return const UnverifiedPrinterService();
});
