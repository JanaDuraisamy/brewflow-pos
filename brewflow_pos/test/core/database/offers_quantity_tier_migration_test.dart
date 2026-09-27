import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// v24 -> v25 migration test (quantity-tier offers)
///
/// `from24To25` widens the `offers.type` CHECK to accept QUANTITY_TIER, which
/// SQLite cannot do in place — the table is rebuilt (backup -> drop -> create
/// -> restore). This test materialises a real database that already contains
/// the v24-shaped `offers` table, seeds one offer row of every pre-existing
/// type plus edge-case values, and then opens the real [AppDatabase] on it so
/// the genuine migration step runs.
///
/// Follows the same approach as `probe_migration_test.dart`: the generated
/// `GeneratedHelper` only goes up to v14, so the v24 `offers` table is created
/// by hand on top of a v14 database and stamped with `user_version = 24`. The
/// migrator then runs exactly the v24 -> v25 step.
///
/// It proves: no offer row is lost or altered, the widened CHECK accepts
/// QUANTITY_TIER, the old CHECK's guarantee still holds for unknown types, and
/// both indexes are restored with no backup table left behind.
/// ---------------------------------------------------------------------------

/// Everything a test needs after the v24 fixture has been built.
class _V24Fixture {
  _V24Fixture({
    required this.newConnection,
    required this.before,
    this.saleItemRowsBefore = const [],
  });
  final DatabaseConnection Function() newConnection;
  final List<QueryRow> before;
  final List<QueryRow> saleItemRowsBefore;
}

/// Columns of the v24-shaped `sale_items` table, in declaration order. The
/// migration copies rows with `SELECT *`, so the fixture must present the
/// exact v24 column set (v14 predates the offer-snapshot columns entirely).
const _saleItemColumns = [
  'id',
  'shop_id',
  'sale_id',
  'product_id',
  'variant_id',
  'product_name',
  'variant_name',
  'sku',
  'unit_price_paise',
  'quantity',
  'line_total_paise',
  'offer_discount_paise',
  'applied_offer_id',
  'applied_offer_name',
  'applied_offer_type',
];

/// Creates the v24-shaped `sale_items` table (old three-value offer-type
/// CHECK) and seeds [rows], each given as a map keyed by [_saleItemColumns].
Future<void> _seedV24SaleItems(
  v14.DatabaseAtV14 db,
  List<Map<String, Object?>> rows,
) async {
  await db.customStatement('DROP TABLE sale_items');
  await db.customStatement(
    'CREATE TABLE sale_items ('
    '"id" TEXT NOT NULL, '
    '"shop_id" TEXT NULL REFERENCES shops (id) ON DELETE CASCADE, '
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
    "applied_offer_type IN ('PERCENTAGE','COMBO','BUY_X_GET_Y')), "
    'PRIMARY KEY ("id"))',
  );
  await db.customStatement(
    'CREATE INDEX idx_sale_items_shop ON sale_items (shop_id)',
  );
  await db.customStatement(
    'CREATE INDEX idx_sale_items_sale_id ON sale_items (shop_id, sale_id)',
  );

  final placeholders = List.filled(_saleItemColumns.length, '?').join(',');
  for (final row in rows) {
    await db.customStatement(
      'INSERT INTO sale_items (${_saleItemColumns.join(',')}) '
      'VALUES ($placeholders)',
      [for (final column in _saleItemColumns) row[column]],
    );
  }
}

