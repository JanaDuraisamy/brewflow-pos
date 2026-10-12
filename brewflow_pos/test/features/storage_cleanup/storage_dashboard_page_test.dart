import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/app_buttons.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/owner_storage_usage_page.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_storage_cleanup_gateway.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Owner storage dashboard widget contract.
///
/// The dashboard shows physical database metrics (labeled DB-wide), the
/// monthly usage ledger and per-month detail with stats, report and cleanup
/// entry points — on narrow phones without overflow.
/// ---------------------------------------------------------------------------

/// Drags the page list up until [target] is built, then settles. The monthly
/// card sits below the fold and ListView builds lazily, so the target may
/// not exist at all before scrolling (scrollUntilVisible cannot help there).
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required double width,
  required FakeStorageCleanupGateway gateway,
  required AppDatabase db,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  // Snapshot/confirmation/marker mirrors scope to the owner's shop, which
  // carries a shops FK like every other business table. Idempotent so tests
  // can seed shop-scoped rows before pumping.
  await db
      .into(db.shops)
      .insertOnConflictUpdate(
        ShopsCompanion.insert(id: const Value('shop-1'), name: 'Shop'),
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageCleanupGatewayProvider.overrideWithValue(gateway),
        storageCleanupRepositoryProvider.overrideWithValue(
          DriftStorageCleanupRepository(db),
        ),
        appDatabaseProvider.overrideWithValue(db),
        ...businessScopeOverrides(),
      ],
      child: const MaterialApp(home: OwnerStorageUsagePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('dashboard layout', () {
    for (final width in [360.0, 430.0]) {
      testWidgets(
        'shows database, files and monthly sections at ${width.toInt()}dp',
        (tester) async {
          final gateway = FakeStorageCleanupGateway()
            ..metricsResult = DatabaseMetrics(
              dbBytesTotal: 12000000,
              tables: const [
                DatabaseTableMetrics(table: 'sales', bytes: 8000000, rows: 100),
              ],
              storageLimitBytes: 100000000,
              measuredAt: DateTime.utc(2026, 9, 15),
            )
            ..monthHistoryResult = [
              MonthlySnapshot(
                month: DateTime.utc(2026, 9),
                counts: const {'sales': 10},
                logicalBytesEst: 20480,
                dbBytesTotal: 12000000,
                createdAt: DateTime.utc(2026, 9, 30),
              ),
            ];
          final db = AppDatabase(NativeDatabase.memory());
          addTearDown(db.close);

          await _pumpPage(tester, width: width, gateway: gateway, db: db);

          expect(find.text('Cloud database'), findsOneWidget);
          expect(find.text('Cloud Storage'), findsOneWidget);
          // The monthly card sits below the fold: scroll in two hops
          // (ListView lazily builds offscreen children, and scrolled-past
          // headers leave the cache extent).
          await _scrollTo(tester, find.text('Monthly database usage'));
          await tester.pumpAndSettle();
          expect(find.text('Monthly database usage'), findsOneWidget);
          await _scrollTo(tester, find.text('Sep 2026'));
          await tester.pumpAndSettle();
          expect(find.text('Sep 2026'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'month row opens the detail sheet with stats and report actions',
      (tester) async {
        final gateway = FakeStorageCleanupGateway()
          ..monthHistoryResult = [
            MonthlySnapshot(
              month: DateTime.utc(2026, 9),
              counts: const {'sales': 10, 'expenses': 4},
              logicalBytesEst: 20480,
              dbBytesTotal: 12000000,
              createdAt: DateTime.utc(2026, 9, 30),
            ),
          ]
          ..monthStatsResult = MonthlyUsageStats(
            month: DateTime.utc(2026, 9),
            counts: const {'sales': 10, 'expenses': 4},
            logicalBytesEst: 20480,
            dbBytesTotal: 12000000,
          );
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await _pumpPage(tester, width: 390, gateway: gateway, db: db);
        await _scrollTo(tester, find.text('Sep 2026'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sep 2026'));
        await tester.pumpAndSettle();

        expect(find.text('Estimated logical size'), findsOneWidget);
        expect(find.text('Generate report'), findsOneWidget);
        expect(find.text('Preview deletion'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'months with activity but no snapshot are offered for refresh',
      (tester) async {
        final gateway = FakeStorageCleanupGateway()
          ..monthHistoryResult = [
            MonthlySnapshot(
              month: DateTime.utc(2026, 9),
              counts: const {'sales': 2},
              logicalBytesEst: 1024,
              dbBytesTotal: 12000000,
              createdAt: DateTime.utc(2026, 9, 30),
            ),
          ];
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        // August has a transaction but no snapshot anywhere: historical month
        // discovery must still offer it so the owner can refresh it on demand.
        await db
            .into(db.shops)
            .insert(
              ShopsCompanion.insert(id: const Value('shop-1'), name: 'Shop'),
            );
        await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                id: const Value('sale-aug'),
                shopId: const Value('shop-1'),
                receiptNumber: 'BF-AUG',
                subtotalPaise: 100,
                totalPaise: 100,
                createdAt: Value(DateTime.utc(2026, 8, 10)),
                updatedAt: Value(DateTime.utc(2026, 8, 10)),
              ),
            );

        await _pumpPage(tester, width: 390, gateway: gateway, db: db);

        await _scrollTo(tester, find.text('Aug 2026'));
        await tester.pumpAndSettle();
        expect(find.text('Aug 2026'), findsOneWidget);
        // Aug has no snapshot (the current month has none either, hence
        // findsWidgets): the row invites an on-demand refresh.
        expect(find.text('No snapshot yet — open to refresh.'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('preview shows counts and the permanent-deletion warning', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..monthHistoryResult = [
          MonthlySnapshot(
            month: DateTime.utc(2026, 9),
            counts: const {'sales': 2},
            logicalBytesEst: 1024,
            dbBytesTotal: 12000000,
            createdAt: DateTime.utc(2026, 9, 30),
          ),
        ]
        ..monthStatsResult = MonthlyUsageStats(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2},
          logicalBytesEst: 1024,
          dbBytesTotal: 12000000,
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2, 'expenses': 1},
          monthOrphans: const [],
          reportConfirmed: true,
          alreadyCleaned: false,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await _pumpPage(tester, width: 390, gateway: gateway, db: db);
      await _scrollTo(tester, find.text('Sep 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 2026'));
      await tester.pumpAndSettle();
      // The cleanup section grew (checkboxes + summary): scroll the button
      // into view before tapping.
      await tester.ensureVisible(find.text('Preview deletion'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview deletion'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 3 records'), findsOneWidget);
      expect(find.textContaining('Will NOT be deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('truthful scan states', () {
    testWidgets('shows Not scanned before any successful scan', (tester) async {
      final gateway = FakeStorageCleanupGateway()..scanResult = null;
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageCleanupGatewayProvider.overrideWithValue(gateway),
            storageCleanupRepositoryProvider.overrideWithValue(
              DriftStorageCleanupRepository(db),
            ),
            appDatabaseProvider.overrideWithValue(db),
            ...businessScopeOverrides(),
          ],
          child: const MaterialApp(home: OwnerStorageUsagePage()),
        ),
      );
      // Before the first scan settles: no fabricated zeros, just the invite.
      expect(find.text('Not scanned yet'), findsOneWidget);
      expect(find.text('Cloud Storage Health'), findsNothing);
      expect(find.text('Product images'), findsNothing);
    });

    testWidgets('shows Unavailable when the scan fails with no prior report', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..scanError = const StorageCleanupServiceFailure(
          'The storage service could not be reached. Check your connection.',
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);

      expect(find.text('Unavailable'), findsOneWidget);
      // Never fabricate zero values for a failed scan.
      expect(find.text('Cloud Storage Health'), findsNothing);
      expect(find.text('Product images'), findsNothing);
      expect(find.text('Product images 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps last successful values with a stale banner on failure', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..scanResult = StorageUsageReport(
          usedBytes: 5000,
          imageCount: 10,
          orphanCount: 2,
          reclaimableBytes: 1000,
          orphanPaths: const ['a.jpg'],
          lastScanAt: DateTime.utc(2026, 9, 20),
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);
      // First scan succeeded: real values show under the health card.
      expect(find.text('Cloud Storage Health'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Image storage'), findsOneWidget);
      expect(find.text('4.9 KB'), findsOneWidget);
      // The health card never shows a usage percentage. ('Configured limit'
      // still exists page-wide — the Cloud database card shows the DB quota.)
      expect(find.text('Usage'), findsNothing);

      // A later scan fails: values stay but are labelled stale.
      gateway.scanError = const StorageCleanupServiceFailure('Edge down');
      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Latest scan failed'), findsOneWidget);
      expect(find.text('4.9 KB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a scan with no orphans reports Healthy', (tester) async {
      final gateway = FakeStorageCleanupGateway()
        ..scanResult = StorageUsageReport(
          usedBytes: 2048,
          imageCount: 4,
          orphanCount: 0,
          reclaimableBytes: 0,
          orphanPaths: const [],
          lastScanAt: DateTime.utc(2026, 9, 20),
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);

      expect(find.text('Cloud Storage Health'), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Product images'), findsOneWidget);
      expect(find.text('Orphan images'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      // Nothing to clean: the primary action is disabled.
      expect(
        find.widgetWithText(PrimaryButton, 'Nothing to review'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('database detail sheet', () {
    Future<void> openDatabaseCard(
      WidgetTester tester,
      FakeStorageCleanupGateway gateway,
      AppDatabase db,
    ) async {
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);
      await _scrollTo(tester, find.text('Cloud database'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View tables & details'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens with total size and a table breakdown', (tester) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'sales', bytes: 8000000, rows: 100),
            DatabaseTableMetrics(table: 'customers', bytes: 500000, rows: 42),
          ],
          storageLimitBytes: 100000000,
          measuredAt: DateTime.utc(2026, 9, 15),
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openDatabaseCard(tester, gateway, db);

      expect(find.text('Total database size'), findsOneWidget);
      expect(find.text('11.4 MB'), findsWidgets);
      // Owner-friendly names, not just raw table names.
      expect(find.text('Sales / Bills'), findsOneWidget);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.textContaining('100 rows'), findsOneWidget);
      expect(find.textContaining('database-wide'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a table opens its detail', (tester) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'sales', bytes: 8000000, rows: 100),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openDatabaseCard(tester, gateway, db);

      await tester.tap(find.text('Sales / Bills'));
      await tester.pumpAndSettle();

      expect(find.text('What is this?'), findsOneWidget);
      expect(find.text('What does it contain?'), findsOneWidget);
      expect(find.text('Where is it used?'), findsOneWidget);
      expect(find.text('Cleanup behavior'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('master data tables show a safety note', (tester) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'products', bytes: 300000, rows: 50),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openDatabaseCard(tester, gateway, db);

      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();

      expect(find.text('Safety note'), findsOneWidget);
      expect(find.textContaining('Master data'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    Future<void> openTable(
      WidgetTester tester,
      FakeStorageCleanupGateway gateway,
      AppDatabase db,
      String friendlyName,
    ) async {
      await openDatabaseCard(tester, gateway, db);
      await tester.tap(find.text(friendlyName));
      await tester.pumpAndSettle();
    }

    testWidgets('cleanup-eligible table shows the month delete section', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'purchases', bytes: 200000, rows: 30),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        )
        ..monthStatsResult = MonthlyUsageStats(
          month: DateTime.utc(2026, 9),
          counts: const {'purchases': 5},
          logicalBytesEst: 600,
          dbBytesTotal: 12000000,
          avgBytes: const {'purchases': 120},
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'purchases': 5},
          monthOrphans: const [],
          reportConfirmed: true,
          alreadyCleaned: false,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openTable(tester, gateway, db, 'Purchases');

      // The section title and the button share the label.
      expect(find.text('Delete this month\u2019s records'), findsWidgets);
      expect(find.text('Selected month'), findsOneWidget);
      expect(find.text('Record count'), findsOneWidget);
      expect(find.text('Estimated logical size'), findsOneWidget);
      expect(
        find.textContaining('Also deletes: purchases, purchase_items'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('master table has no delete section', (tester) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'products', bytes: 300000, rows: 50),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openTable(tester, gateway, db, 'Products');

      expect(find.text('Delete this month\u2019s records'), findsNothing);
      expect(find.text('Selected month'), findsNothing);
      expect(find.text('Record count'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('delete button is disabled until the report is confirmed', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'purchases', bytes: 200000, rows: 30),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'purchases': 5},
          monthOrphans: const [],
          reportConfirmed: false,
          alreadyCleaned: false,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openTable(tester, gateway, db, 'Purchases');

      final delete = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Delete this month\u2019s records'),
      );
      expect(delete.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('delete confirms then calls the scoped cleanup flow', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'purchases', bytes: 200000, rows: 30),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        )
        ..monthStatsResult = MonthlyUsageStats(
          month: DateTime.utc(2026, 9),
          counts: const {'purchases': 5},
          logicalBytesEst: 600,
          dbBytesTotal: 12000000,
          avgBytes: const {'purchases': 120},
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'purchases': 5},
          monthOrphans: const [],
          reportConfirmed: true,
          alreadyCleaned: false,
        )
        ..cleanupResult = MonthCleanupResult(
          month: DateTime.utc(2026, 9),
          deleted: const {'purchases': 5},
          alreadyCleaned: false,
          markerId: 'marker-purchases',
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openTable(tester, gateway, db, 'Purchases');

      await tester.tap(
        find.widgetWithText(PrimaryButton, 'Delete this month\u2019s records'),
      );
      await tester.pumpAndSettle();
      // Confirmation dialog appears before anything is deleted.
      expect(find.text('Delete forever'), findsOneWidget);
      expect(gateway.cleanupCalls, 0);

      await tester.tap(find.text('Delete forever'));
      await tester.pumpAndSettle();

      // The existing month_cleanup_atomic flow ran, scoped to the table's
      // category only.
      expect(gateway.cleanupCalls, 1);
      expect(gateway.lastCleanupCategories, ['purchases']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sales table delete respects open-bill protection', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..metricsResult = DatabaseMetrics(
          dbBytesTotal: 12000000,
          tables: const [
            DatabaseTableMetrics(table: 'sales', bytes: 8000000, rows: 100),
          ],
          measuredAt: DateTime.utc(2026, 9, 15),
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2},
          monthOrphans: const [],
          reportConfirmed: true,
          alreadyCleaned: false,
          openBillCount: 4,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await openTable(tester, gateway, db, 'Sales / Bills');

      expect(find.textContaining('unpaid or partially-paid'), findsOneWidget);
      final delete = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Delete this month\u2019s records'),
      );
      expect(delete.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('month detail', () {
    testWidgets('shows snapshot, report and cleaned status chips', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..monthHistoryResult = [
          MonthlySnapshot(
            month: DateTime.utc(2026, 9),
            counts: const {'sales': 2},
            logicalBytesEst: 1024,
            dbBytesTotal: 12000000,
            createdAt: DateTime.utc(2026, 9, 30),
          ),
        ]
        ..monthStatsResult = MonthlyUsageStats(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2},
          logicalBytesEst: 1024,
          dbBytesTotal: 12000000,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);
      await _scrollTo(tester, find.text('Sep 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 2026'));
      await tester.pumpAndSettle();

      expect(find.text('Snapshot saved'), findsOneWidget);
      expect(find.text('Report not confirmed'), findsOneWidget);
      expect(find.text('Not cleaned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cleanup checkbox selection updates the live summary', (
      tester,
    ) async {
      final gateway = FakeStorageCleanupGateway()
        ..monthHistoryResult = [
          MonthlySnapshot(
            month: DateTime.utc(2026, 9),
            counts: const {'sales': 2},
            logicalBytesEst: 1024,
            dbBytesTotal: 12000000,
            createdAt: DateTime.utc(2026, 9, 30),
          ),
        ]
        ..monthStatsResult = MonthlyUsageStats(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2, 'expenses': 1},
          logicalBytesEst: 300,
          dbBytesTotal: 12000000,
          avgBytes: const {'sales': 100, 'expenses': 80},
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2, 'expenses': 1},
          monthOrphans: const [],
          reportConfirmed: true,
          alreadyCleaned: false,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);
      await _scrollTo(tester, find.text('Sep 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 2026'));
      await tester.pumpAndSettle();

      // All 9 categories selected by default: 3 records total.
      expect(find.textContaining('9 of 9 categories selected'), findsOneWidget);
      expect(find.textContaining('3 records'), findsWidgets);

      // Deselect Expenses: the live summary drops to 2 records. (The
      // stats breakdown also shows an "Expenses" row, so target the
      // checkbox tile's InkWell specifically.)
      final expensesTile = find.widgetWithText(InkWell, 'Expenses');
      await tester.ensureVisible(expensesTile);
      await tester.pumpAndSettle();
      await tester.tap(expensesTile);
      await tester.pumpAndSettle();
      expect(find.textContaining('8 of 9 categories selected'), findsOneWidget);
      expect(find.textContaining('2 records'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('open-bill warning blocks the cleanup preview', (tester) async {
      final gateway = FakeStorageCleanupGateway()
        ..monthHistoryResult = [
          MonthlySnapshot(
            month: DateTime.utc(2026, 9),
            counts: const {'sales': 2},
            logicalBytesEst: 1024,
            dbBytesTotal: 12000000,
            createdAt: DateTime.utc(2026, 9, 30),
          ),
        ]
        ..monthStatsResult = MonthlyUsageStats(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2},
          logicalBytesEst: 1024,
          dbBytesTotal: 12000000,
        )
        ..previewResult = MonthCleanupPreview(
          month: DateTime.utc(2026, 9),
          counts: const {'sales': 2},
          monthOrphans: const [],
          reportConfirmed: true,
          alreadyCleaned: false,
          openBillCount: 2,
        );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpPage(tester, width: 390, gateway: gateway, db: db);
      await _scrollTo(tester, find.text('Sep 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 2026'));
      await tester.pumpAndSettle();

      expect(find.textContaining('unpaid or partially-paid'), findsOneWidget);
      // The Preview deletion button is disabled while open bills exist.
      final preview = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Preview deletion'),
      );
      expect(preview.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
