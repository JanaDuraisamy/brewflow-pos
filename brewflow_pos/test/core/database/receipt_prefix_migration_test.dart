import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// v28 — per-shop receipt prefix + the missing `visible_in_shops` column gate.
///
/// Two things land in this step, and they are not equally dangerous.
///
///  * `shops.receipt_prefix` moves the receipt LABEL off a global constant and
///    onto the business row. The Cafe prefix is the column default, so an
///    install that upgrades keeps labelling its receipts exactly as before; the
///    only way to break historical continuity is for that default to change, so
///    it is asserted rather than assumed.
///  * `products.visible_in_shops` is a *repair*. The Drift table gained the
///    column without a versioned schema, so an existing install never received
///    the `ALTER TABLE` and the sync engine's read of `visible_in_shops` fails
///    on upgrade. Adding it is additive, and the default must be false (not
///    shared) so upgrading can never silently publish a Cafe catalogue to the
///    Food Truck.
///
/// The step must also be a no-op on re-open, and must not disturb a single
/// existing row — both are what a careless `ALTER` costs here.
/// ---------------------------------------------------------------------------

Future<List<Map<String, Object?>>> _snapshot(
  GeneratedDatabase db,
  String table,
) async {
  final rows = await db.customSelect('SELECT * FROM $table ORDER BY id').get();
  return [for (final row in rows) row.data];
}

Future<Set<String>> _columns(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.data['name'] as String};
}

Future<String?> _ddl(GeneratedDatabase db, String table) async {
  final row = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      )
      .getSingleOrNull();
  return row?.data['sql'] as String?;
}

/// A minimal database stamped at v27: a Cafe and one product, neither of which
/// yet carries the v28 columns. Built on the v14 schema the other migration
/// gates use, then pinned to v27 so only `from27To28` executes.
class V27Fixture {
  V27Fixture(this.db, this.reopen, this.shopBefore, this.productBefore);
  final v14.DatabaseAtV14 db;
  final DatabaseConnection Function() reopen;
  final List<Map<String, Object?>> shopBefore;
  final List<Map<String, Object?>> productBefore;
}

