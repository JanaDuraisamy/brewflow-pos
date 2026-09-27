import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/domain/management_report_models.dart';
import 'package:brewflow_pos/features/settings/domain/settings_repository.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_repository.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/payroll_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Management Report Loader
///
/// Pure read-side aggregation for the date-range report. Pulls from the same
/// repositories the live screens use (orders, expenses, staff payroll, daily
/// closing, settings) under the active business context, so the PDF always
/// matches what the owner sees on screen.
///
/// The range is an inclusive pair of LOCAL calendar days. Everything crosses
/// repository boundaries in the conventions each repository expects (UTC
/// instants for orders/expenses, UTC-midnight day cookies for payroll and
/// closings). Rows are sorted deterministically here because section order is
/// a report concern, not a repository one.
///
/// The loader is a plain class the caller constructs with its repositories
/// (widgets use [ManagementReportLoader.from], tests inject fakes), so it is
/// trivially unit-testable and never owns providers.
///
/// Failures surface as sealed [ManagementReportFailure] values or rethrow
/// their typed repository failure — both display-safe.
/// ---------------------------------------------------------------------------

final class ManagementReportLoader {
  ManagementReportLoader({
    required this.orders,
    required this.expenses,
    required this.staff,
    required this.payroll,
    required this.closings,
    required this.settings,
    required this.ledger,
    required this.readShopIds,
    required this.businessLabel,
  });

  static const String tag = 'ManagementReport';

  /// Sales are paged; this caps how many pages we may read to keep the report
  /// bounded even for huge histories.
  static const int _pageSize = 500;
  static const int _maxPages = 10;

  final OrdersRepository orders;
  final ExpensesRepository expenses;
  final StaffRepository staff;
  final StaffPayrollRepository payroll;
  final DailyClosingRepository closings;
  final SettingsRepository settings;
  final CustomerLedgerRepository ledger;

  /// Resolves the current read scope: shop ids for the active business
  /// context. Never used as a write target.
  final Future<List<String>> Function() readShopIds;

  /// Display label of the active business context ('Cafe', 'Food Truck',
  /// 'All Businesses') — rendered in the report header.
  final String businessLabel;

  /// Builds a loader from the widget read scope: reads the same providers the
  /// rest of the UI uses, already scoped to the current business context.
  factory ManagementReportLoader.from(WidgetRef ref) => ManagementReportLoader(
    orders: ref.read(ordersRepositoryProvider),
    expenses: ref.read(expensesRepositoryProvider),
    staff: ref.read(staffRepositoryProvider),
    payroll: ref.read(staffPayrollRepositoryProvider),
    closings: ref.read(dailyClosingRepositoryProvider),
    settings: ref.read(settingsRepositoryProvider),
    ledger: ref.read(customerLedgerRepositoryProvider),
    businessLabel: ref.read(businessSwitcherProvider).label,
    readShopIds: () async => ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(ref.read(businessSwitcherProvider)),
  );

  /// Aggregates everything for the inclusive range [fromLocal]..[toLocal] in
  /// one immutable [ManagementReportData]. Throws
  /// [InvalidManagementReportRangeFailure] when the range is backwards, a
  /// typed repository failure when a data source fails, or
  /// [UnexpectedManagementReportFailure] for anything else.
  Future<ManagementReportData> load({
    required DateTime fromLocal,
    required DateTime toLocal,
  }) async {
    final fromDay = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);
    final toDay = DateTime(toLocal.year, toLocal.month, toLocal.day);
    if (toDay.isBefore(fromDay)) {
      throw const InvalidManagementReportRangeFailure();
    }
    final fromUtc = fromDay.toUtc();
    final toUtc = _endOfDayUtc(toDay);

    // Payroll and closings compare UTC-midnight day cookies; the upper bound
    // is exclusive, so the "end" cookie is the day AFTER the range.
    final startDay = fromDay.toCookie();
    final endExclusive = toDay.toCookie().add(const Duration(days: 1));

