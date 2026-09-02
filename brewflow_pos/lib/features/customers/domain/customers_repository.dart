/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customers Repository Contract
///
/// The single boundary between customers state/UI and the local Drift
/// database. Failures are always safe-to-display [CustomersFailure] values;
/// database details are never exposed to callers.
///
/// Scope: customer profiles only (name + optional contact details + soft
/// activity). Due/credit management and per-customer order history are future
/// modules and intentionally out of scope here.
/// ---------------------------------------------------------------------------
library;

import 'customers_models.dart';
import 'whatsapp_verification.dart';

enum CustomerStatusFilter { all, active, inactive }

/// Base for all customers failures. Every subtype carries a user-safe message.
sealed class CustomersFailure implements Exception {
  const CustomersFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DuplicatePhoneFailure extends CustomersFailure {
  const DuplicatePhoneFailure()
    : super('A customer with this phone number already exists.');
}

final class UnexpectedCustomersFailure extends CustomersFailure {
  const UnexpectedCustomersFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first customer profile persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class CustomersRepository {
  /// Customers filtered and sorted by name in SQL.
  ///
  /// [search] matches name, phone or email (case-insensitive substring).
  /// [status] restricts to active/inactive customers (default: all).
  Future<List<Customer>> customers({
    String? search,
    CustomerStatusFilter status,
  });

  Future<Customer?> customerById(String id);

  /// Whether another customer already uses this phone number
  /// (case-insensitive). [exceptId] excludes one customer so an edit can
  /// keep its own phone.
  Future<bool> phoneExists(String phone, {String? exceptId});

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    bool isActive,
    bool membershipActive,
    int? membershipFeePaise,
    WhatsAppStatus whatsappStatus,
    String? shopId,
  });

  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    required bool isActive,
    bool membershipActive,
    int? membershipFeePaise,
    WhatsAppStatus? whatsappStatus,
  });

  /// Soft switch to hide a customer without deleting their records. The only
  /// removal path; customers are never hard-deleted.
  Future<void> setCustomerActive(String id, bool isActive);

  /// Removes a customer. When the customer has no sales or payment history it
  /// is hard-deleted (and its sync tombstone pushed so other devices learn
  /// it); when history exists, deletion degrades to a safe soft deactivation
  /// and [CustomerDeleteResult.deactivated] is returned.
  Future<CustomerDeleteResult> deleteCustomer(String id);
}

/// Outcome of a [CustomersRepository.deleteCustomer] call.
enum CustomerDeleteResult { deleted, deactivated }
