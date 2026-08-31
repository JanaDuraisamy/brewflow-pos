import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Users — local staff/owner profiles
///
/// One row per person operating the POS. Since v12 this is the authoritative
/// local profile store for the Supabase-authenticated identity:
/// - [authUserId] links the row to the Supabase auth user (unique when set).
/// - [shopId] scopes the profile to the (single) local shop.
/// - [role] is 'OWNER' or 'STAFF' (typed in
///   lib/core/authorization/authorization.dart); the first authenticated user
///   claims OWNER exactly once, later users are STAFF created by the owner.
///
/// Credentials, sessions and tokens are NEVER stored here. Sessions live in
/// secure storage; credentials stay with the auth provider.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_users_updated_at', columns: {#updatedAt})
class Users extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Unique login email; identity for auth linking.
  TextColumn get email => text().unique()();

  /// Supabase auth user id; unique when present. Null for legacy rows that
  /// predate the auth integration and were never linked.
  TextColumn get authUserId => text().nullable().unique()();

  /// Owning shop ([Shops.id]); null only for legacy rows awaiting linkage.
  TextColumn get shopId => text().nullable().references(Shops, #id)();

  /// Display name shown in the POS UI.
  TextColumn get displayName => text().nullable()();

  /// Access role: 'OWNER' or 'STAFF'. Null until a profile is provisioned.
  TextColumn get role => text().nullable()();

  /// Soft switch to block sign-in without deleting the record.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
