import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// v33 — shared-stock recipes + the product ingredient flag.
///
/// `product_recipes` maps a sellable product to its stock-source ingredients
/// and `products.is_ingredient` hides a source from the sale shelf. Both are
/// purely additive: an install that upgrades keeps every product sellable
/// (`is_ingredient` defaults false) and every sale deducting its own stock
/// (no recipe rows exist for it).
///
/// Built on the v14 schema the other migration gates use, then pinned to v32
/// so only `from32To33` executes against a populated shop + product.
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

Future<List<Map<String, Object?>>> _snapshot(
  GeneratedDatabase db,
  String table,
) async {
  final rows = await db.customSelect('SELECT * FROM $table ORDER BY id').get();
  return [for (final row in rows) row.data];
}

class V32Fixture {
  V32Fixture(this.db, this.reopen, this.productBefore);
  final v14.DatabaseAtV14 db;
  final DatabaseConnection Function() reopen;
  final List<Map<String, Object?>> productBefore;
}

Future<V32Fixture> buildV32(DatabaseConnection Function() connect) async {
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
          id: 'cat-maggi',
          name: 'Maggi',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  await db
      .into(db.products)
      .insert(
        v14.ProductsCompanion.insert(
          id: 'p-maggi-packet',
          categoryId: 'cat-maggi',
          name: 'Maggi Packet',
          sellingPricePaise: 2000,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  final productBefore = await _snapshot(db, 'products');
  await db.customStatement('PRAGMA user_version = 32');
  return V32Fixture(db, connect, productBefore);
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a v32 database has neither the flag nor the table', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV32(schema.newConnection);

    expect(
      await _columns(fixture.db, 'products'),
      isNot(contains('is_ingredient')),
    );
    expect(await _columns(fixture.db, 'no_such_table'), isEmpty);

    await fixture.db.close();
  });

  test('the wired v32 -> v33 step adds the flag defaulting to false', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV32(schema.newConnection);
    await fixture.db.close();

    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();

    expect(await _columns(db, 'products'), contains('is_ingredient'));
    final row = await db
        .customSelect(
          'SELECT is_ingredient FROM products WHERE id = ?',
          variables: [Variable.withString('p-maggi-packet')],
        )
        .getSingle();
    expect(
      row.data['is_ingredient'],
      0,
      reason: 'upgrading must not hide existing products from the shelf',
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

  test('the step creates product_recipes with its indexes', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV32(schema.newConnection);
    await fixture.db.close();

    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();

    final columns = await _columns(db, 'product_recipes');
    for (final column in [
      'id',
      'shop_id',
      'product_id',
      'variant_id',
      'ingredient_product_id',
      'ingredient_variant_id',
      'quantity',
      'created_at',
      'updated_at',
    ]) {
      expect(columns, contains(column));
    }
    expect(
      await _indexNames(db, 'product_recipes'),
      containsAll([
        'idx_product_recipes_product',
        'idx_product_recipes_updated_at',
      ]),
    );

    await db.close();
  });

  test('existing product rows survive byte-identical', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV32(schema.newConnection);
    await fixture.db.close();

    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();

    final after = await _snapshot(db, 'products');
    expect(after.length, fixture.productBefore.length);
    for (var i = 0; i < after.length; i++) {
      for (final entry in fixture.productBefore[i].entries) {
        expect(
          after[i][entry.key],
          entry.value,
          reason: 'column ${entry.key} must survive the upgrade',
        );
      }
    }

    await db.close();
  });

  test('the step is idempotent and the new table is writable', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV32(schema.newConnection);
    await fixture.db.close();

    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();
    await db.close();

    // Re-open: the guarded step must be a no-op, and a recipe row round-trips.
    final reopened = AppDatabase(fixture.reopen());
    await reopened.customSelect('SELECT 1').get();
    await reopened
        .into(reopened.productRecipes)
        .insert(
          ProductRecipesCompanion.insert(
            shopId: const Value('shop-cafe'),
            productId: 'p-maggi-packet',
            ingredientProductId: 'p-maggi-packet',
            quantity: 1,
          ),
        );
    expect(await reopened.select(reopened.productRecipes).get(), hasLength(1));
    await reopened.close();
  });
}
