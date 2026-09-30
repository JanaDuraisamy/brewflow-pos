import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/payment_attribution.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Payment attribution — the shared "which bucket does this sale's money
/// belong in" rule used by the Dashboard Payment Summary and the Reports
/// Payment Methods card.
///
/// These lock the three defects the summaries had:
///  - credit (NOT_PAID) sales carry no method, so grouping by method dropped
///    them and the rows never reconciled with the day/range total;
///  - split sales are PAID with a NULL header method and were dropped the
///    same way;
///  - the retired BANK method had its own summary row.
/// ---------------------------------------------------------------------------
void main() {
  OrderSummary sale({
    required String id,
    required int totalPaise,
    PaymentStatus status = PaymentStatus.paid,
    PaymentMethod? method,
  }) => OrderSummary(
    id: id,
    receiptNumber: 'BF-$id',
    itemCount: 1,
    totalPaise: totalPaise,
    paymentStatus: status,
    paymentMethod: method,
    createdAt: DateTime.utc(2026, 9, 30),
  );

  group('attributePayments', () {
    test('no sales attributes nothing', () {
      final result = attributePayments(const []);
      expect(result.cashPaise, 0);
      expect(result.upiPaise, 0);
      expect(result.notPaidPaise, 0);
      expect(result.totalPaise, 0);
      expect(result.isEmpty, isTrue);
    });

    test('splits cash and UPI sales into their own buckets', () {
      final result = attributePayments([
        sale(id: '1', totalPaise: 30000, method: PaymentMethod.cash),
        sale(id: '2', totalPaise: 20000, method: PaymentMethod.upi),
      ]);
      expect(result.cashPaise, 30000);
      expect(result.upiPaise, 20000);
      expect(result.notPaidPaise, 0);
      expect(result.totalPaise, 50000);
    });

    test('credit sales land in Not Paid even though they carry no method', () {
      // A NOT_PAID sale has payment_method = NULL by construction, so the old
      // "skip null methods" loop silently dropped the entire credit book.
      final result = attributePayments([
        sale(id: '1', totalPaise: 30000, method: PaymentMethod.cash),
        sale(
          id: '2',
          totalPaise: 45000,
          status: PaymentStatus.notPaid,
          method: null,
        ),
      ]);
      expect(result.notPaidPaise, 45000);
      expect(result.cashPaise, 30000);
      // Cash + UPI + Not Paid reconciles with the attributed total.
      expect(result.totalPaise, 75000);
    });

    test('payment status decides Not Paid, never the method', () {
      // A stray method on a credit sale must not leak it out of Not Paid.
      final result = attributePayments([
        sale(
          id: '1',
          totalPaise: 10000,
          status: PaymentStatus.notPaid,
          method: PaymentMethod.cash,
        ),
      ]);
      expect(result.notPaidPaise, 10000);
      expect(result.cashPaise, 0);
      expect(result.totalPaise, 10000);
    });

    test('split sales are read from their legs, not the NULL header', () {
      // A split sale is PAID with payment_method = NULL; the legs hold the
      // real CASH/UPI split and must sum to the sale total.
      final result = attributePayments(
        [sale(id: '1', totalPaise: 30000, method: null)],
        legsBySaleId: {
          '1': {PaymentMethod.cash: 12000, PaymentMethod.upi: 18000},
        },
      );
      expect(result.cashPaise, 12000);
      expect(result.upiPaise, 18000);
      expect(result.notPaidPaise, 0);
      expect(result.totalPaise, 30000);
    });

    test('a split sale with no legs read still keeps its total', () {
      // Defensive: a summary must never lose settled money just because the
      // leg lookup was skipped.
      final result = attributePayments([
        sale(id: '1', totalPaise: 30000, method: null),
      ]);
      expect(result.totalPaise, 30000);
      expect(result.cashPaise, 30000);
    });

    test('retired BANK money is folded into Cash, never dropped', () {
      // BANK is no longer a till option, but historical sales still carry
      // it. It must not become a summary category and must not become
      // "Not Paid" either (that money WAS collected).
      final result = attributePayments([
        sale(id: '1', totalPaise: 30000, method: PaymentMethod.bank),
        sale(id: '2', totalPaise: 20000, method: PaymentMethod.cash),
        sale(
          id: '3',
          totalPaise: 10000,
          status: PaymentStatus.notPaid,
          method: null,
        ),
      ]);
      expect(result.retiredBankPaise, 30000);
      expect(result.cashPaise, 50000);
      expect(result.upiPaise, 0);
      expect(result.notPaidPaise, 10000);
      expect(result.totalPaise, 60000);
    });

    test('Bank is never a current category in any combination', () {
      final result = attributePayments(
        [
          sale(id: '1', totalPaise: 11111, method: PaymentMethod.bank),
          sale(id: '2', totalPaise: 22222, method: PaymentMethod.upi),
          sale(
            id: '3',
            totalPaise: 33333,
            status: PaymentStatus.notPaid,
            method: null,
          ),
          sale(
            id: '4',
            totalPaise: 44444,
            method: null,
            // A split sale, cash leg.
          ),
        ],
        legsBySaleId: {
          '4': {PaymentMethod.cash: 44444},
        },
      );
      // The three visible categories always add up to the window total.
      expect(
        result.cashPaise + result.upiPaise + result.notPaidPaise,
        11111 + 22222 + 33333 + 44444,
      );
      expect(result.totalPaise, 11111 + 22222 + 33333 + 44444);
    });

    test('reconciles across a mixed real-world day', () {
      final sales = [
        sale(id: '1', totalPaise: 5000, method: PaymentMethod.cash),
        sale(id: '2', totalPaise: 2500, method: PaymentMethod.upi),
        sale(id: '3', totalPaise: 1500, method: PaymentMethod.bank),
        sale(
          id: '4',
          totalPaise: 1200,
          status: PaymentStatus.notPaid,
          method: null,
        ),
        sale(id: '5', totalPaise: 3000, method: null),
      ];
      final result = attributePayments(
        sales,
        legsBySaleId: {
          '5': {PaymentMethod.cash: 1000, PaymentMethod.upi: 2000},
        },
      );
      final salesTotal = sales.fold(0, (sum, s) => sum + s.totalPaise);
      expect(result.totalPaise, salesTotal);
      expect(result.cashPaise, 7500); // 5000 cash + 1500 bank + 1000 leg
      expect(result.upiPaise, 4500); // 2500 + 2000 leg
      expect(result.notPaidPaise, 1200);
    });
  });

  group('paymentDisplayLabel', () {
    test('renders each bill payment status', () {
      expect(
        paymentDisplayLabel(PaymentStatus.paid, PaymentMethod.cash),
        'Cash',
      );
      expect(paymentDisplayLabel(PaymentStatus.paid, PaymentMethod.upi), 'UPI');
      expect(paymentDisplayLabel(PaymentStatus.notPaid, null), 'Not paid');
    });

    test('a paid sale with a NULL method does not throw', () {
      // The regression: the old UI called paymentMethodLabel(method!) and a
      // split sale (PAID, method NULL) threw a null-check error, which
      // Flutter rendered as the gray block in the payment column.
      expect(
        () => paymentDisplayLabel(PaymentStatus.paid, null),
        returnsNormally,
      );
      expect(paymentDisplayLabel(PaymentStatus.paid, null), 'Split');
    });

    test('a paid sale with a NULL method AND status notPaid is Not paid', () {
      expect(paymentDisplayLabel(PaymentStatus.notPaid, null), 'Not paid');
    });

    test('legacy BANK sales stay readable as history', () {
      expect(
        paymentDisplayLabel(PaymentStatus.paid, PaymentMethod.bank),
        'Bank',
      );
    });
  });
}
