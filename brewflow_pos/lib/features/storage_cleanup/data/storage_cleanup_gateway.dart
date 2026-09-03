import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Storage Cleanup Gateway (client boundary)
///
/// The client NEVER holds service-role credentials and NEVER lists Storage
/// buckets or deletes objects directly. All privileged storage work (listing,
/// orphan detection, permanent deletion) runs inside the `storage-cleanup`
/// Edge Function with the signed-in owner's JWT; the function authorizes the
/// caller as an active OWNER of the shop and uses the service role (available
/// only inside the Supabase runtime).
///
/// Deployment requirement: `supabase functions deploy storage-cleanup` must be
/// done before this works against a real backend. Tests inject a fake gateway.
/// ---------------------------------------------------------------------------

abstract interface class StorageCleanupGateway {
  /// Runs a read-only usage + orphan scan for [shopId]. Never deletes.
  Future<StorageUsageReport> scan({required String shopId});

  /// Permanently deletes the given orphan object [paths] for [shopId] after
  /// the owner confirms. The function re-verifies each path is still an
  /// unreferenced orphan before deleting — a referenced image is never touched.
  Future<CleanupDeleteResult> deleteOrphans({
    required String shopId,
    required List<String> paths,
  });
}

final class SupabaseStorageCleanupGateway implements StorageCleanupGateway {
  SupabaseStorageCleanupGateway(this._functions);

  final FunctionsClient _functions;

  @override
  Future<StorageUsageReport> scan({required String shopId}) async {
    try {
      final data = await _invoke(body: {'action': 'scan', 'shop_id': shopId});
      final report = _parseReport(data);
      if (report == null) throw const StorageCleanupServiceFailure();
      return report;
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  @override
  Future<CleanupDeleteResult> deleteOrphans({
    required String shopId,
    required List<String> paths,
  }) async {
    try {
      final data = await _invoke(
        body: {'action': 'delete', 'shop_id': shopId, 'paths': paths},
      );
      if (data is! Map) throw const StorageCleanupServiceFailure();
      final deleted = data['deleted'];
      final deletedCount = data['deletedCount'];
      if (deleted is! List || deletedCount is! int) {
        throw const StorageCleanupServiceFailure();
      }
      return CleanupDeleteResult(
        deletedPaths: deleted.cast<String>(),
        deletedCount: deletedCount,
      );
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  Future<Object?> _invoke({required Map<String, Object?> body}) async {
    try {
      final response = await _functions.invoke('storage-cleanup', body: body);
      return response.data;
    } on FunctionsHttpException catch (error) {
      throw _mapFunctionError(error.status, error.details);
    } on FunctionsRelayException {
      throw const StorageCleanupServiceFailure(
        'The storage cleanup service is not deployed yet on this project.',
      );
    } on FunctionsFetchException {
      throw const StorageCleanupServiceFailure(
        'The storage service could not be reached. Check your connection.',
      );
    }
  }

  StorageCleanupFailure _mapFunctionError(int status, dynamic details) {
    final code = details is Map ? details['error'] : null;
    switch (status) {
      case 401:
        return const StorageCleanupSessionFailure();
      case 403:
        return const StorageCleanupForbiddenFailure();
      case 400:
      case 500:
      default:
        if (code == 'FORBIDDEN') return const StorageCleanupForbiddenFailure();
        return const StorageCleanupServiceFailure();
    }
  }

  StorageCleanupFailure _mapRelayError() =>
      const StorageCleanupServiceFailure();

  StorageUsageReport? _parseReport(Object? data) {
    if (data is! Map) return null;
    final usedBytes = data['usedBytes'];
    final imageCount = data['imageCount'];
    final orphanCount = data['orphanCount'];
    final reclaimableBytes = data['reclaimableBytes'];
    final orphanPaths = data['orphanPaths'];
    final lastScanAt = data['lastScanAt'];
    if (usedBytes is! int ||
        imageCount is! int ||
        orphanCount is! int ||
        reclaimableBytes is! int ||
        orphanPaths is! List ||
        lastScanAt is! String) {
      return null;
    }
    final limit = data['storageLimitBytes'];
    return StorageUsageReport(
      usedBytes: usedBytes,
      imageCount: imageCount,
      orphanCount: orphanCount,
      reclaimableBytes: reclaimableBytes,
      orphanPaths: orphanPaths.cast<String>(),
      storageLimitBytes: limit is int ? limit : null,
      lastScanAt:
          DateTime.tryParse(lastScanAt)?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}
