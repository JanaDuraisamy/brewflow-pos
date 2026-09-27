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
