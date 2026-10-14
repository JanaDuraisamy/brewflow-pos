/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Models
///
/// End-of-day cash/sales tally. All money is integer paise. The record stores
/// exactly what was observed at close — no invented reconciliation formulas.
/// ---------------------------------------------------------------------------
library;

/// A saved daily closing record.
final class DailyClosingRecord {
  const DailyClosingRecord({
    required this.id,
    required this.businessDate,
    required this.totalCashPaise,
    required this.totalUpiPaise,
    required this.totalSalesPaise,
    required this.totalExpensePaise,
    required this.cashLeftInBoxPaise,
    required this.cashTakenOutPaise,
    required this.takenOutBy,
    required this.talliedBy,
    required this.note,
    required this.createdAt,
  });

  final String id;

  /// Local business-day cookie (UTC midnight) the closing covers.
  final DateTime businessDate;

  final int totalCashPaise;
  final int totalUpiPaise;
  final int totalSalesPaise;
  final int totalExpensePaise;
  final int cashLeftInBoxPaise;
  final int cashTakenOutPaise;
  final String? takenOutBy;
  final String? talliedBy;
  final String? note;
  final DateTime createdAt;
}

/// Display label for a person recorded on a closing (`takenOutBy` /
/// `talliedBy`): trimmed name, or 'Not recorded' when absent. Single source
/// for every Daily Closing person grouping so the Reports page and the
/// management report never diverge.
String dailyClosingPersonLabel(String? raw) {
  final name = raw?.trim();
  return (name == null || name.isEmpty) ? 'Not recorded' : name;
}

/// One person-wise Daily Closing total: who took/talled, on how many distinct
/// business days (with the sorted dates), and the summed cash taken out on
/// those days. Pure read-side aggregation over saved [DailyClosingRecord]s —
/// never mutates records and never invents amounts.
final class DailyClosingPersonTotal {
  const DailyClosingPersonTotal({
    required this.name,
    required this.days,
    required this.totalPaise,
    required this.dates,
  });

  final String name;

  /// Distinct business days counted for this person.
  final int days;
  final int totalPaise;

  /// Distinct business-day cookies, oldest first.
  final List<DateTime> dates;
}

/// Groups [closings] by who took cash (`takenOutBy`). Only closings with
/// `cashTakenOutPaise > 0` count; days are distinct business dates per person.
/// Alphabetical by name (case-insensitive). Reused by the Reports page and the
/// management report loader.
List<DailyClosingPersonTotal> aggregateDailyClosingTakenBy(
  List<DailyClosingRecord> closings,
) {
  final totals = <String, int>{};
  final daysByPerson = <String, Set<DateTime>>{};
  for (final closing in closings) {
    if (closing.cashTakenOutPaise <= 0) continue;
    final key = dailyClosingPersonLabel(closing.takenOutBy);
    totals.update(
      key,
      (total) => total + closing.cashTakenOutPaise,
      ifAbsent: () => closing.cashTakenOutPaise,
    );
    daysByPerson.putIfAbsent(key, () => <DateTime>{}).add(closing.businessDate);
  }
  final rows = [
    for (final entry in totals.entries)
      DailyClosingPersonTotal(
        name: entry.key,
        days: daysByPerson[entry.key]!.length,
        totalPaise: entry.value,
        dates: [...daysByPerson[entry.key]!]..sort(),
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return rows;
}

/// Groups [closings] by who performed/confirmed the tally (`talliedBy`).
/// Every closing counts toward its tally person's day count (even when
/// nothing was taken); [totalPaise] is the cash taken out on the days that
/// person tallied. Alphabetical by name (case-insensitive).
List<DailyClosingPersonTotal> aggregateDailyClosingTalliedBy(
  List<DailyClosingRecord> closings,
) {
  final totals = <String, int>{};
  final daysByPerson = <String, Set<DateTime>>{};
  for (final closing in closings) {
    final key = dailyClosingPersonLabel(closing.talliedBy);
    totals.update(
      key,
      (total) => total + closing.cashTakenOutPaise,
      ifAbsent: () => closing.cashTakenOutPaise,
    );
    daysByPerson.putIfAbsent(key, () => <DateTime>{}).add(closing.businessDate);
  }
  final rows = [
    for (final entry in totals.entries)
      DailyClosingPersonTotal(
        name: entry.key,
        days: daysByPerson[entry.key]!.length,
        totalPaise: entry.value,
        dates: [...daysByPerson[entry.key]!]..sort(),
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return rows;
}

/// Recoverable, user-safe daily closing failures.
sealed class DailyClosingFailure implements Exception {
  const DailyClosingFailure();

  String get message;
}

/// Any closing amount that came through negative.
final class DailyClosingNegativeAmountFailure extends DailyClosingFailure {
  const DailyClosingNegativeAmountFailure();

  @override
  String get message => 'Closing amounts cannot be negative.';
}

/// Recording while the "All businesses" view is selected. A closing belongs
/// to exactly one business, so the owner must pick Cafe or Food Truck first.
final class DailyClosingBusinessScopeFailure extends DailyClosingFailure {
  const DailyClosingBusinessScopeFailure();

  @override
  String get message =>
      'Pick Cafe or Food Truck first — a closing belongs to one business.';
}

/// A cloud-backed closing write requires internet but the device is offline.
/// The record would not be committed everywhere, so the mutation is rejected
/// rather than silently kept device-local.
final class DailyClosingCloudUnavailableFailure extends DailyClosingFailure {
  const DailyClosingCloudUnavailableFailure();

  @override
  String get message =>
      'Internet connection required. Please check your connection and try again.';
}

/// A cloud-backed closing write/delete failed for a non-offline reason.
final class DailyClosingCloudWriteFailure extends DailyClosingFailure {
  const DailyClosingCloudWriteFailure();

  @override
  String get message => 'Could not sync with the cloud. Please try again.';
}
