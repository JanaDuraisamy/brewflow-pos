/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customers Domain Models
///
/// Immutable business models used by controllers and UI. Persistence details
/// (Drift rows) never leak past the repository boundary.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';

final class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    required this.isActive,
    this.membershipActive = false,
    this.membershipFeePaise,
    this.whatsappStatus = WhatsAppStatus.unknown,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Optional phone number; unique when present (case-insensitive). This is
  /// the canonical contact number — WhatsApp state is separate metadata.
  final String? phone;

  /// Optional email address; not unique.
  final String? email;

  /// Optional billing/delivery address.
  final String? address;
  final bool isActive;

  /// Membership enrolment. When active — and membership pricing is enabled
  /// globally (see [ShopSettings.membershipEnabled]) — the counter charges
  /// this customer the configured member price of membership-enabled
  /// products/variants. Deactivation of the customer ends the benefit; the
  /// enrolment flag itself is never auto-cleared.
  final bool membershipActive;

  /// Membership fee snapshot in integer paise (e.g. 5000 = ₹50); optional and
  /// informational. It never influences charged prices by itself.
  final int? membershipFeePaise;

  /// Honest WhatsApp reachability reported by a real verification provider;
  /// never inferred from phone formatting. Starts at [WhatsAppStatus.unknown]
  /// and only a provider can move it to verified/not-verified.
  final WhatsAppStatus whatsappStatus;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const Object _unset = Object();

  Customer copyWith({
    String? name,
    Object? phone = _unset,
    Object? email = _unset,
    Object? address = _unset,
    bool? isActive,
    bool? membershipActive,
    Object? membershipFeePaise = _unset,
    WhatsAppStatus? whatsappStatus,
    DateTime? updatedAt,
  }) => Customer(
    id: id,
    name: name ?? this.name,
    phone: identical(phone, _unset) ? this.phone : phone as String?,
    email: identical(email, _unset) ? this.email : email as String?,
    address: identical(address, _unset) ? this.address : address as String?,
    isActive: isActive ?? this.isActive,
    membershipActive: membershipActive ?? this.membershipActive,
    membershipFeePaise: identical(membershipFeePaise, _unset)
        ? this.membershipFeePaise
        : membershipFeePaise as int?,
    whatsappStatus: whatsappStatus ?? this.whatsappStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
