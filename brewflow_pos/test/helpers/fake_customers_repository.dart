import 'dart:async';

import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';

/// In-memory [CustomersRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// case-insensitive phone uniqueness, blank-optional normalization (empty
/// inputs never store a value), SQL-like search/filtering and safe failures.
/// Probe hooks ([loadError], [loadGate]) drive loading and error states.
final class FakeCustomersRepository implements CustomersRepository {
  final List<Customer> storedCustomers = [];

  /// When set, every load and mutation throws this error instead of running.
  Object? loadError;

  /// When set, customers loads wait for this (loading-state tests).
  Completer<void>? loadGate;

  /// Number of [customers] calls.
  int customersCalls = 0;

  /// Customer ids that have sales/payment history (so delete degrades to
  /// deactivation). Tests can populate this to exercise the safe path.
  final Set<String> customersWithHistory = {};

  @override
  Future<CustomerDeleteResult> deleteCustomer(String id) async {
    _throwIfLoadError();
    final existing = storedCustomers.firstWhere(
      (customer) => customer.id == id,
      orElse: () => throw const UnexpectedCustomersFailure(),
    );
    if (customersWithHistory.contains(id)) {
      _replaceCustomer(
        existing.copyWith(isActive: false, updatedAt: DateTime.now().toUtc()),
      );
      return CustomerDeleteResult.deactivated;
    }
    storedCustomers.removeWhere((customer) => customer.id == id);
    return CustomerDeleteResult.deleted;
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
  Future<List<Customer>> customers({
    String? search,
    CustomerStatusFilter status = CustomerStatusFilter.all,
  }) async {
    customersCalls += 1;
    await _gate();
    _throwIfLoadError();
    var result = List<Customer>.of(storedCustomers);
    final query = search?.trim() ?? '';
    if (query.isNotEmpty) {
      final lower = query.toLowerCase();
      result = result
          .where(
            (customer) =>
                customer.name.toLowerCase().contains(lower) ||
                (customer.phone?.toLowerCase().contains(lower) ?? false) ||
                (customer.email?.toLowerCase().contains(lower) ?? false),
          )
          .toList();
    }
    result = switch (status) {
      CustomerStatusFilter.all => result,
      CustomerStatusFilter.active =>
        result.where((customer) => customer.isActive).toList(),
      CustomerStatusFilter.inactive =>
        result.where((customer) => !customer.isActive).toList(),
    };
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  @override
  Future<Customer?> customerById(String id) async {
    _throwIfLoadError();
    for (final customer in storedCustomers) {
      if (customer.id == id) {
        return customer;
      }
    }
    return null;
  }

  @override
  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    return storedCustomers.any(
      (customer) =>
          customer.phone != null &&
          customer.phone!.toLowerCase() == phone.trim().toLowerCase() &&
          customer.id != exceptId,
    );
  }

  @override
  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    bool isActive = true,
    bool membershipActive = false,
    int? membershipFeePaise,
    WhatsAppStatus whatsappStatus = WhatsAppStatus.unknown,
    String? shopId,
  }) async {
    _throwIfLoadError();
    final normalizedName = _requiredText(name, 'Customer name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    if (normalizedPhone != null &&
        storedCustomers.any(
          (customer) =>
              customer.phone != null &&
              customer.phone!.toLowerCase() == normalizedPhone.toLowerCase(),
        )) {
      throw const DuplicatePhoneFailure();
    }
    final now = DateTime.now().toUtc();
    final customer = Customer(
      id: 'customer-${storedCustomers.length + 1}',
      name: normalizedName,
      phone: normalizedPhone,
      email: normalizedEmail,
      address: normalizedAddress,
      isActive: isActive,
      membershipActive: membershipActive,
      membershipFeePaise: membershipFeePaise,
      whatsappStatus: whatsappStatus,
      createdAt: now,
      updatedAt: now,
    );
    storedCustomers.add(customer);
    return customer;
  }

  @override
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
  }) async {
    _throwIfLoadError();
    final normalizedName = _requiredText(name, 'Customer name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    if (normalizedPhone != null &&
        storedCustomers.any(
          (customer) =>
              customer.phone != null &&
              customer.phone!.toLowerCase() == normalizedPhone.toLowerCase() &&
              customer.id != id,
        )) {
      throw const DuplicatePhoneFailure();
    }
    final existing = storedCustomers.firstWhere(
      (customer) => customer.id == id,
      orElse: () => throw const UnexpectedCustomersFailure(),
    );
    _replaceCustomer(
      existing.copyWith(
        name: normalizedName,
        phone: normalizedPhone,
        email: normalizedEmail,
        address: normalizedAddress,
        isActive: isActive,
        membershipActive: membershipActive,
        membershipFeePaise: membershipFeePaise,
        whatsappStatus: whatsappStatus ?? existing.whatsappStatus,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> setCustomerActive(String id, bool isActive) async {
    _throwIfLoadError();
    final existing = storedCustomers.firstWhere(
      (customer) => customer.id == id,
      orElse: () => throw const UnexpectedCustomersFailure(),
    );
    _replaceCustomer(
      existing.copyWith(isActive: isActive, updatedAt: DateTime.now().toUtc()),
    );
  }

  void _replaceCustomer(Customer customer) {
    final index = storedCustomers.indexWhere((c) => c.id == customer.id);
    if (index == -1) {
      throw const UnexpectedCustomersFailure();
    }
    storedCustomers[index] = customer;
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _requiredText(String value, String message) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw UnexpectedCustomersFailure(message);
    }
    return normalized;
  }
}
