# Printing (Phase 7.8C)

## Service boundary

`PrinterService` (`lib/features/printing/domain/printer_service.dart`):

- `statusLabel` — human-readable printer status string.
- `print(ReceiptDocument)` -> `Future<PrintResult>`.
- `testPrint()` -> `Future<PrintResult>`.

`PrintResult` is sealed: `PrintSuccess`, `PrintUnavailable(message)`, `PrintFailure(message)`.

## Default binding — honest "unavailable"

`UnverifiedPrinterService` (`lib/features/printing/data/unverified_printer_service.dart`)
implements `PrinterService`. It always returns `PrintUnavailable` with the message that
the HOP-E200 adapter is not yet verified, but it still runs the ESC/POS encoder so the
formatter is exercised in tests.

`printerServiceProvider` returns `UnverifiedPrinterService` — this provider is the
composition-root override point for a future hardware transport adapter.

## ESC/POS encoder

`EscPosReceiptEncoder` (`lib/features/printing/data/esc_pos_receipt_encoder.dart`):

- Static `encode(ReceiptDocument)` -> `Uint8List` byte stream.
- Uses standard ESC/POS commands: init (`0x1B 0x40`), alignment, bold, line feed,
  partial cut (`0x1D 0x56 0x42 0x00`).
- Targets 58mm Font A (32 columns); long product names wrap to width.
- The rupee symbol is replaced with `Rs.` for legacy codepage compatibility.
- Includes shop name (centered, bold), receipt number, date, customer name, line items
  (label + qty row), total (bold), and payment method.

## Receipt model

`ReceiptDocument` / `ReceiptLine` (`lib/features/billing/domain/receipt_document.dart`):

- Pure value object: `shopName`, `receiptNumber`, `createdAt`, `totalPaise`,
  `paymentStatus`, `paymentMethod?`, `customerName?`, `lines`.
- Factory constructors `fromSale(...)` (post-checkout) and `fromOrder(...)` (reprint
  from history).
- `toPlainText()` -> human-readable bill string used by share/print channels.

## Transport

No Bluetooth/USB/network transport is implemented yet. The repository has no verified
protocol/connectivity documentation for the HOP-E200. The architecture is ready for a
transport adapter, but none ships — printing currently reports `PrintUnavailable`.
