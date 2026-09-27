import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Master Deletion Regression
///
/// Locks the destructive-delete contract:
///
///  - the local row is NEVER dropped, because staff_attendance /
///    staff_daily_salaries / staff_monthly_salaries / staff_advances all
///    reference users.id with ON DELETE CASCADE and PRAGMA foreign_keys is ON;
///  - every one of those history rows survives and stays attributed to the
///    removed member;
///  - the member leaves the roster, sign-in and the permission grants;
///  - a pulled STAFF_PROFILE tombstone removes the member on a peer device
///    while that device's history copy is equally untouched;
///  - OWNER and unknown profiles are refused rather than archived.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftStaffRepository staff;

  const shopId = 'shop-cafe';
  const authId = 'auth-staff-1';

  Future<UserProfile> seedStaff({String id = 'local-1'}) async {
    await staff.ensureShopWithId(shopId);
    return staff.createStaffProfile(
      identity: const AuthUser(id: authId, email: 'staff@brewflow.example'),
      shopId: shopId,
    );
  }

  Future<void> seedHistory(String localUserId) async {
    final now = DateTime.utc(2026, 1, 15, 9);
    await database
        .into(database.staffAttendance)
        .insert(
          StaffAttendanceCompanion.insert(
            id: const Value('att-1'),
            staffUserId: localUserId,
            inAt: now,
            attendanceDate: now,
          ),
        );
    await database
        .into(database.staffDailySalary)
        .insert(
          StaffDailySalaryCompanion.insert(
            id: const Value('daily-1'),
            staffUserId: localUserId,
            attendanceDate: now,
            salaryPaise: 50000,
          ),
        );
    await database
        .into(database.staffMonthlySalaries)
        .insert(
          StaffMonthlySalariesCompanion.insert(
            id: const Value('monthly-1'),
            staffUserId: localUserId,
            monthDate: DateTime.utc(2026, 1),
            salaryPaise: 900000,
          ),
        );
    await database
        .into(database.staffAdvances)
        .insert(
          StaffAdvancesCompanion.insert(
            id: const Value('adv-1'),
            staffUserId: localUserId,
            amountPaise: 100000,
            advanceDate: now,
          ),
        );
  }

  Future<int> historyRows() async =>
      (await database.select(database.staffAttendance).get()).length +
      (await database.select(database.staffDailySalary).get()).length +
      (await database.select(database.staffMonthlySalaries).get()).length +
      (await database.select(database.staffAdvances).get()).length;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    staff = DriftStaffRepository(database);
  });

  tearDown(() => database.close());

  group('archiveStaffProfile', () {
    test('preserves every attendance, salary and advance row', () async {
      final member = await seedStaff();
      await seedHistory(member.id);
      expect(await historyRows(), 4);

      await staff.archiveStaffProfile(member.id);

      // The whole point: nothing was cascaded away.
      expect(await historyRows(), 4);
      final attendance =
          (await database.select(database.staffAttendance).get()).single;
      final advance =
          (await database.select(database.staffAdvances).get()).single;
      expect(attendance.staffUserId, member.id);
      expect(advance.staffUserId, member.id);
    });

    test(
      'keeps the row as an anchor but removes the member from the roster',
      () async {
        final member = await seedStaff();
        await seedHistory(member.id);

        await staff.archiveStaffProfile(member.id);

        // Row retained so the history FKs stay valid...
        final row = await (database.select(
          database.users,
        )..where((t) => t.id.equals(member.id))).getSingle();
        expect(row.role, kArchivedStaffRole);
        // ...but no longer a user who can sign in or hold grants.
        expect(row.authUserId, isNull);
        expect(row.displayName, isNull);
        expect(row.isActive, isFalse);
        expect(row.email, archivedStaffEmail(member.id));
        expect(await staff.staffMembers(shopId: shopId), isEmpty);
        expect(await staff.profileForAuthUser(authId), isNull);
        expect(
          await (database.select(
            database.staffPermissions,
          )..where((t) => t.userId.equals(member.id))).get(),
          isEmpty,
        );
      },
    );

    test('releases the original email so it can be re-invited', () async {
      await seedStaff();
      final member = (await staff.staffMembers(shopId: shopId)).single;
      await staff.archiveStaffProfile(member.id);

      // Same address, new hire: must not trip the duplicate-email guard.
      final rehire = await staff.createStaffProfile(
        identity: const AuthUser(
          id: 'auth-staff-2',
          email: 'staff@brewflow.example',
        ),
        shopId: shopId,
      );
      expect(rehire.email, 'staff@brewflow.example');
      expect((await staff.staffMembers(shopId: shopId)).single.id, rehire.id);
    });

    test('is idempotent', () async {
      final member = await seedStaff();
      await seedHistory(member.id);

      await staff.archiveStaffProfile(member.id);
      await staff.archiveStaffProfile(member.id);

      expect(await historyRows(), 4);
      final rows = await database.select(database.users).get();
      expect(rows.length, 1, reason: 'no duplicate anchor row may be created');
    });

    test('refuses an owner profile', () async {
      await staff.ensureShopWithId(shopId);
      final owner = await staff.claimOwnership(
        const AuthUser(id: 'auth-owner', email: 'owner@brewflow.example'),
      );

      await expectLater(
        staff.archiveStaffProfile(owner.id),
        throwsA(isA<ProfileNotProvisionedFailure>()),
      );
      expect(
        (await database.select(database.users).get()).single.role,
        UserRole.owner.dbValue,
      );
    });

    test('refuses an unknown profile id', () async {
      await expectLater(
        staff.archiveStaffProfile('does-not-exist'),
        throwsA(isA<ProfileNotProvisionedFailure>()),
      );
    });
  });

  group('cross-device STAFF_PROFILE tombstone', () {
    test('removes the member on a peer and keeps its history copy', () async {
      final member = await seedStaff();
      await seedHistory(member.id);
      final applier = LocalMasterDataApplier(database);

      // The tombstone id is the Supabase auth id, not the local row id.
      await applier.applyDeletion(
        const SyncDeletion(
          entity: MasterEntity.staffProfile,
          id: authId,
          shopId: shopId,
        ),
      );

      expect(await historyRows(), 4);
      expect(await staff.staffMembers(shopId: shopId), isEmpty);
      expect(await staff.profileForAuthUser(authId), isNull);
      final row = await (database.select(
        database.users,
      )..where((t) => t.id.equals(member.id))).getSingle();
      expect(row.role, kArchivedStaffRole);
    });

    test('is a no-op for a member this device never had', () async {
      final applier = LocalMasterDataApplier(database);
      await applier.applyDeletion(
        const SyncDeletion(
          entity: MasterEntity.staffProfile,
          id: 'auth-unknown',
          shopId: shopId,
        ),
      );
      expect(await database.select(database.users).get(), isEmpty);
    });

    test('never archives an owner that a bad tombstone targets', () async {
      await staff.ensureShopWithId(shopId);
      final owner = await staff.claimOwnership(
        const AuthUser(id: 'auth-owner', email: 'owner@brewflow.example'),
      );
      final applier = LocalMasterDataApplier(database);

      await applier.applyDeletion(
        const SyncDeletion(
          entity: MasterEntity.staffProfile,
          id: 'auth-owner',
          shopId: shopId,
        ),
      );

      expect(
        (await database.select(database.users).get()).single.role,
        UserRole.owner.dbValue,
        reason: 'an owner must survive a mis-addressed tombstone',
      );
      expect(owner.role, UserRole.owner);
    });
  });
}
