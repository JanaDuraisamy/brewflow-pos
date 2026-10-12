import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// Product true-delete — populated v30 -> v31 migration gate
///
/// A product that had any sale, purchase or stock history could never be
/// deleted: six historical foreign keys carried `ON DELETE RESTRICT`
/// (`{sale_items,purchase_items,stock_movements}.product_id` and their
/// `variant_id` columns), so the app had to fake deletion with a hidden,
/// deactivated row. Schema v31 removes those six keys while keeping the id as a
/// plain column, retargets the two *operational* keys, and must leave every
/// historical bill byte-identical.
///
/// The fixture below is a real database stamped at v30, built on the frozen v14
/// schema with the five affected tables recreated in their exact v30 shape
/// (RESTRICT keys included) and populated. The real migrator then runs
/// 30 -> 31 over it with foreign keys enforced.
///
/// Two SQLite facts make this non-trivial, and both are exercised here:
///  * `PRAGMA foreign_keys = OFF` is a **no-op inside a transaction**, and drift
///    runs every step inside one, so the textbook rebuild recipe is unavailable.
///  * `product_variants` is a *referenced* table (`shop_product_stock` points at
///    it), so dropping and recreating it needs enforcement deferred to COMMIT.
///
/// Verified with `PRAGMA defer_foreign_keys = ON`, the same technique proven for
/// the customer FK removal in v25 -> v26.
/// ---------------------------------------------------------------------------

/// The historical tables whose every column must survive the migration.
const _historicalTables = ['sale_items', 'purchase_items', 'stock_movements'];

/// v30 `sale_items`: both product/variant keys are `ON DELETE RESTRICT`.
const _saleItemsV30 =
    'CREATE TABLE sale_items ('
    '"id" TEXT NOT NULL PRIMARY KEY, '
    '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"sale_id" TEXT NOT NULL REFERENCES sales (id) ON DELETE RESTRICT, '
    '"product_id" TEXT NOT NULL REFERENCES products (id) ON DELETE RESTRICT, '
    '"variant_id" TEXT NULL REFERENCES product_variants (id) ON DELETE RESTRICT, '
    '"product_name" TEXT NOT NULL, '
    '"variant_name" TEXT NULL, '
    '"sku" TEXT NULL, '
    '"unit_price_paise" INTEGER NOT NULL CHECK (unit_price_paise >= 0), '
    '"quantity" INTEGER NOT NULL CHECK (quantity > 0), '
    '"line_total_paise" INTEGER NOT NULL CHECK (line_total_paise >= 0), '
    '"offer_discount_paise" INTEGER NOT NULL DEFAULT 0 CHECK (offer_discount_paise >= 0), '
    '"applied_offer_id" TEXT NULL, '
    '"applied_offer_name" TEXT NULL, '
    '"applied_offer_type" TEXT CHECK (applied_offer_type IS NULL OR '
    'applied_offer_type IN (\'PERCENTAGE\', \'COMBO\', \'BUY_X_GET_Y\', \'QUANTITY_TIER\')))';

/// v30 `purchase_items`.
const _purchaseItemsV30 =
    'CREATE TABLE purchase_items ('
    '"id" TEXT NOT NULL PRIMARY KEY, '
    '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"purchase_id" TEXT NOT NULL REFERENCES purchases (id) ON DELETE RESTRICT, '
    '"product_id" TEXT NOT NULL REFERENCES products (id) ON DELETE RESTRICT, '
    '"variant_id" TEXT NULL REFERENCES product_variants (id) ON DELETE RESTRICT, '
    '"product_name" TEXT NOT NULL, '
    '"variant_name" TEXT NULL, '
    '"sku" TEXT NULL, '
    '"unit_cost_paise" INTEGER NOT NULL CHECK (unit_cost_paise >= 0), '
    '"quantity" INTEGER NOT NULL CHECK (quantity > 0), '
    '"line_total_paise" INTEGER NOT NULL CHECK (line_total_paise >= 0))';

