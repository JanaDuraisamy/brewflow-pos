import 'package:brewflow_pos/core/services/app_log.dart';
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

  /// Physical database metrics (DB-wide sizes + shop limit). Read-only.
  Future<DatabaseMetrics> dbMetrics({required String shopId});

  /// Computes one month's logical stats AND records the server ledger row.
  /// Byte figures are logical/estimated by construction.
  Future<MonthlyUsageStats> monthStats({
    required String shopId,
    required DateTime month,
  });

  /// Server monthly ledger for [shopId], newest month first.
  Future<List<MonthlySnapshot>> monthHistory({required String shopId});

  /// Read-only month-cleanup preview from the same SQL the cleanup runs.
  Future<MonthCleanupPreview> monthPreview({
    required String shopId,
    required DateTime month,
  });

  /// Owner-confirmed month-scoped HARD DELETE via the atomic RPC. Refuses
  /// months without a report confirmation (server-side). Returns ACTUAL
  /// affected-row counts. [markerId] is the client-generated cleanup marker
  /// id, reused across retries so a retry converges instead of duplicating.
  /// [categories] narrows the scope to the selected cleanup categories; null
  /// deletes the full month scope (the server default).
  Future<MonthCleanupResult> monthCleanup({
    required String shopId,
    required DateTime month,
    required String markerId,
    List<String>? categories,
  });
}

final class SupabaseStorageCleanupGateway implements StorageCleanupGateway {
  SupabaseStorageCleanupGateway(this._functions);

  final FunctionsClient _functions;

