import 'dart:io';
import 'dart:typed_data';

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/inventory/data/drift_image_sync_repository.dart';
import 'package:brewflow_pos/features/inventory/data/image_sync_coordinator.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_cloud_store.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:drift/drift.dart' show Value, DoNothing;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake of the cloud storage contract — records calls and returns
/// canned bytes/errors so the coordinator can be driven without Supabase.
final class _FakeCloud implements ProductImageCloud {
  final Map<String, Uint8List> objects = {};
  final List<String> uploaded = [];
  final List<String> deleted = [];
  final List<String> downloaded = [];

  /// Failure hooks — assign to simulate transient errors.
  Future<void> Function({
    required String shopId,
    required String productId,
    required Uint8List fileBytes,
  })?
  onUpload;
  Future<void> Function(String cloudPath)? onDelete;

  @override
  Future<String> upload({
    required String shopId,
    required String productId,
    required Uint8List fileBytes,
  }) async {
    final hook = onUpload;
    if (hook != null) {
      await hook(shopId: shopId, productId: productId, fileBytes: fileBytes);
    }
    final p = ProductImageCloud.cloudPathFor(shopId, productId);
    objects[p] = fileBytes;
    uploaded.add(p);
    return p;
  }

  @override
  Future<Uint8List?> download(String cloudPath) async {
    downloaded.add(cloudPath);
    return objects[cloudPath];
  }

  @override
  Future<File?> downloadToFile({
    required String cloudPath,
    required File destFile,
  }) async {
    final bytes = objects[cloudPath];
    if (bytes == null) return null;
    await destFile.writeAsBytes(bytes);
    return destFile;
  }

  @override
  Future<void> delete(String cloudPath) async {
    final hook = onDelete;
    if (hook != null) {
      await hook(cloudPath);
    }
    objects.remove(cloudPath);
    deleted.add(cloudPath);
  }
}

