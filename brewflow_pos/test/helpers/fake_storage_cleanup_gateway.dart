import 'package:brewflow_pos/features/storage_cleanup/data/storage_cleanup_gateway.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';

/// Fake [StorageCleanupGateway] for controller tests.
///
/// Returns canned results; configurable failure hooks let tests exercise
/// every error path without touching Supabase.
final class FakeStorageCleanupGateway implements StorageCleanupGateway {
  StorageUsageReport? scanResult;
  Object? scanError;

  CleanupDeleteResult? deleteResult;
  Object? deleteError;

  int scanCalls = 0;
  int deleteCalls = 0;
  List<String> lastDeletedPaths = const [];

  @override
  Future<StorageUsageReport> scan({required String shopId}) async {
    scanCalls++;
    if (scanError != null) throw scanError!;
    return scanResult ??
        StorageUsageReport(
          usedBytes: 0,
          imageCount: 0,
          orphanCount: 0,
          reclaimableBytes: 0,
          orphanPaths: const [],
          lastScanAt: DateTime.utc(2026),
        );
  }

  @override
  Future<CleanupDeleteResult> deleteOrphans({
    required String shopId,
    required List<String> paths,
  }) async {
    deleteCalls++;
    lastDeletedPaths = paths;
    if (deleteError != null) throw deleteError!;
    return deleteResult ??
        CleanupDeleteResult(deletedPaths: paths, deletedCount: paths.length);
  }
}
