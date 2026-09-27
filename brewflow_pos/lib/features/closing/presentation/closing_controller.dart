import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/closing/data/daily_closing_cloud_gateway.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_repository.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing (Riverpod)
///
/// Supplies the saved closing records (scoped to the selected business
/// context) and the owner mutation to record or delete one. Records are
/// reviewable; deleting a record is the only removal path.
///
/// [closingDayTotalsProvider] auto-populates a date from existing data:
/// cash/UPI sums come from completed paid sales for that exact business day,
/// expenses from the expense data for the same day, and
/// Total Sales = Total Cash + Total UPI. The page may override the
/// calculated total before saving — no other reconciliation is invented.
/// ---------------------------------------------------------------------------

/// Cloud gateway provider (null in tests where Supabase is not initialized).
final dailyClosingCloudGatewayProvider = Provider<DailyClosingCloudGateway?>((
  ref,
) {
  try {
    final client = Supabase.instance.client;
    return SupabaseDailyClosingGateway(client);
  } catch (_) {
    return null;
  }
});

/// Owns the single daily-closing repository for the app scope
/// (cloud-authoritative when the gateway is present, local mirror fallback
/// offline; override with a fake in tests).
final dailyClosingRepositoryProvider = Provider<DailyClosingRepository>((ref) {
  return DriftDailyClosingRepository(
    ref.watch(appDatabaseProvider),
    cloudGateway: ref.watch(dailyClosingCloudGatewayProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
  );
});

/// Shop ids for the current business selection (Cafe/Food Truck isolation).
final closingShopScopeProvider = FutureProvider<List<String>?>((ref) async {
  final context = ref.watch(businessSwitcherProvider);
  try {
    return await ref
        .read(businessSwitcherProvider.notifier)
        .shopIdsForRead(context);
  } on Object {
    return null;
  }
});

/// All saved closing records for the current scope, newest business day
/// first.
final dailyClosingsProvider =
    AsyncNotifierProvider<DailyClosingsController, List<DailyClosingRecord>>(
      DailyClosingsController.new,
    );

final class DailyClosingsController
    extends AsyncNotifier<List<DailyClosingRecord>> {
  @override
  Future<List<DailyClosingRecord>> build() async {
    final scope = await ref.watch(closingShopScopeProvider.future);
    return ref
        .watch(dailyClosingRepositoryProvider)
        .closingsFor(shopIds: scope);
  }

  Future<void> record({
    required DateTime businessDate,
    required int totalCashPaise,
    required int totalUpiPaise,
    required int totalSalesPaise,
    required int totalExpensePaise,
    required int cashLeftInBoxPaise,
    required int cashTakenOutPaise,
    String? takenOutBy,
    String? talliedBy,
    String? note,
  }) => _mutate((repository) async {
    final context = ref.read(businessSwitcherProvider);
    if (context == BusinessContext.all) {
      throw const DailyClosingBusinessScopeFailure();
    }
    final shopId = await ref
        .read(businessSwitcherProvider.notifier)
        .requireWritableShopId();
    await repository.recordDailyClosing(
      businessDate: businessDate,
      totalCashPaise: totalCashPaise,
      totalUpiPaise: totalUpiPaise,
      totalSalesPaise: totalSalesPaise,
      totalExpensePaise: totalExpensePaise,
      cashLeftInBoxPaise: cashLeftInBoxPaise,
      cashTakenOutPaise: cashTakenOutPaise,
      shopId: shopId,
      takenOutBy: takenOutBy,
      talliedBy: talliedBy,
      note: note,
    );
  });

  /// Owner-only removal of a recorded closing. The repository deletes in the
  /// cloud FIRST (so other devices never re-pull it), then removes the local
  /// mirror row. Guarded here as well as in the page's action.
  Future<void> remove(String id) {
    requireOwner(ref);
    return _mutate((repository) async => repository.deleteDailyClosing(id));
  }

  Future<void> _mutate(
    Future<void> Function(DailyClosingRepository repository) action,
  ) async {
    state = const AsyncLoading();
    try {
      final repository = ref.read(dailyClosingRepositoryProvider);
      await action(repository);
      ref.invalidateSelf();
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

/// Auto-populated day totals for one business-day cookie.
///
/// Cash/UPI sum paid, non-voided sales for that exact day; expenses sum the
/// expense data for the same day. Total Sales = Cash + UPI (the page may
/// override it before saving).
final class ClosingDayTotals {
  const ClosingDayTotals({
    required this.totalCashPaise,
    required this.totalUpiPaise,
    required this.totalExpensePaise,
  });

  final int totalCashPaise;
  final int totalUpiPaise;
  final int totalExpensePaise;

  int get totalSalesPaise => totalCashPaise + totalUpiPaise;
}

final closingDayTotalsProvider =
    FutureProvider.family<ClosingDayTotals, DateTime>((
      ref,
      businessDate,
    ) async {
      final scope = await ref.watch(closingShopScopeProvider.future);
      final dayStart = DateTime.utc(
        businessDate.year,
        businessDate.month,
        businessDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));

      var cash = 0;
      var upi = 0;
      try {
        final orders = ref.watch(ordersRepositoryProvider);
        var offset = 0;
        const page = 200;
        while (true) {
          final result = await orders.orders(
            filter: OrdersFilter(fromUtc: dayStart, toUtc: dayEnd),
            limit: page,
            offset: offset,
            shopIds: scope,
          );
          for (final order in result.items) {
            if (order.isVoided) continue;
            if (order.paymentStatus != PaymentStatus.paid) continue;
            switch (order.paymentMethod) {
              case PaymentMethod.cash:
                cash += order.totalPaise;
              case PaymentMethod.upi:
                upi += order.totalPaise;
              case PaymentMethod.bank:
              case null:
                break;
            }
          }
          if (!result.hasMore) break;
          offset += page;
        }
      } on Object {
        // Best-effort auto-population: a sales read failure yields zeros
        // rather than blocking the close. The owner can still type values.
        cash = 0;
        upi = 0;
      }

      var expenses = 0;
      try {
        final repository = ref.watch(expensesRepositoryProvider);
        final rows = await repository.expenses(
          fromUtc: dayStart,
          toUtc: dayEnd,
          shopIds: scope,
        );
        expenses = rows.fold(0, (sum, row) => sum + row.amountPaise);
      } on Object {
        expenses = 0;
      }

      return ClosingDayTotals(
        totalCashPaise: cash,
        totalUpiPaise: upi,
        totalExpensePaise: expenses,
      );
    });
