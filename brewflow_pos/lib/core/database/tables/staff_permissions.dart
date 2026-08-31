import 'package:drift/drift.dart';

import 'users.dart';

/// ---------------------------------------------------------------------------
/// StaffPermissions — normalized per-staff capability rows
///
/// One row per (staff profile, permission key). Only STAFF profiles carry
/// rows; the OWNER role implicitly holds every permission and must never be
/// represented here. Enabled=false persists an explicit owner decision so a
/// permission can be switched off and back on without losing the record.
///
/// Permission keys are the stable dbValues of the typed [Permission] enum in
/// lib/core/authorization/authorization.dart.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_staff_permissions_user', columns: {#userId})
class StaffPermissions extends Table {
  /// Owning staff profile ([Users.id]).
  TextColumn get userId => text().references(Users, #id)();

  /// Permission key, e.g. 'BILLING' (stable enum dbValue).
  TextColumn get permission => text()();

  /// Whether the owner granted this capability.
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {userId, permission};
}