/// v30 `stock_movements`.
const _stockMovementsV30 =
    'CREATE TABLE stock_movements ('
    '"id" TEXT NOT NULL PRIMARY KEY, '
    '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"product_id" TEXT NOT NULL REFERENCES products (id) ON DELETE RESTRICT, '
    '"variant_id" TEXT NULL REFERENCES product_variants (id) ON DELETE RESTRICT, '
    '"movement_type" TEXT NOT NULL CHECK (movement_type IN '
    '(\'OPENING\', \'SALE\', \'PURCHASE\', \'ADJUSTMENT_IN\', \'ADJUSTMENT_OUT\')), '
    '"quantity" INTEGER NOT NULL CHECK (quantity <> 0), '
    '"stock_before" INTEGER NOT NULL CHECK (stock_before >= 0), '
    '"stock_after" INTEGER NOT NULL CHECK (stock_after >= 0), '
    '"reason" TEXT CHECK (reason IS NULL OR reason IN '
    '(\'PURCHASE\', \'DAMAGE\', \'WASTAGE\', \'MISSING\', \'CORRECTION\', \'OTHER\')), '
    '"note" TEXT NULL, '
    '"reference_type" TEXT NULL, '
    '"reference_id" TEXT NULL, '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL)';

/// v30 `product_variants` — the key the step retargets to `ON DELETE CASCADE`.
const _productVariantsV30 =
    'CREATE TABLE product_variants ('
    '"id" TEXT NOT NULL PRIMARY KEY, '
    '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"product_id" TEXT NOT NULL REFERENCES products (id) ON DELETE RESTRICT, '
    '"name" TEXT NOT NULL, '
    '"sku" TEXT NULL, '
    '"selling_price_paise" INTEGER NOT NULL CHECK (selling_price_paise >= 0), '
    '"cost_price_paise" INTEGER CHECK (cost_price_paise IS NULL OR cost_price_paise >= 0), '
    '"stock_quantity" INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0), '
    '"low_stock_mode" TEXT NOT NULL DEFAULT \'USE_DEFAULT\' CHECK (low_stock_mode IN '
    '(\'USE_DEFAULT\', \'CUSTOM\', \'OFF\')), '
    '"low_stock_threshold" INTEGER CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0), '
    '"membership_enabled" INTEGER NOT NULL DEFAULT 0 CHECK (membership_enabled IN (0, 1)), '
    '"member_price_paise" INTEGER CHECK (member_price_paise IS NULL OR member_price_paise >= 0), '
    '"is_active" INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)), '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL)';

/// v30 `shop_product_stock` — `variant_id` is the key the step retargets to
/// `ON DELETE SET NULL`; `product_id` already cascades.
const _shopProductStockV30 =
    'CREATE TABLE shop_product_stock ('
    '"id" TEXT NOT NULL PRIMARY KEY, '
    '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"product_id" TEXT NOT NULL REFERENCES products (id) ON DELETE CASCADE, '
    '"variant_id" TEXT NULL REFERENCES product_variants (id) ON DELETE RESTRICT, '
    '"quantity" INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0), '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL)';

/// Index DDL the step must recreate on every rebuilt table.
const _indexesV30 = <String, List<String>>{
  'sale_items': [
    'CREATE INDEX idx_sale_items_shop ON sale_items (shop_id)',
    'CREATE INDEX idx_sale_items_sale_id ON sale_items (shop_id, sale_id)',
  ],
  'purchase_items': [
    'CREATE INDEX idx_purchase_items_shop ON purchase_items (shop_id)',
    'CREATE INDEX idx_purchase_items_purchase_id ON purchase_items (shop_id, purchase_id)',
  ],
  'stock_movements': [
    'CREATE INDEX idx_stock_movements_shop ON stock_movements (shop_id)',
    'CREATE INDEX idx_stock_movements_product_created_at ON stock_movements (shop_id, product_id, created_at)',
    'CREATE INDEX idx_stock_movements_variant_created_at ON stock_movements (shop_id, variant_id, created_at)',
  ],
  'product_variants': [
    'CREATE INDEX idx_product_variants_shop ON product_variants (shop_id)',
    'CREATE INDEX idx_product_variants_product_id ON product_variants (product_id)',
    'CREATE INDEX idx_product_variants_sku ON product_variants (sku)',
    'CREATE INDEX idx_product_variants_updated_at ON product_variants (shop_id, updated_at)',
  ],
  'shop_product_stock': [
    'CREATE INDEX idx_shop_product_stock_shop ON shop_product_stock (shop_id)',
    'CREATE INDEX idx_shop_product_stock_product ON shop_product_stock (shop_id, product_id)',
    'CREATE UNIQUE INDEX ux_shop_product_stock_product_level ON shop_product_stock (shop_id, product_id) WHERE variant_id IS NULL',
    'CREATE UNIQUE INDEX ux_shop_product_stock_variant_level ON shop_product_stock (shop_id, product_id, variant_id) WHERE variant_id IS NOT NULL',
  ],
};

