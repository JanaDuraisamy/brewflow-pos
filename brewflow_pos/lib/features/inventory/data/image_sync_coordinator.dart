import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/inventory/data/drift_image_sync_repository.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_cloud_store.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Image Sync Coordinator
///
/// Drains the [DriftImageSyncRepository] queue, performing the cloud
/// operations (upload / download / delete) via [ProductImageCloudStore] and
/// local cache management via [ProductImageStore].
///
/// After a successful download, the coordinator also writes the local
/// [imagePath] back to the product row so the UI shows the image immediately.
/// After a successful upload, it writes the canonical [cloudImagePath] to the
/// product row so other devices know where to fetch the image.
///
/// Like the master-data [SyncEngine], this coordinator is reentrant and
/// non-blocking: offline POS usage is never gated on image sync.
/// ---------------------------------------------------------------------------

final class ImageSyncCoordinator {
  ImageSyncCoordinator(this._queue, this._cloud, this._local, this._db);

  static const String tag = 'ImageSync';

  final DriftImageSyncRepository _queue;
  final ProductImageCloud? _cloud;
  final ProductImageStore _local;
  final AppDatabase _db;

  bool _running = false;
  bool get isRunning => _running;

  /// Drains the queue until no PENDING entries remain or an error blocks
  /// the head. Each cycle processes one batch; repeated calls (timer /
  /// connectivity) are harmless.
  Future<void> drain() async {
    if (_running) return;
    if (_cloud == null) {
      AppLog.info('Cloud unavailable — image sync skipped', tag: tag);
      return;
    }
    _running = true;
    try {
      // Cross-device reconciliation: enqueue DOWNLOADs for any product that
      // gained a cloudImagePath (e.g. via a pull on this device) but has no
      // local image file yet. Cheap (scan over missing-image products) and
      // idempotent, so a timer/resume that races a pull simply picks it up.
      await _queue.reconcileDownloads();
      while (true) {
        final batch = await _queue.pendingBatch(limit: 5);
        if (batch.isEmpty) return;
        for (final entry in batch) {
          final ok = await _processEntry(entry);
          // On a failed entry, stop this cycle and leave the reopened
          // (PENDING) row for the next drain — offline/cloud blips must not
          // spin a single entry through all its attempts in one go.
          if (!ok) return;
        }
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'Image sync cycle incomplete (will retry)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _running = false;
    }
  }

  /// Processes one queue entry. Returns true on success (entry marked DONE),
  /// false on failure (entry reopened PENDING for the next cycle).
  Future<bool> _processEntry(ProductImageSyncData entry) async {
    await _queue.markInProgress(entry.id);
    try {
      switch (entry.operation) {
        case 'UPLOAD':
          await _upload(entry);
        case 'DOWNLOAD':
          await _download(entry);
        case 'DELETE':
          await _delete(entry);
      }
      await _queue.markDone(entry.id);
      return true;
    } catch (error, stackTrace) {
      AppLog.warning(
        'Image ${entry.operation.toLowerCase()} failed for ${entry.productId}',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      await _queue.incrementAttempt(entry.id, error.toString());
      return false;
    }
  }

  Future<void> _upload(ProductImageSyncData entry) async {
    final localPath = entry.localPath;
    final cloudPath = entry.cloudPath;
    if (localPath == null || cloudPath == null) {
      throw StateError(
        'UPLOAD entry ${entry.id} missing localPath or cloudPath',
      );
    }
    final localFile = _local.resolve(localPath);
    if (localFile == null) {
      // Local file gone — mark done (nothing to upload).
      AppLog.info(
        'Local image gone for ${entry.productId} — skipping upload',
        tag: tag,
      );
      return;
    }
    final bytes = await localFile.readAsBytes();
    await _cloud!.upload(
      shopId: entry.shopId,
      productId: entry.productId,
      fileBytes: bytes,
    );
    // Persist the cloud path on the product so the metadata is available to
    // other devices and the sync push can carry it.
    await (_db.update(_db.products)..where((t) => t.id.equals(entry.productId)))
        .write(ProductsCompanion(cloudImagePath: Value(cloudPath)));
  }

  Future<void> _download(ProductImageSyncData entry) async {
    final cloudPath = entry.cloudPath;
    final localPath = entry.localPath;
    if (cloudPath == null || localPath == null) {
      throw StateError(
        'DOWNLOAD entry ${entry.id} missing cloudPath or localPath',
      );
    }
    final bytes = await _cloud!.download(cloudPath);
    if (bytes == null) {
      // Object not in cloud yet (or already deleted) — mark done.
      AppLog.info(
        'Cloud image absent for ${entry.productId} — marking done',
        tag: tag,
      );
      return;
    }
    // Write to the local cache store.
    final savedRelative = await _local.saveBytes(bytes);
    // Point the product's imagePath to the newly cached local file.
    await (_db.update(_db.products)..where((t) => t.id.equals(entry.productId)))
        .write(ProductsCompanion(imagePath: Value(savedRelative)));
  }

  Future<void> _delete(ProductImageSyncData entry) async {
    final cloudPath = entry.cloudPath;
    final localPath = entry.localPath;
    if (cloudPath != null) {
      await _cloud!.delete(cloudPath);
    }
    if (localPath != null) {
      await _local.delete(localPath);
    }
  }
}

/// Riverpod provider for the image sync coordinator. Returns null when
/// Supabase is unavailable (tests, cold start) or the local store is not
/// ready.
final imageSyncCoordinatorProvider = FutureProvider<ImageSyncCoordinator?>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final queue = DriftImageSyncRepository(db);
  final cloud = ref.watch(productImageCloudStoreProvider);
  final local = await ref.watch(productImageStoreProvider.future);
  return ImageSyncCoordinator(queue, cloud, local, db);
});
