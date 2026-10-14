/// ---------------------------------------------------------------------------
/// BrewFlow POS — Management Report Domain Models
///
/// Read-only aggregation models for the date-range management report PDF.
/// Every value is computed by the report loader from existing repositories
/// (orders, expenses, staff payroll, daily closing); nothing here mutates
/// data and no repository rows leak past the loader boundary.
///
/// Money is always integer paise (see core/utils/money.dart); dates are local
/// calendar days. The report never invents figures — ranges with no records
/// render explicit zeros / empty states.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';

/// One staff row of the "Staff Salary Details" section. Hours and day counts
/// come from the attendance records in range (worked shifts only for hours
/// and present days, Leave rows for leave days — same rules as
/// [MonthlyPayrollSummary]); salary is the sum of the owner-entered daily
/// salary amounts; advance is the sum of advances paid in range; final
/// payable is salary − advance (same rule as payroll, no hourly rate).
final class ManagementStaffRow {
  const ManagementStaffRow({
    required this.name,
    required this.totalMinutes,
    required this.presentDays,
    required this.leaveDays,
    required this.salaryPaise,
    required this.advancePaise,
  });

  final String name;
  final int totalMinutes;

  /// Distinct business days with a worked shift in range.
  final int presentDays;

  /// Distinct business days marked Leave in range.
  final int leaveDays;
  final int salaryPaise;
  final int advancePaise;

  /// Final Payable Amount = Total Salary − Advance Amount. May legitimately
  /// be negative when advances exceed salary.
  int get payablePaise => salaryPaise - advancePaise;
}

/// One row of the expense ledger table. [date] is the local business day;
/// [paymentLabel] is 'Cash' / 'UPI' / 'Bank' / 'Not paid'.
final class ManagementExpenseRow {
  const ManagementExpenseRow({
    required this.date,
    required this.name,
    required this.amountPaise,
    required this.paymentLabel,
  });

  final DateTime date;
  final String name;
  final int amountPaise;
  final String paymentLabel;
}

/// One "cash taken from the box" aggregation row: a floor-summary grouping by
/// [name] (the staff member recorded as taking cash, or 'Not recorded').
final class ManagementTakenByRow {
  const ManagementTakenByRow({
    required this.name,
    required this.daysTaken,
    required this.totalPaise,
  });

  final String name;

  /// Distinct business days on which this person took cash out.
  final int daysTaken;
  final int totalPaise;
}

/// One business day's actual collection from its saved Daily Closing record.
/// [cashPaise]/[upiPaise] come ONLY from the closing for the same shop scope
/// + business date — never substituted from bills and never defaulted: days
/// without a closing carry [hasClosing] false with zero amounts so the
/// renderer shows "No closing recorded" instead of a misleading zero.
final class ManagementClosingCollectionRow {
  const ManagementClosingCollectionRow({
    required this.date,
    required this.hasClosing,
    required this.cashPaise,
    required this.upiPaise,
  });

  /// Local business day.
  final DateTime date;
  final bool hasClosing;
  final int cashPaise;
  final int upiPaise;

  /// Daily Closing collection total: cash + UPI.
  int get totalPaise => cashPaise + upiPaise;
}

/// One row of the "Customer Outstanding" section: a customer's balance as of
/// the report's To Date. [outstandingPaise] is always > 0; [phone] renders as
/// a dash when the profile has none.
final class ManagementCustomerOutstandingRow {
  const ManagementCustomerOutstandingRow({
    required this.name,
    this.phone,
    required this.outstandingPaise,
  });

  final String name;
  final String? phone;
  final int outstandingPaise;
}

