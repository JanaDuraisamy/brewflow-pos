import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_repository.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Staff Repository
///
/// Implements [StaffRepository] on the local Drift database. Owner bootstrap
/// is transactional (one shop, one owner — race-safe through a conditional
/// insert); permission writes replace the staff member's rows atomically.
/// OWNER profiles are never modified through the staff paths below.
/// ---------------------------------------------------------------------------

final class DriftStaffRepository implements StaffRepository {
  DriftStaffRepository(this._database);

  final db.AppDatabase _database;

  @override
  Future<UserProfile?> profileForAuthUser(String authUserId) async {
    final row = await (_database.select(
      _database.users,
    )..where((t) => t.authUserId.equals(authUserId))).getSingleOrNull();
    if (row == null) return null;
    return _profileFromRow(row);
  }

  @override
  Future<UserProfile> claimOwnership(AuthUser user) {
    return _database.transaction(() async {
      // One-time claim: an existing OWNER anywhere in this database blocks it.
      final existingOwner = await (_database.select(
        _database.users,
      )..where((t) => t.role.equals('OWNER'))).get();
      if (existingOwner.isNotEmpty) {
        throw const OwnerAlreadyClaimedFailure();
      }
      final shop = await ensureShop();
      final now = DateTime.now().toUtc();
      final id = await _insertProfile(
        email: user.email,
        authUserId: user.id,
        shopId: shop.id,
        role: UserRole.owner,
        displayName: null,
        isActive: true,
        createdAt: now,
      );
      return UserProfile(
        id: id,
        email: user.email,
        authUserId: user.id,
        shopId: shop.id,
        role: UserRole.owner,
        isActive: true,
        permissions: const {},
      );
    });
  }

  @override
  Future<UserProfile> claimOwnershipForCloud(
    AuthUser user, {
    required String shopId,
  }) async {
    // Idempotent: if a profile already exists for this auth user, return it.
    final existing = await profileForAuthUser(user.id);
    if (existing != null) return existing;

    return _database.transaction(() async {
      final now = DateTime.now().toUtc();
      final id = await _insertProfile(
        email: user.email,
        authUserId: user.id,
        shopId: shopId,
        role: UserRole.owner,
        displayName: null,
        isActive: true,
        createdAt: now,
      );
      return UserProfile(
        id: id,
        email: user.email,
        authUserId: user.id,
        shopId: shopId,
        role: UserRole.owner,
        isActive: true,
        permissions: const {},
      );
    });
  }

  @override
  Future<List<UserProfile>> staffMembers({String? shopId}) async {
    final query = _database.select(_database.users)..where((t) => t.role.equals('STAFF'));
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    final rows = await query.get();
    final profiles = <UserProfile>[];
    for (final row in rows) {
      profiles.add(await _profileFromRow(row));
    }
    profiles.sort(
      (a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase()),
    );
    return profiles;
  }

@override
  Future<UserProfile> createStaffProfile({
    required AuthUser identity,
    required String shopId,
    Set<Permission> permissions = defaultStaffPermissions,
    String? displayName,
  }) async {
    final emailTaken =
        await (_database.select(_database.users)..where(
              (t) =>
                  t.email.lower().equals(identity.email.toLowerCase()) &
                  t.shopId.equals(shopId),
            ))
            .getSingleOrNull();
    if (emailTaken != null) {
      throw const DuplicateStaffEmailFailure();
    }
    final id = await _insertProfile(
      email: identity.email,
      authUserId: identity.id,
      shopId: shopId,
      role: UserRole.staff,
      displayName: displayName,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    );
    await setPermissions(id, permissions);
    return UserProfile(
      id: id,
      email: identity.email,
      authUserId: identity.id,
      shopId: shopId,
      displayName: displayName,
      role: UserRole.staff,
      isActive: true,
      permissions: permissions,
    );
  }

