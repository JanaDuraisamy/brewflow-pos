import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// v29 — the per-business stock overlay for a shared product.
///
/// `shop_product_stock` is the second shelf. A Cafe product is ONE master row,
/// and `products.visible_in_shops` decides which other business may sell it,
/// but the quantity each business sells from is per business. Without this
/// table a Food Truck sale would decrement the Cafe's own `stock_quantity`.
///
/// The table is only half the step, though, and the half that is easy to lose.
/// Its uniqueness is two PARTIAL unique indexes, one per level:
///
///  * `ux_shop_product_stock_product_level` on `(shop_id, product_id) WHERE
///    variant_id IS NULL` — one shelf for the product itself.
///  * `ux_shop_product_stock_variant_level` on `(shop_id, product_id,
///    variant_id) WHERE variant_id IS NOT NULL` — one shelf per variant.
///
/// They are `@TableIndex.sql` entries, so they are separate objects rather than
/// part of the table's `uniqueKeys` and a `createTable` does NOT bring them
/// along. A step that creates the table and forgets them is *invisible on a
/// fresh install* — `createAll` emits them from the definition — and only ever
/// breaks the upgraded population, which is the population that needed the
/// second shelf. These tests therefore run the real wired step from a pinned
/// v28 database rather than asserting against a fresh `createAll`.
///
/// A single `UNIQUE (shop_id, product_id, variant_id)` would be useless:
/// SQLite treats NULLs as distinct, so it would accept any number of
/// product-level rows for one business. Both levels also have to coexist — a
/// product-level row and a variant-level row for the same business and product
/// are different shelves, not a conflict.
/// ---------------------------------------------------------------------------

Future<String?> _ddl(GeneratedDatabase db, String table) async {
  final row = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      )
      .getSingleOrNull();
  return row?.data['sql'] as String?;
}

Future<List<String>> _indexNames(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'shop_product_stock' AND sql IS NOT NULL "
        'ORDER BY name',
      )
      .get();
  return [for (final row in rows) row.data['name'] as String];
}

Future<String?> _indexSql(GeneratedDatabase db, String name) async {
  final row = await db
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE type = ? AND name = ?',
        variables: [Variable.withString('index'), Variable.withString(name)],
      )
      .getSingleOrNull();
  return row?.data['sql'] as String?;
}

Future<Set<String>> _columns(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.data['name'] as String};
}

/// A database stamped at v28, with the two businesses and one shared product
/// that the overlay exists for.
///
/// Built on the v14 schema the other migration gates use (v14 already carries
/// `product_variants`, which a variant-level row has to point at) and then
/// pinned to v28 so only `from28To29` executes.
class V28Fixture {
  V28Fixture(this.db, this.reopen);
  final v14.DatabaseAtV14 db;
  final DatabaseConnection Function() reopen;
}

const _seededAt = '2026-01-01T00:00:00.000Z';

Future<V28Fixture> buildV28(DatabaseConnection Function() connect) async {
  final connection = connect();
  final db = v14.DatabaseAtV14(connection);

  for (final (id, name) in const [
    ('shop-cafe', 'Cafe'),
    ('shop-truck', 'Food Truck'),
  ]) {
    await db
        .into(db.shops)
        .insert(
          v14.ShopsCompanion.insert(
            id: id,
            name: name,
            createdAt: _seededAt,
            updatedAt: _seededAt,
          ),
        );
  }

  await db
      .into(db.categories)
      .insert(
        v14.CategoriesCompanion.insert(
          id: 'cat-chai',
          name: 'Chai',
          createdAt: _seededAt,
          updatedAt: _seededAt,
        ),
      );

  // Owned by the Cafe and published to the truck. SPL Milk Chai ships in two
  // sizes, which is exactly why the overlay is variant-scoped: one number for
  // the whole product would let a 160ml sale eat the 100ml shelf.
  await db
      .into(db.products)
      .insert(
        v14.ProductsCompanion.insert(
          id: 'p-chai',
          categoryId: 'cat-chai',
          name: 'SPL Milk Chai',
          sellingPricePaise: 6000,
          createdAt: _seededAt,
          updatedAt: _seededAt,
        ),
      );

  for (final (id, name, price) in const [
    ('pv-chai-100', '100ml', 6000),
    ('pv-chai-160', '160ml', 9000),
  ]) {
    await db
        .into(db.productVariants)
        .insert(
          v14.ProductVariantsCompanion.insert(
            id: id,
            productId: 'p-chai',
            name: name,
            sellingPricePaise: price,
            createdAt: _seededAt,
            updatedAt: _seededAt,
          ),
        );
  }

  await db.customStatement('PRAGMA user_version = 28');
  return V28Fixture(db, connect);
}

/// Opens the fixture through the real [AppDatabase] so the wired migration
/// runs, exactly as a device upgrading from v28 would experience it.
Future<AppDatabase> migrated(DatabaseConnection Function() connect) async {
  final fixture = await buildV28(connect);
  await fixture.db.close();

  final db = AppDatabase(fixture.reopen());
  await db.customSelect('SELECT 1').get();
  return db;
}