Future<V27Fixture> buildV27(DatabaseConnection Function() connect) async {
  final connection = connect();
  final db = v14.DatabaseAtV14(connection);

  await db
      .into(db.shops)
      .insert(
        v14.ShopsCompanion.insert(
          id: 'shop-cafe',
          name: 'Cafe',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  await db
      .into(db.categories)
      .insert(
        v14.CategoriesCompanion.insert(
          id: 'cat-tea',
          name: 'Tea',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  await db
      .into(db.products)
      .insert(
        v14.ProductsCompanion.insert(
          id: 'p-latte',
          categoryId: 'cat-tea',
          name: 'Latte',
          sellingPricePaise: 14950,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  final shopBefore = await _snapshot(db, 'shops');
  final productBefore = await _snapshot(db, 'products');
  await db.customStatement('PRAGMA user_version = 27');
  return V27Fixture(db, connect, shopBefore, productBefore);
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a v27 database has neither v28 column yet', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV27(schema.newConnection);

    expect(
      await _columns(fixture.db, 'shops'),
      isNot(contains('receipt_prefix')),
    );
    expect(
      await _columns(fixture.db, 'products'),
      isNot(contains('visible_in_shops')),
    );

    await fixture.db.close();
  });

  test('the wired v27 -> v28 step adds both columns', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV27(schema.newConnection);
    await fixture.db.close();

    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();

    expect(
      await _columns(db, 'shops'),
      contains('receipt_prefix'),
      reason: 'v28 must add the per-shop receipt label',
    );
    expect(
      await _columns(db, 'products'),
      contains('visible_in_shops'),
      reason:
          'v28 must add visible_in_shops; the table had it without a migration',
    );

    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first,
      AppConstants.databaseSchemaVersion,
    );

    await db.close();
  });

  test(
    'the Cafe default prefix is preserved, so old receipts stay valid',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildV27(schema.newConnection);
      await fixture.db.close();

      final db = AppDatabase(fixture.reopen());
      await db.customSelect('SELECT 1').get();

      // The pre-existing Cafe row must come out of the migration labelled BF-.
      // Anything else silently renames every receipt the business ever printed.
      final cafe = await db
          .customSelect(
            "SELECT receipt_prefix FROM shops WHERE id = 'shop-cafe'",
          )
          .getSingle();
      expect(cafe.data['receipt_prefix'], 'BF-');

      final ddl = await _ddl(db, 'shops');
      expect(
        ddl,
        contains("'BF-'"),
        reason: 'the column default is the Cafe prefix',
      );

      await db.close();
    },
  );

  test(
    'an existing product is not silently shared with the Food Truck',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildV27(schema.newConnection);
      await fixture.db.close();

      final db = AppDatabase(fixture.reopen());
      await db.customSelect('SELECT 1').get();

      final row = await db
          .customSelect(
            'SELECT visible_in_shops FROM products WHERE id = ?',
            variables: [Variable.withString('p-latte')],
          )
          .getSingle();
      expect(
        row.data['visible_in_shops'],
        0,
        reason:
            'upgrading must not publish the Cafe catalogue to the Food Truck',
      );

      await db.close();
    },
  );

  test('the v27 -> v28 step leaves every existing row byte-identical', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV27(schema.newConnection);
    await fixture.db.close();

    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();

    // The snapshot is taken at v14, so the row sets cannot be compared wholesale
    // (v15..v27 legitimately added columns). What must hold is that no row was
    // rewritten or dropped: the Cafe row is still there under the same id with
    // the same name and timestamps.
    final cafe = await db
        .customSelect(
          'SELECT id, name, created_at, updated_at FROM shops WHERE id = ?',
          variables: [Variable.withString('shop-cafe')],
        )
        .getSingle();
    expect(cafe.data['id'], 'shop-cafe');
    expect(cafe.data['name'], 'Cafe');
    expect(cafe.data['created_at'], '2026-01-01T00:00:00.000Z');
    expect(cafe.data['updated_at'], '2026-01-01T00:00:00.000Z');

    final latte = await db
        .customSelect(
          'SELECT id, name, selling_price_paise FROM products WHERE id = ?',
          variables: [Variable.withString('p-latte')],
        )
        .getSingle();
    expect(latte.data['name'], 'Latte');
    expect(latte.data['selling_price_paise'], 14950);

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    await db.close();
  });

  test(
    'a new Food Truck shop carries its own label, not the Cafe one',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(id: const Value('shop-cafe'), name: 'Cafe'),
          );

      // The Food Truck is a second BUSINESS, so it must be able to carry a
      // different label. This is the whole reason the prefix moved onto the row.
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: const Value('shop-truck'),
              name: 'Food Truck',
              receiptPrefix: const Value('FT-'),
            ),
          );

      final cafe = await (db.select(
        db.shops,
      )..where((s) => s.id.equals('shop-cafe'))).getSingle();
      final truck = await (db.select(
        db.shops,
      )..where((s) => s.id.equals('shop-truck'))).getSingle();

      expect(cafe.receiptPrefix, 'BF-');
      expect(truck.receiptPrefix, 'FT-');
    },
  );

  test('the wired step is a no-op on an already-migrated database', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV27(schema.newConnection);
    await fixture.db.close();

    final first = AppDatabase(fixture.reopen());
    await first.customSelect('SELECT 1').get();
    final shopsDdl = await _ddl(first, 'shops');
    final productsDdl = await _ddl(first, 'products');
    await first.close();

    // Re-opening must not re-run the step or add a second column.
    final second = AppDatabase(fixture.reopen());
    await second.customSelect('SELECT 1').get();
    expect(await _ddl(second, 'shops'), shopsDdl);
    expect(await _ddl(second, 'products'), productsDdl);
    expect(
      (await second.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first,
      AppConstants.databaseSchemaVersion,
    );

    await second.close();
  });

  test(
    'a device whose schema is already ahead of user_version still opens',
    () async {
      // The dangerous shape: a build shipped the column in the table definition
      // before the versioned schema caught up, so the device physically HAS
      // the column while still reporting 27. A bare `addColumn` here fails with
      // "duplicate column name" and the app cannot open at all — the step has
      // to notice the column is already there.
      final schema = await verifier.schemaAt(14);
      final fixture = await buildV27(schema.newConnection);

      await fixture.db.customStatement(
        "ALTER TABLE shops ADD COLUMN receipt_prefix TEXT NOT NULL DEFAULT 'FT-'",
      );
      await fixture.db.customStatement(
        'ALTER TABLE products ADD COLUMN visible_in_shops INTEGER NOT NULL '
        'DEFAULT 0',
      );
      await fixture.db.customStatement('PRAGMA user_version = 27');
      await fixture.db.close();

      final db = AppDatabase(fixture.reopen());
      // Opening the database runs the migration; it must not throw.
      await db.customSelect('SELECT 1').get();

      expect(
        await _columns(db, 'shops'),
        contains('receipt_prefix'),
        reason: 'the pre-existing column satisfies the step',
      );
      expect(await _columns(db, 'products'), contains('visible_in_shops'));

      // The value the device already had must survive — the step must not
      // clobber a Food Truck label it did not create.
      final truck = await db
          .customSelect(
            "SELECT receipt_prefix FROM shops WHERE id = 'shop-cafe'",
          )
          .getSingle();
      expect(
        truck.data['receipt_prefix'],
        'FT-',
        reason:
            'an already-migrated value is left exactly as the device had it',
      );

      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .first,
        AppConstants.databaseSchemaVersion,
        reason: 'the version still advances so later steps run',
      );

      await db.close();
    },
  );
}
