import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_daily_closing_cloud_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Cloud Regression
///
/// Locks the cloud-authoritative contract: records save/load with every
/// field, negative amounts are rejected, reads stay scoped to the requested
/// businesses (Cafe/Food Truck isolation), writes push to the cloud, reads
/// pull first, failures fall back to the local mirror, and a second device
/// (fresh database + same cloud) sees the first device's closings.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late FakeDailyClosingCloudGateway cloud;
  late DriftDailyClosingRepository repository;

  const cafeShop = 'shop-cafe';
  const truckShop = 'shop-truck';

  Future<void> seedShops(AppDatabase db) async {
    for (final shop in [cafeShop, truckShop]) {
      final existing = await (db.select(
        db.shops,
      )..where((t) => t.id.equals(shop))).getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.shops)
            .insert(ShopsCompanion.insert(id: Value(shop), name: shop));
      }
    }
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedShops(database);
    cloud = FakeDailyClosingCloudGateway();
    repository = DriftDailyClosingRepository(database, cloudGateway: cloud);
  });

  tearDown(() async {
    await database.close();
  });

  Future<DailyClosingRecord> record(
    DateTime businessDate, {
    String? shopId,
    int totalCashPaise = 800000,
    int totalUpiPaise = 1200000,
    int totalSalesPaise = 2000000,
    int totalExpensePaise = 100000,
  }) => repository.recordDailyClosing(
    businessDate: businessDate,
    totalCashPaise: totalCashPaise,
    totalUpiPaise: totalUpiPaise,
    totalSalesPaise: totalSalesPaise,
    totalExpensePaise: totalExpensePaise,
    cashLeftInBoxPaise: 50000,
    cashTakenOutPaise: 20000,
    shopId: shopId,
    takenOutBy: 'Owner',
    talliedBy: 'Manager',
  );

  group('save/load', () {
    test('persists a record and round-trips every field', () async {
      final saved = await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);

      final records = await repository.closingsFor(
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(records, hasLength(1));
      expect(records.single.id, saved.id);
      expect(records.single.businessDate, DateTime.utc(2025, 7, 31));
      expect(records.single.totalCashPaise, 800000);
      expect(records.single.totalUpiPaise, 1200000);
      expect(records.single.totalSalesPaise, 2000000);
      expect(records.single.totalExpensePaise, 100000);
      expect(records.single.cashLeftInBoxPaise, 50000);
      expect(records.single.cashTakenOutPaise, 20000);
      expect(records.single.takenOutBy, 'Owner');
      expect(records.single.talliedBy, 'Manager');
    });

    test('opening the same date loads the saved closing record', () async {
      await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);
      final records = await repository.closingsFor(
        startDate: DateTime.utc(2025, 7, 31),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(records, hasLength(1));
      expect(records.single.totalSalesPaise, 2000000);
    });

    test('negative amounts are rejected and never persist', () async {
      expect(
        repository.recordDailyClosing(
          businessDate: DateTime.utc(2025, 7, 31),
          totalCashPaise: -1,
          totalUpiPaise: 0,
          totalSalesPaise: 0,
          totalExpensePaise: 0,
          cashLeftInBoxPaise: 0,
          cashTakenOutPaise: 0,
          shopId: cafeShop,
        ),
        throwsA(isA<DailyClosingNegativeAmountFailure>()),
      );
      expect(await repository.closingsFor(shopIds: [cafeShop]), isEmpty);
    });
  });

  group('business isolation', () {
    test('reads scoped to one shop hide the other shop closings', () async {
      await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);
      await record(DateTime.utc(2025, 7, 31), shopId: truckShop);

      final cafe = await repository.closingsFor(shopIds: [cafeShop]);
      expect(cafe, hasLength(1));
      expect(cafe.single.totalCashPaise, 800000);

      final truck = await repository.closingsFor(shopIds: [truckShop]);
      expect(truck, hasLength(1));

      final both = await repository.closingsFor(shopIds: [cafeShop, truckShop]);
      expect(both, hasLength(2));
    });
  });

  group('cloud behavior', () {
    test('writes push the record to the cloud under its shop', () async {
      await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);
      expect(cloud.storedClosings, hasLength(1));
      expect(cloud.closingShopIds.single, cafeShop);
      expect(cloud.storedClosings.single.totalSalesPaise, 2000000);
    });

    test(
      'a second device loads the first device closings from cloud',
      () async {
        await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);

        final device2 = AppDatabase(NativeDatabase.memory());
        addTearDown(device2.close);
        await seedShops(device2);
        final repo2 = DriftDailyClosingRepository(device2, cloudGateway: cloud);

        final records = await repo2.closingsFor(shopIds: [cafeShop]);
        expect(records, hasLength(1));
        expect(records.single.totalCashPaise, 800000);
        expect(records.single.totalUpiPaise, 1200000);
      },
    );

    test('cloud failure falls back to the local mirror', () async {
      await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);
      cloud.failNext = true;
      final records = await repository.closingsFor(shopIds: [cafeShop]);
      expect(records, hasLength(1));
    });

    test('deletes remove the record locally and in the cloud', () async {
      final saved = await record(DateTime.utc(2025, 7, 31), shopId: cafeShop);
      await repository.deleteDailyClosing(saved.id);
      expect(await repository.closingsFor(shopIds: [cafeShop]), isEmpty);
      expect(cloud.storedClosings, isEmpty);
    });
  });
}