/// Everything the management report renders, computed for one inclusive
/// local date range. Pure read-only value; the loader is its only source.
final class ManagementReportData {
  const ManagementReportData({
    required this.fromLocal,
    required this.toLocal,
    required this.shopName,
    required this.businessLabel,
    required this.salesTotalPaise,
    required this.salesCashPaise,
    required this.salesUpiPaise,
    required this.expenseRows,
    required this.expenseTotalPaise,
    required this.expenseCashPaise,
    required this.expenseUpiPaise,
    required this.expenseBankPaise,
    required this.expenseNotPaidPaise,
    required this.customerOutstandingRows,
    required this.customerOutstandingTotalPaise,
    required this.staffRows,
    required this.closings,
    required this.takenByRows,
    required this.closingCollections,
  });

  /// Inclusive range endpoints as local calendar days.
  final DateTime fromLocal;
  final DateTime toLocal;

  final String shopName;

  /// 'Cafe' / 'Food Truck' / 'All Businesses' — the read scope that produced
  /// the figures (respects the current business context).
  final String businessLabel;

  /// Sales Summary: total of non-voided counter sales (credit included) and
  /// the collected cash / UPI amounts in the range.
  final int salesTotalPaise;
  final int salesCashPaise;
  final int salesUpiPaise;

  /// Expense Summary: the full ledger, oldest day first, plus the totals the
  /// report footer summarizes.
  final List<ManagementExpenseRow> expenseRows;
  final int expenseTotalPaise;
  final int expenseCashPaise;
  final int expenseUpiPaise;
  final int expenseBankPaise;
  final int expenseNotPaidPaise;

  /// Customer Outstanding: balances as of the report's To Date, alphabetical
  /// by customer name; only customers still owing > 0 at that date.
  final List<ManagementCustomerOutstandingRow> customerOutstandingRows;
  final int customerOutstandingTotalPaise;

  /// Staff Salary Details: one row per staff member with any attendance,
  /// daily salary or advance in the range (alphabetical by name).
  final List<ManagementStaffRow> staffRows;

  /// Daily Closing Summary records, oldest business day first.
  final List<DailyClosingRecord> closings;

  /// Cash-taken-out grouped by who took it (alphabetical by name).
  final List<ManagementTakenByRow> takenByRows;

  /// Actual Collection (Daily Closing): one row per business day in range,
  /// oldest first. A day's cash/UPI come only from the saved Daily Closing
  /// record for the same shop scope + business date.
  final List<ManagementClosingCollectionRow> closingCollections;

  /// Collection cash summed over days WITH a saved closing only.
  int get closingCashPaise => closingCollections.fold(
    0,
    (sum, row) => sum + (row.hasClosing ? row.cashPaise : 0),
  );

  /// Collection UPI summed over days WITH a saved closing only.
  int get closingUpiPaise => closingCollections.fold(
    0,
    (sum, row) => sum + (row.hasClosing ? row.upiPaise : 0),
  );

  /// Daily Closing collection total: cash + UPI.
  int get closingCollectionTotalPaise => closingCashPaise + closingUpiPaise;

  /// Whether at least one day in range has a saved closing.
  bool get hasAnyClosing => closingCollections.any((row) => row.hasClosing);

  /// Days in range without a saved closing (rendered honestly, never zeroed).
  int get daysMissingClosing =>
      closingCollections.where((row) => !row.hasClosing).length;

  /// Whether any real record exists anywhere in the report.
  bool get anyRecords =>
      salesTotalPaise > 0 ||
      expenseRows.isNotEmpty ||
      customerOutstandingRows.isNotEmpty ||
      staffRows.isNotEmpty ||
      closings.isNotEmpty;
}

/// Base for all management-report failures. Every subtype carries a
/// user-safe message; details are logged, never shown.
sealed class ManagementReportFailure implements Exception {
  const ManagementReportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// End date before the start date of a requested range.
final class InvalidManagementReportRangeFailure
    extends ManagementReportFailure {
  const InvalidManagementReportRangeFailure()
    : super('Pick an end date after the start date.');
}

/// Unexpected error while building the report; details are logged.
final class UnexpectedManagementReportFailure extends ManagementReportFailure {
  const UnexpectedManagementReportFailure([
    super.message = 'Could not build the report right now.',
  ]);
}
