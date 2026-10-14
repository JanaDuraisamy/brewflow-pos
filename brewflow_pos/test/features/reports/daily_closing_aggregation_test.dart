import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/domain/reports_models.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_daily_closing_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/test_providers.dart';

DailyClosingRecord _record(
  String id,
  DateTime businessDate, {
  int taken = 0,
  String? takenOutBy,
  String? talliedBy,
}) => DailyClosingRecord(
  id: id,
  businessDate: businessDate,
  totalCashPaise: 100000,
  totalUpiPaise: 50000,
  totalSalesPaise: 150000,
  totalExpensePaise: 0,
  cashLeftInBoxPaise: 100000 - taken,
  cashTakenOutPaise: taken,
  takenOutBy: takenOutBy,
  talliedBy: talliedBy,
  note: null,
  createdAt: businessDate.add(const Duration(hours: 19)),
);

ProviderContainer _container({FakeDailyClosingRepository? closings}) {
  final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      dailyClosingRepositoryProvider.overrideWithValue(
        closings ?? FakeDailyClosingRepository(),
      ),
      ...businessScopeOverrides(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ReportsSnapshot> _load(ProviderContainer container) =>
    container.read(reportsControllerProvider.future);

void main() {
  group('aggregateDailyClosingTakenBy', () {
    test('groups by taker with days and totals, alphabetical', () {
      final rows = aggregateDailyClosingTakenBy([
        _record(
          'c1',
          DateTime.utc(2026, 2, 14),
          taken: 30000,
          takenOutBy: 'Ravi',
        ),
        _record(
          'c2',
          DateTime.utc(2026, 2, 20),
          taken: 10000,
          takenOutBy: 'Ravi',
        ),
        _record('c3', DateTime.utc(2026, 2, 25), taken: 5000),
      ]);

      expect(rows, hasLength(2));
      expect(rows.first.name, 'Not recorded');
      expect(rows.first.days, 1);
      expect(rows.first.totalPaise, 5000);
      expect(rows.last.name, 'Ravi');
      expect(rows.last.days, 2);
      expect(rows.last.totalPaise, 40000);
      expect(rows.last.dates, [
        DateTime.utc(2026, 2, 14),
        DateTime.utc(2026, 2, 20),
      ]);
    });

    test('ignores closings with nothing taken and handles empty safely', () {
      expect(aggregateDailyClosingTakenBy(const []), isEmpty);
      final rows = aggregateDailyClosingTakenBy([
        _record('c1', DateTime.utc(2026, 2, 14), taken: 0, takenOutBy: 'Ravi'),
      ]);
      expect(rows, isEmpty);
    });

    test('same-day duplicates count as one day', () {
      final day = DateTime.utc(2026, 2, 14);
      final rows = aggregateDailyClosingTakenBy([
        _record('c1', day, taken: 10000, takenOutBy: 'Ravi'),
        _record('c2', day, taken: 5000, takenOutBy: 'Ravi'),
      ]);
      expect(rows.single.days, 1);
      expect(rows.single.totalPaise, 15000);
    });
  });

  group('aggregateDailyClosingTalliedBy', () {
    test('groups by tally person with days and taken totals', () {
      final rows = aggregateDailyClosingTalliedBy([
        _record(
          'c1',
          DateTime.utc(2026, 2, 14),
          taken: 30000,
          talliedBy: 'Owner',
        ),
        _record('c2', DateTime.utc(2026, 2, 15), taken: 0, talliedBy: 'Owner'),
        _record('c3', DateTime.utc(2026, 2, 16), taken: 5000, talliedBy: null),
      ]);

      expect(rows, hasLength(2));
      expect(rows.first.name, 'Not recorded');
      expect(rows.first.days, 1);
      expect(rows.first.totalPaise, 5000);
      expect(rows.last.name, 'Owner');
      expect(rows.last.days, 2);
      // Total taken on the days Owner tallied (30000 + 0).
      expect(rows.last.totalPaise, 30000);
    });

    test('empty input yields empty tally', () {
      expect(aggregateDailyClosingTalliedBy(const []), isEmpty);
    });
  });

  group('reports controller daily closing range', () {
    test('a 7-day selection aggregates only those 7 days', () async {
      final closings = FakeDailyClosingRepository();
      final now = DateTime.now().toUtc();
      DateTime cookie(int daysAgo) {
        final local = now.toLocal().subtract(Duration(days: daysAgo));
        return DateTime.utc(local.year, local.month, local.day);
      }

      closings.seed(
        'in-1',
        businessDate: cookie(1),
        totalCashPaise: 100000,
        totalUpiPaise: 0,
        totalSalesPaise: 100000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 80000,
        cashTakenOutPaise: 20000,
        takenOutBy: 'Ravi',
        talliedBy: 'Owner',
      );
      closings.seed(
        'in-2',
        businessDate: cookie(5),
        totalCashPaise: 50000,
        totalUpiPaise: 0,
        totalSalesPaise: 50000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 40000,
        cashTakenOutPaise: 10000,
        takenOutBy: 'Meena',
        talliedBy: 'Owner',
      );
      closings.seed(
        'out-1',
        businessDate: cookie(20),
        totalCashPaise: 99990000,
        totalUpiPaise: 0,
        totalSalesPaise: 99990000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 0,
        cashTakenOutPaise: 99990000,
        takenOutBy: 'Old',
        talliedBy: 'Old',
      );

      final container = _container(closings: closings);
      container
          .read(reportsRangeProvider.notifier)
          .setPreset(OrdersDatePreset.last7);

      final snapshot = await _load(container);

      expect(snapshot.dailyClosings.map((c) => c.id).toList(), [
        'in-2',
        'in-1',
      ]);
      expect(snapshot.totalCashTakenPaise, 30000);
      expect(snapshot.takenBy.map((r) => r.name).toList(), ['Meena', 'Ravi']);
      expect(
        snapshot.takenBy.firstWhere((r) => r.name == 'Ravi').totalPaise,
        20000,
      );
      expect(
        snapshot.takenBy.firstWhere((r) => r.name == 'Meena').totalPaise,
        10000,
      );
      // Both in-range days were tallied by Owner: 2 days, 30000 taken.
      expect(snapshot.talliedBy.single.name, 'Owner');
      expect(snapshot.talliedBy.single.days, 2);
      expect(snapshot.talliedBy.single.totalPaise, 30000);
    });

    test('empty range yields honest empty closing state', () async {
      final container = _container();
      final snapshot = await _load(container);

      expect(snapshot.dailyClosings, isEmpty);
      expect(snapshot.takenBy, isEmpty);
      expect(snapshot.talliedBy, isEmpty);
      expect(snapshot.totalCashTakenPaise, 0);
    });

    test('today preset keeps only today’s closing', () async {
      final closings = FakeDailyClosingRepository();
      final now = DateTime.now().toUtc();
      DateTime cookie(int daysAgo) {
        final local = now.toLocal().subtract(Duration(days: daysAgo));
        return DateTime.utc(local.year, local.month, local.day);
      }

      closings.seed(
        'today',
        businessDate: cookie(0),
        totalCashPaise: 10000,
        totalUpiPaise: 0,
        totalSalesPaise: 10000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 5000,
        cashTakenOutPaise: 5000,
        takenOutBy: 'Ravi',
        talliedBy: 'Owner',
      );
      closings.seed(
        'yesterday',
        businessDate: cookie(1),
        totalCashPaise: 20000,
        totalUpiPaise: 0,
        totalSalesPaise: 20000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 10000,
        cashTakenOutPaise: 10000,
        takenOutBy: 'Ravi',
        talliedBy: 'Owner',
      );

      final container = _container(closings: closings);
      // Default range is Today.
      final snapshot = await _load(container);

      expect(snapshot.dailyClosings.map((c) => c.id).toList(), ['today']);
      expect(snapshot.totalCashTakenPaise, 5000);
    });
  });
}
