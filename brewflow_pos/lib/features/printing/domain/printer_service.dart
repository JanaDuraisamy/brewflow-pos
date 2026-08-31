import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Printing Boundary
///
/// Billing/UI depends only on [PrinterService]; the concrete thermal-printer
/// transport lives behind this interface so a POSITEASY HOP-E200 today can be
/// replaced by another supported printer later without touching checkout,
/// sales or receipt logic.
///
/// HARDWARE STATUS: no verified protocol/connectivity documentation for the
/// HOP-E200 exists in this repository, and none is assumed from photos. The
/// default binding is therefore an honest "unavailable" service — it never
/// fakes a successful print. A real adapter must implement this interface
/// once its transport (Bluetooth/USB/Wi-Fi + ESC/POS dialect) is confirmed
/// against the printer's manual.
/// ---------------------------------------------------------------------------

/// Outcome of a print attempt. Never throws for printer-side problems;
/// callers surface [message] to the counter.
sealed class PrintResult {
  const PrintResult();

  /// True for any non-success outcome that should be surfaced with a retry.
  bool get isFailure => this is! PrintSuccess;

  @override
  String toString() => switch (this) {
    PrintSuccess() => 'Printed',
    final PrintUnavailable r => r.message,
    final PrintFailure r => r.message,
  };
}

final class PrintSuccess extends PrintResult {
  const PrintSuccess();
}

/// No usable printer is configured/connected.
final class PrintUnavailable extends PrintResult {
  const PrintUnavailable([
    this.message =
        'No printer connected. Connect a printer in Settings to print.',
  ]);

  final String message;
}

/// A configured printer accepted the job but printing failed (paper, error
/// state, transport drop).
final class PrintFailure extends PrintResult {
  const PrintFailure([
    this.message = 'Printing failed. Check the printer and try again.',
  ]);

  final String message;
}

abstract interface class PrinterService {
  /// Human-readable connection status for Settings/diagnostics.
  String get statusLabel;

  /// Prints the shared bill document. Implementations must be side-effect
  /// free with respect to business data; failures return [PrintFailure].
  Future<PrintResult> print(ReceiptDocument document);

  /// Diagnostics entry point (Settings → test print).
  Future<PrintResult> testPrint();
}
