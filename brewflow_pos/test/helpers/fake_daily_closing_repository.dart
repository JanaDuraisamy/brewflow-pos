import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_repository.dart';

/// In-memory [DailyClosingRepository] for reports tests.
///
/// Stores records per id with an optional owning shop. Filtering mirrors the
/// real repository: [startDate]..[endExclusiveDate) half-open cookie range,
/// and [shopIds] as a hard scope (null = every business, empty = no rows —
/// fail closed). Records seeded without a shop behave as in-scope for any
/// non-empty scope (preserves pre-existing management loader tests).
final class FakeDailyClosingRepository implements DailyClosingRepository {
  final List<DailyClosingRecord> _stored = [];
  final Map<String, String> _shopOf = {};

  Object? loadError;

  void seed(
    String id, {
    required DateTime businessDate,
    required int totalCashPaise,
    required int totalUpiPaise,
    required int totalSalesPaise,
    required int totalExpensePaise,
    required int cashLeftInBoxPaise,
    required int cashTakenOutPaise,
    String? takenOutBy,
    String? talliedBy,
    String? shopId,
  }) {
    if (shopId != null) _shopOf[id] = shopId;
    _stored.add(
      DailyClosingRecord(
        id: id,
        businessDate: businessDate,
        totalCashPaise: totalCashPaise,
        totalUpiPaise: totalUpiPaise,
        totalSalesPaise: totalSalesPaise,
        totalExpensePaise: totalExpensePaise,
        cashLeftInBoxPaise: cashLeftInBoxPaise,
        cashTakenOutPaise: cashTakenOutPaise,
        takenOutBy: takenOutBy,
        talliedBy: talliedBy,
        note: null,
        createdAt: businessDate.add(const Duration(hours: 19)),
      ),
    );
  }

  @override
  Future<List<DailyClosingRecord>> closingsFor({
    DateTime? startDate,
    DateTime? endExclusiveDate,
    List<String>? shopIds,
  }) async {
    final error = loadError;
    if (error != null) throw error;
    return [
      for (final record in _stored)
        if ((startDate == null || !record.businessDate.isBefore(startDate)) &&
            (endExclusiveDate == null ||
                record.businessDate.isBefore(endExclusiveDate)) &&
            _inScope(record, shopIds))
          record,
    ];
  }

  bool _inScope(DailyClosingRecord record, List<String>? shopIds) {
    if (shopIds == null) return true;
    if (shopIds.isEmpty) return false;
    final shopId = _shopOf[record.id];
    if (shopId == null) return true;
    return shopIds.contains(shopId);
  }

  @override
  Future<DailyClosingRecord> recordDailyClosing({
    required DateTime businessDate,
    required int totalCashPaise,
    required int totalUpiPaise,
    required int totalSalesPaise,
    required int totalExpensePaise,
    required int cashLeftInBoxPaise,
    required int cashTakenOutPaise,
    String? shopId,
    String? takenOutBy,
    String? talliedBy,
    String? note,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteDailyClosing(String id) async {}
}