  @override
  Future<StorageUsageReport> scan({required String shopId}) async {
    AppLog.info('Storage scan started for shop $shopId', tag: 'StorageScan');
    try {
      final data = await _invoke(body: {'action': 'scan', 'shop_id': shopId});
      final report = _parseReport(data);
      if (report == null) {
        AppLog.warning(
          'Storage scan parse failed for shop $shopId — response shape mismatch',
          tag: 'StorageScan',
        );
        throw const StorageCleanupServiceFailure();
      }
      AppLog.info(
        'Storage scan succeeded for shop $shopId — ${report.imageCount} images, '
        '${report.orphanCount} orphans',
        tag: 'StorageScan',
      );
      return report;
    } on StorageCleanupFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLog.error(
        'Storage scan failed for shop $shopId: $error',
        tag: 'StorageScan',
        error: error,
        stackTrace: stackTrace,
      );
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

  @override
  Future<DatabaseMetrics> dbMetrics({required String shopId}) async {
    try {
      final data = await _invoke(
        body: {'action': 'db-metrics', 'shop_id': shopId},
      );
      final metrics = _parseMetrics(data);
      if (metrics == null) throw const StorageCleanupServiceFailure();
      return metrics;
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  @override
  Future<MonthlyUsageStats> monthStats({
    required String shopId,
    required DateTime month,
  }) async {
    try {
      final data = await _invoke(
        body: {
          'action': 'month-stats',
          'shop_id': shopId,
          'month': _monthKey(month),
        },
      );
      final stats = _parseMonthStats(data);
      if (stats == null) throw const StorageCleanupServiceFailure();
      return stats;
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  @override
  Future<List<MonthlySnapshot>> monthHistory({required String shopId}) async {
    try {
      final data = await _invoke(
        body: {'action': 'month-history', 'shop_id': shopId},
      );
      if (data is! Map) throw const StorageCleanupServiceFailure();
      final snapshots = data['snapshots'];
      if (snapshots is! List) throw const StorageCleanupServiceFailure();
      return [
        for (final row in snapshots)
          if (_parseSnapshot(row) != null) _parseSnapshot(row)!,
      ];
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  @override
  Future<MonthCleanupPreview> monthPreview({
    required String shopId,
    required DateTime month,
  }) async {
    try {
      final data = await _invoke(
        body: {
          'action': 'month-preview',
          'shop_id': shopId,
          'month': _monthKey(month),
        },
      );
      final preview = _parsePreview(data, month);
      if (preview == null) throw const StorageCleanupServiceFailure();
      return preview;
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  @override
  Future<MonthCleanupResult> monthCleanup({
    required String shopId,
    required DateTime month,
    required String markerId,
    List<String>? categories,
  }) async {
    try {
      final body = <String, Object?>{
        'action': 'month-cleanup',
        'shop_id': shopId,
        'month': _monthKey(month),
        'marker_id': markerId,
      };
      if (categories != null) body['categories'] = categories;
      final data = await _invoke(body: body);
      if (data is! Map) throw const StorageCleanupServiceFailure();
      final deleted = data['deleted'];
      if (deleted is! Map) throw const StorageCleanupServiceFailure();
      return MonthCleanupResult(
        month: _monthCookie(month),
        deleted: {
          for (final e in deleted.entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        },
        alreadyCleaned: data['alreadyCleaned'] == true,
        markerId: markerId,
      );
    } on StorageCleanupFailure {
      rethrow;
    } on Object {
      throw _mapRelayError();
    }
  }

  static String _monthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}-01';

  static DateTime _monthCookie(DateTime month) =>
      DateTime.utc(month.year, month.month);

  Future<Object?> _invoke({required Map<String, Object?> body}) async {
    try {
      final response = await _functions.invoke('storage-cleanup', body: body);
      AppLog.info(
        'Storage scan Edge Function returned status ${response.status}',
        tag: 'StorageScan',
      );
      return response.data;
    } on FunctionsHttpException catch (error) {
      AppLog.warning(
        'Storage scan Edge Function HTTP ${error.status}: ${error.details}',
        tag: 'StorageScan',
      );
      throw _mapFunctionError(error.status, error.details);
    } on FunctionsRelayException {
      AppLog.warning(
        'Storage scan Edge Function relay error (not deployed?)',
        tag: 'StorageScan',
      );
      throw const StorageCleanupServiceFailure(
        'The storage cleanup service is not deployed yet on this project.',
      );
    } on FunctionsFetchException {
      AppLog.warning(
        'Storage scan Edge Function fetch error (network)',
        tag: 'StorageScan',
      );
      throw const StorageCleanupServiceFailure(
        'The storage service could not be reached. Check your connection.',
      );
    }
  }

  StorageCleanupFailure _mapFunctionError(int status, dynamic details) {
    final isMap = details is Map;
    final code = isMap ? details['error'] : null;
    // Surface the function's own message when it relayed one (e.g. the edge
    // function returning 'error' + a human-readable message) so the owner sees
    // the real reason instead of a generic fallback.
    final relayedMessage = isMap
        ? (details['message'] ?? details['error_description'] ?? details['msg'])
        : null;
    String? message;
    if (relayedMessage is String && relayedMessage.trim().isNotEmpty) {
      message = relayedMessage.trim();
    }
    switch (status) {
      case 401:
        return const StorageCleanupSessionFailure();
      case 403:
        return const StorageCleanupForbiddenFailure();
      case 409:
        // Month cleanup refused: no report confirmation for that month.
        // The month is untouched.
        if (code == 'NEEDS_REPORT') {
          return const MonthCleanupBlockedFailure(
            'Generate and confirm this month\u2019s report before cleanup.',
          );
        }
        return const MonthCleanupBlockedFailure();
      case 400:
      case 500:
      default:
        if (code == 'FORBIDDEN') return const StorageCleanupForbiddenFailure();
        if (message != null) return StorageCleanupServiceFailure(message);
        return const StorageCleanupServiceFailure();
    }
  }

  StorageCleanupFailure _mapRelayError() =>
      const StorageCleanupServiceFailure();

  StorageUsageReport? _parseReport(Object? data) {
    if (data is! Map) {
      AppLog.warning(
        'Storage scan parse failed: response is not a Map (${data.runtimeType})',
        tag: 'StorageScan',
      );
      return null;
    }
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
      AppLog.warning(
        'Storage scan parse failed: field type mismatch — '
        'usedBytes=${usedBytes.runtimeType} imageCount=${imageCount.runtimeType} '
        'orphanCount=${orphanCount.runtimeType} reclaimableBytes=${reclaimableBytes.runtimeType} '
        'orphanPaths=${orphanPaths.runtimeType} lastScanAt=${lastScanAt.runtimeType}',
        tag: 'StorageScan',
      );
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

  DatabaseMetrics? _parseMetrics(Object? data) {
    if (data is! Map) return null;
    final dbBytesTotal = data['dbBytesTotal'];
    final tables = data['tables'];
    if (dbBytesTotal is! int || tables is! List) return null;
    final parsed = <DatabaseTableMetrics>[];
    for (final entry in tables) {
      if (entry is! Map) return null;
      final table = entry['table'];
      final bytes = entry['bytes'];
      final rows = entry['rows'];
      if (table is! String || bytes is! int || rows is! int) return null;
      parsed.add(DatabaseTableMetrics(table: table, bytes: bytes, rows: rows));
    }
    final limit = data['storageLimitBytes'];
    return DatabaseMetrics(
      dbBytesTotal: dbBytesTotal,
      tables: parsed,
      storageLimitBytes: limit is int ? limit : null,
      measuredAt: DateTime.now().toUtc(),
    );
  }

  static Map<String, int> _parseCounts(Object? counts) {
    if (counts is! Map) return const {};
    final out = <String, int>{};
    for (final entry in counts.entries) {
      final value = entry.value;
      if (value is num) out[entry.key.toString()] = value.toInt();
    }
    return out;
  }

  MonthlyUsageStats? _parseMonthStats(Object? data) {
    if (data is! Map) return null;
    final month = data['month'];
    final logicalBytesEst = data['logicalBytesEst'];
    final dbBytesTotal = data['dbBytesTotal'];
    if (month is! String || logicalBytesEst is! int || dbBytesTotal is! int) {
      return null;
    }
    final cookie = DateTime.tryParse('${month}T00:00:00Z');
    if (cookie == null) return null;
    return MonthlyUsageStats(
      month: cookie.toUtc(),
      counts: _parseCounts(data['counts']),
      logicalBytesEst: logicalBytesEst,
      dbBytesTotal: dbBytesTotal,
      avgBytes: _parseCounts(data['avgBytes']),
    );
  }

  MonthlySnapshot? _parseSnapshot(Object? data) {
    if (data is! Map) return null;
    final month = data['month'];
    final logicalBytesEst =
        data['logical_bytes_est'] ?? data['logicalBytesEst'];
    final dbBytesTotal = data['db_bytes_total'] ?? data['dbBytesTotal'];
    final createdAt = data['created_at'] ?? data['createdAt'];
    if (month is! String ||
        logicalBytesEst is! int ||
        dbBytesTotal is! int ||
        createdAt is! String) {
      return null;
    }
    final cookie = DateTime.tryParse('${month}T00:00:00Z');
    final stamped = DateTime.tryParse(createdAt);
    if (cookie == null || stamped == null) return null;
    return MonthlySnapshot(
      month: cookie.toUtc(),
      counts: _parseCounts(data['counts']),
      logicalBytesEst: logicalBytesEst,
      dbBytesTotal: dbBytesTotal,
      createdAt: stamped.toUtc(),
    );
  }

  /// Category keys the month SQL reports. The preview response also carries
  /// status flags (`confirmed`, `alreadyCleaned`) that must never leak into
  /// the deletable counts.
  static const _previewCountKeys = <String>{
    'sales',
    'saleItems',
    'salePayments',
    'customerPayments',
    'purchases',
    'purchaseItems',
    'expenses',
    'stockMovements',
    'dailyClosings',
    'staffAttendance',
    'staffAdvances',
    'staffDailySalaries',
    'staffMonthlySalaries',
    'orphanImages',
  };

  MonthCleanupPreview? _parsePreview(Object? data, DateTime month) {
    if (data is! Map) return null;
    final orphans = data['monthOrphans'];
    final parsedOrphans = <OrphanImage>[];
    if (orphans is List) {
      for (final entry in orphans) {
        if (entry is! Map) return null;
        final path = entry['path'];
        final size = entry['sizeBytes'];
        if (path is! String || size is! int) return null;
        parsedOrphans.add(OrphanImage(cloudPath: path, sizeBytes: size));
      }
    } else if (orphans != null) {
      return null;
    }
    final confirmed = data['confirmed'];
    final cleaned = data['alreadyCleaned'];
    if (confirmed is! int || cleaned is! int) return null;
    final counts = <String, int>{};
    for (final key in _previewCountKeys) {
      final value = data[key];
      if (value is num) counts[key] = value.toInt();
    }
    final openBills = data['openBillCount'];
    return MonthCleanupPreview(
      month: _monthCookie(month),
      counts: counts,
      monthOrphans: parsedOrphans,
      reportConfirmed: confirmed > 0,
      alreadyCleaned: cleaned > 0,
      openBillCount: openBills is num ? openBills.toInt() : 0,
    );
  }
}
