/// ---------------------------------------------------------------------------
/// BrewFlow POS — Suppliers Repository Contract
///
/// The single boundary between supplier state/UI and the local Drift
/// database. Failures are always safe-to-display [SuppliersFailure] values;
/// database details are never exposed to callers.
///
/// Scope: supplier profiles only (name + optional contact details + soft
/// activity). Per-supplier purchase history is exposed through the
/// [PurchaseRepository]; the receiving transaction is Phase 10 Step 5.
/// ---------------------------------------------------------------------------
library;

import 'purchases_models.dart';

enum SupplierStatusFilter { all, active, inactive }

/// Base for all suppliers failures. Every subtype carries a user-safe message.
sealed class SuppliersFailure implements Exception {
  const SuppliersFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DuplicateSupplierPhoneFailure extends SuppliersFailure {
  const DuplicateSupplierPhoneFailure()
    : super('A supplier with this phone number already exists.');
}

final class UnexpectedSuppliersFailure extends SuppliersFailure {
  const UnexpectedSuppliersFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first supplier profile persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class SuppliersRepository {
  /// Suppliers filtered and sorted by name in SQL.
  ///
  /// [search] matches name, phone or email (case-insensitive substring).
  /// [status] restricts to active/inactive suppliers (default: all).
  Future<List<Supplier>> suppliers({
    String? search,
    SupplierStatusFilter status,
  });

  Future<Supplier?> supplierById(String id);

  /// Whether another supplier already uses this phone number
  /// (case-insensitive). [exceptId] excludes one supplier so an edit can
  /// keep its own phone.
  Future<bool> phoneExists(String phone, {String? exceptId});

  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool isActive,
  });

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required bool isActive,
  });

  /// Soft switch to hide a supplier without deleting their records. The only
  /// removal path; suppliers are never hard-deleted.
  Future<void> setSupplierActive(String id, bool isActive);

  /// Removes a supplier. When the supplier has no purchase history it is
  /// hard-deleted (and its sync tombstone pushed so other devices learn it);
  /// when purchases still reference it, deletion degrades to a safe soft
  /// deactivation and [SupplierDeleteResult.deactivated] is returned.
  Future<SupplierDeleteResult> deleteSupplier(String id);
}

/// Outcome of a [SuppliersRepository.deleteSupplier] call.
enum SupplierDeleteResult { deleted, deactivated }
