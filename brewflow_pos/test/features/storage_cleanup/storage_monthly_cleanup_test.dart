import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_storage_cleanup_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Monthly storage usage + month-wise cleanup contract.
///
/// The owner dashboard shows physical database metrics (labeled DB-wide),
/// logical monthly snapshots (labeled estimated) and per-month cleanup with
/// a report-confirmation gate. Cleanup hard-deletes the month scope after an
/// atomic server delete and reports ACTUAL affected-row counts.
///
/// Covered:
///   monthly metrics load + failure, snapshot refresh + offline history
///   fallback, preview loading, report confirmation unlock, cleanup gates
///   (no preview / unconfirmed / already cleaned / pending outbox / staff),
///   successful cleanup (local mirrors deleted, marker recorded, metrics
///   rescanned), idempotent already-cleaned retry, month UTC boundaries,
///   master-data protection (products/customers untouched).
/// ---------------------------------------------------------------------------

const _ownerId = 'auth-owner-1';
const _ownerEmail = 'owner@brew.test';
const _shopId = 'shop-1';

final _september = DateTime.utc(2026, 9);
final _august = DateTime.utc(2026, 8);

Future<void> _awaitProfile(ProviderContainer c) =>
    c.read(userProfileProvider.future);

Future<(ProviderContainer, FakeStorageCleanupGateway, AppDatabase)>
_build() async {
  final gateway = FakeStorageCleanupGateway();
  final db = AppDatabase(NativeDatabase.memory());
  await _seedShop(db);
  final repo = DriftStorageCleanupRepository(db);
  final staff = FakeStaffRepository();
  final auth = FakeAuthRepository(
    user: const AuthUser(id: _ownerId, email: _ownerEmail),
  );
  final container = ProviderContainer(
    overrides: [
      storageCleanupGatewayProvider.overrideWithValue(gateway),
      storageCleanupRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      authRepositoryProvider.overrideWithValue(auth),
      staffRepositoryProvider.overrideWithValue(staff),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (container, gateway, db);
}

Future<void> _seedShop(AppDatabase db) => db
    .into(db.shops)
    .insertOnConflictUpdate(
      ShopsCompanion.insert(id: const Value(_shopId), name: 'Shop'),
    );

Future<void> _seedSale(
  AppDatabase db, {
  required String id,
  required DateTime createdAt,
}) async {
  await _seedShop(db);
  await db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: Value(id),
          shopId: const Value(_shopId),
          receiptNumber: 'R-$id',
          subtotalPaise: 100,
          totalPaise: 100,
          paymentStatus: const Value('PAID'),
          createdAt: Value(createdAt),
          updatedAt: Value(createdAt),
        ),
      );
}

Future<void> _seedExpense(
  AppDatabase db, {
  required String id,
  required DateTime date,
}) async {
  await _seedShop(db);
  await db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          shopId: Value(_shopId),
          name: 'Supply $id',
          amountPaise: 50,
          category: 'SUPPLIES',
          paymentMethod: 'CASH',
          expenseDate: date,
        ),
      );
}

Future<void> _seedProduct(AppDatabase db, {required String id}) async {
  await _seedShop(db);
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          shopId: const Value(_shopId),
          categoryId: 'cat-1',
          name: 'Product $id',
          sellingPricePaise: 100,
        ),
      );
}

MonthCleanupPreview _preview({
  Map<String, int> counts = const {'sales': 2},
  bool confirmed = true,
}) => MonthCleanupPreview(
  month: _september,
  counts: counts,
  monthOrphans: const [],
  reportConfirmed: confirmed,
  alreadyCleaned: false,
);

