import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customer_ledger_repository.dart';

void main() {
  late FakeCustomerLedgerRepository ledger;
  late ProviderContainer container;

  final now = DateTime.now().toUtc();

  FakeLedgerBill bill({
    String id = 's1',
    String customerId = 'c1',
    String receiptNumber = 'BF-000001',
    int totalPaise = 12000,
    DateTime? createdAt,
  }) => FakeLedgerBill(
    id: id,
    customerId: customerId,
    receiptNumber: receiptNumber,
    createdAt: createdAt ?? now,
    totalPaise: totalPaise,
  );

  setUp(() {
    ledger = FakeCustomerLedgerRepository();
    container = ProviderContainer(
      overrides: [customerLedgerRepositoryProvider.overrideWithValue(ledger)],
    );
    addTearDown(container.dispose);
  });

  CustomerLedgerController controller(String customerId) =>
      container.read(customerLedgerProvider(customerId).notifier);

  /// Waits (in real async) for invalidation-triggered rebuilds to settle.
  Future<void> awaitUntil(bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not met within the timeout');
  }

  test('loads summary, purchases and payments for one customer', () async {
    ledger.bills
      ..add(bill(id: 's1', totalPaise: 12000))
      ..add(
        bill(
          id: 's2',
          receiptNumber: 'BF-000002',
          totalPaise: 8000,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      )
      ..add(
        bill(
          id: 's3',
          customerId: 'c2',
          receiptNumber: 'BF-000003',
          totalPaise: 5000,
        ),
      );
    ledger.storedPayments.add(
      CustomerPayment(
        id: 'p1',
        customerId: 'c1',
        saleId: 's1',
        amountPaise: 5000,
        paymentMethod: PaymentMethod.upi,
        paidAt: now,
        reversed: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final data = await container.read(customerLedgerProvider('c1').future);

    expect(data.summary.customerId, 'c1');
    expect(data.summary.totalPurchasesPaise, 20000);
    expect(data.summary.totalPaidPaise, 5000);
    expect(data.summary.outstandingPaise, 15000);
    expect(data.summary.purchaseCount, 2);
    expect(data.summary.paymentCount, 1);
    expect(data.purchases.map((p) => p.saleId).toList(), ['s1', 's2']);
    expect(data.purchases.first.duePaise, 7000);
    expect(data.purchases.first.status, SalePaymentStatus.partial);
    expect(data.purchases.last.status, SalePaymentStatus.unpaid);
    expect(data.payments.single.amountPaise, 5000);
  });

  test('a customer without history gets all-zero totals', () async {
    final data = await container.read(customerLedgerProvider('c9').future);

    expect(data.summary.totalPurchasesPaise, 0);
    expect(data.summary.totalPaidPaise, 0);
    expect(data.summary.outstandingPaise, 0);
    expect(data.purchases, isEmpty);
    expect(data.payments, isEmpty);
  });

  test('typed failures pass through untouched', () async {
    expect(
      () => controller('c9').recordPayment(
        saleId: 's1',
        amountPaise: 100,
        paymentMethod: PaymentMethod.cash,
      ),
      throwsA(isA<CustomerNotFoundFailure>()),
    );
  });

  test('unexpected load errors surface as UnexpectedLedgerFailure', () async {
    ledger.recordPaymentError = StateError('boom');

    expect(
      () => controller('c1').recordPayment(
        saleId: 's1',
        amountPaise: 100,
        paymentMethod: PaymentMethod.cash,
      ),
      throwsA(isA<UnexpectedLedgerFailure>()),
    );
  });

  test('recordPayment refreshes the family bundle', () async {
    ledger.bills.add(bill(id: 's1', totalPaise: 12000));
    await container.read(customerLedgerProvider('c1').future);

    await controller('c1').recordPayment(
      saleId: 's1',
      amountPaise: 7000,
      paymentMethod: PaymentMethod.cash,
      note: 'Part payment',
    );

    expect(ledger.storedPayments.single.amountPaise, 7000);
    expect(ledger.storedPayments.single.note, 'Part payment');
    await awaitUntil(() {
      final data = container.read(customerLedgerProvider('c1'));
      return data.value?.summary.outstandingPaise == 5000;
    });
    final refreshed = container.read(customerLedgerProvider('c1'));
    expect(refreshed.value!.summary.totalPaidPaise, 7000);
    expect(refreshed.value!.purchases.single.status, SalePaymentStatus.partial);
  });

  test('a failed payment leaves the bundle unchanged', () async {
    ledger.bills.add(bill(id: 's1', totalPaise: 12000));
    ledger.recordPaymentError = const PaymentExceedsDueFailure();
    await container.read(customerLedgerProvider('c1').future);

    await expectLater(
      controller('c1').recordPayment(
        saleId: 's1',
        amountPaise: 999999,
        paymentMethod: PaymentMethod.upi,
      ),
      throwsA(isA<PaymentExceedsDueFailure>()),
    );

    expect(ledger.storedPayments, isEmpty);
    final data = container.read(customerLedgerProvider('c1'));
    expect(data.value!.summary.outstandingPaise, 12000);
  });

  test('customerLedgerErrorMessage prefers the failure message', () {
    expect(
      customerLedgerErrorMessage(const InvalidPaymentAmountFailure()),
      'Enter an amount greater than zero.',
    );
    expect(
      customerLedgerErrorMessage('junk'),
      'Something went wrong. Please try again.',
    );
    expect(
      customerLedgerErrorMessage('junk', fallback: 'Try again.'),
      'Try again.',
    );
  });
}
