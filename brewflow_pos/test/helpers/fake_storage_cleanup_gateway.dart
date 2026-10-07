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

  DatabaseMetrics? metricsResult;
  Object? metricsError;
  int metricsCalls = 0;

  MonthlyUsageStats? monthStatsResult;
  Object? monthStatsError;
  int monthStatsCalls = 0;

  /// When set, monthStats returns this avgBytes map (category -> avg row
  /// width). Defaults to a small deterministic map so per-category estimates
  /// can be asserted.
  Map<String, int> monthStatsAvgBytes = const {
    'sales': 100,
    'saleItems': 50,
    'salePayments': 40,
    'customerPayments': 40,
    'purchases': 120,
    'purchaseItems': 60,
    'expenses': 80,
    'stockMovements': 30,
    'dailyClosings': 70,
    'staffAttendance': 45,
    'staffAdvances': 35,
    'staffDailySalaries': 55,
    'staffMonthlySalaries': 90,
  };

  List<MonthlySnapshot> monthHistoryResult = const [];
  Object? monthHistoryError;
  int monthHistoryCalls = 0;

  MonthCleanupPreview? previewResult;
  Object? previewError;
  int previewCalls = 0;

  /// When set, the fake preview reports this many open (unpaid/partial)
  /// in-month customer bills.
  int previewOpenBillCount = 0;

  MonthCleanupResult? cleanupResult;
  Object? cleanupError;
  int cleanupCalls = 0;
  String? lastCleanupMarkerId;
  List<String>? lastCleanupCategories;

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

  @override
  Future<DatabaseMetrics> dbMetrics({required String shopId}) async {
    metricsCalls++;
    if (metricsError != null) throw metricsError!;
    return metricsResult ??
        DatabaseMetrics(
          dbBytesTotal: 0,
          tables: const [],
          measuredAt: DateTime.utc(2026),
        );
  }

  @override
  Future<MonthlyUsageStats> monthStats({
    required String shopId,
    required DateTime month,
  }) async {
    monthStatsCalls++;
    if (monthStatsError != null) throw monthStatsError!;
    return monthStatsResult ??
        MonthlyUsageStats(
          month: month,
          counts: const {},
          logicalBytesEst: 0,
          dbBytesTotal: 0,
          avgBytes: monthStatsAvgBytes,
        );
  }

  @override
  Future<List<MonthlySnapshot>> monthHistory({required String shopId}) async {
    monthHistoryCalls++;
    if (monthHistoryError != null) throw monthHistoryError!;
    return monthHistoryResult;
  }

  @override
  Future<MonthCleanupPreview> monthPreview({
    required String shopId,
    required DateTime month,
  }) async {
    previewCalls++;
    if (previewError != null) throw previewError!;
    return previewResult ??
        MonthCleanupPreview(
          month: month,
          counts: const {},
          monthOrphans: const [],
          reportConfirmed: false,
          alreadyCleaned: false,
          openBillCount: previewOpenBillCount,
        );
  }

  @override
  Future<MonthCleanupResult> monthCleanup({
    required String shopId,
    required DateTime month,
    required String markerId,
    List<String>? categories,
  }) async {
    cleanupCalls++;
    lastCleanupMarkerId = markerId;
    lastCleanupCategories = categories;
    if (cleanupError != null) throw cleanupError!;
    return cleanupResult ??
        MonthCleanupResult(
          month: month,
          deleted: const {},
          alreadyCleaned: false,
          markerId: markerId,
        );
  }
}
