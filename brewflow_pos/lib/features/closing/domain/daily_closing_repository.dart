import 'daily_closing_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Repository
///
/// Persistence for end-of-day closing records. [businessDate] crosses the
/// boundary as a UTC-midnight day cookie ([DateTime.utc(year, month, day)]),
/// so day/month ranges are simple half-open comparisons regardless of device
/// timezone. Amounts are validated (>= 0) at implementations with
/// [DailyClosingNegativeAmountFailure].
///
/// [shopIds] scopes reads to businesses (Cafe/Food Truck isolation); writes
/// carry the owning shop. Cloud is authoritative: implementations backed by
/// Supabase read cloud-first when online (mirroring into the local cache)
/// and fall back to the local cache offline. The local cache alone is never
/// the source of truth for these owner records.
/// ---------------------------------------------------------------------------

abstract interface class DailyClosingRepository {
  /// Records in [startDate]..[endExclusiveDate) (both optional; nulls mean
  /// unbounded), newest business day first. [shopIds] restricts the read to
  /// those businesses.
  Future<List<DailyClosingRecord>> closingsFor({
    DateTime? startDate,
    DateTime? endExclusiveDate,
    List<String>? shopIds,
  });

  /// Saves one closing record. Throws [DailyClosingNegativeAmountFailure] for
  /// any negative amount.
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
  });

  /// Permanently removes a closing record by id.
  Future<void> deleteDailyClosing(String id);
}