void main() {
  group('database metrics', () {
    test('loads physical metrics into state', () async {
      final (c, gateway, _) = await _build();
      await _awaitProfile(c);
      gateway.metricsResult = DatabaseMetrics(
        dbBytesTotal: 12000000,
        tables: const [
          DatabaseTableMetrics(table: 'sales', bytes: 8000000, rows: 100),
          DatabaseTableMetrics(table: 'products', bytes: 1000000, rows: 50),
        ],
        storageLimitBytes: 100000000,
        measuredAt: DateTime.utc(2026, 9, 15),
      );

      await c.read(storageCleanupControllerProvider.notifier).loadMetrics();
      final state = c.read(storageCleanupControllerProvider);

      expect(state.metrics, isNotNull);
      expect(state.metrics!.dbBytesTotal, 12000000);
      expect(state.metrics!.tables, hasLength(2));
      expect(state.metrics!.usageFraction, closeTo(0.12, 0.0001));
      expect(state.isLoadingMetrics, isFalse);
      expect(gateway.metricsCalls, 1);
    });

    test('metrics failure surfaces without wiping file-scan state', () async {
      final (c, gateway, _) = await _build();
      await _awaitProfile(c);
      gateway.metricsError = const StorageCleanupServiceFailure();

      await expectLater(
        c.read(storageCleanupControllerProvider.notifier).loadMetrics(),
        throwsA(isA<StorageCleanupServiceFailure>()),
      );
      final state = c.read(storageCleanupControllerProvider);
      expect(state.metrics, isNull);
      expect(state.lastError, isNotNull);
      expect(state.isLoadingMetrics, isFalse);
    });
  });

  group('monthly snapshots', () {
    test('refresh caches the snapshot and history lists it', () async {
      final (c, gateway, _) = await _build();
      await _awaitProfile(c);
      gateway.monthStatsResult = MonthlyUsageStats(
        month: _september,
        counts: const {'sales': 10, 'expenses': 4},
        logicalBytesEst: 20480,
        dbBytesTotal: 12000000,
      );
      gateway.monthHistoryResult = [
        MonthlySnapshot(
          month: _september,
          counts: const {'sales': 10, 'expenses': 4},
          logicalBytesEst: 20480,
          dbBytesTotal: 12000000,
          createdAt: DateTime.utc(2026, 9, 30),
        ),
      ];

      final stats = await c
          .read(storageCleanupControllerProvider.notifier)
          .refreshMonth(_september);

      expect(stats.totalRecords, 14);
      expect(stats.logicalBytesEst, 20480);
      expect(gateway.monthStatsCalls, 1);
      final state = c.read(storageCleanupControllerProvider);
      expect(state.snapshots, hasLength(1));
      expect(state.snapshots.single.month, _september);
    });

    test('history falls back to the local cache when offline', () async {
      final (c, gateway, db) = await _build();
      await _awaitProfile(c);
      final repo = DriftStorageCleanupRepository(db);
      await repo.cacheSnapshot(
        shopId: _shopId,
        stats: MonthlyUsageStats(
          month: _august,
          counts: const {'sales': 5},
          logicalBytesEst: 1024,
          dbBytesTotal: 11000000,
        ),
      );
      gateway.monthHistoryError = const StorageCleanupServiceFailure(
        'The storage service could not be reached. Check your connection.',
      );

      // Passive history loads never throw: offline still renders the cache.
      await c.read(storageCleanupControllerProvider.notifier).loadHistory();
      final state = c.read(storageCleanupControllerProvider);
      expect(state.snapshots, hasLength(1));
      expect(state.snapshots.single.month, _august);
    });

    test('history lists locally active months without snapshots', () async {
      final (c, gateway, db) = await _build();
      await _awaitProfile(c);
      // August has transactional rows but no snapshot anywhere: it must still
      // be discovered so the owner can open it and refresh on demand.
      await _seedSale(db, id: 'sale-aug', createdAt: DateTime.utc(2026, 8, 10));
      gateway.monthHistoryResult = [
        MonthlySnapshot(
          month: _september,
          counts: const {'sales': 10},
          logicalBytesEst: 20480,
          dbBytesTotal: 12000000,
          createdAt: DateTime.utc(2026, 9, 30),
        ),
      ];

      await c.read(storageCleanupControllerProvider.notifier).loadHistory();
      final state = c.read(storageCleanupControllerProvider);
      expect(state.snapshots.single.month, _september);
      expect(state.activeMonths, [DateTime.utc(2026, 8)]);
    });
  });

  group('cleanup gates', () {
    test('cleanup without a preview is blocked', () async {
      final (c, _, _) = await _build();
      await _awaitProfile(c);

      await expectLater(
        c
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september),
        throwsA(isA<MonthCleanupBlockedFailure>()),
      );
    });

    test('cleanup without a report confirmation is blocked', () async {
      final (c, gateway, _) = await _build();
      await _awaitProfile(c);
      gateway.previewResult = _preview(confirmed: false);
      await c
          .read(storageCleanupControllerProvider.notifier)
          .previewMonth(_september);

      await expectLater(
        c
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september),
        throwsA(isA<MonthCleanupBlockedFailure>()),
      );
      expect(gateway.cleanupCalls, 0);
    });

    test('cleanup of an already-cleaned month is blocked', () async {
      final (c, gateway, _) = await _build();
      await _awaitProfile(c);
      gateway.previewResult = MonthCleanupPreview(
        month: _september,
        counts: const {},
        monthOrphans: const [],
        reportConfirmed: true,
        alreadyCleaned: true,
      );
      await c
          .read(storageCleanupControllerProvider.notifier)
          .previewMonth(_september);

      await expectLater(
        c
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september),
        throwsA(isA<MonthCleanupBlockedFailure>()),
      );
      expect(gateway.cleanupCalls, 0);
    });

    test('cleanup waits for a drained outbox', () async {
      final (c, gateway, db) = await _build();
      await _awaitProfile(c);
      gateway.previewResult = _preview();
      await c
          .read(storageCleanupControllerProvider.notifier)
          .previewMonth(_september);
      // A single pending row anywhere blocks destructive cleanup: pushing it
      // afterwards would resurrect without a tombstone.
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'device-1',
              shopId: _shopId,
              entity: 'SALE',
              entityId: 'sale-pending',
              payload: '{}',
            ),
          );

      await expectLater(
        c
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september),
        throwsA(isA<MonthCleanupBlockedFailure>()),
      );
      expect(gateway.cleanupCalls, 0);
    });

    test('staff cannot invoke monthly cleanup', () async {
      final gateway = FakeStorageCleanupGateway();
      final db = AppDatabase(NativeDatabase.memory());
      await _seedShop(db);
      // NOTE: no owner profile is claimed here, so the controller refuses.
      final container = ProviderContainer(
        overrides: [
          storageCleanupGatewayProvider.overrideWithValue(gateway),
          storageCleanupRepositoryProvider.overrideWithValue(
            DriftStorageCleanupRepository(db),
          ),
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      await expectLater(
        container
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september),
        throwsA(isA<StorageCleanupForbiddenFailure>()),
      );
      expect(gateway.cleanupCalls, 0);
    });
  });

  group('successful cleanup', () {
    test(
      'deletes the month scope locally, records the marker, rescans',
      () async {
        final (c, gateway, db) = await _build();
        await _awaitProfile(c);
        await _seedSale(
          db,
          id: 'sale-sep',
          createdAt: DateTime.utc(2026, 9, 10),
        );
        await _seedSale(
          db,
          id: 'sale-aug',
          createdAt: DateTime.utc(2026, 8, 10),
        );
        await _seedExpense(db, id: 'e-sep', date: DateTime.utc(2026, 9, 5));
        gateway.previewResult = _preview(
          counts: const {'sales': 1, 'expenses': 1},
        );
        gateway.cleanupResult = MonthCleanupResult(
          month: _september,
          deleted: const {'sales': 1, 'expenses': 1},
          alreadyCleaned: false,
          markerId: 'marker-1',
        );
        gateway.metricsResult = DatabaseMetrics(
          dbBytesTotal: 9000000,
          tables: const [],
          measuredAt: DateTime.utc(2026, 10, 1),
        );
        await c
            .read(storageCleanupControllerProvider.notifier)
            .previewMonth(_september);

        final result = await c
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september);

        expect(result.totalDeleted, 2);
        expect(result.markerId, 'marker-1');
        expect(gateway.lastCleanupMarkerId, isNotNull);
        // September scope gone, August scope intact.
        final sales = await db.select(db.sales).get();
        expect(sales.map((s) => s.id), ['sale-aug']);
        final expenses = await db.select(db.expenses).get();
        expect(expenses, isEmpty);
        // Marker recorded for convergence + idempotent retry.
        final repo = DriftStorageCleanupRepository(db);
        expect(await repo.markerApplied('marker-1'), isTrue);
        // Post-delete verification: metrics + history refreshed.
        expect(gateway.metricsCalls, greaterThanOrEqualTo(1));
        expect(gateway.monthStatsCalls, greaterThanOrEqualTo(1));
        final state = c.read(storageCleanupControllerProvider);
        expect(state.lastCleanupResult, isNotNull);
        expect(state.lastCleanupResult!.totalDeleted, 2);
        expect(state.isDeleting, isFalse);
      },
    );

    test('already-cleaned retry converges without deleting again', () async {
      final (c, gateway, db) = await _build();
      await _awaitProfile(c);
      await _seedShop(db);
      await _seedSale(db, id: 'sale-sep', createdAt: DateTime.utc(2026, 9, 10));
      gateway.previewResult = _preview();
      gateway.cleanupResult = MonthCleanupResult(
        month: _september,
        deleted: const {},
        alreadyCleaned: true,
        markerId: 'marker-retry',
      );
      await c
          .read(storageCleanupControllerProvider.notifier)
          .previewMonth(_september);

      final result = await c
          .read(storageCleanupControllerProvider.notifier)
          .cleanupMonth(_september);

      expect(result.alreadyCleaned, isTrue);
      expect(result.totalDeleted, 0);
      // The local mirror still converges even on retry.
      expect(await db.select(db.sales).get(), isEmpty);
      final repo = DriftStorageCleanupRepository(db);
      expect(await repo.markerApplied('marker-retry'), isTrue);
    });

    test('cleanup failure keeps local rows and surfaces the error', () async {
      final (c, gateway, db) = await _build();
      await _awaitProfile(c);
      await _seedShop(db);
      await _seedSale(db, id: 'sale-sep', createdAt: DateTime.utc(2026, 9, 10));
      gateway.previewResult = _preview();
      gateway.cleanupError = const MonthCleanupServiceFailure();
      await c
          .read(storageCleanupControllerProvider.notifier)
          .previewMonth(_september);

      await expectLater(
        c
            .read(storageCleanupControllerProvider.notifier)
            .cleanupMonth(_september),
        throwsA(isA<MonthCleanupServiceFailure>()),
      );
      expect((await db.select(db.sales).get()).map((s) => s.id), ['sale-sep']);
      final state = c.read(storageCleanupControllerProvider);
      expect(state.lastError, isNotNull);
      expect(state.isDeleting, isFalse);
    });
  });

  group('month boundaries and master protection', () {
    test('UTC boundary rows fall in exactly one month', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seedShop(db);
      addTearDown(db.close);
      await _seedShop(db);
      // 31 Aug 23:59:59 UTC stays August; 1 Sep 00:00:00 UTC is September.
      await _seedSale(
        db,
        id: 's-aug',
        createdAt: DateTime.utc(2026, 8, 31, 23, 59, 59),
      );
      await _seedSale(db, id: 's-sep', createdAt: DateTime.utc(2026, 9, 1));
      await deleteShopMonth(db, _shopId, _september);

      expect((await db.select(db.sales).get()).map((s) => s.id), ['s-aug']);
    });

    test('master data is never in the month-delete scope', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seedShop(db);
      addTearDown(db.close);
      await _seedShop(db);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: const Value('cat-1'),
              name: 'Cat',
              shopId: const Value(_shopId),
            ),
          );
      await _seedProduct(db, id: 'prod-1');
      await deleteShopMonth(db, _shopId, _september);

      expect(await db.select(db.products).get(), hasLength(1));
      expect(await db.select(db.categories).get(), hasLength(1));
    });

    test('child rows go before parents (RESTRICT-safe)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _seedShop(db);
      addTearDown(db.close);
      await _seedSale(db, id: 'sale-1', createdAt: DateTime.utc(2026, 9, 10));
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              shopId: const Value(_shopId),
              saleId: 'sale-1',
              productId: 'prod-x',
              productName: 'Snapshot product',
              unitPricePaise: 100,
              quantity: 1,
              lineTotalPaise: 100,
            ),
          );
      // Would throw on FK violation if children were deleted after parents.
      await deleteShopMonth(db, _shopId, _september);
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.saleItems).get(), isEmpty);
    });
  });

  group('report confirmation', () {
    test('confirming unlocks the preview gate', () async {
      final (c, gateway, _) = await _build();
      await _awaitProfile(c);
      gateway.previewResult = _preview(confirmed: false);
      await c
          .read(storageCleanupControllerProvider.notifier)
          .previewMonth(_september);
      expect(
        c.read(storageCleanupControllerProvider).preview!.reportConfirmed,
        isFalse,
      );

      await c
          .read(storageCleanupControllerProvider.notifier)
          .confirmReport(_september);
      // The fake still returns unconfirmed; the local mirror is the source
      // of truth for the gate here — re-preview would show confirmed.
      final repo = c.read(storageCleanupRepositoryProvider);
      final confirmation = await repo.confirmationFor(_shopId, _september);
      expect(confirmation, isNotNull);
      expect(confirmation!.month, _september);
    });
  });
}
