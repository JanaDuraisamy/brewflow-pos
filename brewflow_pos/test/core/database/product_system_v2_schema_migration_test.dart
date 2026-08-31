import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v7.dart' as v7;

/// ---------------------------------------------------------------------------
/// Product System v2 — v7 → v8 migration tests (drift SchemaVerifier)
///
/// The v7 database is created from the exported drift schema snapshot, seeded
/// with realistic v7-era data (categories, products, customers, sales, sale
/// items, suppliers, purchases, purchase items and stock movements), then
/// migrated with the app's real migration strategy.
/// [SchemaVerifier.migrateAndValidate] also compares the migrated schema
/// semantically against a fresh v8 database (columns, constraints, foreign
/// keys and indexes must match exactly).
/// ---------------------------------------------------------------------------

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v7 → v8 migration', () {
    test(
      'preserves every existing row exactly and applies v8 defaults',
      () async {
        final schema = await verifier.schemaAt(7);

        final oldDb = v7.DatabaseAtV7(schema.newConnection());
        await oldDb
            .into(oldDb.categories)
            .insert(
              v7.CategoriesCompanion.insert(
                id: 'cat-1',
                name: 'Beans',
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.products)
            .insert(
              v7.ProductsCompanion.insert(
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
              v7.CustomersCompanion.insert(
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
              v7.SalesCompanion.insert(
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
              v7.SaleItemsCompanion.insert(
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
            .into(oldDb.suppliers)
            .insert(
              v7.SuppliersCompanion.insert(
                id: 'sup-1',
                name: 'Annapurna Traders',
                phone: Value('9876500000'),
                email: Value(null),
                address: Value(null),
                notes: Value(null),
                isActive: Value(1),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.purchases)
            .insert(
              v7.PurchasesCompanion.insert(
                id: 'pu-1',
                supplierId: Value('sup-1'),
                purchaseNumber: 'PUR-000001',
                subtotalPaise: 40000,
                totalPaise: 40000,
                notes: Value(null),
                createdAt: '2026-01-03T10:00:00.000Z',
                updatedAt: '2026-01-03T10:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.purchaseItems)
            .insert(
              v7.PurchaseItemsCompanion.insert(
                id: 'pi1',
                purchaseId: 'pu-1',
                productId: 'p1',
                productName: 'Filter Coffee',
                sku: Value('FC-1'),
                unitCostPaise: 8000,
                quantity: 5,
                lineTotalPaise: 40000,
              ),
            );
        await oldDb
            .into(oldDb.stockMovements)
            .insert(
              v7.StockMovementsCompanion.insert(
                id: 'm1',
                productId: 'p1',
                movementType: 'OPENING',
                quantity: 7,
                stockBefore: 0,
                stockAfter: 7,
                reason: Value(null),
                note: Value(null),
                referenceType: Value(null),
                referenceId: Value(null),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.stockMovements)
            .insert(
              v7.StockMovementsCompanion.insert(
                id: 'm2',
                productId: 'p1',
                movementType: 'PURCHASE',
                quantity: 5,
                stockBefore: 7,
                stockAfter: 12,
                reason: Value(null),
                note: Value(null),
                referenceType: Value('PURCHASE'),
                referenceId: Value('pu-1'),
                createdAt: '2026-01-03T10:00:00.000Z',
                updatedAt: '2026-01-03T10:00:00.000Z',
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
        expect(product.imagePath, isNull);
        expect(product.stockUnit, 'COUNT');
        expect(product.lowStockMode, 'USE_DEFAULT');
        expect(product.lowStockThreshold, isNull);
        expect(product.membershipEnabled, false);
        expect(product.memberPricePaise, isNull);

        // The current customers row type requires membership columns (v11);
        // the migrated table only has the v8 columns, so read the preserved
        // columns explicitly.
        final customer =
            await (db.selectOnly(db.customers)
                  ..addColumns([db.customers.name, db.customers.phone])
                  ..where(db.customers.id.equals('c1')))
                .getSingle();
        expect(customer.read(db.customers.name), 'Lakshmi');
        expect(customer.read(db.customers.phone), '9876543210');

        // The current sales row type requires payment_status (v10); the
        // migrated table only has the v8 columns, so read the preserved
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
        expect(item.variantId, isNull);
        expect(item.variantName, isNull);

        final supplier = await (db.select(
          db.suppliers,
        )..where((t) => t.id.equals('sup-1'))).getSingle();
        expect(supplier.name, 'Annapurna Traders');

        final purchase = await (db.select(
          db.purchases,
        )..where((t) => t.id.equals('pu-1'))).getSingle();
        expect(purchase.purchaseNumber, 'PUR-000001');
        expect(purchase.supplierId, 'sup-1');
        expect(purchase.totalPaise, 40000);

        final purchaseItem = await (db.select(
          db.purchaseItems,
        )..where((t) => t.id.equals('pi1'))).getSingle();
        expect(purchaseItem.quantity, 5);
        expect(purchaseItem.unitCostPaise, 8000);
        expect(purchaseItem.variantId, isNull);
        expect(purchaseItem.variantName, isNull);

        final opening = await (db.select(
          db.stockMovements,
        )..where((t) => t.id.equals('m1'))).getSingle();
        expect(opening.movementType, 'OPENING');
        expect(opening.quantity, 7);
        expect(opening.stockBefore, 0);
        expect(opening.stockAfter, 7);
        expect(opening.variantId, isNull);

        final purchaseMovement = await (db.select(
          db.stockMovements,
        )..where((t) => t.id.equals('m2'))).getSingle();
        expect(purchaseMovement.movementType, 'PURCHASE');
        expect(purchaseMovement.referenceType, 'PURCHASE');
        expect(purchaseMovement.referenceId, 'pu-1');
        expect(purchaseMovement.variantId, isNull);

        await db.close();
        schema.close();
      },
    );

    test('v8 additions work after migration: variants, variant movements and '
        'variant receipt lines', () async {
      final schema = await verifier.schemaAt(7);

      final oldDb = v7.DatabaseAtV7(schema.newConnection());
      await oldDb
          .into(oldDb.categories)
          .insert(
            v7.CategoriesCompanion.insert(
              id: 'cat-1',
              name: 'Beverages',
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb
          .into(oldDb.products)
          .insert(
            v7.ProductsCompanion.insert(
              id: 'p1',
              categoryId: 'cat-1',
              name: 'Jigarthanda',
              sellingPricePaise: 12000,
              stockQuantity: Value(0),
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 8);

      // A variant with its own stock, low-stock policy and membership tier.
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: Value('v1'),
              productId: 'p1',
              name: '250 ml',
              sku: Value('JIG-250'),
              sellingPricePaise: 14000,
              costPricePaise: Value(9000),
              stockQuantity: Value(10),
              lowStockMode: Value('CUSTOM'),
              lowStockThreshold: Value(3),
              membershipEnabled: Value(true),
              memberPricePaise: Value(12000),
            ),
          );
      final variant = await (db.select(
        db.productVariants,
      )..where((t) => t.id.equals('v1'))).getSingle();
      expect(variant.name, '250 ml');
      expect(variant.sku, 'JIG-250');
      expect(variant.stockQuantity, 10);
      expect(variant.lowStockMode, 'CUSTOM');
      expect(variant.lowStockThreshold, 3);
      expect(variant.membershipEnabled, true);
      expect(variant.memberPricePaise, 12000);
      expect(variant.isActive, true);

      // A variant-aware SALE movement and a variant-aware receipt line.
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: Value('m3'),
              productId: 'p1',
              variantId: Value('v1'),
              movementType: 'SALE',
              quantity: -2,
              stockBefore: 10,
              stockAfter: 8,
              referenceType: Value('SALE'),
              referenceId: Value('s9'),
              createdAt: Value(DateTime.utc(2026, 1, 4)),
              updatedAt: Value(DateTime.utc(2026, 1, 4)),
            ),
          );
      final movement = await (db.select(
        db.stockMovements,
      )..where((t) => t.id.equals('m3'))).getSingle();
      expect(movement.variantId, 'v1');
      expect(movement.movementType, 'SALE');
      expect(movement.stockAfter, 8);

      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: Value('s9'),
              customerId: Value(null),
              receiptNumber: 'BF-000002',
              subtotalPaise: 28000,
              totalPaise: 28000,
              paymentMethod: Value('CASH'),
              createdAt: Value(DateTime.utc(2026, 1, 4)),
              updatedAt: Value(DateTime.utc(2026, 1, 4)),
            ),
          );
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              id: Value('si2'),
              saleId: 's9',
              productId: 'p1',
              variantId: Value('v1'),
              productName: 'Jigarthanda',
              variantName: Value('250 ml'),
              sku: Value('JIG-250'),
              unitPricePaise: 14000,
              quantity: 2,
              lineTotalPaise: 28000,
            ),
          );
      final line = await (db.select(
        db.saleItems,
      )..where((t) => t.id.equals('si2'))).getSingle();
      expect(line.variantId, 'v1');
      expect(line.variantName, '250 ml');
      expect(line.unitPricePaise, 14000);

      await db.close();
      schema.close();
    });
  });
}