/// One seeded sale-item row.
Map<String, Object?> saleItemRow(
  String id, {
  String saleId = 'sale-1',
  String productId = 'p1',
  int unitPricePaise = 12000,
  int quantity = 2,
  int lineTotalPaise = 24000,
  int offerDiscountPaise = 0,
  String? appliedOfferId,
  String? appliedOfferName,
  String? appliedOfferType,
  String? variantId,
  String? variantName,
  String? sku,
}) => {
  'id': id,
  'shop_id': 'shop-cafe',
  'sale_id': saleId,
  'product_id': productId,
  'variant_id': variantId,
  'product_name': 'Filter Coffee',
  'variant_name': variantName,
  'sku': sku,
  'unit_price_paise': unitPricePaise,
  'quantity': quantity,
  'line_total_paise': lineTotalPaise,
  'offer_discount_paise': offerDiscountPaise,
  'applied_offer_id': appliedOfferId,
  'applied_offer_name': appliedOfferName,
  'applied_offer_type': appliedOfferType,
};

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// One seeded offer row: id, shop, name, type, config, active, start, end.
  List<Object?> offerRow(
    String id,
    String name,
    String type,
    String configJson, {
    String? shopId = 'shop-cafe',
    bool isActive = true,
    String? startAt,
    String? endAt,
  }) => [
    id,
    shopId,
    name,
    type,
    configJson,
    isActive ? 1 : 0,
    startAt,
    endAt,
    '2026-02-01T10:00:00.000Z',
    '2026-02-02T11:30:00.000Z',
  ];

  /// Builds a database stamped at v24 whose `offers` table carries the
  /// pre-v25 three-value type CHECK, seeded with [offerRows], and captures the
  /// pre-migration contents for comparison.
  Future<_V24Fixture> buildV24Database({
    required List<List<Object?>> offerRows,
    List<Map<String, Object?>> saleItemRows = const [],
  }) async {
    final schema = await verifier.schemaAt(14);
    final v14Db = v14.DatabaseAtV14(schema.newConnection());

    // v14 already has `shops`, which `offers` references.
    await v14Db
        .into(v14Db.shops)
        .insert(
          v14.ShopsCompanion.insert(
            id: 'shop-cafe',
            name: 'Cafe',
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        );

    // The v24 offers definition, byte-compatible with the v25 table apart
    // from the widened type CHECK.
    await v14Db.customStatement(
      'CREATE TABLE offers ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'shop_id TEXT NULL REFERENCES shops(id) ON DELETE CASCADE, '
      'name TEXT NOT NULL, '
      "type TEXT NOT NULL CHECK (type IN ('PERCENTAGE','COMBO','BUY_X_GET_Y')), "
      'config_json TEXT NOT NULL, '
      'is_active INTEGER NOT NULL DEFAULT 1, '
      'start_at TEXT NULL, '
      'end_at TEXT NULL, '
      'created_at TEXT NOT NULL, '
      'updated_at TEXT NOT NULL)',
    );
    await v14Db.customStatement(
      'CREATE INDEX idx_offers_shop ON offers (shop_id)',
    );
    await v14Db.customStatement(
      'CREATE INDEX idx_offers_shop_active ON offers (shop_id, is_active)',
    );

    for (final row in offerRows) {
      await v14Db.customStatement(
        'INSERT INTO offers (id, shop_id, name, type, config_json, is_active, '
        'start_at, end_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        row,
      );
    }

    final before = await v14Db
        .customSelect('SELECT * FROM offers ORDER BY id')
        .get();

    // Populated ledger data so the `sale_items` rebuild is exercised against
    // real rows rather than an empty table.
    if (saleItemRows.isNotEmpty) {
      await v14Db
          .into(v14Db.categories)
          .insert(
            v14.CategoriesCompanion.insert(
              id: 'cat-1',
              name: 'Beverages',
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.products)
          .insert(
            v14.ProductsCompanion.insert(
              id: 'p1',
              categoryId: 'cat-1',
              name: 'Filter Coffee',
              sellingPricePaise: 12000,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.sales)
          .insert(
            v14.SalesCompanion.insert(
              id: 'sale-1',
              receiptNumber: 'BF-000001',
              subtotalPaise: 24000,
              totalPaise: 24000,
              paymentMethod: const Value('CASH'),
              createdAt: '2026-01-02T00:00:00.000Z',
              updatedAt: '2026-01-02T00:00:00.000Z',
            ),
          );
      await _seedV24SaleItems(v14Db, saleItemRows);
    }

    final saleItemRowsBefore = await v14Db
        .customSelect('SELECT * FROM sale_items ORDER BY id')
        .get();

    // Claim v24 so the migrator runs only the v24 -> v25 step.
    await v14Db.customStatement('PRAGMA user_version = 24');
    await v14Db.close();
    return _V24Fixture(
      newConnection: schema.newConnection,
      before: before,
      saleItemRowsBefore: saleItemRowsBefore,
    );
  }

  test('v24 -> v25 keeps every offer row byte-for-byte', () async {
    final fixture = await buildV24Database(
      offerRows: [
        offerRow('o1', 'Monsoon 10%', 'PERCENTAGE', '{"percent":10}'),
        offerRow(
          'o2',
          'Two Coffee Combo',
          'COMBO',
          '{"productIds":["p1","p2"],"comboPricePaise":15000}',
        ),
        offerRow(
          'o3',
          'Buy 2 Get 1',
          'BUY_X_GET_Y',
          '{"productId":"p1","buyQty":2,"getQty":1}',
        ),
        // Edge cases: inactive, a scheduled window, and a shop-less legacy row.
        offerRow(
          'o4',
          'Inactive',
          'PERCENTAGE',
          '{"percent":5}',
          isActive: false,
        ),
        offerRow(
          'o5',
          'Windowed',
          'COMBO',
          '{"productIds":["p1"],"comboPricePaise":5000}',
          startAt: '2026-03-01T00:00:00.000Z',
          endAt: '2026-03-31T00:00:00.000Z',
        ),
        offerRow('o6', 'No Shop', 'PERCENTAGE', '{"percent":1}', shopId: null),
      ],
    );
    expect(fixture.before, hasLength(6));

    final db = AppDatabase(fixture.newConnection());
    // Forces the onUpgrade chain to run.
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first;
    expect(
      version,
      AppConstants.databaseSchemaVersion,
      reason: 'v24 -> v25 must land on the live schema',
    );

    final after = await db
        .customSelect('SELECT * FROM offers ORDER BY id')
        .get();
    expect(after, hasLength(6), reason: 'no offer row may be lost');

    for (var i = 0; i < fixture.before.length; i++) {
      final b = fixture.before[i].data;
      final a = after[i].data;
      for (final column in [
        'id',
        'shop_id',
        'name',
        'type',
        'config_json',
        'is_active',
        'start_at',
        'end_at',
        'created_at',
        'updated_at',
      ]) {
        expect(
          a[column],
          b[column],
          reason: 'offers.$column changed for row ${b['id']}',
        );
      }
    }

    await db.close();
  });

  test('v24 -> v25 accepts QUANTITY_TIER and still rejects junk', () async {
    final fixture = await buildV24Database(
      offerRows: [
        offerRow('o1', 'Monsoon 10%', 'PERCENTAGE', '{"percent":10}'),
      ],
    );

    final db = AppDatabase(fixture.newConnection());
    await db.customSelect('SELECT 1').get();

    // The new type is now storable, including a realistic tier ladder.
    await db.customStatement(
      'INSERT INTO offers (id, shop_id, name, type, config_json, is_active, '
      'start_at, end_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'o-tier',
        'shop-cafe',
        'Kulfi Tiers',
        'QUANTITY_TIER',
        '{"productIds":["p1"],"tiers":['
            '{"quantity":1,"pricePaise":4500},'
            '{"quantity":2,"pricePaise":8500},'
            '{"quantity":3,"pricePaise":12000}]}',
        1,
        null,
        null,
        '2026-03-01T00:00:00.000Z',
        '2026-03-01T00:00:00.000Z',
      ],
    );
    final stored = await db
        .customSelect(
          "SELECT type, config_json FROM offers WHERE id = 'o-tier'",
        )
        .getSingle();
    expect(stored.data['type'], 'QUANTITY_TIER');
    expect(stored.data['config_json'], contains('12000'));

    // The pre-existing guarantee still holds for unknown types.
    await expectLater(
      db.customStatement(
        'INSERT INTO offers (id, shop_id, name, type, config_json, is_active, '
        'start_at, end_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          'o-bad',
          'shop-cafe',
          'Bogus',
          'NOT_A_TYPE',
          '{}',
          1,
          null,
          null,
          '2026-03-01T00:00:00.000Z',
          '2026-03-01T00:00:00.000Z',
        ],
      ),
      throwsA(anything),
    );

    await db.close();
  });

  test(
    'v24 -> v25 restores both offers indexes and leaves no backup',
    () async {
      final fixture = await buildV24Database(
        offerRows: [
          offerRow('o1', 'Monsoon 10%', 'PERCENTAGE', '{"percent":10}'),
        ],
      );

      final db = AppDatabase(fixture.newConnection());
      await db.customSelect('SELECT 1').get();

      final indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='index' "
                    "AND tbl_name='offers' AND name NOT LIKE 'sqlite_%'",
                  )
                  .get())
              .map((row) => row.data['name'])
              .toSet();
      expect(
        indexes,
        containsAll(<String>['idx_offers_shop', 'idx_offers_shop_active']),
      );

      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table'",
                  )
                  .get())
              .map((row) => row.data['name'])
              .toSet();
      expect(tables, isNot(contains('offers_bak_v25')));

      await db.close();
    },
  );

  group('v24 -> v25 sale_items rebuild', () {
    /// A populated v24 ledger: a plain line, a percentage-offer line, a
    /// combo line and a variant line.
    List<Map<String, Object?>> populatedLines() => [
      saleItemRow('si-plain'),
      saleItemRow(
        'si-pct',
        appliedOfferId: 'off-pct',
        appliedOfferName: 'Monsoon 10%',
        appliedOfferType: 'PERCENTAGE',
        offerDiscountPaise: 2400,
        lineTotalPaise: 21600,
      ),
      saleItemRow(
        'si-combo',
        productId: 'p1',
        appliedOfferId: 'off-combo',
        appliedOfferName: 'Two Coffee Combo',
        appliedOfferType: 'COMBO',
        offerDiscountPaise: 500,
        lineTotalPaise: 23500,
      ),
      saleItemRow(
        'si-variant',
        variantId: 'v1',
        variantName: 'Large',
        sku: 'FC-L',
        quantity: 1,
        lineTotalPaise: 14000,
      ),
    ];

    test('keeps every sale-item row byte-for-byte and its indexes', () async {
      final fixture = await buildV24Database(
        offerRows: [
          offerRow('o1', 'Monsoon 10%', 'PERCENTAGE', '{"percent":10}'),
        ],
        saleItemRows: populatedLines(),
      );
      expect(fixture.saleItemRowsBefore, hasLength(4));

      final db = AppDatabase(fixture.newConnection());
      await db.customSelect('SELECT 1').get();

      final after = await db
          .customSelect('SELECT * FROM sale_items ORDER BY id')
          .get();
      expect(after, hasLength(4), reason: 'no sale-item row may be lost');

      for (var i = 0; i < fixture.saleItemRowsBefore.length; i++) {
        final b = fixture.saleItemRowsBefore[i].data;
        final a = after[i].data;
        for (final column in _saleItemColumns) {
          expect(
            a[column],
            b[column],
            reason: 'sale_items.$column changed for row ${b['id']}',
          );
        }
      }

      final indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='index' "
                    "AND tbl_name='sale_items' AND name NOT LIKE 'sqlite_%'",
                  )
                  .get())
              .map((row) => row.data['name'])
              .toSet();
      expect(
        indexes,
        containsAll(<String>['idx_sale_items_shop', 'idx_sale_items_sale_id']),
      );

      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table'",
                  )
                  .get())
              .map((row) => row.data['name'])
              .toSet();
      expect(tables, isNot(contains('sale_items_bak_v25')));

      await db.close();
    });

    test('accepts a QUANTITY_TIER snapshot and still rejects junk', () async {
      final fixture = await buildV24Database(
        offerRows: [
          offerRow('o1', 'Monsoon 10%', 'PERCENTAGE', '{"percent":10}'),
        ],
        saleItemRows: populatedLines(),
      );

      final db = AppDatabase(fixture.newConnection());
      await db.customSelect('SELECT 1').get();

      // The exact value that used to fail the insert with SqliteException(275).
      await db.customStatement(
        'INSERT INTO sale_items (${_saleItemColumns.join(',')}) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...saleItemRow(
            'si-tier',
            quantity: 3,
            unitPricePaise: 4500,
            lineTotalPaise: 13500,
            offerDiscountPaise: 1500,
            appliedOfferId: 'off-tier',
            appliedOfferName: 'Kulfi Tiers',
            appliedOfferType: 'QUANTITY_TIER',
          ).values,
        ],
      );
      final stored = await db
          .customSelect(
            "SELECT applied_offer_type FROM sale_items WHERE id = 'si-tier'",
          )
          .getSingle();
      expect(stored.data['applied_offer_type'], 'QUANTITY_TIER');

      // NULL is still allowed (a line with no offer applied).
      await db.customStatement(
        'INSERT INTO sale_items (${_saleItemColumns.join(',')}) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [...saleItemRow('si-no-offer').values],
      );

      // The pre-existing guarantee still holds for unknown types.
      await expectLater(
        db.customStatement(
          'INSERT INTO sale_items (${_saleItemColumns.join(',')}) '
          'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [...saleItemRow('si-bad', appliedOfferType: 'NOT_A_TYPE').values],
        ),
        throwsA(anything),
      );

      await db.close();
    });
  });
}
