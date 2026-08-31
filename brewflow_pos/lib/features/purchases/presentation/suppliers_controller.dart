import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/purchases/data/drift_suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Suppliers State (Riverpod)
///
/// Composition:
/// - [suppliersRepositoryProvider] → Drift-backed repository (override in
///                                    tests with a fake).
/// - [suppliersFilterProvider]     → current supplier list filter.
/// - [suppliersProvider]           → suppliers matching the filter.
///
/// Mutations go through a shared [_mutate] helper: run the repository call,
/// then invalidate the affected state so the UI refreshes. Every failure is
/// translated into a safe [SuppliersFailure] (details logged, never shown).
/// ---------------------------------------------------------------------------

/// Owns the single suppliers repository for the application scope. The
/// outbox coordinator binds supplier writes to the durable sync queue
/// atomically (no-op when no session is active).
final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  return DriftSuppliersRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// Immutable supplier list filter state.
final class SuppliersFilter {
  const SuppliersFilter({
    this.query = '',
    this.status = SupplierStatusFilter.all,
  });

  /// Search text matched against name, phone and email.
  final String query;

  /// Active/inactive restriction.
  final SupplierStatusFilter status;

  SuppliersFilter withQuery(String query) =>
      SuppliersFilter(query: query, status: status);

  SuppliersFilter withStatus(SupplierStatusFilter status) =>
      SuppliersFilter(query: query, status: status);
}

/// Holds the current supplier list filter; changes rebuild [suppliersProvider].
final suppliersFilterProvider =
    NotifierProvider<SuppliersFilterController, SuppliersFilter>(
      SuppliersFilterController.new,
    );

final class SuppliersFilterController extends Notifier<SuppliersFilter> {
  @override
  SuppliersFilter build() => const SuppliersFilter();

  void setQuery(String query) => state = state.withQuery(query);

  void setStatus(SupplierStatusFilter status) =>
      state = state.withStatus(status);

  void clear() => state = const SuppliersFilter();
}

/// Suppliers matching the current [suppliersFilterProvider] state.
final suppliersProvider =
    AsyncNotifierProvider<SuppliersController, List<Supplier>>(
      SuppliersController.new,
    );

final class SuppliersController extends AsyncNotifier<List<Supplier>> {
  static const String tag = 'Suppliers';

  @override
  Future<List<Supplier>> build() async {
    final filter = ref.watch(suppliersFilterProvider);
    final repository = ref.watch(suppliersRepositoryProvider);
    try {
      return await repository.suppliers(
        search: filter.query,
        status: filter.status,
      );
    } on SuppliersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load suppliers',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSuppliersFailure();
    }
  }

  Future<Supplier?> byId(String id) async {
    try {
      return await ref.read(suppliersRepositoryProvider).supplierById(id);
    } on SuppliersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load supplier',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSuppliersFailure();
    }
  }

  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    try {
      return await ref
          .read(suppliersRepositoryProvider)
          .phoneExists(phone, exceptId: exceptId);
    } on SuppliersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to check phone uniqueness',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSuppliersFailure();
    }
  }

  Future<void> create({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool isActive = true,
  }) {
    requirePermission(ref, Permission.suppliers);
    return _mutate(
      () => ref
          .read(suppliersRepositoryProvider)
          .createSupplier(
            name: name,
            phone: phone,
            email: email,
            address: address,
            notes: notes,
            isActive: isActive,
          ),
    );
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required bool isActive,
  }) {
    requirePermission(ref, Permission.suppliers);
    return _mutate(
      () => ref
          .read(suppliersRepositoryProvider)
          .updateSupplier(
            id: id,
            name: name,
            phone: phone,
            email: email,
            address: address,
            notes: notes,
            isActive: isActive,
          ),
    );
  }

  Future<void> setActive(String id, bool isActive) {
    requirePermission(ref, Permission.suppliers);
    return _mutate(
      () =>
          ref.read(suppliersRepositoryProvider).setSupplierActive(id, isActive),
    );
  }

  Future<SupplierDeleteResult> delete(String id) async {
    requireOwner(ref);
    try {
      final result = await ref
          .read(suppliersRepositoryProvider)
          .deleteSupplier(id);
      ref.invalidateSelf();
      return result;
    } on SuppliersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Suppliers delete failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSuppliersFailure();
    }
  }

  /// Runs [action] against the repository, then refreshes this controller's
  /// state. [SuppliersFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedSuppliersFailure].
  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidateSelf();
    } on SuppliersFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Suppliers mutation failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSuppliersFailure();
    }
  }
}

/// Maps any thrown object to a user-safe message.
///
/// [SuppliersFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String suppliersErrorMessage(Object error, {String? fallback}) {
  if (error is SuppliersFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
