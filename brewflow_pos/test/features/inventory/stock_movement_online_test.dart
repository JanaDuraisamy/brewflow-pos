import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_stock_adjustment_cloud_gateway.dart';

void main() {
  group('Online stock adjustment/opening (cloud-authoritative)', () {
    late AppDatabase db;
    late FakeStockAdjustmentCloudGateway cloud;
    late DriftStockMovementRepository repository;

    Future<String> seedShop() async {
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(id: const Value('shop-1'), name: 'Cafe'),
          );
      return 'shop-1';
    }

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

    Future<void> seedVariant({
      required String id,
      required String productId,
      int stock = 10,
    }) async {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: Value(id),
              productId: productId,
              name: 'Variant $id',
              sellingPricePaise: 12000,
              stockQuantity: Value(stock),
              isActive: Value(true),
            ),
          );
    }

    Future<int> productStock(String id) async {
      final row = await (db.select(
        db.products,
      )..where((t) => t.id.equals(id))).getSingle();
      return row.stockQuantity;
    }

    Future<int> variantStock(String id) async {
      final row = await (db.select(
        db.productVariants,
      )..where((t) => t.id.equals(id))).getSingle();
      return row.stockQuantity;
    }

    Future<int> outboxPendingCount() async {
      final q = db.selectOnly(db.syncOutbox)
        ..addColumns([db.syncOutbox.id.count()])
        ..where(db.syncOutbox.status.equals('PENDING'));
      return (await q
          .map((row) => row.read(db.syncOutbox.id.count())!)
          .getSingle());
    }

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await seedShop();
      cloud = FakeStockAdjustmentCloudGateway();
      repository = DriftStockMovementRepository(
        db,
        connectivityService: fakeConnectivityServiceOnline()..init(),
        cloudGateway: cloud,
      );
    });

    tearDown(() async => db.close());

    test('product adjustment mirrors server stock and movement', () async {
      await seedProduct(id: 'p1', stock: 10);
      cloud.stockBefore = 10;

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.damage,
        note: '  spilled batch  ',
      );

      expect(movement.id, 'mov-1');
      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(movement.quantity, 5);
      expect(movement.stockBefore, 10);
      expect(movement.stockAfter, 15);
      expect(movement.reason, StockAdjustmentReason.damage);
      expect(movement.note, 'spilled batch');
      expect(movement.createdAt.isUtc, isTrue);
      expect(await productStock('p1'), 15);

      final call = cloud.calls.single;
      expect(call['shop_id'], 'shop-1');
      expect(call['product_id'], 'p1');
      expect(call['variant_id'], isNull);
      expect(call['delta'], 5);
      expect(call['reason'], 'DAMAGE');
      expect(call['note'], 'spilled batch');
    });

    test('variant adjustment mirrors variant stock and movement', () async {
      await seedProduct(id: 'p1', stock: 10);
      await seedVariant(id: 'v1', productId: 'p1', stock: 10);
      cloud.stockBefore = 10;

      final movement = await repository.adjustStock(
        productId: 'p1',
        variantId: 'v1',
        delta: -3,
        reason: StockAdjustmentReason.wastage,
      );

      expect(movement.id, 'mov-1');
      expect(movement.variantId, 'v1');
      expect(movement.movementType, StockMovementType.adjustmentOut);
      expect(movement.quantity, -3);
      expect(movement.stockBefore, 10);
      expect(movement.stockAfter, 7);
      expect(movement.reason, StockAdjustmentReason.wastage);
      expect(await variantStock('v1'), 7);

      final call = cloud.calls.single;
      expect(call['shop_id'], 'shop-1');
      expect(call['product_id'], 'p1');
      expect(call['variant_id'], 'v1');
      expect(call['delta'], -3);
      expect(call['reason'], 'WASTAGE');
    });

    test('opening records an OPENING movement and sets stock', () async {
      await seedProduct(id: 'p1', stock: 0);
      cloud.stockBefore = 0;

      final movement = await repository.recordOpening(
        productId: 'p1',
        quantity: 20,
        note: 'initial till',
      );

      expect(movement.id, 'mov-1');
      expect(movement.movementType, StockMovementType.opening);
      expect(movement.quantity, 20);
      expect(movement.stockBefore, 0);
      expect(movement.stockAfter, 20);
      expect(movement.reason, isNull);
      expect(await productStock('p1'), 20);

      final call = cloud.calls.single;
      expect(call['shop_id'], 'shop-1');
      expect(call['product_id'], 'p1');
      expect(call['variant_id'], isNull);
      expect(call['delta'], 20);
      expect(call['reason'], 'OPENING');
      expect(call['note'], 'initial till');
    });

    test(
      'server insufficient stock maps to a safe failure and writes nothing',
      () async {
        await seedProduct(id: 'p1', stock: 10);
        // The server is authoritative: it holds less stock than this device.
        cloud.stockBefore = 4;

        await expectLater(
          repository.adjustStock(
            productId: 'p1',
            delta: -5,
            reason: StockAdjustmentReason.damage,
          ),
          throwsA(isA<AdjustmentInsufficientStockFailure>()),
        );

        expect(await productStock('p1'), 10);
        expect(await repository.movementsFor('p1'), isEmpty);
      },
    );

    test(
      'product not found on the server maps to ProductNotFoundFailure',
      () async {
        await seedProduct(id: 'p1', stock: 10);
        cloud.nextError = Exception('PRODUCT_NOT_FOUND');

        await expectLater(
          repository.adjustStock(
            productId: 'ghost',
            delta: 5,
            reason: StockAdjustmentReason.correction,
          ),
          throwsA(isA<ProductNotFoundFailure>()),
        );
        expect(await productStock('p1'), 10);
      },
    );

    test('offline adjustment is rejected and never calls the cloud', () async {
      await seedProduct(id: 'p1', stock: 10);
      repository = DriftStockMovementRepository(
        db,
        connectivityService: fakeConnectivityService()..init(),
        cloudGateway: cloud,
      );

      await expectLater(
        repository.adjustStock(
          productId: 'p1',
          delta: 5,
          reason: StockAdjustmentReason.correction,
        ),
        throwsA(
          isA<StockMovementFailure>().having(
            (e) => e.message,
            'message',
            contains('Internet connection required'),
          ),
        ),
      );

      expect(cloud.calls, isEmpty);
      expect(await productStock('p1'), 10);
      expect(await repository.movementsFor('p1'), isEmpty);
      expect(await outboxPendingCount(), 0);
    });

    test('offline opening is rejected and never calls the cloud', () async {
      await seedProduct(id: 'p1', stock: 0);
      repository = DriftStockMovementRepository(
        db,
        connectivityService: fakeConnectivityService()..init(),
        cloudGateway: cloud,
      );

      await expectLater(
        repository.recordOpening(productId: 'p1', quantity: 20),
        throwsA(
          isA<StockMovementFailure>().having(
            (e) => e.message,
            'message',
            contains('Internet connection required'),
          ),
        ),
      );

      expect(cloud.calls, isEmpty);
      expect(await productStock('p1'), 0);
    });

    test('online writes create no outbox entries', () async {
      await seedProduct(id: 'p1', stock: 10);
      cloud.stockBefore = 10;

      await repository.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.damage,
      );
      await repository.recordOpening(productId: 'p1', quantity: 20);

      expect(cloud.calls, hasLength(2));
      expect(await outboxPendingCount(), 0);
    });

    test('duplicate opening is still rejected online', () async {
      await seedProduct(id: 'p1', stock: 0);
      cloud.stockBefore = 0;

      await repository.recordOpening(productId: 'p1', quantity: 20);

      await expectLater(
        repository.recordOpening(productId: 'p1', quantity: 5),
        throwsA(isA<DuplicateOpeningFailure>()),
      );

      expect(cloud.calls, hasLength(1));
      expect(await productStock('p1'), 20);
    });

    test('local-only fallback still works when no gateway is wired', () async {
      await seedProduct(id: 'p1', stock: 10);
      final local = DriftStockMovementRepository(
        db,
        connectivityService: fakeConnectivityServiceOnline()..init(),
      );

      final movement = await local.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.purchase,
      );

      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(await productStock('p1'), 15);
    });
  });
}
