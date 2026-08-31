/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Domain Models
///
/// [UserProfile] is the authoritative local profile for a Supabase-
/// authenticated user: role, shop scope, activation state and, for staff,
/// the granted permission set. Persistence lives in Drift (users /
/// staff_permissions / shops); Supabase holds only identity.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/core/authorization/authorization.dart';

final class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    required this.permissions,
    this.authUserId,
    this.shopId,
    this.displayName,
  });

  final String id;
  final String email;

  /// Supabase auth user id; null only for legacy unlinked rows.
  final String? authUserId;
  final String? shopId;
  final String? displayName;
  final UserRole role;
  final bool isActive;

  /// Granted capabilities; meaningful for STAFF only (OWNER is implicit-all).
  final Set<Permission> permissions;

  bool get isOwner => role == UserRole.owner;
}

/// A shop row (currently exactly one, created at owner bootstrap).
final class Shop {
  const Shop({required this.id, required this.name});

  final String id;
  final String name;
}

/// Input for creating a staff member: identity comes from the secure
/// provisioning boundary, permissions from the owner's editor.
final class StaffCreateInput {
  const StaffCreateInput({
    required this.email,
    required this.password,
    this.displayName,
    this.permissions = defaultStaffPermissions,
  });

  final String email;
  final String password;
  final String? displayName;
  final Set<Permission> permissions;
}

/// A STAFF profile update performed by the owner.
final class StaffUpdateInput {
  const StaffUpdateInput({
    required this.id,
    this.displayName,
    this.isActive,
    this.permissions,
  });

  final String id;
  final String? displayName;
  final bool? isActive;
  final Set<Permission>? permissions;
}

/// Base for all staff/authorization failures; every subtype carries a
/// user-safe message.
sealed class StaffFailure implements Exception {
  const StaffFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The signed-in user has no provisioned profile for this shop (or their
/// profile is inactive) — access is denied until the owner provisions them.
final class ProfileNotProvisionedFailure extends StaffFailure {
  const ProfileNotProvisionedFailure()
    : super('This account has not been given access to the shop yet.');

  /// The account exists but was deactivated by the owner.
  const ProfileNotProvisionedFailure.inactive()
    : super('This account has been deactivated by the owner.');
}

/// The one-time owner claim was already taken by another account.
final class OwnerAlreadyClaimedFailure extends StaffFailure {
  const OwnerAlreadyClaimedFailure()
    : super('The shop already has an owner. Ask them to add you as staff.');
}

/// Staff provisioning via the server boundary failed (network/validation).
final class ProvisioningFailure extends StaffFailure {
  const ProvisioningFailure([
    super.message = 'Could not create the staff account. Please try again.',
  ]);
}

/// Duplicate email among profiles.
final class DuplicateStaffEmailFailure extends StaffFailure {
  const DuplicateStaffEmailFailure()
    : super('A staff member with this email already exists.');
}
