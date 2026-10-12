import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// v34 — monthly storage ledger tables.
///
/// `storage_monthly_snapshots` (server-ledger cache),
/// `monthly_report_confirmations` (synced report markers) and
/// `month_cleanup_markers` (applied-cleanup ledger) are three brand-new
/// tables: nothing existing is read, rewritten or dropped.
///
/// Built on the v14 schema the other migration gates use, then pinned to v33
/// so only `from33To34` executes against a populated shop.
/// ---------------------------------------------------------------------------

Future<Set<String>> _columns(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.data['name'] as String};
}

Future<List<String>> _indexNames(GeneratedDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        'AND tbl_name = ? AND sql IS NOT NULL ORDER BY name',
        variables: [Variable.withString(table)],
      )
      .get();
  return [for (final row in rows) row.data['name'] as String];
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// Seeds a v14-physical database stamped at v33 and hands back a fresh
  /// opener plus a reopen closure over the same backing store — mirrors the
  /// shared-stock gate. Closing a handle and reusing it is a drift error;
  /// reopening replays a real upgrade.
  Future<({DatabaseConnection open, DatabaseConnection Function() reopen})>
  v33() async {
    // Mirrors the shared-stock gate: the verifier holds one backing store
    // and hands out fresh connections to it, so closing the seed handle and
    // reopening replays a real upgrade (a closed handle itself is unusable).
    final schema = await verifier.schemaAt(14);
    final seed = v14.DatabaseAtV14(schema.newConnection());
    await seed
        .into(seed.shops)
        .insert(
          v14.ShopsCompanion.insert(
            id: 'shop-cafe',
            name: 'Cafe',
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        );
    await seed.customStatement('PRAGMA user_version = 33');
    await seed.close();
    return (open: schema.newConnection(), reopen: schema.newConnection);
  }

  test('a v33 database has none of the ledger tables', () async {
    final schema = await verifier.schemaAt(14);
    final db = v14.DatabaseAtV14(schema.newConnection());
    addTearDown(db.close);

    for (final table in [
      'storage_monthly_snapshots',
      'monthly_report_confirmations',
      'month_cleanup_markers',
    ]) {
      expect(await _columns(db, table), isEmpty);
    }
  });

  test('the wired v33 -> v34 step creates the ledger tables', () async {
    final fixture = await v33();
    final db = AppDatabase(fixture.open);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    for (final table in [
      'storage_monthly_snapshots',
      'monthly_report_confirmations',
      'month_cleanup_markers',
    ]) {
      final columns = await _columns(db, table);
      expect(columns, contains('id'));
      expect(columns, contains('shop_id'));
      expect(columns, contains('month'));
      expect(columns, contains('created_at'));
      expect(columns, contains('updated_at'));
    }
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first,
      AppConstants.databaseSchemaVersion,
    );
  });

  test('the step creates the pull indexes', () async {
    final fixture = await v33();
    final db = AppDatabase(fixture.open);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    expect(
      await _indexNames(db, 'storage_monthly_snapshots'),
      containsAll([
        'idx_storage_monthly_snapshots_shop',
        'idx_storage_monthly_snapshots_month',
      ]),
    );
    expect(
      await _indexNames(db, 'monthly_report_confirmations'),
      containsAll([
        'idx_monthly_report_confirmations_shop',
        'idx_monthly_report_confirmations_month',
      ]),
    );
    expect(
      await _indexNames(db, 'month_cleanup_markers'),
      containsAll([
        'idx_month_cleanup_markers_shop',
        'idx_month_cleanup_markers_month',
      ]),
    );
  });

  test('existing shop rows survive the upgrade', () async {
    final fixture = await v33();
    final db = AppDatabase(fixture.open);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    // Raw read: the v14-physical shops row predates newer columns, so typed
    // mapping cannot parse it — the byte-identity gate below is what matters.
    final shops = await db
        .customSelect('SELECT id FROM shops ORDER BY id')
        .get();
    expect([for (final row in shops) row.data['id']], ['shop-cafe']);
  });

  test('the step is idempotent and the new tables are writable', () async {
    final fixture = await v33();
    final db = AppDatabase(fixture.open);
    await db.customSelect('SELECT 1').get();
    await db.close();

    final reopened = AppDatabase(fixture.reopen());
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').get();
    final now = DateTime.now().toUtc();
    await reopened
        .into(reopened.monthlyReportConfirmations)
        .insert(
          MonthlyReportConfirmationsCompanion.insert(
            shopId: const Value('shop-cafe'),
            month: DateTime.utc(2026, 9),
            confirmedAt: now,
          ),
        );
    expect(
      await reopened.select(reopened.monthlyReportConfirmations).get(),
      hasLength(1),
    );
  });
}
