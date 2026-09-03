import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftStorageCleanupRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftStorageCleanupRepository(database);
  });

  tearDown(() async => database.close());

  const shopA = 'shop-alpha';
  const shopB = 'shop-beta';

  group('Notification lifecycle', () {
    test('postNotification inserts a new notification', () async {
      final posted = await repository.postNotification(
        shopId: shopA,
        orphanCount: 3,
        reclaimableBytes: 512,
      );
      expect(posted, isTrue);

      final active = await repository.activeNotification(shopId: shopA);
      expect(active, isNotNull);
      expect(active!.orphanCount, 3);
      expect(active.reclaimableBytes, 512);
      expect(active.dismissed, isFalse);
      expect(active.isRead, isFalse);
    });

    test(
      'postNotification dedupes while an active notification exists',
      () async {
        await repository.postNotification(
          shopId: shopA,
          orphanCount: 1,
          reclaimableBytes: 100,
        );
        final second = await repository.postNotification(
          shopId: shopA,
          orphanCount: 5,
          reclaimableBytes: 500,
        );
        expect(second, isFalse);

        final active = await repository.activeNotification(shopId: shopA);
        expect(active!.orphanCount, 1);
      },
    );

    test(
      'postNotification allows a new notification after dismissal',
      () async {
        await repository.postNotification(
          shopId: shopA,
          orphanCount: 1,
          reclaimableBytes: 100,
        );
        final active = await repository.activeNotification(shopId: shopA);
        await repository.markNotification(id: active!.id, dismissed: true);

        final second = await repository.postNotification(
          shopId: shopA,
          orphanCount: 2,
          reclaimableBytes: 200,
        );
        expect(second, isTrue);

        final refreshed = await repository.activeNotification(shopId: shopA);
        expect(refreshed!.orphanCount, 2);
      },
    );

    test('markNotification updates isRead', () async {
      await repository.postNotification(
        shopId: shopA,
        orphanCount: 1,
        reclaimableBytes: 100,
      );
      final active = await repository.activeNotification(shopId: shopA);
      await repository.markNotification(id: active!.id, isRead: true);

      final refreshed = await repository.activeNotification(shopId: shopA);
      expect(refreshed!.isRead, isTrue);
    });

    test('activeNotification returns null when dismissed', () async {
      await repository.postNotification(
        shopId: shopA,
        orphanCount: 1,
        reclaimableBytes: 100,
      );
      final active = await repository.activeNotification(shopId: shopA);
      await repository.markNotification(id: active!.id, dismissed: true);

      final refreshed = await repository.activeNotification(shopId: shopA);
      expect(refreshed, isNull);
    });

    test('different shops have independent notifications', () async {
      await repository.postNotification(
        shopId: shopA,
        orphanCount: 1,
        reclaimableBytes: 100,
      );
      await repository.postNotification(
        shopId: shopB,
        orphanCount: 2,
        reclaimableBytes: 200,
      );

      final noteA = await repository.activeNotification(shopId: shopA);
      final noteB = await repository.activeNotification(shopId: shopB);
      expect(noteA!.orphanCount, 1);
      expect(noteB!.orphanCount, 2);
    });
  });

  group('Cleanup state', () {
    test('lastCleanupAt is null before any cleanup', () async {
      final at = await repository.lastCleanupAt(shopA);
      expect(at, isNull);
    });

    test('recordCleanup persists timestamp', () async {
      await repository.recordCleanup(
        shopId: shopA,
        usedBytes: 1024,
        reclaimableBytes: 512,
      );
      final at = await repository.lastCleanupAt(shopA);
      expect(at, isNotNull);
    });

    test('recordCleanup is idempotent (upserts)', () async {
      await repository.recordCleanup(
        shopId: shopA,
        usedBytes: 100,
        reclaimableBytes: 50,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repository.recordCleanup(
        shopId: shopA,
        usedBytes: 200,
        reclaimableBytes: 100,
      );
      final at = await repository.lastCleanupAt(shopA);
      expect(at, isNotNull);
    });

    test('recordScan persists state without touching lastCleanupAt', () async {
      await repository.recordScan(
        shopId: shopA,
        usedBytes: 500,
        reclaimableBytes: 0,
      );
      final at = await repository.lastCleanupAt(shopA);
      expect(at, isNull);
    });

    test('different shops have independent cleanup state', () async {
      await repository.recordCleanup(
        shopId: shopA,
        usedBytes: 100,
        reclaimableBytes: 50,
      );
      await repository.recordScan(
        shopId: shopB,
        usedBytes: 200,
        reclaimableBytes: 0,
      );
      final atA = await repository.lastCleanupAt(shopA);
      final atB = await repository.lastCleanupAt(shopB);
      expect(atA, isNotNull);
      expect(atB, isNull);
    });
  });
}
