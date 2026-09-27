import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// Customer true-delete — populated-data safety gate
///
/// This file is the gate the user asked for: it proves the customer-FK removal
/// is safe on **populated** data BEFORE any production schema change is
/// written. If it fails, the production migration must not be attempted.
///
/// Deleting a customer has to become a real delete, and
/// `sales.customer_id` / `customer_payments.customer_id` currently carry
/// `ON DELETE RESTRICT`. SQLite cannot drop a foreign key in place, so both
/// tables must be rebuilt. Two things make that risky:
///
///  * `sales` is a *referenced* table — `sale_items.sale_id` and
///    `customer_payments.sale_id` both point at it with RESTRICT, so dropping
///    it orphans children and trips the FK.
///  * `PRAGMA foreign_keys = OFF` is a **no-op inside a transaction**, and
///    drift runs every migration step inside one — so the textbook SQLite
///    rebuild recipe is unavailable here.
///
/// The technique validated below is `PRAGMA defer_foreign_keys = ON`, which
/// *is* honoured inside a transaction: enforcement is postponed to COMMIT, by
/// which point the copy is complete and every remaining constraint holds.
/// ---------------------------------------------------------------------------

/// Every table the customer migration must not disturb.
const _ledgerTables = ['sales', 'sale_items', 'customer_payments'];

/// The v25 definition of `sales`: the customer FK is the only thing the
/// migration removes.
const _salesV25 =
    'CREATE TABLE sales ('
    '"id" TEXT NOT NULL, '
    '"shop_id" TEXT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"customer_id" TEXT NULL REFERENCES customers (id) ON DELETE RESTRICT, '
    '"receipt_number" TEXT NOT NULL, '
    '"subtotal_paise" INTEGER NOT NULL CHECK (subtotal_paise >= 0), '
    '"total_paise" INTEGER NOT NULL CHECK (total_paise >= 0), '
    '"offer_discount_paise" INTEGER NOT NULL DEFAULT 0 CHECK (offer_discount_paise >= 0), '
    '"payment_method" TEXT CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\')), '
    '"payment_status" TEXT NOT NULL DEFAULT \'PAID\' CHECK (payment_status IN (\'PAID\', \'NOT_PAID\')), '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL, '
    '"voided" INTEGER NOT NULL DEFAULT 0 CHECK ("voided" IN (0, 1)), '
    '"voided_at" TEXT NULL, '
    '"is_opening_balance" INTEGER NOT NULL DEFAULT 0 CHECK ("is_opening_balance" IN (0, 1)), '
    'PRIMARY KEY ("id"), UNIQUE ("shop_id", "receipt_number"))';

/// v26: identical, minus the customer foreign key. `customer_id` stays a
/// plain column so historical sales keep pointing at the deleted customer.
const _salesV26 =
    'CREATE TABLE sales_v26 ('
    '"id" TEXT NOT NULL, '
    '"shop_id" TEXT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"customer_id" TEXT NULL, '
    '"receipt_number" TEXT NOT NULL, '
    '"subtotal_paise" INTEGER NOT NULL CHECK (subtotal_paise >= 0), '
    '"total_paise" INTEGER NOT NULL CHECK (total_paise >= 0), '
    '"offer_discount_paise" INTEGER NOT NULL DEFAULT 0 CHECK (offer_discount_paise >= 0), '
    '"payment_method" TEXT CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\')), '
    '"payment_status" TEXT NOT NULL DEFAULT \'PAID\' CHECK (payment_status IN (\'PAID\', \'NOT_PAID\')), '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL, '
    '"voided" INTEGER NOT NULL DEFAULT 0 CHECK ("voided" IN (0, 1)), '
    '"voided_at" TEXT NULL, '
    '"is_opening_balance" INTEGER NOT NULL DEFAULT 0 CHECK ("is_opening_balance" IN (0, 1)), '
    'PRIMARY KEY ("id"), UNIQUE ("shop_id", "receipt_number"))';

/// v25 `sale_items` — the child of `sales` that makes the rebuild risky. It
/// is NOT rebuilt by the migration; it only has to survive.
const _saleItemsV25 =
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
    "applied_offer_type IN ('PERCENTAGE','COMBO','BUY_X_GET_Y','QUANTITY_TIER')), "
    'PRIMARY KEY ("id"))';