  @override
  Future<void> updateStaff(StaffUpdateInput input) async {
    await _database.transaction(() async {
      final row = await (_database.select(
        _database.users,
      )..where((t) => t.id.equals(input.id))).getSingleOrNull();
      if (row == null || row.role != 'STAFF') {
        // Unknown ids and OWNER profiles are untouchable from staff paths.
        throw const ProfileNotProvisionedFailure();
      }
      await (_database.update(
        _database.users,
      )..where((t) => t.id.equals(input.id))).write(
        db.UsersCompanion(
          displayName: input.displayName != null
              ? Value(input.displayName)
              : const Value.absent(),
          isActive: input.isActive != null
              ? Value(input.isActive!)
              : const Value.absent(),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      if (input.permissions != null) {
        await setPermissions(input.id, input.permissions!);
      }
    });
  }

  @override
  Future<void> setPermissions(String userId, Set<Permission> permissions) {
    return _database.transaction(() async {
      await (_database.delete(
        _database.staffPermissions,
      )..where((t) => t.userId.equals(userId))).go();
      for (final permission in Permission.values) {
        await _database
            .into(_database.staffPermissions)
            .insert(
              db.StaffPermissionsCompanion.insert(
                userId: userId,
                permission: permission.dbValue,
                enabled: Value(permissions.contains(permission)),
              ),
            );
      }
    });
  }

  @override
  Future<Shop> ensureShop({String name = 'My Shop'}) async {
    final existing = await _database.select(_database.shops).get();
    if (existing.isNotEmpty) {
      final row = existing.first;
      return Shop(id: row.id, name: row.name);
    }
    final id = const Uuid().v4();
    await _database
        .into(_database.shops)
        .insert(db.ShopsCompanion.insert(id: Value(id), name: name));
    return Shop(id: id, name: name);
  }

  @override
  Future<Shop> ensureShopWithId(String id, {String name = 'My Shop'}) async {
    final existing = await (_database.select(
      _database.shops,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing != null) {
      return Shop(id: existing.id, name: existing.name);
    }
    await _database
        .into(_database.shops)
        .insert(db.ShopsCompanion.insert(id: Value(id), name: name));
    return Shop(id: id, name: name);
  }

  /// Migrates all local shop_id references from [oldShopId] to [newShopId].
  /// Called when a second device resolves to the cloud's authoritative shop.
  /// Only touches tables that carry a shopId column.
  ///
  /// The authoritative [newShopId] shop row is created locally FIRST so the
  /// foreign-key from `users`/`devices` stays valid while references are
  /// repointed. (SQLite ignores `PRAGMA foreign_keys` inside a transaction, so
  /// we cannot toggle enforcement here — inserting the target row is the
  /// correct way to keep the constraint satisfied.)
  @override
  Future<void> migrateLocalShopId(
    String oldShopId,
    String newShopId, [
    String? newShopName,
  ]) async {
    if (oldShopId == newShopId) return;
    await _database.transaction(() async {
      // 1. Ensure the authoritative shop row exists locally (FK target).
      await _database
          .into(_database.shops)
          .insertOnConflictUpdate(
            db.ShopsCompanion.insert(
              id: Value(newShopId),
              name: newShopName ?? 'My Shop',
            ),
          );

      // 2. Update identity tables (have shopId FK to shops).
      await _database.customUpdate(
        'UPDATE users SET shop_id = ? WHERE shop_id = ?',
        variables: [
          Variable.withString(newShopId),
          Variable.withString(oldShopId),
        ],
      );
      await _database.customUpdate(
        'UPDATE devices SET shop_id = ? WHERE shop_id = ?',
        variables: [
          Variable.withString(newShopId),
          Variable.withString(oldShopId),
        ],
      );

      // 3. Update sync infrastructure (shopId is plain text, no FK).
      await _database.customUpdate(
        'UPDATE sync_outbox SET shop_id = ? WHERE shop_id = ?',
        variables: [
          Variable.withString(newShopId),
          Variable.withString(oldShopId),
        ],
      );
      await _database.customUpdate(
        'UPDATE sync_state SET shop_id = ? WHERE shop_id = ?',
        variables: [
          Variable.withString(newShopId),
          Variable.withString(oldShopId),
        ],
      );

      // 4. Old shop row is now unreferenced locally — remove it.
      await (_database.delete(
        _database.shops,
      )..where((t) => t.id.equals(oldShopId))).go();
    });
  }

  Future<String> _insertProfile({
    required String email,
    required String? authUserId,
    required String? shopId,
    required UserRole role,
    required String? displayName,
    required bool isActive,
    required DateTime createdAt,
  }) async {
    final id = const Uuid().v4();
    await _database
        .into(_database.users)
        .insert(
          db.UsersCompanion.insert(
            id: Value(id),
            email: email,
            authUserId: Value(authUserId),
            shopId: Value(shopId),
            displayName: Value(displayName),
            role: Value(role.dbValue),
            isActive: Value(isActive),
          ),
        );
    return id;
  }

  Future<UserProfile> _profileFromRow(db.User row) async {
    final role = UserRole.fromDbValue(row.role ?? '');
    var permissions = const <Permission>{};
    if (role == UserRole.staff) {
      final rows = await (_database.select(
        _database.staffPermissions,
      )..where((t) => t.userId.equals(row.id))).get();
      permissions = {
        for (final entry in rows)
          if (entry.enabled)
            if (Permission.fromDbValue(entry.permission) != null)
              Permission.fromDbValue(entry.permission)!,
      };
    }
    return UserProfile(
      id: row.id,
      email: row.email,
      authUserId: row.authUserId,
      shopId: row.shopId,
      displayName: row.displayName,
      role: role ?? UserRole.staff,
      isActive: row.isActive,
      permissions: permissions,
    );
  }
}

/// Isolated so tests can substitute deterministic ids if ever needed.
class UuidSafe {
  const UuidSafe();
  String newId() => const Uuid().v4();
}
