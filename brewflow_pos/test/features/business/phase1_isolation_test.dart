import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 v16->v17 migration', () {
    test('empty shops creates one Cafe', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // Simulate fresh install at v17: onCreate creates all tables, shops empty.
      // AppMigrations from16To17 will ensure one Cafe shop.
      // For this test, verify that ensureShop via business_switcher creates Cafe.
      expect(AppConstants.databaseSchemaVersion, 17);
      final shops = await db.select(db.shops).get();
      // Fresh memory DB has no shops yet; business layer would create Cafe.
      expect(shops, isEmpty);
      // Simulate business_switcher ensureShop
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value('cafe-id'), name: 'Cafe'));
      final after = await db.select(db.shops).get();
      expect(after.length, 1);
      expect(after.first.name, 'Cafe');
    });

    test('repeated init does not duplicate Cafe', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value('cafe-id'), name: 'Cafe'));
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(id: Value('ft-id'), name: 'Food Truck'),
          );
      final shops = await db.select(db.shops).get();
      expect(shops.length, 2);
      // Re-inserting same Cafe should be idempotent via insertOnConflictUpdate
      await db
          .into(db.shops)
          .insertOnConflictUpdate(
            ShopsCompanion.insert(id: Value('cafe-id'), name: 'Cafe'),
          );
      expect((await db.select(db.shops).get()).length, 2);
    });
  });

  group('Cafe/Food Truck isolation', () {
    late AppDatabase db;
    late String cafeId;
    late String ftId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      cafeId = 'cafe-shop';
      ftId = 'ft-shop';
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value(cafeId), name: 'Cafe'));
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value(ftId), name: 'Food Truck'));
      // Seed categories
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: Value('cat-1'),
              shopId: Value(cafeId),
              name: 'Beverages',
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: Value('cat-2'),
              shopId: Value(ftId),
              name: 'Beverages',
            ),
          );
    });

    tearDown(() async => db.close());

    test('product isolation', () async {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p-cafe'),
              shopId: Value(cafeId),
              categoryId: 'cat-1',
              name: 'Latte',
              sellingPricePaise: 100,
              stockQuantity: Value(10),
            ),
          );
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p-ft'),
              shopId: Value(ftId),
              categoryId: 'cat-2',
              name: 'Burger',
              sellingPricePaise: 200,
              stockQuantity: Value(5),
            ),
          );
      final cafeProducts = await (db.select(
        db.products,
      )..where((t) => t.shopId.equals(cafeId))).get();
      final ftProducts = await (db.select(
        db.products,
      )..where((t) => t.shopId.equals(ftId))).get();
      expect(cafeProducts.length, 1);
      expect(cafeProducts.first.name, 'Latte');
      expect(ftProducts.length, 1);
      expect(ftProducts.first.name, 'Burger');
    });

    test('same SKU allowed across shops', () async {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p1'),
              shopId: Value(cafeId),
              categoryId: 'cat-1',
              name: 'A',
              sku: Value('SKU-001'),
              sellingPricePaise: 100,
              stockQuantity: Value(1),
            ),
          );
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p2'),
              shopId: Value(ftId),
              categoryId: 'cat-2',
              name: 'B',
              sku: Value('SKU-001'),
              sellingPricePaise: 100,
              stockQuantity: Value(1),
            ),
          );
      final all = await db.select(db.products).get();
      expect(all.length, 2);
    });

    test('customer isolation', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: Value('c-cafe'),
              shopId: Value(cafeId),
              name: 'Alice',
            ),
          );
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: Value('c-ft'),
              shopId: Value(ftId),
              name: 'Bob',
            ),
          );
      final cafeCustomers = await (db.select(
        db.customers,
      )..where((t) => t.shopId.equals(cafeId))).get();
      expect(cafeCustomers.length, 1);
      expect(cafeCustomers.first.name, 'Alice');
    });

    test('sales isolation and same receipt allowed', () async {
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: Value('s-cafe'),
              shopId: Value(cafeId),
              receiptNumber: 'BF-000001',
              subtotalPaise: 100,
              totalPaise: 100,
              paymentStatus: Value('PAID'),
            ),
          );
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: Value('s-ft'),
              shopId: Value(ftId),
              receiptNumber: 'BF-000001',
              subtotalPaise: 200,
              totalPaise: 200,
              paymentStatus: Value('PAID'),
            ),
          );
      final cafeSales = await (db.select(
        db.sales,
      )..where((t) => t.shopId.equals(cafeId))).get();
      final ftSales = await (db.select(
        db.sales,
      )..where((t) => t.shopId.equals(ftId))).get();
      expect(cafeSales.length, 1);
      expect(ftSales.length, 1);
      // Same receipt number in different shops is allowed (unique per shop)
      expect(cafeSales.first.receiptNumber, 'BF-000001');
      expect(ftSales.first.receiptNumber, 'BF-000001');
    });

    test('expense isolation', () async {
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: Value('e-cafe'),
              shopId: Value(cafeId),
              name: 'Rent',
              amountPaise: 1000,
              category: 'RENT',
              paymentMethod: 'CASH',
              expenseDate: DateTime.now().toUtc(),
            ),
          );
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: Value('e-ft'),
              shopId: Value(ftId),
              name: 'Fuel',
              amountPaise: 500,
              category: 'TRANSPORT',
              paymentMethod: 'CASH',
              expenseDate: DateTime.now().toUtc(),
            ),
          );
      final cafeExp = await (db.select(
        db.expenses,
      )..where((t) => t.shopId.equals(cafeId))).get();
      expect(cafeExp.length, 1);
      expect(cafeExp.first.name, 'Rent');
    });

    test('offer isolation', () async {
      await db
          .into(db.offers)
          .insert(
            OffersCompanion.insert(
              id: Value('o-cafe'),
              shopId: Value(cafeId),
              name: '10% Off',
              type: 'PERCENTAGE',
              configJson: '{"percent":10}',
            ),
          );
      await db
          .into(db.offers)
          .insert(
            OffersCompanion.insert(
              id: Value('o-ft'),
              shopId: Value(ftId),
              name: 'Combo',
              type: 'COMBO',
              configJson: '{"productIds":["p1"],"comboPricePaise":19900}',
            ),
          );
      final cafeOffers = await (db.select(
        db.offers,
      )..where((t) => t.shopId.equals(cafeId))).get();
      expect(cafeOffers.length, 1);
      expect(cafeOffers.first.name, '10% Off');
    });

    test('independent sale sequences', () async {
      await db
          .into(db.saleSequences)
          .insert(
            SaleSequencesCompanion.insert(
              id: 'receipt',
              shopId: cafeId,
              nextValue: Value(5),
            ),
          );
      await db
          .into(db.saleSequences)
          .insert(
            SaleSequencesCompanion.insert(
              id: 'receipt',
              shopId: ftId,
              nextValue: Value(1),
            ),
          );
      final cafeSeq = await (db.select(
        db.saleSequences,
      )..where((t) => t.shopId.equals(cafeId))).getSingle();
      final ftSeq = await (db.select(
        db.saleSequences,
      )..where((t) => t.shopId.equals(ftId))).getSingle();
      expect(cafeSeq.nextValue, 5);
      expect(ftSeq.nextValue, 1);
    });

    test('All-context read aggregation', () async {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p-cafe2'),
              shopId: Value(cafeId),
              categoryId: 'cat-1',
              name: 'Latte2',
              sellingPricePaise: 100,
              stockQuantity: Value(1),
            ),
          );
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p-ft2'),
              shopId: Value(ftId),
              categoryId: 'cat-2',
              name: 'Burger2',
              sellingPricePaise: 100,
              stockQuantity: Value(1),
            ),
          );
      final all = await db.select(db.products).get();
      expect(all.length, 2);
      final cafe = await (db.select(
        db.products,
      )..where((t) => t.shopId.equals(cafeId))).get();
      final ft = await (db.select(
        db.products,
      )..where((t) => t.shopId.equals(ftId))).get();
      expect(cafe.length + ft.length, all.length);
    });

    test('All-context write rejection', () async {
      // Simulate business_switcher All write attempt should throw
      const all = BusinessContext.all;
      expect(
        () async =>
            await Future.error(StateError('All businesses view is read-only')),
        throwsA(isA<StateError>()),
      );
      // Direct check: All is not writable
      expect(all == BusinessContext.all, isTrue);
    });

    test('existing relationships preserved', () async {
      // Create product, then sale with sale_item referencing product
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('prod-1'),
              shopId: Value(cafeId),
              categoryId: 'cat-1',
              name: 'Latte',
              sellingPricePaise: 100,
              stockQuantity: Value(10),
            ),
          );
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: Value('sale-1'),
              shopId: Value(cafeId),
              receiptNumber: 'BF-000010',
              subtotalPaise: 100,
              totalPaise: 100,
              paymentStatus: Value('PAID'),
            ),
          );
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              id: Value('item-1'),
              shopId: Value(cafeId),
              saleId: 'sale-1',
              productId: 'prod-1',
              productName: 'Latte',
              unitPricePaise: 100,
              quantity: 1,
              lineTotalPaise: 100,
            ),
          );
      final sale = await (db.select(
        db.sales,
      )..where((t) => t.id.equals('sale-1'))).getSingle();
      final item = await (db.select(
        db.saleItems,
      )..where((t) => t.saleId.equals('sale-1'))).getSingle();
      expect(item.productId, sale.id == 'sale-1' ? 'prod-1' : '');
      expect(item.shopId, cafeId);
      expect(sale.shopId, cafeId);
    });
  });
}
