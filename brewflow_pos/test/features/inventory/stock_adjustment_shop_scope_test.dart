import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_stock_adjustment_cloud_gateway.dart';

/// Regression for FINAL E2E Failure 4:
/// inventory showed Allpanso Mango (stock 0) but Adjust Stock → Stock In 10
/// failed with "Product not found". The dialog carries only ids while the
/// repository scoped the `adjust_stock_atomic` RPC to the profile-resolved
/// shop instead of the shop owning the shelf row.
///
/// The RPC must be scoped to the entity's own shop; server validation stays
/// intact (PRODUCT_NOT_FOUND / INACTIVE / FORBIDDEN still map).
void main() {
  late AppDatabase db;
  late FakeStockAdjustmentCloudGateway gateway;
  late DriftStockMovementRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeStockAdjustmentCloudGateway();
    repo = DriftStockMovementRepository(db, cloudGateway: gateway);
    for (final shop in ['shop-entity', 'shop-profile']) {
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value(shop), name: shop));
    }
    // Profile resolver would pick shop-profile (OWNER). The product lives in
    // shop-entity, so a resolver-scoped RPC would hit the wrong shop.
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            email: 'owner@example.com',
            shopId: const Value('shop-profile'),
            role: const Value('OWNER'),
          ),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: const Value('cat-1'),
            shopId: const Value('shop-entity'),
            name: 'Beverages',
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: const Value('prod-1'),
            shopId: const Value('shop-entity'),
            categoryId: 'cat-1',
            name: 'Allpanso Mango',
            sellingPricePaise: 6500,
            stockQuantity: const Value(0),
            isActive: const Value(true),
          ),
        );
  });

  tearDown(() async => db.close());

  test('adjustment RPC uses the product owning shop', () async {
    gateway.stockBefore = 0;
    await repo.adjustStock(
      productId: 'prod-1',
      delta: 10,
      reason: StockAdjustmentReason.correction,
    );
    expect(gateway.calls.length, 1);
    expect(gateway.calls.single['shop_id'], 'shop-entity');
    expect(gateway.calls.single['product_id'], 'prod-1');
    final row = await (db.select(
      db.products,
    )..where((t) => t.id.equals('prod-1'))).getSingle();
    expect(row.stockQuantity, 10);
  });

  test('unknown product still raises ProductNotFound locally', () async {
    expect(
      () => repo.adjustStock(
        productId: 'missing',
        delta: 1,
        reason: StockAdjustmentReason.correction,
      ),
      throwsA(isA<ProductNotFoundFailure>()),
    );
    expect(gateway.calls, isEmpty);
  });
}
