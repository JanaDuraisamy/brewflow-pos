import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Image Cloud Store
///
/// Wraps Supabase Storage for product images. Every cloud path is scoped to
/// a business/shop so different businesses never share the same object space.
///
/// Auth boundary: uploads, downloads and deletes run through the *authenticated
/// user session* (JWT). The service-role key is never used client-side — all
/// access is governed by Supabase Storage RLS policies that check the
/// caller's shop membership.
///
/// Cloud path convention:
///   `{shop_id}/products/{product_id}.jpg`
///
/// The store writes metadata-only rows to Drift (see ProductImageSync queue);
/// image bytes are never persisted in the database.
/// ---------------------------------------------------------------------------

/// Abstraction over Supabase Storage for product images. Production uses
/// [ProductImageCloudStore]; tests inject a fake so the coordinator can be
/// exercised without a Supabase client.
abstract interface class ProductImageCloud {
  Future<String> upload({
    required String shopId,
    required String productId,
    required Uint8List fileBytes,
  });

  /// Returns raw image bytes, or null when the object does not exist.
  Future<Uint8List?> download(String cloudPath);

  Future<File?> downloadToFile({
    required String cloudPath,
    required File destFile,
  });

  Future<void> delete(String cloudPath);

  static String cloudPathFor(String shopId, String productId) =>
      '$shopId/products/$productId.jpg';
}

final class ProductImageCloudStore implements ProductImageCloud {
  ProductImageCloudStore(this._client);

  final SupabaseClient _client;

  /// Returns the Storage bucket used for product images.
  StorageFileApi get _bucket => _client.storage.from('product-images');

  /// Uploads [fileBytes] to the cloud under [shopId]/products/[productId].jpg.
  ///
  /// If an object already exists at that path it is replaced atomically —
  /// Supabase Storage upserts are object-level, so a failed upload never
  /// corrupts the previous version.
  ///
  /// Returns the canonical cloud object path.
  @override
  Future<String> upload({
    required String shopId,
    required String productId,
    required Uint8List fileBytes,
  }) async {
    final path = ProductImageCloud.cloudPathFor(shopId, productId);
    await _bucket.uploadBinary(
      path,
      fileBytes,
      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
    );
    return path;
  }

  /// Downloads the image at [cloudPath] and returns its raw bytes.
  /// Returns null when the object does not exist (404 treated as absence,
  /// not an error).
  @override
  Future<Uint8List?> download(String cloudPath) async {
    try {
      return await _bucket.download(cloudPath);
    } on StorageException catch (e) {
      if (e.statusCode == '404' || e.message.contains('not found')) {
        return null;
      }
      rethrow;
    }
  }

  /// Downloads [cloudPath] and writes it to [destFile] atomically (write-
  /// then-rename). Returns the local [File], or null when the object does
  /// not exist.
  @override
  Future<File?> downloadToFile({
    required String cloudPath,
    required File destFile,
  }) async {
    final bytes = await download(cloudPath);
    if (bytes == null) return null;
    // Write to a temp file then rename so a crash never leaves a partial file.
    final temp = File('${destFile.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(destFile.path);
    return destFile;
  }

  /// Deletes the object at [cloudPath]. Missing objects are a no-op.
  @override
  Future<void> delete(String cloudPath) async {
    try {
      await _bucket.remove([cloudPath]);
    } on StorageException catch (e) {
      if (e.statusCode == '404' || e.message.contains('not found')) return;
      rethrow;
    }
  }
}

/// Riverpod provider exposing the cloud store. Requires an active Supabase
/// session — returns null (and is never used) when the client is not
/// initialized (e.g. in tests).
final productImageCloudStoreProvider = Provider<ProductImageCloudStore?>((ref) {
  try {
    return ProductImageCloudStore(Supabase.instance.client);
  } catch (_) {
    // Supabase not initialized (tests, cold start) — cloud unavailable.
    return null;
  }
});
