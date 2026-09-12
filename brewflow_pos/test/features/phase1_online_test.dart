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
  });
}
