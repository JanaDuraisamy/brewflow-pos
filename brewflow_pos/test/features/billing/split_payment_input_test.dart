import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Split-payment input contract.
///
/// The cashier-facing contract is RUPEES. Everything below the UI is paise.
/// The regression these tests lock: the split sheet used to `int.tryParse` the
/// raw field, so a cashier typing `200` against a ₹278 total produced 200
/// paise — ₹2 — and the sale was then rejected as short. A unit label the
/// cashier cannot act on is a data bug, not a cosmetic one.
/// ---------------------------------------------------------------------------
void main() {
  // The reported scenario, verbatim.
  const totalRupees = 278;

  group('rupees in, paise out', () {
    test('₹200 is 20000 paise, not 200', () {
      final draft = SplitPaymentDraft.fromRupeeInput(
        cash: '200',
        upi: '78',
        totalPaise: totalRupees * 100,
      );
      expect(draft.cashPaise, 20000);
      expect(draft.upiPaise, 7800);
    });

    test('a whole rupee amount becomes 100x its integer value', () {
      final draft = SplitPaymentDraft.fromRupeeInput(
        cash: '200',
        upi: '78',
        totalPaise: 0,
      );
      expect(draft.cashPaise, 200 * 100);
      expect(draft.upiPaise, 78 * 100);
    });

    test('₹200 cash + ₹78 UPI exactly completes ₹278', () {
      final draft = SplitPaymentDraft.fromRupeeInput(
        cash: '200',
        upi: '78',
        totalPaise: 27800,
      );
      expect(draft.sumPaise, 27800);
      expect(draft.remainingPaise, 0);
      expect(draft.state, SplitDraftState.exact);
      expect(draft.canSubmit, isTrue);
      expect(draft.problem, isNull);
    });

    test('the legs handed to the repository are the paise amounts', () {
      final payments = SplitPaymentDraft.fromRupeeInput(
        cash: '200',
        upi: '78',
        totalPaise: 27800,
      ).toPayments();

      expect(payments, hasLength(2));
      expect(payments[0].paymentMethod, PaymentMethod.cash);
      expect(payments[0].amountPaise, 20000);
      expect(payments[1].paymentMethod, PaymentMethod.upi);
      expect(payments[1].amountPaise, 7800);
    });

    test('a decimal rupee amount keeps its paise precision', () {
      final draft = SplitPaymentDraft.fromRupeeInput(
        cash: '200.50',
        upi: '77.50',
        totalPaise: 27800,
      );
      expect(draft.cashPaise, 20050);
      expect(draft.upiPaise, 7750);
      expect(draft.state, SplitDraftState.exact);
    });

    test('a single decimal place is read as paise, not truncated', () {
      final draft = SplitPaymentDraft.fromRupeeInput(
        cash: '200.5',
        upi: '77.5',
        totalPaise: 27800,
      );
      expect(draft.cashPaise, 20050);
      expect(draft.state, SplitDraftState.exact);
    });
  });

  group('edge cases required by the brief', () {
    SplitPaymentDraft draft(String cash, String upi) =>
        SplitPaymentDraft.fromRupeeInput(
          cash: cash,
          upi: upi,
          totalPaise: 27800,
        );

    test('under the total is reported as remaining', () {
      final result = draft('150', '100');
      expect(result.state, SplitDraftState.under);
      expect(result.canSubmit, isFalse);
      expect(result.sumPaise, 25000);
      expect(result.remainingPaise, 2800);
      expect(result.problem, 'Remaining: ₹28.00');
    });

    test('over the total is reported as overpaid', () {
      final result = draft('200', '100');
      expect(result.state, SplitDraftState.over);
      expect(result.canSubmit, isFalse);
      expect(result.sumPaise, 30000);
      expect(result.remainingPaise, -2200);
      expect(result.problem, 'Overpaid: ₹22.00');
    });

    test('an empty field is a zero leg, not invalid input', () {
      // Typing only one instrument is a normal thing to do, so a blank must not
      // be rejected as unreadable text. It is still not a submittable split:
      // one instrument is a normal payment, not split tender.
      final result = draft('278', '');
      expect(result.state, SplitDraftState.exact);
      expect(result.cashPaise, 27800);
      expect(result.upiPaise, 0);
      expect(result.legCount, 1);
      expect(result.canSubmit, isFalse);
      expect(result.problem, 'A split needs both Cash and UPI');
    });

    test('both fields empty is short, not invalid', () {
      final result = draft('', '');
      expect(result.state, SplitDraftState.under);
      expect(result.problem, 'Remaining: ₹278.00');
    });

    test('a zero leg is never persisted', () {
      // `sale_payments.amount_paise` has CHECK (> 0); a zero leg would abort
      // the whole sale at the insert.
      final payments = draft('278', '').toPayments();
      expect(payments, hasLength(1));
      expect(payments.single.amountPaise, 27800);
    });

    test('unreadable text is invalid and never submittable', () {
      for (final bad in ['abc', '12.345', '-5', '1,000', '₹200', '2 0']) {
        final result = draft(bad, '78');
        expect(
          result.state,
          SplitDraftState.invalid,
          reason: 'input "$bad" has no safe rupee reading',
        );
        expect(result.canSubmit, isFalse);
        expect(result.toPayments().every((p) => p.amountPaise > 0), isTrue);
      }
    });

    test('an unreadable field blocks even when the other sums correctly', () {
      // Otherwise `200` + `nonsense` would read as exactly ₹200 and commit.
      final result = draft('200', '78.005');
      expect(result.state, SplitDraftState.invalid);
      expect(result.canSubmit, isFalse);
    });

    test('surrounding whitespace is tolerated', () {
      final result = draft('  200  ', ' 78 ');
      expect(result.state, SplitDraftState.exact);
    });

    test('an amount beyond the safe ceiling is invalid, not wrapped', () {
      // Nine integer digits is past the rupee parser's 8-digit range, so it
      // is rejected outright rather than silently truncated into a real
      // (wrong) amount.
      final result = draft('123456789', '1');
      expect(result.state, SplitDraftState.invalid);
      expect(result.cashPaise, 0);
    });

    test('the largest representable rupee amount is read, not rejected', () {
      // ₹99,999,999.99 is exactly Money.maxPaise, so it is a legal reading and
      // must classify as over rather than invalid.
      final result = draft('99999999.99', '0');
      expect(result.state, SplitDraftState.over);
      expect(result.cashPaise, 9999999999);
    });
  });

  group('formatted messages carry exactly one currency symbol', () {
    test('the under/over labels are not doubled', () {
      // The reported `₹₹28.00` / `₹₹22.00`: formatPaise already prefixes ₹
      // and the template added another.
      final under = SplitPaymentDraft.fromRupeeInput(
        cash: '250',
        upi: '0',
        totalPaise: 27800,
      ).problem!;
      final over = SplitPaymentDraft.fromRupeeInput(
        cash: '300',
        upi: '0',
        totalPaise: 27800,
      ).problem!;

      expect(under, 'Remaining: ₹28.00');
      expect(over, 'Overpaid: ₹22.00');
      for (final label in [under, over]) {
        expect(
          '₹₹'.allMatches(label).length,
          0,
          reason: '"$label" shows a doubled currency symbol',
        );
        expect(RegExp('₹').allMatches(label).length, 1);
      }
    });
  });
}
