import 'package:brewflow_pos/features/closing/data/daily_closing_cloud_gateway.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';

/// ---------------------------------------------------------------------------
/// In-memory fake of [DailyClosingCloudGateway]: acts as the "second device"
/// cloud store. Keyed by shop so business isolation is testable. Set
/// [failNext] to simulate offline/cloud errors (repository must fall back to
/// the local mirror).
/// ---------------------------------------------------------------------------

final class FakeDailyClosingCloudGateway implements DailyClosingCloudGateway {
  final List<DailyClosingRecord> storedClosings = [];
  final List<String> closingShopIds = [];

  /// When true, the next cloud call throws (then resets to false).
  bool failNext = false;

  /// Every method call, in order, for behavior assertions.
  final List<String> calls = [];

  void _maybeFail(String call) {
    calls.add(call);
    if (failNext) {
      failNext = false;
      throw StateError('cloud unavailable');
    }
  }

  @override
  Future<List<DailyClosingRecord>> fetchClosings({
    required String shopId,
    DateTime? startDate,
    DateTime? endExclusiveDate,
  }) async {
    _maybeFail('fetchClosings');
    final result = <DailyClosingRecord>[];
    for (var i = 0; i < storedClosings.length; i++) {
      final record = storedClosings[i];
      if (closingShopIds[i] != shopId) continue;
      if (startDate != null && record.businessDate.isBefore(startDate)) {
        continue;
      }
      if (endExclusiveDate != null &&
          !record.businessDate.isBefore(endExclusiveDate)) {
        continue;
      }
      result.add(record);
    }
    return result;
  }

  @override
  Future<void> upsertClosing({
    required String shopId,
    required DailyClosingRecord record,
  }) async {
    _maybeFail('upsertClosing');
    for (var i = 0; i < storedClosings.length; i++) {
      if (storedClosings[i].id == record.id) {
        storedClosings[i] = record;
        closingShopIds[i] = shopId;
        return;
      }
    }
    storedClosings.add(record);
    closingShopIds.add(shopId);
  }

  @override
  Future<void> deleteClosing({required String id}) async {
    _maybeFail('deleteClosing');
    for (var i = 0; i < storedClosings.length; i++) {
      if (storedClosings[i].id == id) {
        storedClosings.removeAt(i);
        closingShopIds.removeAt(i);
        return;
      }
    }
  }
}
