import 'dart:async';

import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';

/// In-memory [SuppliersRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// case-insensitive phone uniqueness, blank-optional normalization (empty
/// inputs never store a value), SQL-like search/filtering and safe failures.
/// Probe hooks ([loadError], [loadGate]) drive loading and error states.
final class FakeSuppliersRepository implements SuppliersRepository {
  final List<Supplier> storedSuppliers = [];

  /// When set, every load and mutation throws this error instead of running.
  Object? loadError;

  /// When set, suppliers loads wait for this (loading-state tests).
  Completer<void>? loadGate;

  /// Number of [suppliers] calls.
  int suppliersCalls = 0;

  /// Supplier ids that have purchase history (so delete degrades to
  /// deactivation). Tests can populate this to exercise the safe path.
  final Set<String> suppliersWithPurchases = {};

  @override
  Future<SupplierDeleteResult> deleteSupplier(String id) async {
    _throwIfLoadError();
    final existing = storedSuppliers.firstWhere(
      (supplier) => supplier.id == id,
      orElse: () => throw const UnexpectedSuppliersFailure(),
    );
    if (suppliersWithPurchases.contains(id)) {
      _replaceSupplier(
        existing.copyWith(isActive: false, updatedAt: DateTime.now().toUtc()),
      );
      return SupplierDeleteResult.deactivated;
    }
    storedSuppliers.removeWhere((supplier) => supplier.id == id);
    return SupplierDeleteResult.deleted;
  }

  Future<void> _gate() async {
    final gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
  }

  void _throwIfLoadError() {
    final error = loadError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<List<Supplier>> suppliers({
    String? search,
    SupplierStatusFilter status = SupplierStatusFilter.all,
  }) async {
    suppliersCalls += 1;
    await _gate();
    _throwIfLoadError();
    var result = List<Supplier>.of(storedSuppliers);
    final query = search?.trim() ?? '';
    if (query.isNotEmpty) {
      final lower = query.toLowerCase();
      result = result
          .where(
            (supplier) =>
                supplier.name.toLowerCase().contains(lower) ||
                (supplier.phone?.toLowerCase().contains(lower) ?? false) ||
                (supplier.email?.toLowerCase().contains(lower) ?? false),
          )
          .toList();
    }
    result = switch (status) {
      SupplierStatusFilter.all => result,
      SupplierStatusFilter.active =>
        result.where((supplier) => supplier.isActive).toList(),
      SupplierStatusFilter.inactive =>
        result.where((supplier) => !supplier.isActive).toList(),
    };
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  @override
  Future<Supplier?> supplierById(String id) async {
    _throwIfLoadError();
    for (final supplier in storedSuppliers) {
      if (supplier.id == id) {
        return supplier;
      }
    }
    return null;
  }

  @override
  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    return storedSuppliers.any(
      (supplier) =>
          supplier.phone != null &&
          supplier.phone!.toLowerCase() == phone.trim().toLowerCase() &&
          supplier.id != exceptId,
    );
  }

  @override
  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool isActive = true,
  }) async {
    _throwIfLoadError();
    final normalizedName = _requiredText(name, 'Supplier name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    final normalizedNotes = _optionalText(notes);
    if (normalizedPhone != null &&
        storedSuppliers.any(
          (supplier) =>
              supplier.phone != null &&
              supplier.phone!.toLowerCase() == normalizedPhone.toLowerCase(),
        )) {
      throw const DuplicateSupplierPhoneFailure();
    }
    final now = DateTime.now().toUtc();
    final supplier = Supplier(
      id: 'supplier-${storedSuppliers.length + 1}',
      name: normalizedName,
      phone: normalizedPhone,
      email: normalizedEmail,
      address: normalizedAddress,
      notes: normalizedNotes,
      isActive: isActive,
      createdAt: now,
      updatedAt: now,
    );
    storedSuppliers.add(supplier);
    return supplier;
  }

  @override
  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required bool isActive,
  }) async {
    _throwIfLoadError();
    final normalizedName = _requiredText(name, 'Supplier name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    final normalizedNotes = _optionalText(notes);
    if (normalizedPhone != null &&
        storedSuppliers.any(
          (supplier) =>
              supplier.phone != null &&
              supplier.phone!.toLowerCase() == normalizedPhone.toLowerCase() &&
              supplier.id != id,
        )) {
      throw const DuplicateSupplierPhoneFailure();
    }
    final existing = storedSuppliers.firstWhere(
      (supplier) => supplier.id == id,
      orElse: () => throw const UnexpectedSuppliersFailure(),
    );
    _replaceSupplier(
      existing.copyWith(
        name: normalizedName,
        phone: normalizedPhone,
        email: normalizedEmail,
        address: normalizedAddress,
        notes: normalizedNotes,
        isActive: isActive,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> setSupplierActive(String id, bool isActive) async {
    _throwIfLoadError();
    final existing = storedSuppliers.firstWhere(
      (supplier) => supplier.id == id,
      orElse: () => throw const UnexpectedSuppliersFailure(),
    );
    _replaceSupplier(
      existing.copyWith(isActive: isActive, updatedAt: DateTime.now().toUtc()),
    );
  }

  void _replaceSupplier(Supplier supplier) {
    final index = storedSuppliers.indexWhere((s) => s.id == supplier.id);
    if (index == -1) {
      throw const UnexpectedSuppliersFailure();
    }
    storedSuppliers[index] = supplier;
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _requiredText(String value, String message) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw UnexpectedSuppliersFailure(message);
    }
    return normalized;
  }
}
