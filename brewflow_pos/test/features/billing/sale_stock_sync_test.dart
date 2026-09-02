import 'dart:convert';

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BUG 1 — stock must reduce after a sale and the change must sync.
///
/// Verifies, against the real Drift stack:
///  - tracked product + PAID sale deducts local stock AND enqueues a PRODUCT
///    outbox entry with the reduced level (so the other device converges);
///  - tracked product + UNPAID (credit) sale deducts stock the same way;
///  - untracked (stockUnit NONE) product is never deducted and enqueues no
///    inventory outbox entry;
///  - stock can never go negative (insufficient stock rolls the whole
///    transaction back, leaking no outbox rows);
///  - a variant-line sale deducts the variant and enqueues a PRODUCT_VARIANT
///    entry with the reduced level.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late DriftSyncRepository sync;
  late SyncOutboxCoordinator coordinator;
  late DriftBillingRepository billing;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sync = DriftSyncRepository(db);
    coordinator = SyncOutboxCoordinator(
      sync,
      () async => const SyncSessionContext(
        deviceId: 'test-device',
        shopId: 'shop-test',
        userId: 'user-test',
      ),
    );
    billing = DriftBillingRepository(db, outboxCoordinator: coordinator);
  });

  tearDown(() => db.close());

  Future<void> seedProduct({
    required String id,
    required String name,
    int stock = 10,
    String stockUnit = 'COUNT',
    int pricePaise = 12000,
  }) async {
    await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(id: Value(id), name: 'Cat $id'));
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sellingPricePaise: pricePaise,
            stockQuantity: Value(stock),
            stockUnit: Value(stockUnit),
          ),
        );
  }

  Future<void> seedVariantProduct({
    required String id,
    required String name,
    required List<({String id, String name, int stock})> variants,
  }) async {
    await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(id: Value(id), name: 'Cat $id'));
    final stockSum = variants.fold<int>(0, (sum, v) => sum + v.stock);
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sellingPricePaise: 12000,
            stockQuantity: Value(stockSum),
          ),
        );
    for (final variant in variants) {
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: Value(variant.id),
              productId: id,
              name: variant.name,
              sellingPricePaise: 12000,
              stockQuantity: Value(variant.stock),
            ),
          );
    }
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

  Future<List<({String entity, String entityId, Map<String, dynamic> payload})>>
  outbox(String entityWire) async {
    final rows =
        await (db.select(db.syncOutbox)..where(
              (t) => t.entity.equals(entityWire) & t.status.equals('PENDING'),
            ))
            .get();
    return [
      for (final r in rows)
        (
          entity: r.entity,
          entityId: r.entityId,
          payload: jsonDecode(r.payload) as Map<String, dynamic>,
        ),
    ];
  }

  group('BUG 1 — stock reduction on sale', () {
    test(
      'tracked product + PAID sale reduces stock and enqueues PRODUCT sync',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 10);

        await billing.completeSale(
          lines: [
            CartLine(
              productId: 'p1',
              productName: 'Filter Coffee',
              unitPricePaise: 12000,
              quantity: 3,
              maxQuantity: 99,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );

        expect(await productStock('p1'), 7, reason: 'paid sale deducts stock');
        final products = await outbox('PRODUCT');
        expect(products, hasLength(1));
        expect(products.single.entityId, 'p1');
        expect(products.single.payload['stockQuantity'], 7);
        expect(products.single.payload['stockUnit'], 'COUNT');
      },
    );

    test(
      'tracked product + UNPAID (credit) sale reduces stock and syncs',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 10);
        await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(id: Value('c1'), name: 'Customer One'),
            );

        await billing.completeSale(
          lines: [
            CartLine(
              productId: 'p1',
              productName: 'Filter Coffee',
              unitPricePaise: 12000,
              quantity: 3,
              maxQuantity: 99,
            ),
          ],
          paymentStatus: PaymentStatus.notPaid,
          customerId: 'c1',
        );

        expect(
          await productStock('p1'),
          7,
          reason: 'unpaid (credit) sale also deducts stock',
        );
        final products = await outbox('PRODUCT');
        expect(products, hasLength(1));
        expect(products.single.payload['stockQuantity'], 7);
      },
    );

    test(
      'untracked product is never deducted and enqueues no inventory sync',
      () async {
        await seedProduct(
          id: 'p1',
          name: 'Made-to-order',
          stock: 0,
          stockUnit: 'NONE',
        );

        await billing.completeSale(
          lines: [
            CartLine(
              productId: 'p1',
              productName: 'Made-to-order',
              unitPricePaise: 5000,
              quantity: 2,
              maxQuantity: 99,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );

        expect(await productStock('p1'), 0, reason: 'untracked keeps stock');
        expect(await outbox('PRODUCT'), isEmpty);
      },
    );

    test('stock cannot become negative; the whole sale rolls back', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 2);

      expect(
        () => billing.completeSale(
          lines: [
            CartLine(
              productId: 'p1',
              productName: 'Filter Coffee',
              unitPricePaise: 12000,
              quantity: 5,
              maxQuantity: 99,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await productStock('p1'), 2, reason: 'stock untouched on failure');
      expect(await outbox('PRODUCT'), isEmpty);
      expect(await outbox('SALE'), isEmpty);
    });

    test(
      'variant-line sale deducts the variant and enqueues PRODUCT_VARIANT',
      () async {
        await seedVariantProduct(
          id: 'p1',
          name: 'Beverage',
          variants: [
            (id: 'v1', name: 'Small', stock: 5),
            (id: 'v2', name: 'Large', stock: 5),
          ],
        );

        await billing.completeSale(
          lines: [
            CartLine(
              productId: 'p1',
              variantId: 'v1',
              productName: 'Beverage',
              variantName: 'Small',
              unitPricePaise: 12000,
              quantity: 2,
              maxQuantity: 99,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );

        expect(await variantStock('v1'), 3, reason: 'sold variant deducted');
        expect(await variantStock('v2'), 5, reason: 'other variant untouched');
        final variants = await outbox('PRODUCT_VARIANT');
        expect(variants, hasLength(1));
        expect(variants.single.entityId, 'v1');
        expect(variants.single.payload['stockQuantity'], 3);
        expect(
          await outbox('PRODUCT'),
          isEmpty,
          reason: 'variant product-level mirror is not a deducted entity',
        );
      },
    );
  });
}
