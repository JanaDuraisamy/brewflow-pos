import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for FINAL E2E Failure 2:
/// the cart carries product ids without shop scope, and checkout resolved the
/// write shop purely from the profile. When the shelf row belonged to a
/// different shop, `create_sale_atomic` correctly rejected the lines with
/// UNAVAILABLE_PRODUCT while the UI showed a sellable product.
///
/// The repository must derive the sale shop from the actual stock entities
/// and reject mixed-shop carts without weakening product validation.
void main() {
  late AppDatabase db;
  late DriftBillingRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftBillingRepository(db);
    for (final shop in ['shop-product', 'shop-profile', 'shop-b']) {
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value(shop), name: shop));
    }
    // Profile resolver would pick shop-profile (OWNER) if the repository
    // guessed instead of deriving from the products.
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
            shopId: const Value('shop-product'),
            name: 'Beverages',
          ),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: const Value('cat-b'),
            shopId: const Value('shop-b'),
            name: 'Snacks',
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> seedProduct({
    required String id,
    required String shopId,
    required String categoryId,
    int stock = 10,
  }) async {
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            categoryId: categoryId,
            name: 'Product $id',
            sellingPricePaise: 6500,
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
        );
  }

  CartLine line(String id) => CartLine(
    productId: id,
    productName: 'Product $id',
    sku: null,
    unitPricePaise: 6500,
    quantity: 1,
    maxQuantity: 99,
  );

  Future<String?> saleShop(String saleId) async {
    final row = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(saleId))).getSingleOrNull();
    return row?.shopId;
  }

  test(
    'checkout uses the products owning shop, not the profile shop',
    () async {
      await seedProduct(id: 'p-1', shopId: 'shop-product', categoryId: 'cat-1');
      final completed = await repo.completeSale(
        lines: [line('p-1')],
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );
      expect(await saleShop(completed.sale.id), 'shop-product');
    },
  );

  test('mixed-shop cart is rejected without weakening validation', () async {
    await seedProduct(id: 'p-1', shopId: 'shop-product', categoryId: 'cat-1');
    await seedProduct(id: 'p-2', shopId: 'shop-b', categoryId: 'cat-b');
    expect(
      () => repo.completeSale(
        lines: [line('p-1'), line('p-2')],
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      ),
      throwsA(isA<UnexpectedBillingFailure>()),
    );
    final count = await db.select(db.sales).get().then((rows) => rows.length);
    expect(count, 0);
  });

  test('explicit shopId still wins for callers with context', () async {
    await seedProduct(id: 'p-1', shopId: 'shop-product', categoryId: 'cat-1');
    final completed = await repo.completeSale(
      lines: [line('p-1')],
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.cash,
      shopId: 'shop-product',
    );
    expect(await saleShop(completed.sale.id), 'shop-product');
  });
}
