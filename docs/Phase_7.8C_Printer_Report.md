# Phase 7.8C — Printer Audit + Real Fix

BrewFlow POS · Scope: printer functionality only · No backup/restore work

## Printer architecture found

Layered, transport-agnostic design:

1. **Boundary** — `lib/features/printing/domain/printer_service.dart`
   `PrinterService` interface (`statusLabel`, `print(ReceiptDocument)`,
   `testPrint()`) and sealed `PrintResult` (`PrintSuccess`, `PrintUnavailable`,
   `PrintFailure`). Printer-side problems never throw.
2. **Binding** — `lib/features/printing/data/unverified_printer_service.dart`
   `UnverifiedPrinterService`, composed by `printerServiceProvider`. Honest
   stub: runs the real ESC/POS encoder, then returns `PrintUnavailable`.
3. **Rendering** — `lib/features/printing/data/esc_pos_receipt_encoder.dart`
   printer-independent ESC/POS byte stream for 58mm thermal printers.
4. **Shared document** — `lib/features/billing/domain/receipt_document.dart`
   canonical bill (`fromSale` / `fromOrder` + `toPlainText()`).
5. **Consumers**
   - `pos_page.dart` `_ReceiptDialog` → **Print** (snackbar result) and Share.
   - `settings_page.dart` `_PrinterRow` (desktop) / `_MobilePrinterSection`
     (phone) → status + **Test Print**.
   - `order_detail_page.dart` → share only (no print from orders).

## Supported transport

**None — not implemented.** No Bluetooth/USB/network/`esc_pos` package exists
in `pubspec.yaml`. The HOP-E200 adapter referenced in the status label is
unverified (no protocol documentation in repo), so the default binding
correctly refuses to fake a print. Discovery/connection, saved-printer
selection, and reconnect therefore do not exist yet — they are transport work
blocked on verified hardware documentation, not regressions.

## Bugs found (genuine)

1. **₹ destroyed on paper** — `Money.formatPaise` returns `₹…`; the encoder's
   ASCII filter mapped every ₹ to `?`, so all amounts printed as `?120.00`.
2. **No receipt-width handling** — lines were written unbounded; long product
   names overflowed the ~32-column 58mm line and wrapped unpredictably, with
   no aligned totals.
3. **Payment method missing from the printed receipt** — encoder printed only
   the status label, unlike the share text (`Paid via CASH`).
4. **Customer never printed** — `ReceiptDocument` had no customer field, so
   both print and share omitted the customer even for customer-linked sales.
5. **Duplicate-print risk** — the Print action had no in-flight guard; a
   double-tap could submit the receipt twice.

## Fixes made

- `esc_pos_receipt_encoder.dart` rewritten:
  - ₹ → readable `Rs.` (ASCII-clean, correct on legacy codepages).
  - Every printable line wrapped/centered/right-aligned to a fixed 32-column
    width; long labels wrap (never truncate).
  - Added `Paid via <METHOD>` (when a method exists) and `Customer: <name>`
    (when present).
- `receipt_document.dart`: optional `customerName` added; populated from
  `fromOrder` (`order.customerName`) and injectable for `fromSale`; included in
  `toPlainText()` so share matches print.
- `pos_page.dart` `_ReceiptDialog` (now `ConsumerStatefulWidget`):
  - **Duplicate-print guard** — Print disabled and relabelled `Printing…`
    while a job is in flight; one sale = at most one enqueued job.
  - Resolves the linked customer name at open time and passes it to both Print
    and Share.
- Business/billing logic untouched; no schema or data changes.

## Real hardware result

**NOT TESTED** — no printer hardware available/connected. No print result was
claimed from code or tests.

## Phone result

**Pass (shared flow, code + widget tests).** The receipt-dialog Print flow is
the same checkout path on phone and desktop; printer settings surface is
present on both via the shared `_PrinterRow`. New phone-width suite still
green (receipt dialog behavior asserted at 1280×800 and mobile POS tests at
390–480dp unchanged).

## Tablet result

**Pass.** No tablet printer layout was changed; `_PrinterRow`/status/Test
Print desktop surface untouched. Encoder output and duplicate-print guard are
transport-independent, so tablet benefits identically.

## Tests

- New encoder tests: `₹ → Rs.`, payment method + customer lines, 32-column
  wrap with no truncation, `fromOrder` customer snapshot (print + plain text).
- New widget tests (`bill_print_test.dart`): retry after failure (attempts
  increment, sale intact), **no double-submit while in flight**, receipt print
  carries the linked customer name.
- Existing tests preserved (not weakened).
- `dart format .` — clean · `flutter analyze` — No issues found ·
  `flutter test` — **1224 passed, 2 skipped** (baseline 1218 → 1224).

## Remaining issues

- No transport: Bluetooth/USB/network adapter, discovery, saved-printer
  selection and reconnect are unimplemented (blocked on verified hardware
  documentation).
- Orders reprint surface (`order_detail_page.dart`) has **Share only** — no
  Print action there yet; wiring it to `printerServiceProvider` is a small
  follow-up once a transport exists.
- Hardware print validation remains **NOT TESTED**.