const _saleItemIndexes = [
  'CREATE INDEX idx_sale_items_shop ON %s (shop_id)',
  'CREATE INDEX idx_sale_items_sale_id ON %s (shop_id, sale_id)',
];

const _customerPaymentsV25 =
    'CREATE TABLE customer_payments ('
    '"id" TEXT NOT NULL, '
    '"shop_id" TEXT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"customer_id" TEXT NOT NULL REFERENCES customers (id) ON DELETE RESTRICT, '
    '"sale_id" TEXT NULL REFERENCES sales (id) ON DELETE RESTRICT, '
    '"payment_group_id" TEXT NULL, '
    '"amount_paise" INTEGER NOT NULL CHECK (amount_paise >= 0), '
    '"payment_method" TEXT NOT NULL CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\')), '
    '"note" TEXT NULL, '
    '"paid_at" TEXT NOT NULL, '
    '"reversed" INTEGER NOT NULL DEFAULT 0 CHECK ("reversed" IN (0, 1)), '
    '"reversed_at" TEXT NULL, '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL, '
    'PRIMARY KEY ("id"))';

/// v26: the customer FK is gone; the sale FK stays (a payment still belongs
/// to a real sale).
const _customerPaymentsV26 =
    'CREATE TABLE customer_payments_v26 ('
    '"id" TEXT NOT NULL, '
    '"shop_id" TEXT NULL REFERENCES shops (id) ON DELETE CASCADE, '
    '"customer_id" TEXT NOT NULL, '
    '"sale_id" TEXT NULL REFERENCES sales (id) ON DELETE RESTRICT, '
    '"payment_group_id" TEXT NULL, '
    '"amount_paise" INTEGER NOT NULL CHECK (amount_paise >= 0), '
    '"payment_method" TEXT NOT NULL CHECK (payment_method IN (\'CASH\', \'UPI\', \'BANK\')), '
    '"note" TEXT NULL, '
    '"paid_at" TEXT NOT NULL, '
    '"reversed" INTEGER NOT NULL DEFAULT 0 CHECK ("reversed" IN (0, 1)), '
    '"reversed_at" TEXT NULL, '
    '"created_at" TEXT NOT NULL, '
    '"updated_at" TEXT NOT NULL, '
    'PRIMARY KEY ("id"))';

const _salesIndexes = [
  'CREATE INDEX idx_sales_shop ON %s (shop_id)',
  'CREATE INDEX idx_sales_created_at ON %s (shop_id, created_at)',
  'CREATE INDEX idx_sales_customer_id ON %s (shop_id, customer_id)',
];

const _paymentIndexes = [
  'CREATE INDEX idx_customer_payments_shop ON %s (shop_id)',
  'CREATE INDEX idx_customer_payments_customer_id ON %s (shop_id, customer_id)',
  'CREATE INDEX idx_customer_payments_sale_id ON %s (sale_id)',
  'CREATE INDEX idx_customer_payments_paid_at ON %s (shop_id, paid_at)',
  'CREATE INDEX idx_customer_payments_group ON %s (payment_group_id, sale_id)',
];

