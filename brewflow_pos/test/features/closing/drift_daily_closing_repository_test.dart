import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Repository Regression Test
///
/// Locks the local-first persistence contract and the amount-validation rules
/// for end-of-day closing records. Every record carries a UTC-midnight
/// business-day cookie so day/month comparisons are half-open and
/// timezone-independent. Negative amounts must always surface as
/// [DailyClosingNegativeAmountFailure] and never persist.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftDailyClosingRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftDailyClosingRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<DailyClosingRecord> record(
    DateTime businessDate, {
    int totalCashPaise = 1500000,
    int totalUpiPaise = 400000,
    int totalSalesPaise = 2000000,
    int totalExpensePaise = 100000,
    int cashLeftInBoxPaise = 50000,
    int cashTakenOutPaise = 20000,
  }) {
    return repository.recordDailyClosing(
      businessDate: businessDate,
      totalCashPaise: totalCashPaise,
      totalUpiPaise: totalUpiPaise,
      totalSalesPaise: totalSalesPaise,
      totalExpensePaise: totalExpensePaise,
      cashLeftInBoxPaise: cashLeftInBoxPaise,
      cashTakenOutPaise: cashTakenOutPaise,
    );
  }

  group('recordDailyClosing + closingsFor', () {
    test('persists a record and round-trips it back unchanged', () async {
      final saved = await record(DateTime.utc(2025, 7, 31));

      final records = await repository.closingsFor(
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );

      expect(records, hasLength(1));
      expect(records.single.id, saved.id);
      expect(records.single.businessDate, DateTime.utc(2025, 7, 31));
      expect(records.single.totalCashPaise, 1500000);
      expect(records.single.totalUpiPaise, 400000);
      expect(records.single.totalSalesPaise, 2000000);
      expect(records.single.totalExpensePaise, 100000);
      expect(records.single.cashLeftInBoxPaise, 50000);
      expect(records.single.cashTakenOutPaise, 20000);
    });

    test('returns records newest business day first within a range', () async {
      await record(DateTime.utc(2025, 7, 15));
      await record(DateTime.utc(2025, 7, 31));

      final records = await repository.closingsFor(
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );

      expect(records, hasLength(2));
      expect(records.first.businessDate, DateTime.utc(2025, 7, 31));
      expect(records.last.businessDate, DateTime.utc(2025, 7, 15));
    });

    test('honors the half-open date window', () async {
      await record(DateTime.utc(2025, 6, 10));
      await record(DateTime.utc(2025, 7, 10));
      await record(DateTime.utc(2025, 7, 20));

      final records = await repository.closingsFor(
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );

      expect(records.map((r) => r.businessDate), [
        DateTime.utc(2025, 7, 20),
        DateTime.utc(2025, 7, 10),
      ]);
    });
  });

  group('amount validation', () {
    test('rejects any negative amount with the typed failure', () async {
      await expectLater(
        repository.recordDailyClosing(
          businessDate: DateTime.utc(2025, 7, 31),
          totalCashPaise: -1,
          totalUpiPaise: 0,
          totalSalesPaise: 0,
          totalExpensePaise: 0,
          cashLeftInBoxPaise: 0,
          cashTakenOutPaise: 0,
        ),
        throwsA(isA<DailyClosingNegativeAmountFailure>()),
      );

      await expectLater(
        repository.recordDailyClosing(
          businessDate: DateTime.utc(2025, 7, 31),
          totalCashPaise: 0,
          totalUpiPaise: 0,
          totalSalesPaise: 0,
          totalExpensePaise: -5,
          cashLeftInBoxPaise: 0,
          cashTakenOutPaise: 0,
        ),
        throwsA(isA<DailyClosingNegativeAmountFailure>()),
      );
    });

    test('does not persist a rejected record', () async {
      try {
        await repository.recordDailyClosing(
          businessDate: DateTime.utc(2025, 7, 31),
          totalCashPaise: -50,
          totalUpiPaise: 0,
          totalSalesPaise: 0,
          totalExpensePaise: 0,
          cashLeftInBoxPaise: 0,
          cashTakenOutPaise: 0,
        );
        fail('Expected DailyClosingNegativeAmountFailure');
      } on DailyClosingNegativeAmountFailure {
        // Expected.
      }

      final records = await repository.closingsFor();
      expect(records, isEmpty);
    });
  });

  group('deleteDailyClosing', () {
    test('removes the record permanently', () async {
      final saved = await record(DateTime.utc(2025, 7, 31));

      await repository.deleteDailyClosing(saved.id);

      final records = await repository.closingsFor();
      expect(records, isEmpty);
    });
  });
}