/// True to run against a real, full console test.
void main() {
  late AppDatabase database;
  late DriftImageSyncRepository queue;
  late _FakeCloud cloud;
  late ProductImageStore local;
  late Directory tempDir;
  late ImageSyncCoordinator coordinator;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('brewflow_coordinator_');
    database = AppDatabase(NativeDatabase.memory());
    queue = DriftImageSyncRepository(database);
    cloud = _FakeCloud();
    local = ProductImageStore(documentsDir: tempDir);
    coordinator = ImageSyncCoordinator(queue, cloud, local, database);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> insertProduct({
    required String id,
    required String shopId,
    String? cloudImagePath,
    String? imagePath,
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
            isActive: Value(true),
            imagePath: Value(imagePath),
            cloudImagePath: Value(cloudImagePath),
          ),
        );
  }

  Future<db.Product?> productById(String id) => (database.select(
    database.products,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  group('UPLOAD', () {
    test('reads the local file, uploads and writes cloudImagePath', () async {
      // Local job: the product's uploaded image file.
      final jobDir = Directory('${tempDir.path}/product_images')..createSync();
      File('${jobDir.path}/img.jpg').writeAsBytesSync([1, 2, 3, 4]);
      await insertProduct(id: 'p1', shopId: 'shop1');

      final cloudPath = 'shop1/products/p1.jpg';
      await queue.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'product_images/img.jpg',
        cloudPath: cloudPath,
      );

      await coordinator.drain();

      expect(cloud.uploaded, [cloudPath]);
      expect(cloud.objects[cloudPath], [1, 2, 3, 4]);
      final row = await productById('p1');
      expect(row!.cloudImagePath, cloudPath);
    });

    test('a missing local file is skipped without failing', () async {
      await insertProduct(id: 'p1', shopId: 'shop1');
      await queue.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'product_images/gone.jpg',
        cloudPath: 'shop1/products/p1.jpg',
      );

      await coordinator.drain();

      expect(cloud.uploaded, isEmpty);
      expect(await queue.hasPendingWork(), isFalse);
    });

    test('a cloud failure increments the attempt and stays pending', () async {
      await insertProduct(id: 'p1', shopId: 'shop1');
      final jobDir = Directory('${tempDir.path}/product_images')..createSync();
      File('${jobDir.path}/img.jpg').writeAsBytesSync([1, 2, 3, 4]);
      cloud.onUpload =
          ({required shopId, required productId, required fileBytes}) async {
            throw StateError('boom');
          };

      await queue.enqueueUpload(
        shopId: 'shop1',
        productId: 'p1',
        localPath: 'product_images/img.jpg',
        cloudPath: 'shop1/products/p1.jpg',
      );
      await coordinator.drain();

      expect(await queue.hasPendingWork(), isTrue);
      final rows = await queue.pendingBatch();
      expect(rows.single.attemptCount, 1);
      expect(rows.single.lastError, contains('boom'));
      // Restore and drain again to prove retry succeeds.
      cloud.onUpload = null;
      await coordinator.drain();
      expect(await queue.hasPendingWork(), isFalse);
    });
  });

  group('DOWNLOAD', () {
    test('downloads, caches locally and writes imagePath', () async {
      cloud.objects['shop1/products/p1.jpg'] = Uint8List.fromList([9, 8, 7]);
      await insertProduct(
        id: 'p1',
        shopId: 'shop1',
        cloudImagePath: 'shop1/products/p1.jpg',
      );

      await queue.enqueueDownload(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'shop1/products/p1.jpg',
        localPath: 'product_images/fetch.jpg',
      );
      await coordinator.drain();

      final row = await productById('p1');
      expect(row!.imagePath, isNotNull);
      final file = local.resolve(row.imagePath!);
      expect(file, isNotNull);
      expect(file!.readAsBytesSync(), [9, 8, 7]);
      expect(await queue.hasPendingWork(), isFalse);
    });

    test('a missing cloud object is marked done, not failed', () async {
      await insertProduct(
        id: 'p1',
        shopId: 'shop1',
        cloudImagePath: 'shop1/products/p1.jpg',
      );
      await queue.enqueueDownload(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'shop1/products/missing.jpg',
        localPath: 'product_images/fetch.jpg',
      );

      await coordinator.drain();

      expect(await queue.hasPendingWork(), isFalse);
      expect(cloud.downloaded, ['shop1/products/missing.jpg']);
    });
  });

  group('DELETE', () {
    test('removes the cloud object and the local cached file', () async {
      cloud.objects['c'] = Uint8List.fromList([1, 2]);
      final rel = await local.saveBytes(Uint8List.fromList([1, 2]));
      await insertProduct(id: 'p1', shopId: 'shop1');
      await queue.enqueueDelete(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'c',
        localPath: rel,
      );

      await coordinator.drain();

      expect(cloud.deleted, ['c']);
      expect(local.resolve(rel), isNull);
      expect(await queue.hasPendingWork(), isFalse);
    });

    test('delete tolerates cloud failure by retrying', () async {
      await queue.enqueueDelete(
        shopId: 'shop1',
        productId: 'p1',
        cloudPath: 'c',
      );
      cloud.onDelete = (_) async {
        throw StateError('offline');
      };

      await coordinator.drain();
      expect(await queue.hasPendingWork(), isTrue);

      cloud.onDelete = null;
      await coordinator.drain();
      expect(await queue.hasPendingWork(), isFalse);
    });
  });

  group('reconcile on drain', () {
    test(
      'a pull-arrived cloudImagePath is downloaded on the next drain',
      () async {
        cloud.objects['shop1/products/p1.jpg'] = Uint8List.fromList([5, 6]);
        // No local image: this is exactly what a pull leaves behind.
        await insertProduct(
          id: 'p1',
          shopId: 'shop1',
          cloudImagePath: 'shop1/products/p1.jpg',
        );

        await coordinator.drain();

        final row = await productById('p1');
        expect(row!.imagePath, isNotNull);
        expect(cloud.downloaded, isNotEmpty);
      },
    );

    test(
      'a product that already has a local image is left untouched',
      () async {
        final rel = await local.saveBytes(Uint8List.fromList([1, 1]));
        await insertProduct(
          id: 'p1',
          shopId: 'shop1',
          cloudImagePath: 'shop1/products/p1.jpg',
          imagePath: rel,
        );

        await coordinator.drain();

        expect(cloud.downloaded, isEmpty);
        expect((await productById('p1'))!.imagePath, rel);
      },
    );
  });
}
