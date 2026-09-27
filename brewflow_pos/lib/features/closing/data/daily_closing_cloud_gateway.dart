import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Cloud Gateway
///
/// Cloud-authoritative adapter for end-of-day closing records
/// (supabase/migrations/0023). Direct-table access with shop RLS
/// (`is_shop_member(shop_id)`); the client never weakens RLS. Business-day
/// cookies cross as `yyyy-MM-dd` dates; money stays integer paise.
/// ---------------------------------------------------------------------------

abstract interface class DailyClosingCloudGateway {
  Future<List<DailyClosingRecord>> fetchClosings({
    required String shopId,
    DateTime? startDate,
    DateTime? endExclusiveDate,
  });

  Future<void> upsertClosing({
    required String shopId,
    required DailyClosingRecord record,
  });

  Future<void> deleteClosing({required String id});
}

final class SupabaseDailyClosingGateway implements DailyClosingCloudGateway {
  SupabaseDailyClosingGateway(this._client);

  final SupabaseClient _client;

  static String _day(DateTime cookie) =>
      cookie.toUtc().toIso8601String().substring(0, 10);

  @override
  Future<List<DailyClosingRecord>> fetchClosings({
    required String shopId,
    DateTime? startDate,
    DateTime? endExclusiveDate,
  }) async {
    var query = _client.from('daily_closings').select().eq('shop_id', shopId);
    if (startDate != null) {
      query = query.gte('business_date', _day(startDate));
    }
    if (endExclusiveDate != null) {
      query = query.lt('business_date', _day(endExclusiveDate));
    }
    final data = await query.order('business_date', ascending: false);
    return [
      for (final json in data)
        DailyClosingRecord(
          id: json['id'] as String,
          businessDate: DateTime.parse('${json['business_date']}T00:00:00Z'),
          totalCashPaise: (json['total_cash_paise'] as num).toInt(),
          totalUpiPaise: (json['total_upi_paise'] as num).toInt(),
          totalSalesPaise: (json['total_sales_paise'] as num).toInt(),
          totalExpensePaise: (json['total_expense_paise'] as num).toInt(),
          cashLeftInBoxPaise: (json['cash_left_in_box_paise'] as num).toInt(),
          cashTakenOutPaise: (json['cash_taken_out_paise'] as num).toInt(),
          takenOutBy: json['taken_out_by'] as String?,
          talliedBy: json['tallied_by'] as String?,
          note: json['note'] as String?,
          createdAt: json['created_at'] == null
              ? DateTime.now().toUtc()
              : DateTime.parse(json['created_at'] as String).toUtc(),
        ),
    ];
  }

  @override
  Future<void> upsertClosing({
    required String shopId,
    required DailyClosingRecord record,
  }) async {
    await _client.from('daily_closings').upsert(<String, dynamic>{
      'id': record.id,
      'shop_id': shopId,
      'business_date': _day(record.businessDate),
      'total_cash_paise': record.totalCashPaise,
      'total_upi_paise': record.totalUpiPaise,
      'total_sales_paise': record.totalSalesPaise,
      'total_expense_paise': record.totalExpensePaise,
      'cash_left_in_box_paise': record.cashLeftInBoxPaise,
      'cash_taken_out_paise': record.cashTakenOutPaise,
      'taken_out_by': record.takenOutBy,
      'tallied_by': record.talliedBy,
      'note': record.note,
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteClosing({required String id}) async {
    await _client.from('daily_closings').delete().eq('id', id);
  }
}
