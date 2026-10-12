import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_billing_cloud_gateway.dart';
import '../helpers/fake_connectivity_service.dart';
import '../helpers/fake_purchases_cloud_gateway.dart';

void main() {
  group('Phase 1 online-only guard', () {
    late AppDatabase db;

    Future<void> seedProduct({required String id, int stock = 10}) async {
      await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(id: Value(id), name: 'Cat $id'));
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value(id),
              categoryId: id,
              name: 'Product $id',
              sellingPricePaise: 10000,
              stockQuantity: Value(stock),
              isActive: Value(true),
            ),
          );
    }

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test(
      'offline checkout is rejected with Internet connection required',
      () async {
        await seedProduct(id: 'p1', stock: 5);
        final connectivity = fakeConnectivityService(); // disconnected
        await connectivity.init();
        final cloud = FakeBillingCloudGateway();
        final repo = DriftBillingRepository(
          db,
          connectivityService: connectivity,
          cloudGateway: cloud,
        );

        expect(
          () => repo.completeSale(
            lines: [
              const CartLine(
                productId: 'p1',
                productName: 'Product p1',
                unitPricePaise: 10000,
                quantity: 1,
                maxQuantity: 5,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(
            isA<BillingFailure>().having(
              (e) => e.message,
              'message',
              contains('Internet connection required'),
            ),
          ),
        );
        expect(cloud.calls, isEmpty);
      },
    );

    test('offline void is rejected', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final cloud = FakeBillingCloudGateway();
      final repo = DriftBillingRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );
      // create a sale locally first via repo without cloud (fallback)
      final localRepo = DriftBillingRepository(db);
      final completed = await localRepo.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Product p1',
            unitPricePaise: 10000,
            quantity: 1,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );
      expect(
        () => repo.voidSale(completed.sale.id),
        throwsA(
          isA<BillingFailure>().having(
            (e) => e.message,
            'message',
            contains('Internet connection required'),
          ),
        ),
      );
    });

    test('offline purchase receive is rejected', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final cloud = FakePurchasesCloudGateway();
      final repo = DriftPurchaseRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );
      expect(
        () => repo.receivePurchase(
          lines: [
            const PurchaseLine(
              productId: 'p1',
              quantity: 2,
              unitCostPaise: 5000,
            ),
          ],
        ),
        throwsA(
          isA<PurchasesFailure>().having(
            (e) => e.message,
            'message',
            contains('Internet connection required'),
          ),
        ),
      );
    });

    test('online checkout succeeds via cloud and mirrors locally', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = FakeBillingCloudGateway();
      final repo = DriftBillingRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );

      final completed = await repo.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Product p1',
            unitPricePaise: 10000,
            quantity: 2,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      expect(completed.sale.receiptNumber, 'BF-000001');
      expect(completed.sale.id, 'sale-1');
      expect(cloud.calls, hasLength(1));
      // local stock deducted
      final row = await (db.select(
        db.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(row.stockQuantity, 3);
      // local sale persisted
      final sales = await (db.select(db.sales)).get();
      expect(sales, hasLength(1));
      expect(sales.first.receiptNumber, 'BF-000001');
    });

    test('online checkout insufficient stock via cloud is mapped', () async {
      await seedProduct(id: 'p1', stock: 2);
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = FakeBillingCloudGateway();
      cloud.nextError = Exception('INSUFFICIENT_STOCK: Product p1');
      final repo = DriftBillingRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );

      await expectLater(
        repo.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Product p1',
              unitPricePaise: 10000,
              quantity: 5,
              maxQuantity: 5,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );
      // no local mutation
      final sales = await (db.select(db.sales)).get();
      expect(sales, isEmpty);
    });

    test(
      'concurrent online checkouts get unique receipt numbers via cloud sequence',
      () async {
        await seedProduct(id: 'p1', stock: 20);
        final connectivity = fakeConnectivityServiceOnline();
        await connectivity.init();
        final cloud = FakeBillingCloudGateway();
        final repo = DriftBillingRepository(
          db,
          connectivityService: connectivity,
          cloudGateway: cloud,
        );

        final results = await Future.wait([
          repo.completeSale(
            lines: [
              const CartLine(
                productId: 'p1',
                productName: 'Product p1',
                unitPricePaise: 10000,
                quantity: 1,
                maxQuantity: 20,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
          ),
          repo.completeSale(
            lines: [
              const CartLine(
                productId: 'p1',
                productName: 'Product p1',
                unitPricePaise: 10000,
                quantity: 1,
                maxQuantity: 20,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
          ),
          repo.completeSale(
            lines: [
              const CartLine(
                productId: 'p1',
                productName: 'Product p1',
                unitPricePaise: 10000,
                quantity: 1,
                maxQuantity: 20,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
          ),
        ]);

        final receipts = results.map((r) => r.sale.receiptNumber).toSet();
        expect(receipts, hasLength(3));
        expect(receipts, contains('BF-000001'));
        expect(receipts, contains('BF-000002'));
        expect(receipts, contains('BF-000003'));
      },
    );

    test('void restores stock exactly once and double void rejected', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = FakeBillingCloudGateway();
      final repo = DriftBillingRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );

      final completed = await repo.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Product p1',
            unitPricePaise: 10000,
            quantity: 2,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );
      expect(
        (await (db.select(
          db.products,
        )..where((t) => t.id.equals('p1'))).getSingle()).stockQuantity,
        3,
      );

      await repo.voidSale(completed.sale.id);
      expect(
        (await (db.select(
          db.products,
        )..where((t) => t.id.equals('p1'))).getSingle()).stockQuantity,
        5,
      );
      final saleRow = await (db.select(
        db.sales,
      )..where((t) => t.id.equals(completed.sale.id))).getSingle();
      expect(saleRow.voided, isTrue);

      // double void via cloud ALREADY_VOIDED
      cloud.nextError = Exception('ALREADY_VOIDED');
      await expectLater(
        repo.voidSale(completed.sale.id),
        throwsA(isA<SaleAlreadyVoidedFailure>()),
      );
      // stock not restored twice
      expect(
        (await (db.select(
          db.products,
        )..where((t) => t.id.equals('p1'))).getSingle()).stockQuantity,
        5,
      );
    });

    test('online purchase receive succeeds via cloud', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = FakePurchasesCloudGateway();
      final repo = DriftPurchaseRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );

      final purchase = await repo.receivePurchase(
        lines: [
          const PurchaseLine(productId: 'p1', quantity: 3, unitCostPaise: 5000),
        ],
      );
      expect(purchase.purchaseNumber, 'PUR-000001');
      final prod = await (db.select(
        db.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(prod.stockQuantity, 8);
    });

    test('shop isolation: FORBIDDEN maps to access denied', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = FakeBillingCloudGateway();
      final repo = DriftBillingRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );
      // seed forbidden shop handling: cloud throws FORBIDDEN when shopId == forbidden-shop
      // We bypass shop resolver by passing explicit shopId that cloud checks
      // To trigger, we need a shop row with that id
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: Value('forbidden-shop'),
              name: 'Forbidden',
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: Value('forbidden-cat'),
              shopId: Value('forbidden-shop'),
              name: 'Cat',
            ),
          );
      // Need product in forbidden shop? Instead just test via direct cloud call mapping
      cloud.nextError = Exception('FORBIDDEN');
      await expectLater(
        repo.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Product p1',
              unitPricePaise: 10000,
              quantity: 1,
              maxQuantity: 5,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
          shopId: 'forbidden-shop',
        ),
        throwsA(
          isA<BillingFailure>().having(
            (e) => e.message,
            'message',
            contains('Access denied'),
          ),
        ),
      );
    });

    test(
      'no-restore cloud void calls the no-restore RPC and never restores stock',
      () async {
        await seedProduct(id: 'p1', stock: 5);
        final connectivity = fakeConnectivityServiceOnline();
        await connectivity.init();
        final cloud = FakeBillingCloudGateway();
        final repo = DriftBillingRepository(
          db,
          connectivityService: connectivity,
          cloudGateway: cloud,
        );

        final completed = await repo.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Product p1',
              unitPricePaise: 10000,
              quantity: 2,
              maxQuantity: 5,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        );
        expect(
          (await (db.select(
            db.products,
          )..where((t) => t.id.equals('p1'))).getSingle()).stockQuantity,
          3,
        );

        await repo.voidSaleWithoutRestore(completed.sale.id);

        expect(cloud.voidWithoutRestoreCalls, contains(completed.sale.id));
        expect(cloud.voidRestoreCalls, isEmpty);
        // The no-restore path leaves stock untouched.
        expect(
          (await (db.select(
            db.products,
          )..where((t) => t.id.equals('p1'))).getSingle()).stockQuantity,
          3,
        );
        final saleRow = await (db.select(
          db.sales,
        )..where((t) => t.id.equals(completed.sale.id))).getSingle();
        expect(saleRow.voided, isTrue);
      },
    );

    test(
      'cloud void of pruned history maps to VoidHistoryPrunedFailure',
      () async {
        await seedProduct(id: 'p1', stock: 5);
        final connectivity = fakeConnectivityServiceOnline();
        await connectivity.init();
        final cloud = FakeBillingCloudGateway();
        final repo = DriftBillingRepository(
          db,
          connectivityService: connectivity,
          cloudGateway: cloud,
        );

        final completed = await repo.completeSale(
          lines: [
            const CartLine(
              productId: 'p1',
              productName: 'Product p1',
              unitPricePaise: 10000,
              quantity: 2,
              maxQuantity: 5,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        );

        cloud.nextError = Exception('VOID_HISTORY_PRUNED');
        await expectLater(
          repo.voidSale(completed.sale.id),
          throwsA(isA<VoidHistoryPrunedFailure>()),
        );

        // The server rolled the void back; the local mirror must NOT have voided.
        final saleRow = await (db.select(
          db.sales,
        )..where((t) => t.id.equals(completed.sale.id))).getSingle();
        expect(saleRow.voided, isFalse);
        expect(
          (await (db.select(
            db.products,
          )..where((t) => t.id.equals('p1'))).getSingle()).stockQuantity,
          3,
        );
      },
    );

    test('cloud checkout sends a consumption snapshot per line', () async {
      await seedProduct(id: 'p1', stock: 5);
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = FakeBillingCloudGateway();
      final repo = DriftBillingRepository(
        db,
        connectivityService: connectivity,
        cloudGateway: cloud,
      );

      await repo.completeSale(
        lines: [
          const CartLine(
            productId: 'p1',
            productName: 'Product p1',
            unitPricePaise: 10000,
            quantity: 1,
            maxQuantity: 5,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      final sentConsumed = cloud.lastCreateSale!.lines.single['consumed'];
      // Unmapped tracked line: a known-empty snapshot (own-stock path), sent as
      // the decoded jsonb value, never as JSON text.
      expect(sentConsumed, isA<List<dynamic>>());
      expect(sentConsumed, isEmpty);
    });

    test(
      'cloud checkout sends a populated snapshot for a mapped line',
      () async {
        await db
            .into(db.shops)
            .insert(
              ShopsCompanion.insert(id: const Value('shop-1'), name: 'Cafe'),
            );
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: const Value('cat-1'),
                name: 'Maggi',
                shopId: const Value('shop-1'),
              ),
            );
        for (final id in ['menu-1', 'ing-1']) {
          await db
              .into(db.products)
              .insert(
                ProductsCompanion.insert(
                  id: Value(id),
                  categoryId: 'cat-1',
                  name: 'Product $id',
                  sellingPricePaise: 10000,
                  stockQuantity: Value(id == 'menu-1' ? 0 : 60),
                  isActive: const Value(true),
                  shopId: const Value('shop-1'),
                ),
              );
        }
        // menu-1 consumes 2 × ing-1 per unit sold.
        await db
            .into(db.productRecipes)
            .insert(
              ProductRecipesCompanion.insert(
                shopId: const Value('shop-1'),
                productId: 'menu-1',
                ingredientProductId: 'ing-1',
                quantity: 2,
              ),
            );

        final connectivity = fakeConnectivityServiceOnline();
        await connectivity.init();
        final cloud = FakeBillingCloudGateway();
        final repo = DriftBillingRepository(
          db,
          connectivityService: connectivity,
          cloudGateway: cloud,
        );

        await repo.completeSale(
          lines: [
            const CartLine(
              productId: 'menu-1',
              productName: 'Product menu-1',
              unitPricePaise: 10000,
              quantity: 1,
              maxQuantity: 5,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        );

        // A non-empty snapshot must pass the guard and reach the RPC decoded,
        // carrying the exact ingredient + quantity a void restores.
        final sentConsumed = cloud.lastCreateSale!.lines.single['consumed'];
        expect(sentConsumed, [
          {'ip': 'ing-1', 'iv': null, 'q': 2},
        ]);
      },
    );

    test(
      'cloud checkout aborts before the RPC when a line snapshot read fails',
      () async {
        // A "partial" capture: p1's recipe read succeeds (empty = []), p2's
        // throws. Committing now would persist p2 as consumed = NULL, a mixed
        // sale the server can never void-restore (VOID_SNAPSHOT_MIXED), so the
        // checkout must be rejected before the RPC.
        final failDb = AppDatabase(
          NativeDatabase.memory().interceptWith(_FailRecipeReadFor('p2')),
        );
        addTearDown(failDb.close);
        await failDb
            .into(failDb.shops)
            .insert(
              ShopsCompanion.insert(id: const Value('shop-1'), name: 'Cafe'),
            );
        await failDb
            .into(failDb.categories)
            .insert(
              CategoriesCompanion.insert(
                id: const Value('cat-1'),
                name: 'Cat',
                shopId: const Value('shop-1'),
              ),
            );
        for (final id in ['p1', 'p2']) {
          await failDb
              .into(failDb.products)
              .insert(
                ProductsCompanion.insert(
                  id: Value(id),
                  categoryId: 'cat-1',
                  name: 'Product $id',
                  sellingPricePaise: 10000,
                  stockQuantity: const Value(5),
                  isActive: const Value(true),
                  shopId: const Value('shop-1'),
                ),
              );
        }

        final connectivity = fakeConnectivityServiceOnline();
        await connectivity.init();
        final cloud = FakeBillingCloudGateway();
        final repo = DriftBillingRepository(
          failDb,
          connectivityService: connectivity,
          cloudGateway: cloud,
        );

        await expectLater(
          repo.completeSale(
            lines: [
              const CartLine(
                productId: 'p1',
                productName: 'Product p1',
                unitPricePaise: 10000,
                quantity: 1,
                maxQuantity: 5,
              ),
              const CartLine(
                productId: 'p2',
                productName: 'Product p2',
                unitPricePaise: 10000,
                quantity: 1,
                maxQuantity: 5,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(
            isA<UnexpectedBillingFailure>().having(
              (e) => e.message,
              'message',
              contains('Could not read the sale history'),
            ),
          ),
        );

        // The RPC was never reached and nothing was persisted or deducted.
        expect(cloud.calls, isEmpty);
        expect(cloud.createSaleArgs, isEmpty);
        expect(await failDb.select(failDb.sales).get(), isEmpty);
        final p1 = await (failDb.select(
          failDb.products,
        )..where((t) => t.id.equals('p1'))).getSingle();
        expect(p1.stockQuantity, 5);
      },
    );
  });
}

/// Throws on a `product_recipes` select whose bound arguments include
/// [failProductId], simulating one line's snapshot read failing while the rest
/// of the cart reads normally.
class _FailRecipeReadFor extends QueryInterceptor {
  _FailRecipeReadFor(this.failProductId);

  final String failProductId;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('product_recipes') && args.contains(failProductId)) {
      throw Exception('simulated recipe read failure for $failProductId');
    }
    return executor.runSelect(statement, args);
  }
}
