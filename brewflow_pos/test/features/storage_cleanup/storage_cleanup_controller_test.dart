import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_storage_cleanup_gateway.dart';

const _ownerId = 'auth-owner-1';
const _ownerEmail = 'owner@brew.test';
const _shopId = 'shop-1';

Future<void> _awaitProfile(ProviderContainer c) =>
    c.read(userProfileProvider.future);

(ProviderContainer, FakeStorageCleanupGateway) _build({
  StorageUsageReport? scanResult,
  Object? scanError,
  CleanupDeleteResult? deleteResult,
  Object? deleteError,
}) {
  final gateway = FakeStorageCleanupGateway()
    ..scanResult = scanResult
    ..scanError = scanError
    ..deleteResult = deleteResult
    ..deleteError = deleteError;
  final db = AppDatabase(NativeDatabase.memory());
  final repo = DriftStorageCleanupRepository(db);
  final staff = FakeStaffRepository();
  final auth = FakeAuthRepository(
    user: const AuthUser(id: _ownerId, email: _ownerEmail),
  );

  final container = ProviderContainer(
    overrides: [
      storageCleanupGatewayProvider.overrideWithValue(gateway),
      storageCleanupRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      authRepositoryProvider.overrideWithValue(auth),
      staffRepositoryProvider.overrideWithValue(staff),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (container, gateway);
}

void main() {
  group('scan()', () {
    test('sets report and posts notification when orphans found', () async {
      final report = StorageUsageReport(
        usedBytes: 5000,
        imageCount: 10,
        orphanCount: 3,
        reclaimableBytes: 1500,
        orphanPaths: ['a/orphan1.jpg', 'b/orphan2.jpg', 'c/orphan3.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
        storageLimitBytes: 10000,
      );
      final (c, _) = _build(scanResult: report);
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();
      final state = c.read(storageCleanupControllerProvider);

      expect(state.report, isNotNull);
      expect(state.report!.orphanCount, 3);
      expect(state.report!.usedBytes, 5000);
      expect(state.notification, isNotNull);
      expect(state.notification!.orphanCount, 3);
      expect(state.isScanning, isFalse);
      expect(state.lastError, isNull);
    });

    test('scan with no orphans does not post notification', () async {
      final report = StorageUsageReport(
        usedBytes: 2000,
        imageCount: 5,
        orphanCount: 0,
        reclaimableBytes: 0,
        orphanPaths: [],
        lastScanAt: DateTime.utc(2026, 6, 1),
      );
      final (c, _) = _build(scanResult: report);
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();
      final state = c.read(storageCleanupControllerProvider);

      expect(state.report!.orphanCount, 0);
      expect(state.notification, isNull);
    });

    test('records scan metadata in local repository', () async {
      final report = StorageUsageReport(
        usedBytes: 3000,
        imageCount: 7,
        orphanCount: 1,
        reclaimableBytes: 400,
        orphanPaths: ['orphan.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
      );
      final (c, _) = _build(scanResult: report);
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();

      final repo = c.read(storageCleanupRepositoryProvider);
      final lastCleanup = await repo.lastCleanupAt(_shopId);
      expect(lastCleanup, isNull);
    });

    test('propagates gateway errors and sets lastError', () async {
      final (c, _) = _build(
        scanError: const StorageCleanupServiceFailure('Edge down'),
      );
      await _awaitProfile(c);

      await expectLater(
        c.read(storageCleanupControllerProvider.notifier).scan(),
        throwsA(isA<StorageCleanupServiceFailure>()),
      );
      final state = c.read(storageCleanupControllerProvider);
      expect(state.isScanning, isFalse);
      expect(state.lastError, contains('Edge down'));
    });

    test(
      'deduplicates notifications when re-scanning with same orphans',
      () async {
        final report = StorageUsageReport(
          usedBytes: 1000,
          imageCount: 3,
          orphanCount: 2,
          reclaimableBytes: 600,
          orphanPaths: ['a.jpg', 'b.jpg'],
          lastScanAt: DateTime.utc(2026, 6, 1),
        );
        final (c, _) = _build(scanResult: report);
        await _awaitProfile(c);

        final ctrl = c.read(storageCleanupControllerProvider.notifier);
        await ctrl.scan();
        final first = c.read(storageCleanupControllerProvider).notification;
        await ctrl.scan();
        final second = c.read(storageCleanupControllerProvider).notification;

        expect(first!.id, second!.id);
      },
    );
  });

  group('deleteOrphans()', () {
    test('deletes and refreshes report', () async {
      final report = StorageUsageReport(
        usedBytes: 5000,
        imageCount: 10,
        orphanCount: 2,
        reclaimableBytes: 1000,
        orphanPaths: ['a.jpg', 'b.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
        storageLimitBytes: 10000,
      );
      final (c, gw) = _build(
        scanResult: report,
        deleteResult: const CleanupDeleteResult(
          deletedPaths: ['a.jpg'],
          deletedCount: 1,
        ),
      );
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();
      final result = await c
          .read(storageCleanupControllerProvider.notifier)
          .deleteOrphans(['a.jpg']);

      expect(result.deletedCount, 1);
      expect(gw.deleteCalls, 1);
      expect(gw.lastDeletedPaths, ['a.jpg']);
    });

    test('empty path list returns immediately without gateway call', () async {
      final (c, gw) = _build();
      await _awaitProfile(c);

      final result = await c
          .read(storageCleanupControllerProvider.notifier)
          .deleteOrphans([]);

      expect(result.deletedCount, 0);
      expect(gw.deleteCalls, 0);
    });

    test('records cleanup timestamp after successful deletion', () async {
      final report = StorageUsageReport(
        usedBytes: 2000,
        imageCount: 4,
        orphanCount: 1,
        reclaimableBytes: 500,
        orphanPaths: ['orphan.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
      );
      final (c, _) = _build(
        scanResult: report,
        deleteResult: const CleanupDeleteResult(
          deletedPaths: ['orphan.jpg'],
          deletedCount: 1,
        ),
      );
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();
      await c.read(storageCleanupControllerProvider.notifier).deleteOrphans([
        'orphan.jpg',
      ]);

      final repo = c.read(storageCleanupRepositoryProvider);
      final at = await repo.lastCleanupAt(_shopId);
      expect(at, isNotNull);
    });

    test('propagates gateway errors', () async {
      final (c, _) = _build(
        deleteError: const StorageCleanupServiceFailure('delete failed'),
      );
      await _awaitProfile(c);

      await expectLater(
        c.read(storageCleanupControllerProvider.notifier).deleteOrphans([
          'a.jpg',
        ]),
        throwsA(isA<StorageCleanupServiceFailure>()),
      );
      final state = c.read(storageCleanupControllerProvider);
      expect(state.isDeleting, isFalse);
      expect(state.lastError, contains('delete failed'));
    });
  });

  group('notification management', () {
    test('markNotificationRead updates state', () async {
      final report = StorageUsageReport(
        usedBytes: 1000,
        imageCount: 3,
        orphanCount: 2,
        reclaimableBytes: 400,
        orphanPaths: ['a.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
      );
      final (c, _) = _build(scanResult: report);
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();
      expect(
        c.read(storageCleanupControllerProvider).notification!.isRead,
        isFalse,
      );

      await c
          .read(storageCleanupControllerProvider.notifier)
          .markNotificationRead();
      expect(
        c.read(storageCleanupControllerProvider).notification!.isRead,
        isTrue,
      );
    });

    test('dismissNotification clears notification', () async {
      final report = StorageUsageReport(
        usedBytes: 1000,
        imageCount: 3,
        orphanCount: 1,
        reclaimableBytes: 200,
        orphanPaths: ['x.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
      );
      final (c, _) = _build(scanResult: report);
      await _awaitProfile(c);

      await c.read(storageCleanupControllerProvider.notifier).scan();
      expect(c.read(storageCleanupControllerProvider).notification, isNotNull);

      await c
          .read(storageCleanupControllerProvider.notifier)
          .dismissNotification();
      expect(c.read(storageCleanupControllerProvider).notification, isNull);
    });
  });

  group('owner gating', () {
    test('scan throws for non-owner profile', () async {
      final staff = FakeStaffRepository();
      staff.storedProfiles.add(
        const UserProfile(
          id: 'staff-p1',
          email: 'staff@brew.test',
          authUserId: 'auth-staff-1',
          shopId: _shopId,
          role: UserRole.staff,
          isActive: true,
          permissions: {},
        ),
      );
      staff.profilesByAuthId['auth-staff-1'] = staff.storedProfiles.last;

      final gateway = FakeStorageCleanupGateway();
      final db = AppDatabase(NativeDatabase.memory());
      final repo = DriftStorageCleanupRepository(db);
      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'auth-staff-1', email: 'staff@brew.test'),
      );

      final c = ProviderContainer(
        overrides: [
          storageCleanupGatewayProvider.overrideWithValue(gateway),
          storageCleanupRepositoryProvider.overrideWithValue(repo),
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(auth),
          staffRepositoryProvider.overrideWithValue(staff),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await db.close();
      });

      await _awaitProfile(c);

      await expectLater(
        c.read(storageCleanupControllerProvider.notifier).scan(),
        throwsA(isA<StorageCleanupForbiddenFailure>()),
      );
    });
  });

  group('business isolation', () {
    test('different shops produce independent cleanup state', () async {
      final report = StorageUsageReport(
        usedBytes: 1000,
        imageCount: 3,
        orphanCount: 1,
        reclaimableBytes: 200,
        orphanPaths: ['orphan.jpg'],
        lastScanAt: DateTime.utc(2026, 6, 1),
      );

      final staff = FakeStaffRepository();
      staff.storedProfiles.add(
        const UserProfile(
          id: 'profile-1',
          email: 'multi@test.com',
          authUserId: 'auth-multi-1',
          shopId: 'shop-X',
          role: UserRole.owner,
          isActive: true,
          permissions: {},
        ),
      );
      staff.profilesByAuthId['auth-multi-1'] = staff.storedProfiles.last;

      final gateway = FakeStorageCleanupGateway()..scanResult = report;
      final db = AppDatabase(NativeDatabase.memory());
      final repo = DriftStorageCleanupRepository(db);
      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'auth-multi-1', email: 'multi@test.com'),
      );

      final c = ProviderContainer(
        overrides: [
          storageCleanupGatewayProvider.overrideWithValue(gateway),
          storageCleanupRepositoryProvider.overrideWithValue(repo),
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(auth),
          staffRepositoryProvider.overrideWithValue(staff),
        ],
      );
      addTearDown(() async {
        c.dispose();
        await db.close();
      });

      await _awaitProfile(c);
      await c.read(storageCleanupControllerProvider.notifier).scan();
      expect(c.read(storageCleanupControllerProvider).report!.orphanCount, 1);
    });
  });
}
