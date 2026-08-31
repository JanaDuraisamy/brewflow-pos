import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v6.dart' as v6;

/// ---------------------------------------------------------------------------
/// Phase 10 Step 4 — v6 → v7 migration tests (drift SchemaVerifier)
///
/// The v6 database is created from the exported drift schema snapshot, seeded
/// with realistic v6-era data, then migrated with the app's real migration
/// strategy. [SchemaVerifier.migrateAndValidate] also compares the migrated
/// schema semantically against a fresh database at the current version
/// (columns, constraints, foreign keys and indexes must match exactly).
/// ---------------------------------------------------------------------------

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v6 → v7 migration', () {
    test('preserves product, customer, sale, sale item and OPENING movement '
        'rows exactly, and accepts PURCHASE movements afterwards', () async {
      final schema = await verifier.schemaAt(6);

      final oldDb = v6.DatabaseAtV6(schema.newConnection());
      await oldDb
          .into(oldDb.categories)
          .insert(
            v6.CategoriesCompanion.insert(
              id: 'cat-1',
              name: 'Beans',
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb
          .into(oldDb.products)
          .insert(
            v6.ProductsCompanion.insert(
              id: 'p1',
              categoryId: 'cat-1',
              name: 'Filter Coffee',
              sku: Value('FC-1'),
              sellingPricePaise: 12000,
              costPricePaise: Value(8000),
              stockQuantity: Value(7),
              isActive: Value(1),
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb
          .into(oldDb.customers)
          .insert(
            v6.CustomersCompanion.insert(
              id: 'c1',
              name: 'Lakshmi',
              phone: Value('9876543210'),
              isActive: Value(1),
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb
          .into(oldDb.sales)
          .insert(
            v6.SalesCompanion.insert(
              id: 's1',
              customerId: Value('c1'),
              receiptNumber: 'BF-000001',
              subtotalPaise: 24000,
              totalPaise: 24000,
              paymentMethod: 'CASH',
              createdAt: '2026-01-02T10:00:00.000Z',
              updatedAt: '2026-01-02T10:00:00.000Z',
            ),
          );
      await oldDb
          .into(oldDb.saleItems)
          .insert(
            v6.SaleItemsCompanion.insert(
              id: 'si1',
              saleId: 's1',
              productId: 'p1',
              productName: 'Filter Coffee',
              sku: Value('FC-1'),
              unitPricePaise: 12000,
              quantity: 2,
              lineTotalPaise: 24000,
            ),
          );
      await oldDb
          .into(oldDb.stockMovements)
          .insert(
            v6.StockMovementsCompanion.insert(
              id: 'm1',
              productId: 'p1',
              movementType: 'OPENING',
              quantity: 7,
              stockBefore: 0,
              stockAfter: 7,
              referenceType: Value(null),
              referenceId: Value(null),
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 8);

      final product = await (db.select(
        db.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(product.name, 'Filter Coffee');
      expect(product.sku, 'FC-1');
      expect(product.sellingPricePaise, 12000);
      expect(product.costPricePaise, 8000);
      expect(product.stockQuantity, 7);

      // The current customers row type requires membership columns (v11);
      // the migrated table only has the v7 columns, so read the preserved
      // columns explicitly.
      final customer =
          await (db.selectOnly(db.customers)
                ..addColumns([db.customers.name, db.customers.phone])
                ..where(db.customers.id.equals('c1')))
              .getSingle();
      expect(customer.read(db.customers.name), 'Lakshmi');
      expect(customer.read(db.customers.phone), '9876543210');

      // The current sales row type requires payment_status (v10); the
      // migrated table only has the v7 columns, so read the preserved
      // columns explicitly.
      final sale =
          await (db.selectOnly(db.sales)
                ..addColumns([
                  db.sales.receiptNumber,
                  db.sales.customerId,
                  db.sales.subtotalPaise,
                  db.sales.totalPaise,
                  db.sales.paymentMethod,
                  db.sales.createdAt,
                  db.sales.updatedAt,
                ])
                ..where(db.sales.id.equals('s1')))
              .getSingle();
      expect(sale.read(db.sales.receiptNumber), 'BF-000001');
      expect(sale.read(db.sales.customerId), 'c1');
      expect(sale.read(db.sales.subtotalPaise), 24000);
      expect(sale.read(db.sales.totalPaise), 24000);
      expect(sale.read(db.sales.paymentMethod), 'CASH');

      final item = await (db.select(
        db.saleItems,
      )..where((t) => t.id.equals('si1'))).getSingle();
      expect(item.quantity, 2);
      expect(item.unitPricePaise, 12000);

      final movement = await (db.select(
        db.stockMovements,
      )..where((t) => t.id.equals('m1'))).getSingle();
      expect(movement.movementType, 'OPENING');
      expect(movement.quantity, 7);
      expect(movement.stockBefore, 0);
      expect(movement.stockAfter, 7);
      expect(movement.referenceType, isNull);
      expect(movement.referenceId, isNull);

      // The recreated CHECK must accept a PURCHASE movement now.
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: Value('m2'),
              productId: 'p1',
              movementType: StockMovementType.purchase.dbValue,
              quantity: 5,
              stockBefore: 7,
              stockAfter: 12,
              referenceType: Value('PURCHASE'),
              referenceId: Value('pu-1'),
              createdAt: Value(DateTime.utc(2026, 1, 3)),
              updatedAt: Value(DateTime.utc(2026, 1, 3)),
            ),
          );
      final purchaseMovement = await (db.select(
        db.stockMovements,
      )..where((t) => t.id.equals('m2'))).getSingle();
      expect(purchaseMovement.movementType, 'PURCHASE');
      expect(purchaseMovement.referenceType, 'PURCHASE');
      expect(purchaseMovement.referenceId, 'pu-1');
      expect(purchaseMovement.stockAfter, 12);

      await db.close();
      schema.close();
    });

    test(
      'still writes and reads all five movement types after migration',
      () async {
        final schema = await verifier.schemaAt(6);
        final oldDb = v6.DatabaseAtV6(schema.newConnection());
        await oldDb
            .into(oldDb.categories)
            .insert(
              v6.CategoriesCompanion.insert(
                id: 'cat-1',
                name: 'Beans',
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.products)
            .insert(
              v6.ProductsCompanion.insert(
                id: 'p1',
                categoryId: 'cat-1',
                name: 'Filter Coffee',
                sellingPricePaise: 12000,
                stockQuantity: Value(10),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb.close();

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 8);

        final entries = <(String, int, int)>[
          (StockMovementType.opening.dbValue, 10, 10),
          (StockMovementType.purchase.dbValue, 5, 15),
          (StockMovementType.sale.dbValue, -3, 12),
          (StockMovementType.adjustmentIn.dbValue, 2, 14),
          (StockMovementType.adjustmentOut.dbValue, -4, 10),
        ];
        var stock = 10;
        for (final (index, (type, delta, after)) in entries.indexed) {
          await db
              .into(db.stockMovements)
              .insert(
                StockMovementsCompanion.insert(
                  id: Value('m-$index'),
                  productId: 'p1',
                  movementType: type,
                  quantity: delta,
                  stockBefore: stock,
                  stockAfter: after,
                  createdAt: Value(DateTime.utc(2026, 1, 3)),
                  updatedAt: Value(DateTime.utc(2026, 1, 3)),
                ),
              );
          stock = after;
        }

        final rows = await (db.select(
          db.stockMovements,
        )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
        expect(rows, hasLength(5));
        for (var i = 0; i < rows.length; i++) {
          final (type, delta, after) = entries[i];
          expect(rows[i].movementType, type);
          expect(
            StockMovementType.fromDbValue(rows[i].movementType),
            StockMovementType.fromDbValue(type),
          );
          expect(rows[i].quantity, delta);
          expect(rows[i].stockAfter, after);
        }

        await db.close();
        schema.close();
      },
    );
  });

  group('movement types on the current schema', () {
    test('all five values round-trip through the CHECK', () async {
      final database = AppDatabase(NativeDatabase.memory());
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(id: Value('cat-1'), name: 'Beans'),
          );
      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p1'),
              categoryId: 'cat-1',
              name: 'Filter Coffee',
              sellingPricePaise: 12000,
            ),
          );

      final types = [
        StockMovementType.opening,
        StockMovementType.sale,
        StockMovementType.purchase,
        StockMovementType.adjustmentIn,
        StockMovementType.adjustmentOut,
      ];
      var stock = 0;
      for (final (index, type) in types.indexed) {
        final delta = switch (type) {
          StockMovementType.opening ||
          StockMovementType.purchase ||
          StockMovementType.adjustmentIn => 5,
          StockMovementType.sale || StockMovementType.adjustmentOut => -1,
        };
        await database
            .into(database.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: Value('m-$index'),
                productId: 'p1',
                movementType: type.dbValue,
                quantity: delta,
                stockBefore: stock,
                stockAfter: stock + delta,
                createdAt: Value(DateTime.utc(2026, 1, 3)),
                updatedAt: Value(DateTime.utc(2026, 1, 3)),
              ),
            );
        stock += delta;
      }

      final rows = await (database.select(
        database.stockMovements,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      expect(rows, hasLength(5));
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].movementType, types[i].dbValue);
        expect(StockMovementType.fromDbValue(rows[i].movementType), types[i]);
      }

      await database.close();
    });

    test('unknown stored values still fail safely', () {
      expect(StockMovementType.fromDbValue('REFUND'), isNull);
    });
  });
}
