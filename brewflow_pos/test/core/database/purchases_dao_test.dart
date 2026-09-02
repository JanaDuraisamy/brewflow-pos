import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/daos/purchase_items_dao.dart';
import 'package:brewflow_pos/core/database/daos/purchases_dao.dart';
import 'package:brewflow_pos/core/database/daos/suppliers_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Phase 10 Step 4 — suppliers / purchases / purchase_items DAO foundation
///
/// Exercises the DAO layer against a real (in-memory) database: supplier
/// persistence and soft deactivation, purchase header + snapshot line round
/// trips, walk-in purchases without a supplier, and the immutability of the
/// unit-cost snapshot when the product's cost price changes later.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late SuppliersDao suppliers;
  late PurchasesDao purchases;
  late PurchaseItemsDao purchaseItems;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    suppliers = SuppliersDao(database);
    purchases = PurchasesDao(database);
    purchaseItems = PurchaseItemsDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedSupplier({
    required String id,
    required String name,
    String? phone,
    bool active = true,
  }) async {
    await suppliers.insert(
      SuppliersCompanion.insert(
        id: Value(id),
        name: name,
        phone: Value(phone),
        isActive: Value(active),
      ),
    );
  }

  Future<void> seedProduct({
    required String id,
    required String name,
    String? sku,
    int? costPaise,
    int stock = 0,
  }) async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: Value('cat-$id'),
            name: 'Category $id',
          ),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: 'cat-$id',
            name: name,
            sku: Value(sku),
            sellingPricePaise: 12000,
            costPricePaise: Value(costPaise),
            stockQuantity: Value(stock),
          ),
        );
  }

  Future<String> seedShop(String id) async {
    await database
        .into(database.shops)
        .insert(ShopsCompanion.insert(id: Value(id), name: 'Shop $id'));
    return id;
  }

  Future<Purchase> seedPurchase({
    required String id,
    String? supplierId,
    String? shopId,
    String purchaseNumber = 'PUR-000001',
    int totalPaise = 1000,
  }) => purchases.insert(
    PurchasesCompanion.insert(
      id: Value(id),
      shopId: Value(shopId),
      supplierId: Value(supplierId),
      purchaseNumber: purchaseNumber,
      subtotalPaise: totalPaise,
      totalPaise: totalPaise,
      notes: Value(null),
    ),
  );

  Future<PurchaseItem> seedItem({
    required String purchaseId,
    required String productId,
    String productName = 'Filter Coffee',
    String? sku,
    int unitCostPaise = 8000,
    int quantity = 1,
  }) => purchaseItems.insert(
    PurchaseItemsCompanion.insert(
      purchaseId: purchaseId,
      productId: productId,
      productName: productName,
      sku: Value(sku),
      unitCostPaise: unitCostPaise,
      quantity: quantity,
      lineTotalPaise: unitCostPaise * quantity,
    ),
  );

  group('SuppliersDao', () {
    test('inserts and reads a supplier back with all fields', () async {
      final row = await suppliers.insert(
        SuppliersCompanion.insert(
          id: Value('s-1'),
          name: 'Arabian Roasters',
          phone: Value('9000000001'),
          email: Value('hello@arabianroasters.in'),
          address: Value('T. Nagar, Chennai'),
          notes: Value('Weekly delivery'),
          isActive: Value(true),
        ),
      );

      expect(row.id, 's-1');
      expect(row.name, 'Arabian Roasters');
      expect(row.phone, '9000000001');
      expect(row.email, 'hello@arabianroasters.in');
      expect(row.address, 'T. Nagar, Chennai');
      expect(row.notes, 'Weekly delivery');
      expect(row.isActive, isTrue);

      final byId = await suppliers.byId('s-1');
      expect(byId?.name, 'Arabian Roasters');
      expect(byId?.phone, '9000000001');
    });

    test('lists suppliers sorted by name and filters by search', () async {
      await seedSupplier(id: 's-1', name: 'Zed Exports');
      await seedSupplier(id: 's-2', name: 'Alpha Mills', phone: '9000000002');
      await seedSupplier(id: 's-3', name: 'Mid Beans');

      final all = await suppliers.query();
      expect(all.map((s) => s.name).toList(), [
        'Alpha Mills',
        'Mid Beans',
        'Zed Exports',
      ]);

      final search = await suppliers.query(search: 'alpha');
      expect(search, hasLength(1));
      expect(search.single.name, 'Alpha Mills');

      final phoneSearch = await suppliers.query(search: '9000000002');
      expect(phoneSearch, hasLength(1));
      expect(phoneSearch.single.id, 's-2');

      final empty = await suppliers.query(search: 'nope');
      expect(empty, isEmpty);
    });

    test('active toggle hides suppliers without deleting them', () async {
      await seedSupplier(id: 's-1', name: 'Alpha Mills');

      await suppliers.updateActive('s-1', false);

      final inactive = await suppliers.query(active: false);
      expect(inactive, hasLength(1));
      expect(inactive.single.id, 's-1');

      final active = await suppliers.query(active: true);
      expect(active, isEmpty);

      final byId = await suppliers.byId('s-1');
      expect(byId?.isActive, isFalse);
      expect(byId?.name, 'Alpha Mills');
    });

    test('phone uniqueness is case-insensitive', () async {
      await seedSupplier(id: 's-1', name: 'Alpha Mills', phone: '9000000001');

      expect(await suppliers.phoneExists('9000000001'), isTrue);
      expect(await suppliers.phoneExists('9000000002'), isFalse);

      await seedSupplier(id: 's-2', name: 'Beta Mills', phone: '9000000002');
      expect(
        await suppliers.phoneExists('9000000002', exceptId: 's-2'),
        isFalse,
      );
      expect(
        await suppliers.phoneExists('9000000001', exceptId: 's-2'),
        isTrue,
      );
      expect(
        await suppliers.phoneExists('9000000001', exceptId: 's-1'),
        isFalse,
      );
    });

    test('multiple suppliers without a phone are allowed', () async {
      await seedSupplier(id: 's-1', name: 'Alpha Mills');
      await seedSupplier(id: 's-2', name: 'Beta Mills');

      expect(await suppliers.query(), hasLength(2));
      expect(await suppliers.phoneExists(''), isFalse);
    });

    test('update changes editable fields and bumps updatedAt', () async {
      await seedSupplier(id: 's-1', name: 'Alpha Mills', phone: '9000000001');

      await suppliers.update(
        's-1',
        SuppliersCompanion(
          name: Value('Alpha Mills Ltd'),
          phone: Value('9000000009'),
        ),
      );

      final row = await suppliers.byId('s-1');
      expect(row, isNot(isNull));
      expect(row!.name, 'Alpha Mills Ltd');
      expect(row.phone, '9000000009');
      expect(row.updatedAt.isAfter(row.createdAt), isTrue);
    });
  });

  group('PurchasesDao', () {
    test('inserts and reads a purchase header back', () async {
      await seedSupplier(id: 's-1', name: 'Alpha Mills');
      final row = await seedPurchase(
        id: 'pu-1',
        supplierId: 's-1',
        purchaseNumber: 'PUR-000001',
        totalPaise: 24000,
      );

      expect(row.purchaseNumber, 'PUR-000001');
      expect(row.supplierId, 's-1');
      expect(row.subtotalPaise, 24000);
      expect(row.totalPaise, 24000);

      final byId = await purchases.byId('pu-1');
      expect(byId?.supplierId, 's-1');
      expect(byId?.subtotalPaise, 24000);
      expect(byId?.notes, isNull);
    });

    test('walk-in purchase with a null supplierId is allowed', () async {
      final row = await seedPurchase(id: 'pu-1');

      expect(row.supplierId, isNull);
      final byId = await purchases.byId('pu-1');
      expect(byId?.supplierId, isNull);
    });

    test('lists purchases newest first and persists notes', () async {
      await seedPurchase(
        id: 'pu-1',
        purchaseNumber: 'PUR-000001',
        totalPaise: 1000,
      );
      await seedPurchase(
        id: 'pu-2',
        purchaseNumber: 'PUR-000002',
        totalPaise: 2000,
      );
      await purchases.insert(
        PurchasesCompanion.insert(
          id: Value('pu-3'),
          purchaseNumber: 'PUR-000003',
          subtotalPaise: 3000,
          totalPaise: 3000,
          notes: Value('Urgent restock'),
        ),
      );

      final all = await purchases.all();
      expect(all, hasLength(3));
      expect(all.first.purchaseNumber, 'PUR-000003');
      expect(all.first.notes, 'Urgent restock');
    });

    test(
      'purchase headers must reference an existing supplier (RESTRICT)',
      () async {
        await expectLater(
          seedPurchase(id: 'pu-1', supplierId: 'ghost'),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('purchase numbers are unique per shop', () async {
      final shopId = await seedShop('shop-a');
      await seedPurchase(
        id: 'pu-1',
        shopId: shopId,
        purchaseNumber: 'PUR-000001',
      );
      // Same purchase number within the same shop must conflict.
      await expectLater(
        seedPurchase(
          id: 'pu-2',
          shopId: shopId,
          purchaseNumber: 'PUR-000001',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('purchase numbers may repeat across different shops', () async {
      final shopA = await seedShop('shop-a');
      final shopB = await seedShop('shop-b');
      await seedPurchase(
        id: 'pu-1',
        shopId: shopA,
        purchaseNumber: 'PUR-000001',
      );
      // The same purchase number is allowed under a different shop.
      await seedPurchase(
        id: 'pu-2',
        shopId: shopB,
        purchaseNumber: 'PUR-000001',
      );
      expect(
        (await purchases.all()).map((p) => p.id),
        containsAll(['pu-1', 'pu-2']),
      );
    });
  });

  group('PurchaseItemsDao', () {
    test('persists snapshot lines with insertion order', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', sku: 'FC-1');
      await seedProduct(id: 'p2', name: 'Cocoa Powder', sku: 'CP-1');
      await seedPurchase(id: 'pu-1');

      await seedItem(
        purchaseId: 'pu-1',
        productId: 'p1',
        productName: 'Filter Coffee',
        sku: 'FC-1',
        unitCostPaise: 8000,
        quantity: 5,
      );
      await seedItem(
        purchaseId: 'pu-1',
        productId: 'p2',
        productName: 'Cocoa Powder',
        sku: 'CP-1',
        unitCostPaise: 6000,
        quantity: 2,
      );

      final lines = await purchaseItems.byPurchase('pu-1');
      expect(lines, hasLength(2));
      expect(lines[0].productName, 'Filter Coffee');
      expect(lines[0].sku, 'FC-1');
      expect(lines[0].unitCostPaise, 8000);
      expect(lines[0].quantity, 5);
      expect(lines[0].lineTotalPaise, 40000);
      expect(lines[1].productName, 'Cocoa Powder');
      expect(lines[1].lineTotalPaise, 12000);
    });

    test('historical cost snapshot survives product cost changes', () async {
      await seedProduct(
        id: 'p1',
        name: 'Filter Coffee',
        costPaise: 8000,
        stock: 5,
      );
      await seedPurchase(id: 'pu-1');
      await seedItem(
        purchaseId: 'pu-1',
        productId: 'p1',
        unitCostPaise: 8000,
        quantity: 5,
      );

      await (database.update(
        database.products,
      )..where((t) => t.id.equals('p1'))).write(
        ProductsCompanion(
          costPricePaise: Value(9500),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

      final product = await (database.select(
        database.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(product.costPricePaise, 9500);

      final lines = await purchaseItems.byPurchase('pu-1');
      expect(lines.single.unitCostPaise, 8000);
      expect(lines.single.lineTotalPaise, 40000);
    });

    test('lines belong to their own purchase', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee');
      await seedPurchase(id: 'pu-1', purchaseNumber: 'PUR-000001');
      await seedPurchase(id: 'pu-2', purchaseNumber: 'PUR-000002');
      await seedItem(purchaseId: 'pu-1', productId: 'p1');
      await seedItem(purchaseId: 'pu-2', productId: 'p1');

      expect(await purchaseItems.byPurchase('pu-1'), hasLength(1));
      expect(await purchaseItems.byPurchase('pu-2'), hasLength(1));
    });

    test(
      'item must reference an existing purchase and product (RESTRICT)',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee');
        await expectLater(
          seedItem(purchaseId: 'ghost', productId: 'p1'),
          throwsA(isA<SqliteException>()),
        );
        await seedPurchase(id: 'pu-1');
        await expectLater(
          seedItem(purchaseId: 'pu-1', productId: 'ghost'),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('quantity and unit cost are validated by CHECKs', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee');
      await seedPurchase(id: 'pu-1');

      await expectLater(
        purchaseItems.insert(
          PurchaseItemsCompanion.insert(
            purchaseId: 'pu-1',
            productId: 'p1',
            productName: 'Filter Coffee',
            unitCostPaise: 8000,
            quantity: 0,
            lineTotalPaise: 0,
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        purchaseItems.insert(
          PurchaseItemsCompanion.insert(
            purchaseId: 'pu-1',
            productId: 'p1',
            productName: 'Filter Coffee',
            unitCostPaise: -1,
            quantity: 1,
            lineTotalPaise: -1,
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
