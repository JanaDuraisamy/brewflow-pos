import 'package:brewflow_pos/core/database/app_database.dart' hide Purchase;
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftPurchaseRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPurchaseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct({
    required String id,
    required String name,
    int stock = 10,
    bool active = true,
    String? sku,
  }) async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sku: Value(sku),
            sellingPricePaise: 12000,
            stockQuantity: Value(stock),
            isActive: Value(active),
          ),
        );
  }

  Future<void> seedSupplier({required String id, bool active = true}) async {
    await database
        .into(database.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: Value(id),
            name: 'Supplier $id',
            isActive: Value(active),
          ),
        );
  }

  Future<void> seedVariant({
    required String id,
    required String productId,
    required String name,
    String? sku,
    int stock = 10,
    int? costPaise,
  }) async {
    await database
        .into(database.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: Value(id),
            productId: productId,
            name: name,
            sku: Value(sku),
            sellingPricePaise: 15000,
            costPricePaise: Value(costPaise),
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
        );
  }

  List<PurchaseLine> purchaseLines(
    List<(String, int)> entries, {
    int costPaise = 12000,
  }) => [
    for (final (id, quantity) in entries)
      PurchaseLine(productId: id, quantity: quantity, unitCostPaise: costPaise),
  ];

  Future<int> countPurchases() async {
    final query = database.selectOnly(database.purchases)
      ..addColumns([database.purchases.id.count()]);
    return query
        .map((row) => row.read(database.purchases.id.count())!)
        .getSingle();
  }

  Future<int> countPurchaseItems() async {
    final query = database.selectOnly(database.purchaseItems)
      ..addColumns([database.purchaseItems.id.count()]);
    return query
        .map((row) => row.read(database.purchaseItems.id.count())!)
        .getSingle();
  }

  Future<int> countMovements() async {
    final query = database.selectOnly(database.stockMovements)
      ..addColumns([database.stockMovements.id.count()]);
    return query
        .map((row) => row.read(database.stockMovements.id.count())!)
        .getSingle();
  }

  Future<int> stockOf(String id) async {
    final row = await (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
    return row.stockQuantity;
  }

  /// Test-only trigger on an isolated in-memory database that aborts every
  /// insert into [table], forcing the receiving transaction to roll back.
  Future<void> createFailTrigger(String table, String name) async {
    await database.customStatement(
      "CREATE TRIGGER $name BEFORE INSERT ON $table "
      "BEGIN SELECT RAISE(ABORT, 'forced failure'); END",
    );
  }

  group('receivePurchase', () {
    test(
      'persists header, snapshot items and increases stock atomically',
      () async {
        await seedProduct(
          id: 'p1',
          name: 'Filter Coffee',
          stock: 5,
          sku: 'FC-01',
        );
        await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);

        final purchase = await repository.receivePurchase(
          lines: [
            const PurchaseLine(
              productId: 'p1',
              quantity: 2,
              unitCostPaise: 12000,
            ),
            const PurchaseLine(
              productId: 'p2',
              quantity: 1,
              unitCostPaise: 8000,
            ),
          ],
        );

        expect(purchase.purchaseNumber, 'PUR-000001');
        expect(purchase.supplierId, isNull);
        expect(purchase.notes, isNull);
        expect(purchase.subtotalPaise, 32000);
        expect(purchase.totalPaise, 32000);
        expect(purchase.createdAt.isUtc, isTrue);
        expect(purchase.updatedAt.isUtc, isTrue);

        final items = await repository.purchaseItems(purchase.id);
        expect(items, hasLength(2));
        expect(items[0].productName, 'Filter Coffee');
        expect(items[0].sku, 'FC-01');
        expect(items[0].unitCostPaise, 12000);
        expect(items[0].quantity, 2);
        expect(items[0].lineTotalPaise, 24000);
        expect(items[0].purchaseId, purchase.id);
        expect(items[1].productName, 'Green Tea');
        expect(items[1].quantity, 1);
        expect(items[1].lineTotalPaise, 8000);

        expect(await stockOf('p1'), 7);
        expect(await stockOf('p2'), 4);

        final loaded = await repository.purchaseById(purchase.id);
        expect(loaded!.purchaseNumber, 'PUR-000001');
        expect(loaded.totalPaise, 32000);
        expect((await repository.purchases()).length, 1);
      },
    );

    test(
      'issues gapless sequential purchase numbers across purchases',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 20);
        for (var i = 1; i <= 3; i++) {
          final purchase = await repository.receivePurchase(
            lines: purchaseLines([('p1', 1)]),
          );
          expect(
            purchase.purchaseNumber,
            'PUR-${i.toString().padLeft(6, '0')}',
          );
        }
        final all = await repository.purchases();
        expect(all.map((p) => p.purchaseNumber).toSet(), {
          'PUR-000001',
          'PUR-000002',
          'PUR-000003',
        });
        expect(await stockOf('p1'), 23);
      },
    );

    test('never touches the sale receipt sequence', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await repository.receivePurchase(lines: purchaseLines([('p1', 2)]));

      final query = database.selectOnly(database.saleSequences)
        ..addColumns([database.saleSequences.id.count()]);
      expect(
        await query
            .map((row) => row.read(database.saleSequences.id.count())!)
            .getSingle(),
        0,
      );
    });

    test('persists supplier reference and notes when given', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedSupplier(id: 's1');

      final purchase = await repository.receivePurchase(
        lines: purchaseLines([('p1', 2)]),
        supplierId: 's1',
        notes: 'Morning restock',
      );

      expect(purchase.supplierId, 's1');
      expect(purchase.notes, 'Morning restock');
      final loaded = await repository.purchaseById(purchase.id);
      expect(loaded!.supplierId, 's1');
      expect(loaded.notes, 'Morning restock');
    });

    test('rejects empty line lists', () async {
      expect(
        () => repository.receivePurchase(lines: const []),
        throwsA(isA<EmptyPurchaseFailure>()),
      );
    });

    test('rejects zero and negative quantities', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.receivePurchase(lines: purchaseLines([('p1', 0)])),
        throwsA(isA<InvalidPurchaseQuantityFailure>()),
      );
      await expectLater(
        repository.receivePurchase(lines: purchaseLines([('p1', -3)])),
        throwsA(isA<InvalidPurchaseQuantityFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects negative unit costs', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.receivePurchase(
          lines: const [
            PurchaseLine(productId: 'p1', quantity: 2, unitCostPaise: -100),
          ],
        ),
        throwsA(isA<InvalidPurchaseCostFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects duplicate product lines before any write', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.receivePurchase(
          lines: purchaseLines([('p1', 2), ('p1', 3)]),
        ),
        throwsA(isA<DuplicateProductLineFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects missing products and touches no stock at all', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.receivePurchase(
          lines: purchaseLines([('p1', 2), ('missing', 1)]),
        ),
        throwsA(
          isA<UnknownProductFailure>().having(
            (f) => f.productId,
            'productId',
            'missing',
          ),
        ),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects inactive products and rolls back', () async {
      await seedProduct(
        id: 'p1',
        name: 'Filter Coffee',
        stock: 5,
        active: false,
      );

      await expectLater(
        repository.receivePurchase(lines: purchaseLines([('p1', 1)])),
        throwsA(
          isA<InactiveProductFailure>().having(
            (f) => f.productName,
            'productName',
            'Filter Coffee',
          ),
        ),
      );
      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('rejects line totals above the safe ceiling', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 1000);

      await expectLater(
        repository.receivePurchase(
          lines: const [
            PurchaseLine(
              productId: 'p1',
              quantity: 2,
              unitCostPaise: 9999999999,
            ),
          ],
        ),
        throwsA(isA<UnexpectedPurchasesFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 1000);
    });
  });

  group('supplier linked purchases', () {
    test('accepts an active supplier', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedSupplier(id: 's1');

      final purchase = await repository.receivePurchase(
        lines: purchaseLines([('p1', 2)]),
        supplierId: 's1',
      );

      expect(purchase.supplierId, 's1');
      expect(await stockOf('p1'), 7);
    });

    test('rejects a missing supplier and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

      await expectLater(
        repository.receivePurchase(
          lines: purchaseLines([('p1', 1)]),
          supplierId: 'missing',
        ),
        throwsA(isA<UnknownSupplierFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);

      // The failed attempt must not consume a purchase sequence value.
      final next = await repository.receivePurchase(
        lines: purchaseLines([('p1', 1)]),
      );
      expect(next.purchaseNumber, 'PUR-000001');
    });

    test('rejects a deactivated supplier and rolls back everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedSupplier(id: 's1', active: false);

      await expectLater(
        repository.receivePurchase(
          lines: purchaseLines([('p1', 1)]),
          supplierId: 's1',
        ),
        throwsA(isA<InactiveSupplierFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await stockOf('p1'), 5);
    });
  });

  group('receive stock movements', () {
    test(
      'writes one PURCHASE movement per line with the purchase reference',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);

        final purchase = await repository.receivePurchase(
          lines: purchaseLines([('p1', 2), ('p2', 1)]),
        );

        final stock = DriftStockMovementRepository(database);
        final p1 = await stock.movementsFor('p1');
        expect(p1, hasLength(1));
        expect(p1.single.movementType, StockMovementType.purchase);
        expect(p1.single.quantity, 2);
        expect(p1.single.stockBefore, 5);
        expect(p1.single.stockAfter, 7);
        expect(p1.single.referenceType, 'PURCHASE');
        expect(p1.single.referenceId, purchase.id);
        expect(p1.single.reason, isNull);
        expect(p1.single.note, isNull);

        final p2 = await stock.movementsFor('p2');
        expect(p2, hasLength(1));
        expect(p2.single.movementType, StockMovementType.purchase);
        expect(p2.single.quantity, 1);
        expect(p2.single.stockBefore, 3);
        expect(p2.single.stockAfter, 4);
        expect(p2.single.referenceId, purchase.id);

        expect(await stockOf('p1'), 7);
        expect(await stockOf('p2'), 4);
      },
    );

    test(
      'keeps the audit chain consistent across OPENING and PURCHASE',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 0);
        final stock = DriftStockMovementRepository(database);
        await stock.recordOpening(productId: 'p1', quantity: 25);

        await repository.receivePurchase(lines: purchaseLines([('p1', 5)]));

        final history = await stock.movementsFor('p1');
        expect(history, hasLength(2));
        expect(history[0].movementType, StockMovementType.purchase);
        expect(history[0].quantity, 5);
        expect(history[0].stockBefore, 25);
        expect(history[0].stockAfter, 30);
        expect(history[0].stockBefore, history[1].stockAfter);
        expect(history[1].movementType, StockMovementType.opening);
        expect(history[1].quantity, 25);
        expect(history[1].stockBefore, 0);
        expect(history[1].stockAfter, 25);
        expect(await stockOf('p1'), 30);
      },
    );

    test('failed receive leaves no movements behind', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);

      await expectLater(
        repository.receivePurchase(
          lines: purchaseLines([('p1', 2), ('p2', 1)]),
          supplierId: 'missing',
        ),
        throwsA(isA<UnknownSupplierFailure>()),
      );

      expect(await countMovements(), 0);
      expect(await stockOf('p1'), 5);
      expect(await stockOf('p2'), 3);
    });

    test('touches only the products on the purchase', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3);
      await seedProduct(id: 'p3', name: 'Matcha', stock: 8);

      final purchase = await repository.receivePurchase(
        lines: purchaseLines([('p1', 2), ('p2', 1)]),
      );

      final stock = DriftStockMovementRepository(database);
      expect(await stock.movementsFor('p1'), hasLength(1));
      expect(await stock.movementsFor('p2'), hasLength(1));
      expect(await stock.movementsFor('p3'), isEmpty);
      expect(await stockOf('p3'), 8);

      final items = await repository.purchaseItems(purchase.id);
      expect(items.map((i) => i.productId), ['p1', 'p2']);
    });
  });

  group('receive hardening', () {
    test('purchase snapshots survive later product edits', () async {
      await seedProduct(
        id: 'p1',
        name: 'Filter Coffee',
        stock: 5,
        sku: 'FC-01',
      );

      final purchase = await repository.receivePurchase(
        lines: const [
          PurchaseLine(productId: 'p1', quantity: 2, unitCostPaise: 12000),
        ],
      );

      await (database.update(
        database.products,
      )..where((t) => t.id.equals('p1'))).write(
        ProductsCompanion(
          name: const Value('Filter Coffee Supreme'),
          sellingPricePaise: const Value(99900),
        ),
      );

      final items = await repository.purchaseItems(purchase.id);
      expect(items.single.productName, 'Filter Coffee');
      expect(items.single.sku, 'FC-01');
      expect(items.single.unitCostPaise, 12000);
      expect(items.single.quantity, 2);
      expect(items.single.lineTotalPaise, 24000);
      expect((await repository.purchaseById(purchase.id))!.totalPaise, 24000);
    });

    test(
      'purchase insert failure rolls back stock, items and movements',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await createFailTrigger('purchases', 'fail_purchase_insert');

        await expectLater(
          repository.receivePurchase(lines: purchaseLines([('p1', 2)])),
          throwsA(isA<UnexpectedPurchasesFailure>()),
        );

        expect(await countPurchases(), 0);
        expect(await countPurchaseItems(), 0);
        expect(await countMovements(), 0);
        expect(await stockOf('p1'), 5);

        await database.customStatement('DROP TRIGGER fail_purchase_insert');
        final next = await repository.receivePurchase(
          lines: purchaseLines([('p1', 1)]),
        );
        expect(next.purchaseNumber, 'PUR-000001');
      },
    );

    test('purchase item insert failure rolls back the whole receive', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await createFailTrigger('purchase_items', 'fail_purchase_item_insert');

      await expectLater(
        repository.receivePurchase(lines: purchaseLines([('p1', 2)])),
        throwsA(isA<UnexpectedPurchasesFailure>()),
      );

      expect(await countPurchases(), 0);
      expect(await countPurchaseItems(), 0);
      expect(await countMovements(), 0);
      expect(await stockOf('p1'), 5);

      await database.customStatement('DROP TRIGGER fail_purchase_item_insert');
      final next = await repository.receivePurchase(
        lines: purchaseLines([('p1', 1)]),
      );
      expect(next.purchaseNumber, 'PUR-000001');
    });

    test(
      'PURCHASE movement insert failure rolls back the whole receive',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await createFailTrigger('stock_movements', 'fail_movement_insert');

        await expectLater(
          repository.receivePurchase(lines: purchaseLines([('p1', 2)])),
          throwsA(isA<UnexpectedPurchasesFailure>()),
        );

        expect(await countPurchases(), 0);
        expect(await countPurchaseItems(), 0);
        expect(await countMovements(), 0);
        expect(await stockOf('p1'), 5);

        await database.customStatement('DROP TRIGGER fail_movement_insert');
        final next = await repository.receivePurchase(
          lines: purchaseLines([('p1', 1)]),
        );
        expect(next.purchaseNumber, 'PUR-000001');
      },
    );

    test(
      'concurrent single-item receives are additive with no lost updates',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);

        final outcomes = await Future.wait<Object?>([
          repository
              .receivePurchase(lines: purchaseLines([('p1', 4)]))
              .then<Object?>((purchase) => purchase)
              .catchError((Object error) => error),
          repository
              .receivePurchase(lines: purchaseLines([('p1', 4)]))
              .then<Object?>((purchase) => purchase)
              .catchError((Object error) => error),
        ]);

        final successes = outcomes.whereType<Purchase>().toList();
        final failures = outcomes.whereType<PurchasesFailure>().toList();
        expect(successes, hasLength(2));
        expect(failures, isEmpty);
        expect(await stockOf('p1'), 13);
        expect(await countPurchases(), 2);
        expect(await countPurchaseItems(), 2);
        expect(await countMovements(), 2);

        final numbers = successes.map((p) => p.purchaseNumber).toSet();
        expect(numbers, {'PUR-000001', 'PUR-000002'});

        final stock = DriftStockMovementRepository(database);
        final p1 = await stock.movementsFor('p1');
        expect(p1, hasLength(2));
        expect(p1.map((m) => m.quantity), containsAll([4, 4]));
        expect(p1.map((m) => m.stockAfter).toSet(), {9, 13});
        expect(p1.map((m) => m.referenceId).toSet(), {
          successes[0].id,
          successes[1].id,
        });
      },
    );

    test('concurrent multi-item receives are additive and atomic', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 5);

      final outcomes = await Future.wait<Object?>([
        repository
            .receivePurchase(lines: purchaseLines([('p1', 4), ('p2', 4)]))
            .then<Object?>((purchase) => purchase)
            .catchError((Object error) => error),
        repository
            .receivePurchase(lines: purchaseLines([('p1', 4), ('p2', 4)]))
            .then<Object?>((purchase) => purchase)
            .catchError((Object error) => error),
      ]);

      final successes = outcomes.whereType<Purchase>().toList();
      final failures = outcomes.whereType<PurchasesFailure>().toList();
      expect(successes, hasLength(2));
      expect(failures, isEmpty);
      expect(await stockOf('p1'), 13);
      expect(await stockOf('p2'), 13);
      expect(await countPurchases(), 2);
      expect(await countPurchaseItems(), 4);
      expect(await countMovements(), 4);

      final numbers = successes.map((p) => p.purchaseNumber).toSet();
      expect(numbers, {'PUR-000001', 'PUR-000002'});

      final stock = DriftStockMovementRepository(database);
      final p1 = await stock.movementsFor('p1');
      final p2 = await stock.movementsFor('p2');
      expect(p1, hasLength(2));
      expect(p2, hasLength(2));
      expect(p1.map((m) => m.quantity), containsAll([4, 4]));
      expect(p2.map((m) => m.quantity), containsAll([4, 4]));
      expect(p1.map((m) => m.stockAfter).toSet(), {9, 13});
      expect(p2.map((m) => m.stockAfter).toSet(), {9, 13});
      expect(p1.map((m) => m.referenceId).toSet(), {
        successes[0].id,
        successes[1].id,
      });
      expect(p2.map((m) => m.referenceId).toSet(), {
        successes[0].id,
        successes[1].id,
      });
    });
  });

  group('variant lines', () {
    test('receivePurchase snapshots variant identity and writes the '
        'PURCHASE movement on the variant', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 0);
      await seedVariant(
        id: 'v1',
        productId: 'p1',
        name: 'Small',
        sku: 'FC-S',
        stock: 10,
        costPaise: 8000,
      );

      final purchase = await repository.receivePurchase(
        lines: const [
          PurchaseLine(
            productId: 'p1',
            variantId: 'v1',
            quantity: 5,
            unitCostPaise: 8000,
          ),
        ],
      );

      expect(purchase.totalPaise, 40000);

      final items = await repository.purchaseItems(purchase.id);
      expect(items, hasLength(1));
      expect(items[0].productId, 'p1');
      expect(items[0].variantId, 'v1');
      expect(items[0].variantName, 'Small');
      expect(items[0].sku, 'FC-S');
      expect(items[0].quantity, 5);
      expect(items[0].unitCostPaise, 8000);

      // Variant stock increased; the parent product's effective stock
      // (domain level) mirrors the sum of its variants.
      final variant = await (database.select(
        database.productVariants,
      )..where((t) => t.id.equals('v1'))).getSingle();
      expect(variant.stockQuantity, 15);
      final loaded = await DriftInventoryRepository(database).products();
      expect(loaded.single.stockQuantity, 15);

      final movements = await (database.select(
        database.stockMovements,
      )..where((t) => t.referenceId.equals(purchase.id))).get();
      expect(movements, hasLength(1));
      expect(movements[0].variantId, 'v1');
      expect(movements[0].movementType, StockMovementType.purchase.dbValue);
      expect(movements[0].quantity, 5);
      expect(movements[0].stockBefore, 10);
      expect(movements[0].stockAfter, 15);
    });

    test(
      'purchase snapshots survive a variant rename after receiving',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 0);
        await seedVariant(id: 'v1', productId: 'p1', name: 'Small', stock: 10);

        final purchase = await repository.receivePurchase(
          lines: const [
            PurchaseLine(
              productId: 'p1',
              variantId: 'v1',
              quantity: 2,
              unitCostPaise: 8000,
            ),
          ],
        );

        await (database.update(database.productVariants)
              ..where((t) => t.id.equals('v1')))
            .write(const ProductVariantsCompanion(name: Value('Mini')));

        final items = await repository.purchaseItems(purchase.id);
        expect(items[0].variantId, 'v1');
        expect(items[0].variantName, 'Small');
      },
    );
  });

  group('reads', () {
    test('purchaseById returns null for unknown ids', () async {
      expect(await repository.purchaseById('missing'), isNull);
    });

    test('purchases() returns newest first', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 20);
      await repository.receivePurchase(
        lines: purchaseLines([('p1', 1)]),
        notes: 'First',
      );
      await repository.receivePurchase(
        lines: purchaseLines([('p1', 1)]),
        notes: 'Second',
      );
      final all = await repository.purchases();
      expect(all.length, 2);
      expect(all[0].notes, 'Second');
      expect(all[1].notes, 'First');
    });
  });
}
