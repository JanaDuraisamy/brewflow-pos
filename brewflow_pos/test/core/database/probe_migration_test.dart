import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// Full-chain regression: a real v14 database upgrades through v16 → v17's
/// shop-scoping step and lands on the live schema with every legacy row
/// assigned to the Cafe shop.
///
/// This is the only faithful way to exercise `from16To17`: the generated
/// `GeneratedHelper` caps at v14, so a real `AppDatabase` open of a v14-born
/// database runs the genuine v14 → v19 chain (including the v16→17 step that
/// previously crashed with `no such column: shop_id` on the 9 legacy tables).
/// ---------------------------------------------------------------------------

void main() {
  test(
    'real AppDatabase open migrates a v14 database to the live schema, landing '
    'every legacy row on the Cafe shop with receipt offer columns',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(14);
      // Ensure the underlying db is created at v14 first via its own database
      // class, seeding the Cafe shop and legacy business rows that existed on
      // a real v16-era device.
      final v14Conn = schema.newConnection();
      final v14Db = v14.DatabaseAtV14(v14Conn);

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
      await v14Db
          .into(v14Db.categories)
          .insert(
            v14.CategoriesCompanion.insert(
              id: 'cat-1',
              name: 'Beans',
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
          .into(v14Db.productVariants)
          .insert(
            v14.ProductVariantsCompanion.insert(
              id: 'var-1',
              productId: 'p1',
              name: '250 ml',
              sellingPricePaise: 14000,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.customers)
          .insert(
            v14.CustomersCompanion.insert(
              id: 'c1',
              name: 'Lakshmi',
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.sales)
          .insert(
            v14.SalesCompanion.insert(
              id: 's1',
              receiptNumber: 'BF-000001',
              subtotalPaise: 24000,
              totalPaise: 24000,
              createdAt: '2026-01-02T10:00:00.000Z',
              updatedAt: '2026-01-02T10:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.saleItems)
          .insert(
            v14.SaleItemsCompanion.insert(
              id: 'si1',
              saleId: 's1',
              productId: 'p1',
              productName: 'Filter Coffee',
              unitPricePaise: 12000,
              quantity: 2,
              lineTotalPaise: 24000,
            ),
          );
      await v14Db
          .into(v14Db.customerPayments)
          .insert(
            v14.CustomerPaymentsCompanion.insert(
              id: 'cp1',
              customerId: 'c1',
              amountPaise: 24000,
              paymentMethod: 'CASH',
              paidAt: '2026-01-02T10:00:00.000Z',
              createdAt: '2026-01-02T10:00:00.000Z',
              updatedAt: '2026-01-02T10:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.expenses)
          .insert(
            v14.ExpensesCompanion.insert(
              id: 'exp-1',
              name: 'Rent',
              amountPaise: 50000,
              category: 'RENT',
              paymentMethod: 'UPI',
              expenseDate: '2026-01-05T00:00:00.000Z',
              createdAt: '2026-01-05T00:00:00.000Z',
              updatedAt: '2026-01-05T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.suppliers)
          .insert(
            v14.SuppliersCompanion.insert(
              id: 'sup-1',
              name: 'Annapurna Traders',
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.purchases)
          .insert(
            v14.PurchasesCompanion.insert(
              id: 'pu-1',
              purchaseNumber: 'PUR-000001',
              subtotalPaise: 40000,
              totalPaise: 40000,
              createdAt: '2026-01-03T10:00:00.000Z',
              updatedAt: '2026-01-03T10:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.purchaseItems)
          .insert(
            v14.PurchaseItemsCompanion.insert(
              id: 'pi1',
              purchaseId: 'pu-1',
              productId: 'p1',
              productName: 'Filter Coffee',
              unitCostPaise: 8000,
              quantity: 5,
              lineTotalPaise: 40000,
            ),
          );
      await v14Db
          .into(v14Db.stockMovements)
          .insert(
            v14.StockMovementsCompanion.insert(
              id: 'm1',
              productId: 'p1',
              movementType: 'OPENING',
              quantity: 7,
              stockBefore: 0,
              stockAfter: 7,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await v14Db
          .into(v14Db.saleSequences)
          .insert(v14.SaleSequencesCompanion.insert(id: 'sale-seq'));
      await v14Db
          .into(v14Db.purchaseSequences)
          .insert(v14.PurchaseSequencesCompanion.insert(id: 'purchase-seq'));
      await v14Db.customSelect('SELECT 1').get();
      await v14Db.close();

      final db = AppDatabase(schema.newConnection());
      await db.customSelect('SELECT 1').get();

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.data.values.first,
        19,
        reason: 'real upgrade chain v14 -> live must land on the latest schema',
      );

      // v16 → v17 shop-scoping must have assigned every legacy row to the
      // pre-existing Cafe shop (no orphan NULLs, no crash on the missing
      // v16 shop_id column).
      final cafeId = 'shop-cafe';
      Future<String?> legacyShopId(String table, String id) async {
        final rows = await db
            .customSelect(
              'SELECT shop_id FROM $table WHERE id = ?',
              variables: [Variable<String>(id)],
            )
            .get();
        return rows.isEmpty ? null : rows.first.data.values.first as String?;
      }

      for (final entry in {
        'categories': ['cat-1'],
        'products': ['p1'],
        'product_variants': ['var-1'],
        'customers': ['c1'],
        'sales': ['s1'],
        'sale_items': ['si1'],
        'customer_payments': ['cp1'],
        'expenses': ['exp-1'],
        'suppliers': ['sup-1'],
        'purchases': ['pu-1'],
        'purchase_items': ['pi1'],
        'stock_movements': ['m1'],
        'sale_sequences': ['sale-seq'],
        'purchase_sequences': ['purchase-seq'],
      }.entries) {
        for (final id in entry.value) {
          final shopId = await legacyShopId(entry.key, id);
          expect(
            shopId,
            cafeId,
            reason:
                'legacy row $id in ${entry.key} must be scoped to Cafe '
                'after the v16 -> v17 migration',
          );
        }
      }

      final saleItems = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('sale_items') ORDER BY name",
          )
          .get();
      final saleItemCols = saleItems
          .map((row) => row.data.values.first as String)
          .toList();
      expect(saleItemCols, contains('offer_discount_paise'));
      expect(saleItemCols, contains('applied_offer_id'));
      expect(saleItemCols, contains('applied_offer_name'));
      expect(saleItemCols, contains('applied_offer_type'));

      final salesCols =
          (await db
                  .customSelect(
                    "SELECT name FROM pragma_table_info('sales') ORDER BY name",
                  )
                  .get())
              .map((row) => row.data.values.first as String)
              .toList();
      expect(salesCols, contains('offer_discount_paise'));

      await db.close();
      schema.close();
    },
  );
}
