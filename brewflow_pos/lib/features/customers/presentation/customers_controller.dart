import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/customers/data/drift_customers_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customers State (Riverpod)
///
/// Composition:
/// - [customersRepositoryProvider]  → Drift-backed repository (override in
///                                    tests with a fake).
/// - [customersFilterProvider]      → current customer list filter.
/// - [customersProvider]            → customers matching the filter.
///
/// Mutations go through a shared [_mutate] helper: run the repository call,
/// then invalidate the affected state so the UI refreshes. Every failure is
/// translated into a safe [CustomersFailure] (details logged, never shown).
/// ---------------------------------------------------------------------------

/// Owns the single customers repository for the application scope. The
/// outbox coordinator binds customer writes to the durable sync queue
/// atomically (no-op when no session is active).
final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return DriftCustomersRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// Immutable customer list filter state.
final class CustomersFilter {
  const CustomersFilter({
    this.query = '',
    this.status = CustomerStatusFilter.all,
    this.dueOnly = false,
  });

  /// Search text matched against name, phone and email.
  final String query;

  /// Active/inactive restriction.
  final CustomerStatusFilter status;

  /// When true, only customers that currently have an outstanding balance
  /// are listed (the dashboard Due Reminders surface). The due set comes
  /// from the authoritative ledger repository — never recomputed here.
  final bool dueOnly;

  CustomersFilter withQuery(String query) =>
      CustomersFilter(query: query, status: status, dueOnly: dueOnly);

  CustomersFilter withStatus(CustomerStatusFilter status) =>
      CustomersFilter(query: query, status: status, dueOnly: dueOnly);

  CustomersFilter withDueOnly(bool dueOnly) =>
      CustomersFilter(query: query, status: status, dueOnly: dueOnly);
}

/// Holds the current customer list filter; changes rebuild [customersProvider].
final customersFilterProvider =
    NotifierProvider<CustomersFilterController, CustomersFilter>(
      CustomersFilterController.new,
    );

final class CustomersFilterController extends Notifier<CustomersFilter> {
  @override
  CustomersFilter build() => const CustomersFilter();

  void setQuery(String query) => state = state.withQuery(query);

  void setStatus(CustomerStatusFilter status) =>
      state = state.withStatus(status);

  void setDueOnly(bool dueOnly) => state = state.withDueOnly(dueOnly);

  void clear() => state = const CustomersFilter();
}

/// Customers matching the current [customersFilterProvider] state.
final customersProvider =
    AsyncNotifierProvider<CustomersController, List<Customer>>(
      CustomersController.new,
    );

final class CustomersController extends AsyncNotifier<List<Customer>> {
  static const String tag = 'Customers';

  @override
  Future<List<Customer>> build() async {
    final filter = ref.watch(customersFilterProvider);
    final repository = ref.watch(customersRepositoryProvider);
    try {
      var items = await repository.customers(
        search: filter.query,
        status: filter.status,
      );
      if (filter.dueOnly) {
        // Due membership is decided by the ledger's own aggregation; here we
        // only intersect profiles with it (keeps search/status behaviour).
        final ledger = ref.watch(customerLedgerRepositoryProvider);
        final dueIds = await ledger.customerIdsWithDue();
        items = [
          for (final customer in items)
            if (dueIds.contains(customer.id)) customer,
        ];
      }
      return items;
    } on CustomersFailure {
      rethrow;
    } on CustomerLedgerFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load customers',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedCustomersFailure();
    }
  }

  Future<Customer?> byId(String id) async {
    try {
      return await ref.read(customersRepositoryProvider).customerById(id);
    } on CustomersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load customer',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedCustomersFailure();
    }
  }

  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    try {
      return await ref
          .read(customersRepositoryProvider)
          .phoneExists(phone, exceptId: exceptId);
    } on CustomersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to check phone uniqueness',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedCustomersFailure();
    }
  }

  Future<void> create({
    required String name,
    String? phone,
    String? email,
    String? address,
    bool isActive = true,
    bool membershipActive = false,
    int? membershipFeePaise,
    WhatsAppStatus whatsappStatus = WhatsAppStatus.unknown,
  }) => _mutate(
    () => ref
        .read(customersRepositoryProvider)
        .createCustomer(
          name: name,
          phone: phone,
          email: email,
          address: address,
          isActive: isActive,
          membershipActive: membershipActive,
          membershipFeePaise: membershipFeePaise,
          whatsappStatus: whatsappStatus,
        ),
  );

  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    required bool isActive,
    bool membershipActive = false,
    int? membershipFeePaise,
    WhatsAppStatus? whatsappStatus,
  }) => _mutate(
    () => ref
        .read(customersRepositoryProvider)
        .updateCustomer(
          id: id,
          name: name,
          phone: phone,
          email: email,
          address: address,
          isActive: isActive,
          membershipActive: membershipActive,
          membershipFeePaise: membershipFeePaise,
          whatsappStatus: whatsappStatus,
        ),
  );

  Future<void> setActive(String id, bool isActive) => _mutate(
    () => ref.read(customersRepositoryProvider).setCustomerActive(id, isActive),
  );

  Future<CustomerDeleteResult> delete(String id) async {
    requireOwner(ref);
    try {
      final result = await ref
          .read(customersRepositoryProvider)
          .deleteCustomer(id);
      ref.invalidateSelf();
      return result;
    } on CustomersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Customers delete failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedCustomersFailure();
    }
  }

  /// Runs [action] against the repository, then refreshes this controller's
  /// state. [CustomersFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedCustomersFailure].
  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidateSelf();
    } on CustomersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Customers mutation failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedCustomersFailure();
    }
  }
}

/// Maps any thrown object to a user-safe message.
///
/// [CustomersFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String customersErrorMessage(Object error, {String? fallback}) {
  if (error is CustomersFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