/// Full contents of [table], ordered by id.
Future<List<Map<String, Object?>>> _snapshot(
  GeneratedDatabase db,
  String table,
) async {
  final rows = await db.customSelect('SELECT * FROM $table ORDER BY id').get();
  return [for (final row in rows) row.data];
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

/// A populated database stamped at v25, with the customer FKs still in place.
class V25Fixture {
  V25Fixture(this.db, this.reopen, this.before);
  final v14.DatabaseAtV14 db;

  /// A fresh connection to the same database, so the fixture's own wrapper can
  /// be closed before the real [AppDatabase] takes over.
  final DatabaseConnection Function() reopen;
  final Map<String, List<Map<String, Object?>>> before;
}

Future<V25Fixture> buildPopulatedV25(
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
          id: 'p1',
          categoryId: 'cat-1',
          name: 'Filter Coffee',
          sellingPricePaise: 12000,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  // Rebuild the three tables in their exact v25 shape.
  await db.customStatement('DROP TABLE sales');
  await db.customStatement(_salesV25);
  for (final ddl in _salesIndexes) {
    await db.customStatement(ddl.replaceAll('%s', 'sales'));
  }
  await db.customStatement('DROP TABLE sale_items');
  await db.customStatement(_saleItemsV25);
  for (final ddl in _saleItemIndexes) {
    await db.customStatement(ddl.replaceAll('%s', 'sale_items'));
  }
  await db.customStatement('DROP TABLE customer_payments');
  await db.customStatement(_customerPaymentsV25);
  for (final ddl in _paymentIndexes) {
    await db.customStatement(ddl.replaceAll('%s', 'customer_payments'));
  }

  // c-busy has real billing history; c-quiet only an opening balance.
  for (final (id, name, phone) in [
    ('c-busy', 'Asha Rao', '9800000001'),
    ('c-quiet', 'Vikram Das', '9800000002'),
  ]) {
    await db
        .into(db.customers)
        .insert(
          v14.CustomersCompanion.insert(
            id: id,
            name: name,
            phone: Value(phone),
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        );
  }

  Future<void> sale(
    String id,
    String? customerId,
    String receipt,
    int total,
    String status,
    String? method, {
    int discount = 0,
    bool openingBalance = false,
  }) => db.customStatement(
    'INSERT INTO sales (id, shop_id, customer_id, receipt_number, '
    'subtotal_paise, total_paise, offer_discount_paise, payment_method, '
    'payment_status, created_at, updated_at, voided, voided_at, '
    'is_opening_balance) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
    [
      id,
      'shop-cafe',
      customerId,
      receipt,
      total,
      total,
      discount,
      method,
      status,
      '2026-01-10T10:00:00.000Z',
      '2026-01-10T10:00:00.000Z',
      0,
      null,
      openingBalance ? 1 : 0,
    ],
  );

  await sale('s1', 'c-busy', 'BF-000001', 24000, 'NOT_PAID', null);
  await sale('s2', null, 'BF-000002', 12000, 'PAID', 'UPI', discount: 2000);
  await sale(
    's3',
    'c-quiet',
    'OB-0001',
    5000,
    'NOT_PAID',
    null,
    openingBalance: true,
  );

  for (final (id, saleId, qty, total, discount) in [
    ('si1', 's1', 2, 24000, 0),
    ('si2', 's1', 1, 0, 0),
    ('si3', 's2', 1, 12000, 2000),
  ]) {
    await db.customStatement(
      'INSERT INTO sale_items (id, shop_id, sale_id, product_id, variant_id, '
      'product_name, variant_name, sku, unit_price_paise, quantity, '
      'line_total_paise, offer_discount_paise, applied_offer_id, '
      'applied_offer_name, applied_offer_type) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        'shop-cafe',
        saleId,
        'p1',
        null,
        'Filter Coffee',
        null,
        null,
        12000,
        qty,
        total,
        discount,
        discount > 0 ? 'off-1' : null,
        discount > 0 ? 'Monsoon 10%' : null,
        discount > 0 ? 'PERCENTAGE' : null,
      ],
    );
  }

  for (final (id, customerId, saleId, amount, method, group) in [
    ('pay1', 'c-busy', 's1', 10000, 'CASH', null),
    ('pay2', 'c-busy', 's1', 5000, 'UPI', 'grp-1'),
    ('pay3', 'c-quiet', 's3', 1000, 'CASH', null),
  ]) {
    await db.customStatement(
      'INSERT INTO customer_payments (id, shop_id, customer_id, sale_id, '
      'payment_group_id, amount_paise, payment_method, note, paid_at, '
      'reversed, reversed_at, created_at, updated_at) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        'shop-cafe',
        customerId,
        saleId,
        group,
        amount,
        method,
        null,
        '2026-01-12T12:00:00.000Z',
        0,
        null,
        '2026-01-12T12:00:00.000Z',
        '2026-01-12T12:00:00.000Z',
      ],
    );
  }

  final before = <String, List<Map<String, Object?>>>{};
  for (final table in _ledgerTables) {
    before[table] = await _snapshot(db, table);
  }
  await db.customStatement('PRAGMA user_version = 25');
  return V25Fixture(db, connect, before);
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    'the current schema blocks a hard delete of a customer with history',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV25(schema.newConnection);
      await fixture.db.customStatement('PRAGMA foreign_keys = ON');

      // The bug the migration removes.
      await expectLater(
        fixture.db.customStatement("DELETE FROM customers WHERE id = 'c-busy'"),
        throwsA(anything),
        reason: 'ON DELETE RESTRICT must block this before the migration',
      );
      final still = await fixture.db
          .customSelect("SELECT id FROM customers WHERE id = 'c-busy'")
          .get();
      expect(
        still,
        hasLength(1),
        reason: 'the customer must survive the refusal',
      );

      await fixture.db.close();
    },
  );

  test('the wired v25 -> v26 step preserves a populated ledger', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildPopulatedV25(schema.newConnection);
    await fixture.db.close();

    // The real migrator runs exactly the v25 -> v26 step over the populated
    // fixture, on a database with foreign keys enforced.
    final db = AppDatabase(fixture.reopen());
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first;
    // The migrator runs the whole remaining chain from the v25 fixture, so it
    // lands on whatever the current live schema version is (v26 for the customer
    // FK rebuild, then anything added since). Asserting the constant instead of
    // a literal keeps this test valid as later steps are appended.
    expect(
      version,
      AppConstants.databaseSchemaVersion,
      reason: 'the step must land on the live schema',
    );

    for (final table in _ledgerTables) {
      expect(
        await _snapshot(db, table),
        fixture.before[table],
        reason: '$table changed during the wired migration',
      );
    }

    // customer_id survived as a plain column, still attributed.
    final sales = await db
        .customSelect('SELECT id, customer_id FROM sales ORDER BY id')
        .get();
    expect(
      {for (final row in sales) row.data['id']: row.data['customer_id']},
      {'s1': 'c-busy', 's2': null, 's3': 'c-quiet'},
    );

    // The customer FKs are gone; the sale FK is intact.
    expect(await _ddl(db, 'sales'), isNot(contains('REFERENCES customers')));
    expect(
      await _ddl(db, 'customer_payments'),
      isNot(contains('REFERENCES customers')),
    );
    expect(await _ddl(db, 'customer_payments'), contains('REFERENCES sales'));

    // Indexes restored, no backup tables left, nothing dangling.
    expect(
      await _indexes(db, 'sales'),
      containsAll(<String>{
        'idx_sales_shop',
        'idx_sales_created_at',
        'idx_sales_customer_id',
      }),
    );
    expect(
      await _indexes(db, 'customer_payments'),
      containsAll(<String>{
        'idx_customer_payments_shop',
        'idx_customer_payments_customer_id',
        'idx_customer_payments_sale_id',
        'idx_customer_payments_paid_at',
        'idx_customer_payments_group',
      }),
    );
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((row) => row.data['name'])
            .toSet();
    expect(tables, isNot(contains('sales_bak_v26')));
    expect(tables, isNot(contains('customer_payments_bak_v26')));
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

    // The real delete the owner was previously blocked from.
    await db.customStatement("DELETE FROM customers WHERE id = 'c-busy'");
    expect(
      await db
          .customSelect("SELECT id FROM customers WHERE id = 'c-busy'")
          .get(),
      isEmpty,
    );
    final sale = await db
        .customSelect(
          'SELECT customer_id, total_paise FROM sales WHERE id = ?',
          variables: [Variable.withString('s1')],
        )
        .getSingle();
    expect(
      sale.data['customer_id'],
      'c-busy',
      reason: 'history keeps its link',
    );
    expect(sale.data['total_paise'], 24000);
    expect(
      await db
          .customSelect(
            'SELECT * FROM sale_items WHERE sale_id = ?',
            variables: [Variable.withString('s1')],
          )
          .get(),
      hasLength(2),
    );
    expect(
      await db
          .customSelect(
            "SELECT * FROM customer_payments WHERE customer_id = 'c-busy'",
          )
          .get(),
      hasLength(2),
    );

    // A payment still cannot outlive its sale.
    await expectLater(
      db.customStatement(
        'INSERT INTO customer_payments (id, shop_id, customer_id, sale_id, '
        'payment_group_id, amount_paise, payment_method, note, paid_at, '
        'reversed, reversed_at, created_at, updated_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          'pay-bad',
          'shop-cafe',
          'c-quiet',
          's-nope',
          null,
          100,
          'CASH',
          null,
          '2026-01-12T12:00:00.000Z',
          0,
          null,
          '2026-01-12T12:00:00.000Z',
          '2026-01-12T12:00:00.000Z',
        ],
      ),
      throwsA(anything),
    );

    await db.close();
  });

  test(
    'the wired v25 -> v26 step is a no-op on an already-migrated database',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV25(schema.newConnection);
      await fixture.db.close();

      // First run performs the rebuild.
      final first = AppDatabase(fixture.reopen());
      await first.customSelect('SELECT 1').get();
      final migrated = await _snapshot(first, 'sales');
      await first.close();

      // Re-running the same step against the rebuilt table must not run a second
      // rebuild (and must not lose anything).
      final second = AppDatabase(fixture.reopen());
      await second.customSelect('SELECT 1').get();
      expect(await _snapshot(second, 'sales'), migrated);
      expect(
        (await second.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .first,
        AppConstants.databaseSchemaVersion,
      );
      await second.close();
    },
  );

  test(
    'defer_foreign_keys rebuild preserves every ledger row on populated data',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildPopulatedV25(schema.newConnection);
      final db = fixture.db;

      expect(fixture.before['sales'], hasLength(3));
      expect(fixture.before['sale_items'], hasLength(3));
      expect(fixture.before['customer_payments'], hasLength(3));

      // The exact sequence the production migration will run, inside one
      // transaction, with FK enforcement deferred rather than disabled.
      await db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');

        await db.customStatement(
          'CREATE TABLE sales_bak_v26 AS SELECT * FROM sales',
        );
        await db.customStatement('DROP TABLE sales');
        await db.customStatement(_salesV26);
        await db.customStatement(
          'INSERT INTO sales_v26 SELECT * FROM sales_bak_v26',
        );
        await db.customStatement('DROP TABLE sales_bak_v26');
        await db.customStatement('ALTER TABLE sales_v26 RENAME TO sales');
        for (final ddl in _salesIndexes) {
          await db.customStatement(ddl.replaceAll('%s', 'sales'));
        }

        await db.customStatement(
          'CREATE TABLE customer_payments_bak_v26 AS SELECT * FROM customer_payments',
        );
        await db.customStatement('DROP TABLE customer_payments');
        await db.customStatement(_customerPaymentsV26);
        await db.customStatement(
          'INSERT INTO customer_payments_v26 SELECT * FROM customer_payments_bak_v26',
        );
        await db.customStatement('DROP TABLE customer_payments_bak_v26');
        await db.customStatement(
          'ALTER TABLE customer_payments_v26 RENAME TO customer_payments',
        );
        for (final ddl in _paymentIndexes) {
          await db.customStatement(ddl.replaceAll('%s', 'customer_payments'));
        }
      });

      // 1. Every historical row survived, unchanged.
      for (final table in _ledgerTables) {
        expect(
          await _snapshot(db, table),
          fixture.before[table],
          reason: '$table changed during the rebuild',
        );
      }

      // 2. customer_id values are preserved, not nulled.
      final sales = await db
          .customSelect('SELECT id, customer_id FROM sales ORDER BY id')
          .get();
      expect(
        {for (final row in sales) row.data['id']: row.data['customer_id']},
        {'s1': 'c-busy', 's2': null, 's3': 'c-quiet'},
      );
      final payments = await db
          .customSelect(
            'SELECT id, customer_id FROM customer_payments ORDER BY id',
          )
          .get();
      expect(
        {for (final row in payments) row.data['id']: row.data['customer_id']},
        {'pay1': 'c-busy', 'pay2': 'c-busy', 'pay3': 'c-quiet'},
      );

      // 3. The customer FKs are gone; the sale FK survived.
      expect(await _ddl(db, 'sales'), isNot(contains('REFERENCES customers')));
      expect(
        await _ddl(db, 'customer_payments'),
        isNot(contains('REFERENCES customers')),
      );
      expect(await _ddl(db, 'customer_payments'), contains('REFERENCES sales'));

      // 4. Every index is back.
      expect(
        await _indexes(db, 'sales'),
        containsAll(<String>{
          'idx_sales_shop',
          'idx_sales_created_at',
          'idx_sales_customer_id',
        }),
      );
      expect(
        await _indexes(db, 'customer_payments'),
        containsAll(<String>{
          'idx_customer_payments_shop',
          'idx_customer_payments_customer_id',
          'idx_customer_payments_sale_id',
          'idx_customer_payments_paid_at',
          'idx_customer_payments_group',
        }),
      );

      // 5. No leftover backup tables and no dangling references.
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table'",
                  )
                  .get())
              .map((row) => row.data['name'])
              .toSet();
      expect(tables, isNot(contains('sales_bak_v26')));
      expect(tables, isNot(contains('customer_payments_bak_v26')));

      await db.customStatement('PRAGMA foreign_keys = ON');
      final violations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(
        violations,
        isEmpty,
        reason: 'the rebuild must not leave a single dangling reference',
      );

      await db.close();
    },
  );

  test('after the rebuild the customer hard-deletes and history remains', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildPopulatedV25(schema.newConnection);
    final db = fixture.db;

    await db.transaction(() async {
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      await db.customStatement(
        'CREATE TABLE sales_bak_v26 AS SELECT * FROM sales',
      );
      await db.customStatement('DROP TABLE sales');
      await db.customStatement(_salesV26);
      await db.customStatement(
        'INSERT INTO sales_v26 SELECT * FROM sales_bak_v26',
      );
      await db.customStatement('DROP TABLE sales_bak_v26');
      await db.customStatement('ALTER TABLE sales_v26 RENAME TO sales');
      await db.customStatement(
        'CREATE TABLE customer_payments_bak_v26 AS SELECT * FROM customer_payments',
      );
      await db.customStatement('DROP TABLE customer_payments');
      await db.customStatement(_customerPaymentsV26);
      await db.customStatement(
        'INSERT INTO customer_payments_v26 SELECT * FROM customer_payments_bak_v26',
      );
      await db.customStatement('DROP TABLE customer_payments_bak_v26');
      await db.customStatement(
        'ALTER TABLE customer_payments_v26 RENAME TO customer_payments',
      );
    });

    await db.customStatement('PRAGMA foreign_keys = ON');

    // The real delete now succeeds with FK enforcement active.
    await db.customStatement("DELETE FROM customers WHERE id = 'c-busy'");
    expect(
      await db
          .customSelect("SELECT id FROM customers WHERE id = 'c-busy'")
          .get(),
      isEmpty,
    );

    // History is intact and still attributed to the deleted customer.
    final sale = await db
        .customSelect(
          "SELECT customer_id, total_paise FROM sales WHERE id = 's1'",
        )
        .getSingle();
    expect(sale.data['customer_id'], 'c-busy');
    expect(sale.data['total_paise'], 24000);

    final items = await db
        .customSelect(
          'SELECT * FROM sale_items WHERE sale_id = ?',
          variables: [Variable.withString('s1')],
        )
        .get();
    expect(items, hasLength(2), reason: 'the bill lines must survive');

    final payments = await db
        .customSelect(
          'SELECT customer_id, amount_paise FROM customer_payments '
          "WHERE customer_id = 'c-busy' ORDER BY id",
        )
        .get();
    expect(payments, hasLength(2), reason: 'the ledger must survive');
    expect(payments.map((row) => row.data['amount_paise']), [10000, 5000]);

    // The sale FK is still enforced: a payment cannot outlive its sale.
    await expectLater(
      db.customStatement(
        'INSERT INTO customer_payments (id, shop_id, customer_id, sale_id, '
        'payment_group_id, amount_paise, payment_method, note, paid_at, '
        'reversed, reversed_at, created_at, updated_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          'pay-bad',
          'shop-cafe',
          'c-quiet',
          's-does-not-exist',
          null,
          100,
          'CASH',
          null,
          '2026-01-12T12:00:00.000Z',
          0,
          null,
          '2026-01-12T12:00:00.000Z',
          '2026-01-12T12:00:00.000Z',
        ],
      ),
      throwsA(anything),
      reason: 'the sale foreign key must not be weakened by this migration',
    );

    await db.close();
  });
}
