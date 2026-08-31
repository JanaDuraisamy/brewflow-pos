import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../sync/presentation/sync_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Ledger State (Riverpod)
///
/// Composition:
/// - [customerLedgerRepositoryProvider] → Drift-backed repository (override in
///                                        tests with a fake).
/// - [customerLedgerProvider]            → per-customer financial bundle
///                                        (summary + purchases + payments).
///
/// Mutations go through [recordPayment] and refresh the watching family
/// member so the detail page always shows fresh totals. Every failure is
/// translated into a safe [CustomerLedgerFailure] (details logged, never
/// shown).
/// ---------------------------------------------------------------------------

/// Owns the single customer-ledger repository for the application scope.
final customerLedgerRepositoryProvider = Provider<CustomerLedgerRepository>((
  ref,
) {
  return DriftCustomerLedgerRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// One customer's financial view: summary totals plus both histories, loaded
/// together so the page renders a consistent snapshot.
final class CustomerLedgerData {
  const CustomerLedgerData({
    required this.summary,
    required this.purchases,
    required this.payments,
  });

  final CustomerLedgerSummary summary;
  final List<CustomerPurchase> purchases;
  final List<CustomerPayment> payments;
}

/// Summary + histories for one customer; rebuilds after [recordPayment].
final customerLedgerProvider =
    AsyncNotifierProvider.family<
      CustomerLedgerController,
      CustomerLedgerData,
      String
    >(CustomerLedgerController.new);

final class CustomerLedgerController extends AsyncNotifier<CustomerLedgerData> {
  /// The customer whose ledger this controller holds; injected by the family
  /// provider (Riverpod 3 passes the family argument to the constructor).
  CustomerLedgerController(this.customerId);

  final String customerId;

  static const String tag = 'Ledger';

  @override
  Future<CustomerLedgerData> build() async {
    final repository = ref.watch(customerLedgerRepositoryProvider);
    try {
      final summary = await repository.summary(customerId);
      final purchases = await repository.purchases(customerId);
      final payments = await repository.payments(customerId);
      return CustomerLedgerData(
        summary: summary,
        purchases: purchases,
        payments: payments,
      );
    } on CustomerLedgerFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load customer ledger',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedLedgerFailure();
    }
  }

  /// Records a payment against [saleId] and refreshes this customer's
  /// bundle. [CustomerLedgerFailure]s pass through untouched; anything
  /// unexpected is logged and rethrown as [UnexpectedLedgerFailure].
  Future<CustomerPayment> recordPayment({
    required String saleId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    try {
      final payment = await ref
          .read(customerLedgerRepositoryProvider)
          .recordPayment(
            customerId: customerId,
            saleId: saleId,
            amountPaise: amountPaise,
            paymentMethod: paymentMethod,
            note: note,
          );
      ref.invalidateSelf();
      // A settled bill flips sales.payment_status → PAID; every derived
      // read model (orders list/detail, dashboard, reports) must re-read
      // the authoritative row instead of serving the stale unpaid state.
      ref.invalidate(ordersListProvider);
      ref.invalidate(orderDetailProvider);
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
      return payment;
    } on CustomerLedgerFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to record customer payment',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedLedgerFailure();
    }
  }
}

/// Maps any thrown object to a user-safe message.
///
/// [CustomerLedgerFailure]s already carry display-ready text; anything else
/// falls back to a generic message (with [fallback] when provided).
String customerLedgerErrorMessage(Object error, {String? fallback}) {
  if (error is CustomerLedgerFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
