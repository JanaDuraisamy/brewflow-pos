/// ---------------------------------------------------------------------------
/// BrewFlow POS — Payment Attribution
///
/// The single definition of "which payment summary bucket does this sale's
/// money belong in", shared by the Dashboard Payment Summary and the Reports
/// Payment Methods card so the two can never disagree.
///
/// It deliberately builds on the EXISTING payment model rather than a second
/// one: [PaymentStatus] decides settled-vs-credit and [PaymentMethod] names
/// the instrument. A sale is unpaid if and only if its status says so; the
/// method never decides that.
///
/// Three real facts make a naive "group by paymentMethod" wrong:
///
/// 1. A NOT_PAID credit sale carries NO method (`payment_method` is NULL for
///    credit bills). Grouping by method silently drops every credit sale, so
///    the rows never add up to the day total. Those belong in **Not Paid**.
/// 2. A split sale is stored as PAID with a NULL header method and one
///    `sale_payments` row per leg (`sales.payment_method` is only kept for
///    single-payment sales). Skipping null methods therefore drops split
///    sales too. Their legs are the truth, so they are read back and split
///    across the live methods.
/// 3. `PaymentMethod.bank` is a RETIRED till method: the POS never offers it
///    and `sale_payments` constrains legs to CASH/UPI, but historical sales
///    still carry it and must stay readable per-bill. Since the summaries now
///    show exactly Cash / UPI / Not Paid, retired-BANK money is folded into
///    Cash as settled counter money (tracked separately as
///    [PaymentAttribution.retiredBankPaise] so it stays auditable and
///    testable) — it is genuinely collected, so calling it "Not Paid" would be
///    a lie, and dropping it would break the sum.
///
/// The result satisfies, by construction:
/// `cashPaise + upiPaise + notPaidPaise == totalPaise` of the attributed
/// sales.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

import 'orders_models.dart';

/// How a window's sales split across the three payment summary categories.
final class PaymentAttribution {
  const PaymentAttribution({
    required this.cashPaise,
    required this.upiPaise,
    required this.notPaidPaise,
    this.retiredBankPaise = 0,
  });

  /// Nothing at all in the window (no sales, or no attributed money).
  static const PaymentAttribution empty = PaymentAttribution(
    cashPaise: 0,
    upiPaise: 0,
    notPaidPaise: 0,
  );

  /// Settled money taken at the till. Includes [retiredBankPaise].
  final int cashPaise;

  /// Settled money received over UPI.
  final int upiPaise;

  /// Credit sales still owed: the total of every NOT_PAID sale in the window.
  /// This is the "Not Paid" row — it is never used as a catch-all for money
  /// that failed to resolve to a method.
  final int notPaidPaise;

  /// Settled legacy BANK money folded into [cashPaise]. Kept out of the UI
  /// (BANK is not a current category) but never discarded.
  final int retiredBankPaise;

  /// Every attributed paise: exactly the summed totals of [sales].
  int get totalPaise => cashPaise + upiPaise + notPaidPaise;

  bool get isEmpty => totalPaise == 0;
}

/// Attributes [sales] to Cash / UPI / Not Paid.
///
/// [legsBySaleId] carries the `sale_payments` rows of the same sales (see
/// [OrdersRepository.paymentLegsFor]); pass an empty map when no legs were
/// read — split sales then fall back to Cash as settled-but-unsplit money, so
/// the totals still reconcile instead of going missing.
PaymentAttribution attributePayments(
  List<OrderSummary> sales, {
  Map<String, Map<PaymentMethod, int>> legsBySaleId = const {},
}) {
  var cash = 0;
  var upi = 0;
  var notPaid = 0;
  var retiredBank = 0;

  void addCash(int paise) => cash += paise;
  void addUpi(int paise) => upi += paise;

  for (final sale in sales) {
    // A credit bill is money that has NOT been collected. The existing status
    // is the only thing that decides this; the method is irrelevant (it is
    // NULL for credit sales by construction).
    if (sale.paymentStatus == PaymentStatus.notPaid) {
      notPaid += sale.totalPaise;
      continue;
    }

    final method = sale.paymentMethod;
    if (method != null) {
      switch (method) {
        case PaymentMethod.cash:
          addCash(sale.totalPaise);
        case PaymentMethod.upi:
          addUpi(sale.totalPaise);
        case PaymentMethod.bank:
          // Retired instrument: keep it out of the categories but never drop
          // it from the total. Settled, so it counts as counter money.
          retiredBank += sale.totalPaise;
          addCash(sale.totalPaise);
      }
      continue;
    }

    // PAID with a NULL header method: a split sale. Its legs are the truth.
    final legs = legsBySaleId[sale.id];
    if (legs == null || legs.isEmpty) {
      // Settled but unattributable (no legs read, or a legacy row with no
      // method and no legs). Keep the total honest rather than losing it.
      addCash(sale.totalPaise);
      continue;
    }
    legs.forEach((legMethod, legPaise) {
      switch (legMethod) {
        case PaymentMethod.cash:
          addCash(legPaise);
        case PaymentMethod.upi:
          addUpi(legPaise);
        case PaymentMethod.bank:
          retiredBank += legPaise;
          addCash(legPaise);
      }
    });
  }

  return PaymentAttribution(
    cashPaise: cash,
    upiPaise: upi,
    notPaidPaise: notPaid,
    retiredBankPaise: retiredBank,
  );
}

/// Display label for a sale's payment column.
///
/// Never force-unwraps [method]: a PAID sale can legitimately carry a NULL
/// header method (split sales leave `sales.payment_method` NULL and store
/// their legs in `sale_payments`). The old UI read
/// `paymentMethodLabel(bill.paymentMethod!)`, which threw a null-check error
/// on exactly those sales and rendered the whole payment column as the gray
/// error block on the dashboard's Recent Bills and on Orders.
String paymentDisplayLabel(PaymentStatus status, PaymentMethod? method) =>
    switch (status) {
      PaymentStatus.notPaid => 'Not paid',
      PaymentStatus.paid => switch (method) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.upi => 'UPI',
        // Retired method: still readable as history, per-bill.
        PaymentMethod.bank => 'Bank',
        null => 'Split',
      },
    };