/// Writes one overlay row as raw SQL.
///
/// Raw rather than a Drift insert on purpose: the point of these tests is what
/// the DATABASE accepts, so the statement has to be the one the constraints
/// actually see. `created_at` / `updated_at` are Dart-side `clientDefault`s
/// rather than SQL defaults, which is exactly why they are spelled out here.
Future<void> addShelf(
  AppDatabase db, {
  required String id,
  required String shopId,
  String productId = 'p-chai',
  String? variantId,
  required int quantity,
}) {
  return db.customStatement(
    'INSERT INTO shop_product_stock '
    '(id, shop_id, product_id, variant_id, quantity, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [id, shopId, productId, variantId, quantity, _seededAt, _seededAt],
  );
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a v28 database has no overlay table and no overlay indexes', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV28(schema.newConnection);

    expect(await _ddl(fixture.db, 'shop_product_stock'), isNull);
    expect(await _indexNames(fixture.db), isEmpty);

    await fixture.db.close();
  });

  test(
    'the wired v28 -> v29 step adds the table and the variant column',
    () async {
      final schema = await verifier.schemaAt(14);
      final db = await migrated(schema.newConnection);
      addTearDown(db.close);

      expect(await _ddl(db, 'shop_product_stock'), isNotNull);
      expect(
        await _columns(db, 'shop_product_stock'),
        containsAll(<String>[
          'id',
          'shop_id',
          'product_id',
          'variant_id',
          'quantity',
          'created_at',
          'updated_at',
        ]),
        reason: 'a sellable unit is either the product or one of its variants',
      );

      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .first,
        AppConstants.databaseSchemaVersion,
      );
    },
  );

  test(
    'the step creates all four indexes, both unique ones included',
    () async {
      final schema = await verifier.schemaAt(14);
      final db = await migrated(schema.newConnection);
      addTearDown(db.close);

      expect(
        await _indexNames(db),
        containsAll(<String>[
          'idx_shop_product_stock_shop',
          'idx_shop_product_stock_product',
          'ux_shop_product_stock_product_level',
          'ux_shop_product_stock_variant_level',
        ]),
        reason: 'the plain lookups AND the two partial unique indexes',
      );
    },
  );

  test('the two unique indexes are partial and keyed as designed', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    final product = await _indexSql(db, 'ux_shop_product_stock_product_level');
    expect(product, contains('UNIQUE'));
    expect(product, contains('(shop_id, product_id)'));
    expect(product, contains('variant_id IS NULL'));

    final variant = await _indexSql(db, 'ux_shop_product_stock_variant_level');
    expect(variant, contains('UNIQUE'));
    expect(variant, contains('(shop_id, product_id, variant_id)'));
    expect(variant, contains('variant_id IS NOT NULL'));
  });

  test('a duplicate product-level row for one shop is rejected', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    await addShelf(db, id: 'row-1', shopId: 'shop-truck', quantity: 30);

    await expectLater(
      addShelf(db, id: 'row-2', shopId: 'shop-truck', quantity: 5),
      throwsA(anything),
      reason:
          'two shelves for the same business and product would make the '
          'deduction ambiguous and the read a SUM instead of a single row',
    );

    final remaining = await db
        .customSelect(
          "SELECT id FROM shop_product_stock WHERE shop_id = 'shop-truck'",
        )
        .get();
    expect(remaining, hasLength(1));
    expect(remaining.single.data['id'], 'row-1');
  });

  test('two businesses can each hold the same product-level shelf', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    // Cafe 100, truck 30: the same drink, two physically separate shelves.
    // The uniqueness is per business precisely so this is legal.
    await addShelf(db, id: 'cafe-chai', shopId: 'shop-cafe', quantity: 100);
    await addShelf(db, id: 'truck-chai', shopId: 'shop-truck', quantity: 30);

    final rows = await db
        .customSelect(
          'SELECT shop_id, quantity FROM shop_product_stock '
          'WHERE product_id = ? ORDER BY shop_id',
          variables: [Variable.withString('p-chai')],
        )
        .get();
    expect(rows, hasLength(2));
    expect(rows[0].data['shop_id'], 'shop-cafe');
    expect(rows[0].data['quantity'], 100);
    expect(rows[1].data['shop_id'], 'shop-truck');
    expect(rows[1].data['quantity'], 30);
  });

  test('a product-level and a variant-level row can coexist', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    // The plain product shelf and the 100ml variant shelf are different
    // shelves. A `UNIQUE (shop_id, product_id, variant_id)` with no partial
    // split would let the two levels collide here by accident, so this is the
    // case that proves the indexes are actually partial.
    await addShelf(db, id: 'row-product', shopId: 'shop-truck', quantity: 10);
    await addShelf(
      db,
      id: 'row-100',
      shopId: 'shop-truck',
      variantId: 'pv-chai-100',
      quantity: 4,
    );
    await addShelf(
      db,
      id: 'row-160',
      shopId: 'shop-truck',
      variantId: 'pv-chai-160',
      quantity: 7,
    );

    final rows = await db
        .customSelect(
          'SELECT variant_id, quantity FROM shop_product_stock '
          "WHERE shop_id = 'shop-truck' ORDER BY variant_id",
        )
        .get();
    expect(rows, hasLength(3));
    expect(rows[0].data['variant_id'], isNull);
    expect(rows[0].data['quantity'], 10);
    expect(rows[1].data['variant_id'], 'pv-chai-100');
    expect(rows[1].data['quantity'], 4);
    expect(rows[2].data['variant_id'], 'pv-chai-160');
    expect(rows[2].data['quantity'], 7);
  });

  test('a duplicate variant-level row for one shop is rejected', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    await addShelf(
      db,
      id: 'row-1',
      shopId: 'shop-truck',
      variantId: 'pv-chai-100',
      quantity: 4,
    );

    await expectLater(
      addShelf(
        db,
        id: 'row-2',
        shopId: 'shop-truck',
        variantId: 'pv-chai-100',
        quantity: 9,
      ),
      throwsA(anything),
      reason: 'one shelf per business per variant is the whole point',
    );

    final remaining = await db
        .customSelect(
          'SELECT id, quantity FROM shop_product_stock '
          "WHERE variant_id = 'pv-chai-100'",
        )
        .get();
    expect(remaining, hasLength(1));
    expect(remaining.single.data['quantity'], 4);
  });

  test('the same variant shelf is independent per business', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    await addShelf(
      db,
      id: 'cafe-100',
      shopId: 'shop-cafe',
      variantId: 'pv-chai-100',
      quantity: 60,
    );
    await addShelf(
      db,
      id: 'truck-100',
      shopId: 'shop-truck',
      variantId: 'pv-chai-100',
      quantity: 12,
    );

    final rows = await db
        .customSelect(
          'SELECT shop_id, quantity FROM shop_product_stock '
          "WHERE variant_id = 'pv-chai-100' ORDER BY shop_id",
        )
        .get();
    expect(rows, hasLength(2));
    expect(rows[0].data['quantity'], 60);
    expect(rows[1].data['quantity'], 12);
  });

  test(
    'the step leaves the existing Cafe rows and the stock floor intact',
    () async {
      final schema = await verifier.schemaAt(14);
      final db = await migrated(schema.newConnection);
      addTearDown(db.close);

      final shops = await db
          .customSelect('SELECT id, name FROM shops ORDER BY id')
          .get();
      expect(shops, hasLength(2));
      expect(shops[0].data['id'], 'shop-cafe');
      expect(shops[1].data['id'], 'shop-truck');

      final chai = await db
          .customSelect(
            'SELECT name, selling_price_paise FROM products WHERE id = ?',
            variables: [Variable.withString('p-chai')],
          )
          .getSingle();
      expect(chai.data['name'], 'SPL Milk Chai');
      expect(chai.data['selling_price_paise'], 6000);

      // A shared definition is shared; the step must not republish or reprice it.
      expect(
        await db.customSelect('SELECT * FROM shop_product_stock').get(),
        isEmpty,
        reason: 'the overlay is a shelf, not a seeded quantity',
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test('a negative overlay quantity is still refused', () async {
    final schema = await verifier.schemaAt(14);
    final db = await migrated(schema.newConnection);
    addTearDown(db.close);

    // The CHECK travels with the table definition, and a negative shelf would
    // let a sale hand out stock that was never there.
    await expectLater(
      addShelf(db, id: 'row-neg', shopId: 'shop-truck', quantity: -1),
      throwsA(anything),
    );
  });

  test('the wired step is a no-op on an already-migrated database', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV28(schema.newConnection);
    await fixture.db.close();

    final first = AppDatabase(fixture.reopen());
    await first.customSelect('SELECT 1').get();
    final indexes = await _indexNames(first);
    final ddl = await _ddl(first, 'shop_product_stock');
    await first.close();

    final second = AppDatabase(fixture.reopen());
    await second.customSelect('SELECT 1').get();
    expect(await _indexNames(second), indexes);
    expect(await _ddl(second, 'shop_product_stock'), ddl);
    expect(indexes, hasLength(4), reason: 're-opening must not add a fifth');
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
    'a fresh install gets the same two unique indexes as an upgrade',
    () async {
      // The gap this step fixes is invisible on a fresh install, because
      // `createAll` emits every index in the definition. Comparing the two paths
      // is what proves an upgraded device is not silently weaker.
      final fresh = AppDatabase(NativeDatabase.memory());
      await fresh.customSelect('SELECT 1').get();
      final freshIndexes = await _indexNames(fresh);
      await fresh.close();

      final schema = await verifier.schemaAt(14);
      final upgraded = await migrated(schema.newConnection);
      addTearDown(upgraded.close);

      expect(await _indexNames(upgraded), freshIndexes);
    },
  );
}