/// Full contents of [table], ordered by id.
Future<List<Map<String, Object?>>> _snapshot(
  GeneratedDatabase db,
  String table,
) async {
  final rows = await db.customSelect('SELECT * FROM $table ORDER BY id').get();
  return [for (final row in rows) row.data];
}

/// Asserts every column the fixture captured survives unchanged, matching by
/// content rather than by an exact column set. The migrator runs the whole
/// remaining chain to the live schema, so a later *additive* step (e.g.
/// `sale_items.consumed` at v35) may append a column to a historical table;
/// that is not this migration's doing and is ignored.
void _expectPreserved(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after, {
  required String reason,
}) {
  expect(after, hasLength(before.length), reason: reason);
  for (var i = 0; i < before.length; i++) {
    for (final entry in before[i].entries) {
      expect(
        after[i][entry.key],
        entry.value,
        reason: '$reason (column ${entry.key})',
      );
    }
  }
}

Future<String> _ddl(GeneratedDatabase db, String table) async {
  final row = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      )
      .getSingle();
  return row.data['sql'] as String;
}

Future<Set<String>> _indexes(GeneratedDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ? "
        "AND name NOT LIKE 'sqlite_%'",
        variables: [Variable.withString(table)],
      )
      .get();
  return {for (final row in rows) row.data['name'] as String};
}

/// Every foreign key declared on [table], as `from -> table ON DELETE action`.
Future<Set<String>> _foreignKeys(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA foreign_key_list($table)').get();
  return {
    for (final row in rows)
      '${row.read<String>('from')} -> ${row.read<String>('table')} '
          'ON DELETE ${row.read<String>('on_delete')}',
  };
}

/// A populated database stamped at v30, with all six historical RESTRICT keys
/// and both operational keys still in their old shape.
class V30Fixture {
  V30Fixture(this.db, this.reopen, this.before);
  final v14.DatabaseAtV14 db;

  /// A fresh connection to the same database, so the fixture's own wrapper can
  /// be closed before the real [AppDatabase] takes over.
  final DatabaseConnection Function() reopen;

  /// Byte-for-byte contents of [_historicalTables] before migrating.
  final Map<String, List<Map<String, Object?>>> before;
}

