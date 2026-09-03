import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/inventory/data/drift_image_sync_repository.dart';
import 'package:drift/drift.dart' show Value, DoNothing;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Image Sync Queue Repository
///
/// Covers enqueue (upload/download/delete), dedupe-while-pending, retry /
/// FAILED parking, pending-count and cross-device reconcileDownloads.
/// Uses a real in-memory Drift database so CHECK/index semantics are exact.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftImageSyncRepository repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = DriftImageSyncRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> countAll() async {
    final rows = await database
        .customSelect('SELECT COUNT(*) as cnt FROM product_image_sync')
        .get();
    return rows.first.data['cnt'] as int;
  }

  group('enqueueUpload', () {
    test('inserts a PENDING entry without bytes on disk', () async {
      await repo.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'product_images/p1.jpg',
        cloudPath: 'shop1/products/p1.jpg',
      );

      final rows = await repo.pendingBatch();
      expect(rows, hasLength(1));
      expect(rows.single.operation, 'UPLOAD');
      expect(rows.single.status, 'PENDING');
      expect(rows.single.shopId, 'shop1');
      expect(rows.single.localPath, 'product_images/p1.jpg');
      expect(rows.single.cloudPath, 'shop1/products/p1.jpg');
    });

    test('re-enqueueing while PENDING updates, never duplicates', () async {
      await repo.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'a.jpg',
        cloudPath: 'c1',
      );
      await repo.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'b.jpg',
        cloudPath: 'c1',
      );

      expect(await countAll(), 1);
      // The later local path replaces the earlier one.
      expect((await repo.pendingBatch()).single.localPath, 'b.jpg');
    });

    test('a distinct product enqueues a separate row', () async {
      await repo.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'a.jpg',
        cloudPath: 'c1',
      );
      await repo.enqueueUpload(
        shopId: 'shop1',
        productId: 'p2',
        localPath: 'b.jpg',
        cloudPath: 'c2',
      );
      expect(await countAll(), 2);
    });
  });

  group('enqueueDownload / enqueueDelete', () {
    test('download and delete insert their own operation rows', () async {
      await repo.enqueueDownload(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'shop1/products/p1.jpg',
        localPath: 'product_images/p1.jpg',
      );
      await repo.enqueueDelete(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'shop1/products/p1.jpg',
        localPath: 'product_images/p1.jpg',
      );

      expect(await countAll(), 2);
      final ops = (await repo.pendingBatch()).map((r) => r.operation).toSet();
      expect(ops, {'DOWNLOAD', 'DELETE'});
    });

    test('download dedupes while pending', () async {
      await repo.enqueueDownload(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'c',
        localPath: 'l',
      );
      await repo.enqueueDownload(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'c2',
        localPath: 'l2',
      );
      expect(await countAll(), 1);
      final row = (await repo.pendingBatch()).single;
      expect(row.cloudPath, 'c2');
      expect(row.localPath, 'l2');
    });
  });

  group('retry & status', () {
    test('incrementAttempt parks a row as FAILED after maxAttempts', () async {
      await repo.enqueueDelete(
        shopId: 's',
        productId: 'p1',
        cloudPath: 'c',
        localPath: 'l',
      );
      final id = (await repo.pendingBatch()).single.id;
      await repo.markInProgress(id);

      for (var i = 0; i < DriftImageSyncRepository.maxAttempts; i++) {
        await repo.incrementAttempt(id, 'nope');
      }

      final rows = await repo.pendingBatch();
      expect(rows, isEmpty);
      final all = await database
          .customSelect('SELECT status, attempt_count FROM product_image_sync')
          .get();
      final row = all.first.data;
      expect(row['status'], 'FAILED');
      expect(row['attempt_count'], DriftImageSyncRepository.maxAttempts);
    });

    test(
      'markDone transitions a row to DONE and leaves the queue empty',
      () async {
        await repo.enqueueUpload(
          shopId: 's',
          productId: 'p1',
          localPath: 'l',
          cloudPath: 'c',
        );
        final id = (await repo.pendingBatch()).single.id;
        await repo.markInProgress(id);
        expect(await repo.hasPendingWork(), isTrue);

        await repo.markDone(id);
        expect(await repo.hasPendingWork(), isFalse);
        expect(await repo.pendingBatch(), isEmpty);
      },
    );

    test('pendingCount counts only PENDING and IN_FLIGHT rows', () async {
      await repo.enqueueUpload(
        shopId: 's',
        productId: 'p1',
        localPath: 'l',
        cloudPath: 'c',
      );
      final id = (await repo.pendingBatch()).single.id;
      await repo.markInProgress(id);
      await repo.enqueueDownload(
        shopId: 's',
        productId: 'p2',
        cloudPath: 'c2',
        localPath: 'l2',
      );
      // Mark p2's download done.
      final p2 = (await repo.pendingBatch()).firstWhere(
        (r) => r.productId == 'p2',
      );
      await repo.markDone(p2.id);

      expect(await repo.pendingCount(), 1);
    });
  });

  group('reconcileDownloads', () {
    Future<void> insertProduct({
      required String id,
      required String shopId,
      String? cloudImagePath,
      String? imagePath,
      bool isActive = true,
    }) async {
      // FK chain: products.category_id → categories, categories.shop_id → shops.
      await database
          .into(database.shops)
          .insert(
            db.ShopsCompanion.insert(id: Value(shopId), name: 'Shop'),
            onConflict: DoNothing(),
          );
      await database
          .into(database.categories)
          .insert(
            db.CategoriesCompanion.insert(
              id: const Value('cat1'),
              name: 'Cat',
              shopId: Value(shopId),
            ),
            onConflict: DoNothing(),
          );
      await database
          .into(database.products)
          .insert(
            db.ProductsCompanion.insert(
              id: Value(id),
              shopId: Value(shopId),
              categoryId: 'cat1',
              name: 'P $id',
              sellingPricePaise: 100,
              stockUnit: Value('COUNT'),
              lowStockMode: Value('USE_DEFAULT'),
              isActive: Value(isActive),
              imagePath: Value(imagePath),
              cloudImagePath: Value(cloudImagePath),
            ),
          );
    }

    test(
      'enqueues DOWNLOAD for cloud products missing a local image',
      () async {
        await insertProduct(
          id: 'p1',
          shopId: 'shop1',
          cloudImagePath: 'shop1/products/p1.jpg',
        );
        await insertProduct(
          id: 'p2',
          shopId: 'shop1',
          cloudImagePath: 'shop1/products/p2.jpg',
        );

        final enqueued = await repo.reconcileDownloads();

        expect(enqueued, 2);
        final downloads = (await repo.pendingBatch())
            .where((r) => r.operation == 'DOWNLOAD')
            .toList();
        expect(downloads, hasLength(2));
        expect(downloads.map((r) => r.productId), containsAll(['p1', 'p2']));
      },
    );

    test('is idempotent: a repeated reconcile does not re-enqueue', () async {
      await insertProduct(id: 'p1', shopId: 'shop1', cloudImagePath: 'c');
      await repo.reconcileDownloads();
      final again = await repo.reconcileDownloads();
      expect(again, 0);
      expect(await countAll(), 1);
    });

    test('skips products that already have a local image', () async {
      await insertProduct(
        id: 'p1',
        shopId: 'shop1',
        cloudImagePath: 'c',
        imagePath: 'product_images/p1.jpg',
      );
      await insertProduct(id: 'p2', shopId: 'shop1', cloudImagePath: 'c2');

      final enqueued = await repo.reconcileDownloads();
      expect(enqueued, 1);
      expect((await repo.pendingBatch()).single.productId, 'p2');
    });

    test('skips inactive products', () async {
      await insertProduct(
        id: 'p1',
        shopId: 'shop1',
        cloudImagePath: 'c',
        isActive: false,
      );
      final enqueued = await repo.reconcileDownloads();
      expect(enqueued, 0);
    });
  });
}