    try {
      final shopIds = await readShopIds();
      final scopedShopIds = shopIds.isEmpty ? null : shopIds;
      final staffShopId = shopIds.isEmpty ? null : shopIds.first;

      final shopSettings = await settings.load();
      final shopName = _shopNameOf(
        shopSettings.shopName,
        shopSettings.appDisplayName,
      );

      // ---- Sales Summary ----------------------------------------------------
      var salesTotalPaise = 0;
      var salesCashPaise = 0;
      var salesUpiPaise = 0;
      var offset = 0;
      var hasMore = true;
      while (hasMore && offset < _maxPages * _pageSize) {
        final page = await orders.orders(
          filter: OrdersFilter(fromUtc: fromUtc, toUtc: toUtc),
          limit: _pageSize,
          offset: offset,
          shopIds: scopedShopIds,
        );
        for (final order in page.items) {
          if (order.isVoided) continue;
          salesTotalPaise += order.totalPaise;
          if (order.paymentStatus != PaymentStatus.paid) continue;
          switch (order.paymentMethod) {
            case PaymentMethod.cash:
              salesCashPaise += order.totalPaise;
            case PaymentMethod.upi:
              salesUpiPaise += order.totalPaise;
            case PaymentMethod.bank:
            case null:
              break;
          }
        }
        hasMore = page.hasMore;
        offset += _pageSize;
      }

      // ---- Customer Outstanding as of the To Date ----------------------------
      // Not a range sum: the ledger derives each customer's balance from the
      // full open-bill history, so bills created before the From date still
      // count, and only sales created on/before the To date and payments
      // recorded on/before it affect the snapshot.
      final outstandingRows = await ledger.outstandingAsOf(
        toUtc: toUtc,
        shopIds: scopedShopIds,
      );
      var customerOutstandingTotalPaise = 0;
      final customerOutstandingRows = <ManagementCustomerOutstandingRow>[];
      for (final entry in outstandingRows) {
        customerOutstandingTotalPaise += entry.outstandingPaise;
        customerOutstandingRows.add(
          ManagementCustomerOutstandingRow(
            name: entry.customerName,
            phone: entry.phone,
            outstandingPaise: entry.outstandingPaise,
          ),
        );
      }

      // ---- Expense Summary --------------------------------------------------
      final expenseList = await expenses.expenses(
        fromUtc: fromUtc,
        toUtc: toUtc,
        status: ExpenseStatusFilter.active,
        shopIds: scopedShopIds,
      );
      var expenseTotalPaise = 0;
      var expenseCashPaise = 0;
      var expenseUpiPaise = 0;
      var expenseBankPaise = 0;
      var expenseNotPaidPaise = 0;
      final expenseRows = <ManagementExpenseRow>[];
      for (final expense in expenseList) {
        expenseTotalPaise += expense.amountPaise;
        final paid = expense.paymentStatus == ExpensePaymentStatus.paid;
        if (paid) {
          switch (expense.paymentMethod) {
            case PaymentMethod.cash:
              expenseCashPaise += expense.amountPaise;
            case PaymentMethod.upi:
              expenseUpiPaise += expense.amountPaise;
            case PaymentMethod.bank:
              expenseBankPaise += expense.amountPaise;
          }
        } else {
          expenseNotPaidPaise += expense.amountPaise;
        }
        expenseRows.add(
          ManagementExpenseRow(
            date: _localDay(expense.expenseDate),
            name: expense.name.trim(),
            amountPaise: expense.amountPaise,
            paymentLabel: paid
                ? paymentMethodLabel(expense.paymentMethod)
                : 'Not paid',
          ),
        );
      }
      expenseRows.sort(
        (a, b) => a.date.compareTo(b.date) != 0
            ? a.date.compareTo(b.date)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      // ---- Staff Salary Details ---------------------------------------------
      final staffRows = <ManagementStaffRow>[];
      final members = await staff.staffMembers(shopId: staffShopId);
      for (final member in members) {
        final memberShopIds = member.shopId == null
            ? scopedShopIds
            : <String>[member.shopId!];
        final attendance = await payroll.attendanceFor(
          staffUserId: member.id,
          startDate: startDay,
          endExclusiveDate: endExclusive,
          shopIds: memberShopIds,
        );
        final dailySalaries = await payroll.dailySalariesFor(
          staffUserId: member.id,
          startDate: startDay,
          endExclusiveDate: endExclusive,
          shopIds: memberShopIds,
        );
        final advances = await payroll.advancesFor(
          staffUserId: member.id,
          startDate: startDay,
          endExclusiveDate: endExclusive,
          shopIds: memberShopIds,
        );
        if (attendance.isEmpty && dailySalaries.isEmpty && advances.isEmpty) {
          continue;
        }
        final totalMinutes = attendance.fold(
          0,
          (sum, shift) => sum + shift.workedMinutes,
        );
        final salaryPaise = dailySalaries.fold(
          0,
          (sum, day) => sum + day.salaryPaise,
        );
        final advancePaise = advances.fold(
          0,
          (sum, advance) => sum + advance.amountPaise,
        );
        staffRows.add(
          ManagementStaffRow(
            name: _displayNameOf(member),
            totalMinutes: totalMinutes,
            salaryPaise: salaryPaise,
            advancePaise: advancePaise,
          ),
        );
      }
      staffRows.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      // ---- Daily Closing Summary ---------------------------------------------
      final closingList = await closings.closingsFor(
        startDate: startDay,
        endExclusiveDate: endExclusive,
        shopIds: scopedShopIds,
      );
      final ascendingClosings = [...closingList]
        ..sort((a, b) => a.businessDate.compareTo(b.businessDate));

      final takenByPaise = <String, int>{};
      final takenDaysByPerson = <String, Set<DateTime>>{};
      for (final closing in ascendingClosings) {
        if (closing.cashTakenOutPaise <= 0) continue;
        final key = _takenByLabel(closing.takenOutBy);
        takenByPaise.update(
          key,
          (total) => total + closing.cashTakenOutPaise,
          ifAbsent: () => closing.cashTakenOutPaise,
        );
        takenDaysByPerson
            .putIfAbsent(key, () => <DateTime>{})
            .add(closing.businessDate);
      }
      final takenByRows = [
        for (final entry in takenByPaise.entries)
          ManagementTakenByRow(
            name: entry.key,
            daysTaken: takenDaysByPerson[entry.key]!.length,
            totalPaise: entry.value,
          ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      return ManagementReportData(
        fromLocal: fromDay,
        toLocal: toDay,
        shopName: shopName,
        businessLabel: businessLabel,
        salesTotalPaise: salesTotalPaise,
        salesCashPaise: salesCashPaise,
        salesUpiPaise: salesUpiPaise,
        expenseRows: expenseRows,
        expenseTotalPaise: expenseTotalPaise,
        expenseCashPaise: expenseCashPaise,
        expenseUpiPaise: expenseUpiPaise,
        expenseBankPaise: expenseBankPaise,
        expenseNotPaidPaise: expenseNotPaidPaise,
        customerOutstandingRows: customerOutstandingRows,
        customerOutstandingTotalPaise: customerOutstandingTotalPaise,
        staffRows: staffRows,
        closings: ascendingClosings,
        takenByRows: takenByRows,
      );
    } on CustomerLedgerFailure {
      rethrow;
    } on DailyClosingFailure {
      rethrow;
    } on ExpensesFailure {
      rethrow;
    } on OrdersFailure {
      rethrow;
    } on SettingsFailure {
      rethrow;
    } on StaffFailure {
      rethrow;
    } on StaffPayrollFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Could not build management report',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedManagementReportFailure();
    }
  }

  String _shopNameOf(String shopName, String appDisplayName) {
    final trimmed = shopName.trim();
    return trimmed.isEmpty ? appDisplayName : trimmed;
  }

  String _displayNameOf(UserProfile member) {
    final name = member.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = member.email.trim();
    if (email.isNotEmpty) return email;
    return member.id;
  }

  String _takenByLabel(String? takenOutBy) {
    final name = takenOutBy?.trim();
    return (name == null || name.isEmpty) ? 'Not recorded' : name;
  }
}

extension on DateTime {
  /// UTC-midnight local business-day cookie.
  DateTime toCookie() => DateTime.utc(year, month, day);
}

/// UTC instant just before the end of the day after [localDay] (inclusive
/// upper bound for UTC-instant filters).
DateTime _endOfDayUtc(DateTime localDay) => DateTime.utc(
  localDay.year,
  localDay.month,
  localDay.day,
).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));

/// A UTC instant normalized to its local calendar day, midnight.
DateTime _localDay(DateTime utcInstant) {
  final local = utcInstant.toLocal();
  return DateTime(local.year, local.month, local.day);
}