Future<V30Fixture> buildPopulatedV30(
  DatabaseConnection Function() connect,
) async {
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
          id: 'cat-1',
          name: 'Beverages',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  await db
      .into(db.products)
      .insert(
        v14.ProductsCompanion.insert(
          id: 'p-busy',
          categoryId: 'cat-1',
          name: 'Filter Coffee',
          sellingPricePaise: 12000,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  await db
      .into(db.products)
      .insert(
        v14.ProductsCompanion.insert(
          id: 'p-quiet',
          categoryId: 'cat-1',
          name: 'Never Sold',
          sellingPricePaise: 9000,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  // The two tables that did not exist at v14, in their exact v30 shape.
  await db.customStatement('DROP TABLE IF EXISTS shop_product_stock');
  await db.customStatement('DROP TABLE IF EXISTS product_variants');
  await db.customStatement(_productVariantsV30);
  await db.customStatement(_shopProductStockV30);

  // The three historical tables already carry the right v30 keys at v14; only
  // sale_items still needs its offer columns added to reach the v30 shape.
  await db.customStatement('DROP TABLE IF EXISTS sale_items');
  await db.customStatement(_saleItemsV30);
  for (final ddl in _indexesV30['sale_items']!) {
    await db.customStatement(ddl);
  }
  await db.customStatement('DROP TABLE IF EXISTS purchase_items');
  await db.customStatement(_purchaseItemsV30);
  for (final ddl in _indexesV30['purchase_items']!) {
    await db.customStatement(ddl);
  }
  await db.customStatement('DROP TABLE IF EXISTS stock_movements');
  await db.customStatement(_stockMovementsV30);
  for (final ddl in _indexesV30['stock_movements']!) {
    await db.customStatement(ddl);
  }
  for (final ddl in _indexesV30['product_variants']!) {
    await db.customStatement(ddl);
  }
  for (final ddl in _indexesV30['shop_product_stock']!) {
    await db.customStatement(ddl);
  }

  await db.customStatement(
    'INSERT INTO product_variants (id, shop_id, product_id, name, sku, '
    'selling_price_paise, cost_price_paise, stock_quantity, is_active, '
    'created_at, updated_at) VALUES '
    "('v-1', 'shop-cafe', 'p-busy', 'Large', 'CF-L', 15000, 7000, 4, 1, "
    "'2026-01-02T00:00:00.000Z', '2026-01-02T00:00:00.000Z')",
  );
  await db.customStatement(
    'INSERT INTO shop_product_stock (id, shop_id, product_id, variant_id, '
    'quantity, created_at, updated_at) VALUES '
    "('sps-1', 'shop-cafe', 'p-busy', 'v-1', 3, "
    "'2026-01-02T00:00:00.000Z', '2026-01-02T00:00:00.000Z')",
  );

  // `sales` / `purchases` / `suppliers` are left in their frozen v14 shape —
  // v31 does not touch them — so these inserts use the columns that exist
  // there. `sale_items` / `purchase_items` / `stock_movements` were recreated
  // above at the v30 shape, so their `shop_id` is present.
  await db.customStatement(
    'INSERT INTO sales (id, receipt_number, subtotal_paise, total_paise, '
    'payment_method, payment_status, created_at, updated_at) '
    "VALUES ('s-1', 'BF-000001', 30000, 30000, 'CASH', 'PAID', "
    "'2026-01-03T10:00:00.000Z', '2026-01-03T10:00:00.000Z')",
  );
  await db.customStatement(
    'INSERT INTO sale_items (id, shop_id, sale_id, product_id, variant_id, '
    'product_name, variant_name, sku, unit_price_paise, quantity, '
    'line_total_paise) VALUES '
    "('si-1', 'shop-cafe', 's-1', 'p-busy', 'v-1', 'Filter Coffee', 'Large', "
    "'CF-L', 15000, 2, 30000)",
  );

  await db.customStatement(
    'INSERT INTO suppliers (id, name, created_at, updated_at) '
    "VALUES ('sup-1', 'Beans Co', "
    "'2026-01-04T00:00:00.000Z', '2026-01-04T00:00:00.000Z')",
  );
  await db.customStatement(
    'INSERT INTO purchases (id, supplier_id, purchase_number, subtotal_paise, '
    'total_paise, created_at, updated_at) '
    "VALUES ('pu-1', 'sup-1', 'PUR-000001', 14000, 14000, "
    "'2026-01-04T11:00:00.000Z', '2026-01-04T11:00:00.000Z')",
  );
  await db.customStatement(
    'INSERT INTO purchase_items (id, shop_id, purchase_id, product_id, '
    'variant_id, product_name, variant_name, sku, unit_cost_paise, quantity, '
    'line_total_paise) VALUES '
    "('pi-1', 'shop-cafe', 'pu-1', 'p-busy', 'v-1', 'Filter Coffee', 'Large', "
    "'CF-L', 7000, 2, 14000)",
  );

  await db.customStatement(
    'INSERT INTO stock_movements (id, shop_id, product_id, variant_id, '
    'movement_type, quantity, stock_before, stock_after, reference_type, '
    'reference_id, created_at, updated_at) VALUES '
    "('sm-1', 'shop-cafe', 'p-busy', 'v-1', 'OPENING', 5, 0, 5, NULL, NULL, "
    "'2026-01-02T00:00:00.000Z', '2026-01-02T00:00:00.000Z'), "
    "('sm-2', 'shop-cafe', 'p-busy', 'v-1', 'SALE', -2, 5, 3, 'SALE', 's-1', "
    "'2026-01-03T10:00:00.000Z', '2026-01-03T10:00:00.000Z')",
  );

  final before = <String, List<Map<String, Object?>>>{};
  for (final table in _historicalTables) {
    before[table] = await _snapshot(db, table);
  }
  await db.customStatement('PRAGMA user_version = 30');
  return V30Fixture(db, connect, before);
}

/// Runs the real migrator from the fixture's v30 stamp to the live schema.
Future<AppDatabase> migrateToLive(V30Fixture fixture) async {
  final db = AppDatabase(fixture.reopen());
  await db.customSelect('SELECT 1').get();
  return db;
}

/// The index names a set of `CREATE INDEX` statements declares.
Set<String> _indexNames(List<String> ddl) {
  return {
    for (final statement in ddl)
      RegExp(r'INDEX\s+(\w+)').firstMatch(statement)!.group(1)!,
  };
}

Future<int> _userVersion(GeneratedDatabase db) async {
  return (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first!
      as int;
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    'the v30 schema blocks a hard delete of a product with history',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV30(schema.newConnection);
      await fixture.db.customStatement('PRAGMA foreign_keys = ON');

      // The exact bug v31 removes: one sale line, one purchase line and two
      // stock movements are enough to make the product undeletable.
      await expectLater(
        fixture.db.customStatement("DELETE FROM products WHERE id = 'p-busy'"),
        throwsA(anything),
        reason: 'ON DELETE RESTRICT must block this before the migration',
      );
      final still = await fixture.db
          .customSelect("SELECT id FROM products WHERE id = 'p-busy'")
          .get();
      expect(
        still,
        hasLength(1),
        reason: 'the product must survive the refusal',
      );

      await fixture.db.close();
    },
  );

  test('the wired v30 -> v31 step preserves a populated history', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildPopulatedV30(schema.newConnection);
    await fixture.db.close();

    final db = await migrateToLive(fixture);
    try {
      expect(
        await _userVersion(db),
        AppConstants.databaseSchemaVersion,
        reason: 'the step must land on the live schema',
      );

      for (final table in _historicalTables) {
        _expectPreserved(
          fixture.before[table]!,
          await _snapshot(db, table),
          reason: '$table must survive the migration byte-identical',
        );
      }

      // Every index on a rebuilt table is recreated with the table.
      for (final entry in _indexesV30.entries) {
        expect(
          await _indexes(db, entry.key),
          _indexNames(entry.value),
          reason: '${entry.key} indexes must be preserved',
        );
      }
    } finally {
      await db.close();
    }
  });

  test(
    'v31 drops the historical keys and retargets the operational ones',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV30(schema.newConnection);
      await fixture.db.close();
      final db = await migrateToLive(fixture);
      try {
        // Historical ledgers: no product/variant key at all. The id survives as a
        // plain column, which is what keeps the ledger's attribution.
        for (final table in _historicalTables) {
          final keys = await _foreignKeys(db, table);
          expect(
            keys.any((k) => k.contains(' -> products ')),
            isFalse,
            reason: '$table must no longer reference products',
          );
          expect(
            keys.any((k) => k.contains(' -> product_variants ')),
            isFalse,
            reason: '$table must no longer reference product_variants',
          );
        }

        // A variant is part of the product's definition, so it cascades.
        expect(
          await _foreignKeys(db, 'product_variants'),
          contains('product_id -> products ON DELETE CASCADE'),
        );

        // A current stock overlay can never veto a variant's removal.
        expect(
          await _foreignKeys(db, 'shop_product_stock'),
          contains('variant_id -> product_variants ON DELETE SET NULL'),
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'after migrating, the product is really deletable and history is not',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV30(schema.newConnection);
      await fixture.db.close();
      final db = await migrateToLive(fixture);
      try {
        await db.customStatement('PRAGMA foreign_keys = ON');

        await db.customStatement("DELETE FROM products WHERE id = 'p-busy'");

        expect(
          await db
              .customSelect("SELECT id FROM products WHERE id = 'p-busy'")
              .get(),
          isEmpty,
          reason: 'the catalogue row must be gone, not deactivated',
        );

        // Operational rows die with the product.
        expect(
          await _snapshot(db, 'product_variants'),
          isEmpty,
          reason: 'variants are product definition, not history',
        );
        expect(
          await _snapshot(db, 'shop_product_stock'),
          isEmpty,
          reason: 'no dangling active stock may survive',
        );

        // History is untouched, snapshots included.
        for (final table in _historicalTables) {
          _expectPreserved(
            fixture.before[table]!,
            await _snapshot(db, table),
            reason: '$table must be completely unaffected by the delete',
          );
        }

        // The sale header is intact too, so the bill still reconciles.
        final sale = await db
            .customSelect(
              "SELECT receipt_number, total_paise FROM sales WHERE id = 's-1'",
            )
            .getSingle();
        expect(sale.data['receipt_number'], 'BF-000001');
        expect(sale.data['total_paise'], 30000);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'a deleted product leaves its bill readable from its own snapshots',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV30(schema.newConnection);
      await fixture.db.close();
      final db = await migrateToLive(fixture);
      try {
        await db.customStatement('PRAGMA foreign_keys = ON');
        await db.customStatement("DELETE FROM products WHERE id = 'p-busy'");

        // Exactly what a receipt renders: the line's own name/sku/price snapshot,
        // with the product id left dangling rather than nulled or erased.
        final line = await db
            .customSelect(
              'SELECT product_id, product_name, variant_name, sku, '
              'unit_price_paise, quantity, line_total_paise '
              "FROM sale_items WHERE id = 'si-1'",
            )
            .getSingle();
        expect(line.data['product_id'], 'p-busy');
        expect(line.data['product_name'], 'Filter Coffee');
        expect(line.data['variant_name'], 'Large');
        expect(line.data['sku'], 'CF-L');
        expect(line.data['unit_price_paise'], 15000);
        expect(line.data['quantity'], 2);
        expect(line.data['line_total_paise'], 30000);

        final purchaseLine = await db
            .customSelect(
              'SELECT product_name, variant_name, sku, unit_cost_paise, '
              'quantity, line_total_paise FROM purchase_items WHERE id = \'pi-1\'',
            )
            .getSingle();
        expect(purchaseLine.data['product_name'], 'Filter Coffee');
        expect(purchaseLine.data['variant_name'], 'Large');
        expect(purchaseLine.data['unit_cost_paise'], 7000);
        expect(purchaseLine.data['line_total_paise'], 14000);

        final movements = await _snapshot(db, 'stock_movements');
        expect(movements, hasLength(2));
        expect(movements.map((m) => m['quantity']), containsAll(<int>[5, -2]));
      } finally {
        await db.close();
      }
    },
  );

  test(
    'a product with no history at all is unaffected by the rebuild',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV30(schema.newConnection);
      await fixture.db.close();
      final db = await migrateToLive(fixture);
      try {
        await db.customStatement('PRAGMA foreign_keys = ON');
        await db.customStatement("DELETE FROM products WHERE id = 'p-quiet'");
        expect(
          await db
              .customSelect("SELECT id FROM products WHERE id = 'p-quiet'")
              .get(),
          isEmpty,
          reason: 'a product that never transacted deletes like any other',
        );
        expect(
          await db
              .customSelect("SELECT id FROM products WHERE id = 'p-busy'")
              .get(),
          hasLength(1),
          reason: 'deleting one product must not touch another',
        );
        for (final table in _historicalTables) {
          _expectPreserved(
            fixture.before[table]!,
            await _snapshot(db, table),
            reason: '$table must survive deleting an unrelated product',
          );
        }
      } finally {
        await db.close();
      }
    },
  );

  test(
    'the wired v30 -> v31 step is a no-op on an already-migrated database',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV30(schema.newConnection);
      await fixture.db.close();

      final first = await migrateToLive(fixture);
      final migrated = <String, List<Map<String, Object?>>>{};
      for (final table in _historicalTables) {
        migrated[table] = await _snapshot(first, table);
      }
      final ddls = <String, String>{
        for (final table in _historicalTables) table: await _ddl(first, table),
      };
      await first.close();

      // Re-running the wired step must not rebuild the tables a second time:
      // a rebuild rewrites every historical row, and doing it twice is exactly
      // the kind of thing a migration must never do.
      final second = AppDatabase(fixture.reopen());
      await second.customSelect('SELECT 1').get();
      try {
        expect(await _userVersion(second), AppConstants.databaseSchemaVersion);
        for (final table in _historicalTables) {
          expect(await _snapshot(second, table), migrated[table]);
          expect(await _ddl(second, table), ddls[table]);
        }
      } finally {
        await second.close();
      }
    },
  );
}
