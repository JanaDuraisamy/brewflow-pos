import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/tables/product_image_sync.dart';
import 'package:brewflow_pos/core/database/tables/products.dart';
import 'package:drift/drift.dart';

part 'drift_image_sync_repository.g.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Image Sync Queue Repository
///
/// Wraps the [ProductImageSync] Drift table into a typed, durable queue of
/// product image cloud intents (UPLOAD / DOWNLOAD / DELETE). Every entry is
/// purely metadata — cloud path + local path — so bytes are never held in
/// the database.
///
/// The coordinator (see [ImageSyncCoordinator]) drains this queue and
/// uploads/downloads/deletes via [ProductImageCloudStore], retrying with
/// exponential backoff and parking exhausted entries as FAILED.
///
/// Duplicate safety: the identity index (product_id, operation) collapses
/// replays of the same logical intent while it is still PENDING, so re-saving
/// a product image or re-running a download can never create duplicate cloud
/// work.
/// ---------------------------------------------------------------------------

@DriftAccessor(tables: [ProductImageSync, Products])
class DriftImageSyncRepository extends DatabaseAccessor<AppDatabase>
    with _$DriftImageSyncRepositoryMixin {
  DriftImageSyncRepository(super.db);

  static const int maxAttempts = 8;

  Future<void> enqueueUpload({
    required String shopId,
    required String productId,
    required String localPath,
    required String cloudPath,
  }) async {
    final existing =
        await (select(productImageSync)
              ..where(
                (t) =>
                    t.productId.equals(productId) &
                    t.operation.equals('UPLOAD') &
                    t.status.equals('PENDING'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      await (update(
        productImageSync,
      )..where((t) => t.id.equals(existing.id))).write(
        ProductImageSyncCompanion(
          localPath: Value(localPath),
          cloudPath: Value(cloudPath),
        ),
      );
      return;
    }
    await into(productImageSync).insert(
      ProductImageSyncCompanion.insert(
        shopId: shopId,
        productId: productId,
        operation: 'UPLOAD',
        localPath: Value(localPath),
        cloudPath: Value(cloudPath),
      ),
    );
  }

  Future<void> enqueueDownload({
    required String shopId,
    required String productId,
    required String cloudPath,
    required String localPath,
  }) async {
    final existing =
        await (select(productImageSync)
              ..where(
                (t) =>
                    t.productId.equals(productId) &
                    t.operation.equals('DOWNLOAD') &
                    t.status.equals('PENDING'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      await (update(
        productImageSync,
      )..where((t) => t.id.equals(existing.id))).write(
        ProductImageSyncCompanion(
          cloudPath: Value(cloudPath),
          localPath: Value(localPath),
        ),
      );
      return;
    }
    await into(productImageSync).insert(
      ProductImageSyncCompanion.insert(
        shopId: shopId,
        productId: productId,
        operation: 'DOWNLOAD',
        cloudPath: Value(cloudPath),
        localPath: Value(localPath),
      ),
    );
  }

  Future<void> enqueueDelete({
    required String shopId,
    required String productId,
    required String cloudPath,
    String? localPath,
  }) async {
    final existing =
        await (select(productImageSync)
              ..where(
                (t) =>
                    t.productId.equals(productId) &
                    t.operation.equals('DELETE') &
                    t.status.equals('PENDING'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      await (update(
        productImageSync,
      )..where((t) => t.id.equals(existing.id))).write(
        ProductImageSyncCompanion(
          cloudPath: Value(cloudPath),
          localPath: Value(localPath),
        ),
      );
      return;
    }
    await into(productImageSync).insert(
      ProductImageSyncCompanion.insert(
        shopId: shopId,
        productId: productId,
        operation: 'DELETE',
        cloudPath: Value(cloudPath),
        localPath: Value(localPath),
      ),
    );
  }

  Future<List<ProductImageSyncData>> pendingBatch({int limit = 5}) =>
      (select(productImageSync)
            ..where((t) => t.status.equals('PENDING'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(limit))
          .get();

  Future<void> markInProgress(String id) async {
    await (update(productImageSync)..where((t) => t.id.equals(id))).write(
      ProductImageSyncCompanion(
        status: const Value('IN_FLIGHT'),
        lastAttemptAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> markDone(String id) async {
    await (update(productImageSync)..where((t) => t.id.equals(id))).write(
      const ProductImageSyncCompanion(status: Value('DONE')),
    );
  }

  Future<void> incrementAttempt(String id, String error) async {
    final entry = await (select(
      productImageSync,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (entry == null) return;
    final nextCount = entry.attemptCount + 1;
    if (nextCount >= maxAttempts) {
      await (update(productImageSync)..where((t) => t.id.equals(id))).write(
        ProductImageSyncCompanion(
          status: const Value('FAILED'),
          attemptCount: Value(nextCount),
          lastError: Value(error),
        ),
      );
    } else {
      // Reopen the entry so the next drain picks it up again.
      await (update(productImageSync)..where((t) => t.id.equals(id))).write(
        ProductImageSyncCompanion(
          status: const Value('PENDING'),
          attemptCount: Value(nextCount),
          lastError: Value(error),
        ),
      );
    }
  }

  Future<bool> hasPendingWork() async => (await pendingCount()) > 0;

  /// Scans products that carry a [Products.cloudImagePath] but are missing a
  /// local image file path, and enqueues a DOWNLOAD for each that is not
  /// already pending. This is the cross-device entry point: after a pull
  /// writes `cloudImagePath` (see [LocalMasterDataApplier]), a later
  /// reconciliation run picks the image up here without coupling the applier
  /// to the image queue.
  ///
  /// Returns the number of new DOWNLOAD intents enqueued.
  Future<int> reconcileDownloads() async {
    final productsWithCloud =
        await (select(products)..where(
              (t) =>
                  t.cloudImagePath.isNotNull() &
                  t.imagePath.isNull() &
                  t.isActive.equals(true),
            ))
            .get();
    var enqueued = 0;
    for (final p in productsWithCloud) {
      final cloud = p.cloudImagePath!;
      final pending =
          await (select(productImageSync)..where(
                (t) =>
                    t.productId.equals(p.id) &
                    t.operation.equals('DOWNLOAD') &
                    t.status.equals('PENDING'),
              ))
              .getSingleOrNull();
      if (pending != null) continue;
      final shopId = p.shopId;
      if (shopId == null) continue;
      await enqueueDownload(
        shopId: shopId,
        productId: p.id,
        cloudPath: cloud,
        localPath: 'products/${p.id}.jpg',
      );
      enqueued++;
    }
    return enqueued;
  }

  Future<int> pendingCount() async {
    final q = customSelect(
      'SELECT COUNT(*) as cnt FROM product_image_sync'
      " WHERE status IN ('PENDING', 'IN_FLIGHT')",
    );
    final rows = await q.get();
    return rows.first.data['cnt'] as int;
  }
}
