import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_shop_product_stock_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/shop_product_stock_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// ShopProductStock — the per-business stock overlay.
///
/// The rule under test throughout: a shared product is ONE definition, and the
/// STOCK is per business. Cafe 100 and truck 30 are the same drink on two
/// different shelves, and no read or write here may ever confuse them.
///
/// The two halves of that are the two halves of this file:
///  * the ROUTING decision — owned product reads the existing stock column,
///    foreign product reads the overlay, and no overlay row means not sellable;
///  * the SAFETY rules — the variant must belong to the product, quantities
///    cannot go negative, and nothing leaks across businesses.
///
/// The Cafe path is deliberately exercised alongside the Food Truck path
/// throughout: a change that only looks correct in the truck and quietly
/// alters Cafe stock is exactly the regression this layer must not introduce.
/// ---------------------------------------------------------------------------

const _cafe = 'shop-cafe';
const _truck = 'shop-truck';
const _chai = 'p-chai';
const _chai100 = 'pv-chai-100';
const _chai160 = 'pv-chai-160';
final _at = DateTime.utc(2026, 1, 1);

void main() {
  late AppDatabase db;
  late DriftShopProductStockRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftShopProductStockRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seedCafeCatalogue() async {
    await _shop(db, _cafe, 'Cafe');
    await _shop(db, _truck, 'Food Truck');
    await _category(db, 'cat-chai', 'Chai');
    await _product(
      db,
      _chai,
      'cat-chai',
      'SPL Milk Chai',
      stock: 100,
      shopId: _cafe,
    );
    await _variant(db, _chai100, _chai, '100ml', stock: 60);
    await _variant(db, _chai160, _chai, '160ml', stock: 40);
  }

  group('owned product', () {
    test('effective stock is the existing product stock_quantity', () async {
      await seedCafeCatalogue();

      final stock = await repo.effectiveStock(shopId: _cafe, productId: _chai);

      expect(stock.quantity, 100);
      expect(stock.source, StockSource.owned);
      expect(stock.isSellable, isTrue);
      expect(stock.shopId, _cafe);
    });

    test(
      'effective stock of an owned variant is its own stock_quantity',
      () async {
        await seedCafeCatalogue();

        final stock = await repo.effectiveStock(
          shopId: _cafe,
          productId: _chai,
          variantId: _chai100,
        );

        expect(stock.quantity, 60);
        expect(stock.source, StockSource.owned);
      },
    );

    test(
      'an owned product ignores any overlay row that somehow exists',
      () async {
        await seedCafeCatalogue();
        // A contradictory row must not be able to shadow the owner's number.
        await _overlay(
          db,
          id: 'stray',
          shopId: _cafe,
          productId: _chai,
          qty: 7,
        );

        final stock = await repo.effectiveStock(
          shopId: _cafe,
          productId: _chai,
        );

        expect(stock.quantity, 100);
        expect(stock.source, StockSource.owned);
      },
    );

    test(
      'an owned product refuses an overlay write rather than fork stock',
      () async {
        await seedCafeCatalogue();

        await expectLater(
          repo.upsertShelf(shopId: _cafe, productId: _chai, quantity: 5),
          throwsA(isA<OwnedProductOverlayFailure>()),
        );

        final rows = await db.select(db.shopProductStock).get();
        expect(rows, isEmpty, reason: 'the rejected write must leave no row');
      },
    );

    test(
      'owned variants report their own stock through the variant list',
      () async {
        await seedCafeCatalogue();

        final stocks = await repo.effectiveStockForVariants(
          shopId: _cafe,
          productId: _chai,
        );

        expect(stocks, hasLength(2));
        expect(stocks[0].variantId, _chai100);
        expect(stocks[0].quantity, 60);
        expect(stocks[0].source, StockSource.owned);
        expect(stocks[1].variantId, _chai160);
        expect(stocks[1].quantity, 40);
        expect(stocks[1].source, StockSource.owned);
      },
    );
  });

  group('foreign product with no overlay', () {
    test('is not sellable and reports zero, not the owner number', () async {
      await seedCafeCatalogue();

      final stock = await repo.effectiveStock(shopId: _truck, productId: _chai);

      expect(stock.quantity, 0);
      expect(stock.source, StockSource.notCarried);
      expect(
        stock.isSellable,
        isFalse,
        reason: 'no shelf means the truck is not carrying it',
      );
      expect(
        stock.quantity,
        isNot(100),
        reason: 'the Cafe shelf must never leak into the truck',
      );
    });

    test('a foreign variant with no overlay is not sellable either', () async {
      await seedCafeCatalogue();

      final stock = await repo.effectiveStock(
        shopId: _truck,
        productId: _chai,
        variantId: _chai160,
      );

      expect(stock.quantity, 0);
      expect(stock.source, StockSource.notCarried);
    });

    test('one carried variant does not make its siblings sellable', () async {
      await seedCafeCatalogue();
      // The truck stocks only the 100ml. The 160ml must stay unsellable: a
      // 160ml sale eating the 100ml shelf is the whole reason this is
      // variant-scoped.
      await _overlay(
        db,
        id: 'truck-100',
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        qty: 4,
      );

      final carried = await repo.effectiveStock(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
      );
      final notCarried = await repo.effectiveStock(
        shopId: _truck,
        productId: _chai,
        variantId: _chai160,
      );

      expect(carried.quantity, 4);
      expect(carried.source, StockSource.overlay);
      expect(notCarried.quantity, 0);
      expect(notCarried.source, StockSource.notCarried);
    });

    test(
      'the variant list marks carried and uncarried sizes separately',
      () async {
        await seedCafeCatalogue();
        await _overlay(
          db,
          id: 'truck-100',
          shopId: _truck,
          productId: _chai,
          variantId: _chai100,
          qty: 4,
        );

        final stocks = await repo.effectiveStockForVariants(
          shopId: _truck,
          productId: _chai,
        );

        expect(stocks, hasLength(2));
        expect(stocks[0].variantId, _chai100);
        expect(stocks[0].quantity, 4);
        expect(stocks[0].source, StockSource.overlay);
        expect(stocks[1].variantId, _chai160);
        expect(stocks[1].quantity, 0);
        expect(stocks[1].source, StockSource.notCarried);
      },
    );

    test(
      'adjusting an absent shelf is refused instead of creating one',
      () async {
        await seedCafeCatalogue();

        await expectLater(
          repo.adjustShelf(shopId: _truck, productId: _chai, delta: 10),
          throwsA(isA<ShelfNotCarriedFailure>()),
        );

        expect(await db.select(db.shopProductStock).get(), isEmpty);
      },
    );
  });

  group('foreign product with an overlay', () {
    test('effective stock is the overlay quantity', () async {
      await seedCafeCatalogue();
      await _overlay(
        db,
        id: 'truck-chai',
        shopId: _truck,
        productId: _chai,
        qty: 30,
      );

      final stock = await repo.effectiveStock(shopId: _truck, productId: _chai);

      expect(stock.quantity, 30);
      expect(stock.source, StockSource.overlay);
      expect(stock.isSellable, isTrue);
    });

    test('an overlay of zero is carried but empty', () async {
      await seedCafeCatalogue();
      await _overlay(
        db,
        id: 'truck-chai',
        shopId: _truck,
        productId: _chai,
        qty: 0,
      );

      final stock = await repo.effectiveStock(shopId: _truck, productId: _chai);

      expect(stock.quantity, 0);
      expect(
        stock.source,
        StockSource.overlay,
        reason: 'stocked-but-empty is not the same as not carried',
      );
    });

    test('upsert creates the shelf and reports the new quantity', () async {
      await seedCafeCatalogue();

      final stock = await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        quantity: 12,
      );

      expect(stock.quantity, 12);
      expect(stock.source, StockSource.overlay);
      final rows = await db.select(db.shopProductStock).get();
      expect(rows, hasLength(1));
      expect(rows.single.shopId, _truck);
      expect(rows.single.quantity, 12);
    });

    test('upsert on an existing shelf replaces the quantity', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 12);

      final stock = await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        quantity: 25,
      );

      expect(stock.quantity, 25);
      final rows = await db.select(db.shopProductStock).get();
      expect(rows, hasLength(1), reason: 'upsert must not add a second row');
      expect(rows.single.quantity, 25);
    });

    test('upsert accepts zero and refuses a negative quantity', () async {
      await seedCafeCatalogue();

      expect(
        (await repo.upsertShelf(
          shopId: _truck,
          productId: _chai,
          quantity: 0,
        )).quantity,
        0,
      );

      await expectLater(
        repo.upsertShelf(shopId: _truck, productId: _chai, quantity: -1),
        throwsA(isA<NegativeShelfStockFailure>()),
      );

      final row = await db.select(db.shopProductStock).getSingle();
      expect(row.quantity, 0, reason: 'the rejected write changed nothing');
    });

    test('adjust adds to an existing shelf', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 12);

      final stock = await repo.adjustShelf(
        shopId: _truck,
        productId: _chai,
        delta: 8,
      );

      expect(stock.quantity, 20);
    });

    test('adjust cannot drive a shelf negative', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 3);

      await expectLater(
        repo.adjustShelf(shopId: _truck, productId: _chai, delta: -10),
        throwsA(isA<NegativeShelfStockFailure>()),
      );

      final row = await db.select(db.shopProductStock).getSingle();
      expect(row.quantity, 3);
    });

    test('deduct takes from the overlay and reports the remainder', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 30);

      final stock = await repo.deductShelf(
        shopId: _truck,
        productId: _chai,
        delta: 4,
      );

      expect(stock.quantity, 26);
      expect((await db.select(db.shopProductStock).getSingle()).quantity, 26);
    });

    test(
      'deduct refuses to go below zero and leaves the shelf intact',
      () async {
        await seedCafeCatalogue();
        await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 2);

        await expectLater(
          repo.deductShelf(shopId: _truck, productId: _chai, delta: 5),
          throwsA(isA<InsufficientShelfStockFailure>()),
        );

        expect((await db.select(db.shopProductStock).getSingle()).quantity, 2);
      },
    );

    test('deduct of the exact quantity empties the shelf, not below', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 2);

      final stock = await repo.deductShelf(
        shopId: _truck,
        productId: _chai,
        delta: 2,
      );

      expect(stock.quantity, 0);
    });

    test('deduct with a negative delta is refused', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 10);

      await expectLater(
        repo.deductShelf(shopId: _truck, productId: _chai, delta: -1),
        throwsA(isA<NegativeShelfStockFailure>()),
      );
      expect((await db.select(db.shopProductStock).getSingle()).quantity, 10);
    });

    test('deduct distinguishes a missing shelf from a short one', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 1);

      await expectLater(
        repo.deductShelf(shopId: _truck, productId: _chai, delta: 4),
        throwsA(
          isA<InsufficientShelfStockFailure>().having(
            (f) => f.message,
            'message',
            contains('Not enough stock'),
          ),
        ),
      );
      await expectLater(
        repo.deductShelf(
          shopId: _truck,
          productId: _chai,
          variantId: _chai160,
          delta: 1,
        ),
        throwsA(
          isA<ShelfNotCarriedFailure>().having(
            (f) => f.message,
            'message',
            contains('not stocked'),
          ),
        ),
      );
    });

    test('restore puts a unit back after a void', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 30);
      await repo.deductShelf(shopId: _truck, productId: _chai, delta: 4);

      final stock = await repo.restoreShelf(
        shopId: _truck,
        productId: _chai,
        delta: 4,
      );

      expect(stock.quantity, 30);
      expect(
        (await repo.effectiveStock(shopId: _truck, productId: _chai)).quantity,
        30,
      );
    });

    test('restore onto a deleted shelf is refused, not invented', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 30);
      await repo.removeShelf(shopId: _truck, productId: _chai);

      await expectLater(
        repo.restoreShelf(shopId: _truck, productId: _chai, delta: 4),
        throwsA(isA<ShelfNotCarriedFailure>()),
      );
      expect(await db.select(db.shopProductStock).get(), isEmpty);
    });

    test('removeShelf makes the unit not sellable again', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 30);

      await repo.removeShelf(shopId: _truck, productId: _chai);

      final stock = await repo.effectiveStock(shopId: _truck, productId: _chai);
      expect(stock.source, StockSource.notCarried);
      expect(stock.isSellable, isFalse);
    });

    test('removeShelf on one variant leaves its sibling alone', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai160,
        quantity: 6,
      );

      await repo.removeShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
      );

      final remaining = await db.select(db.shopProductStock).get();
      expect(remaining, hasLength(1));
      expect(remaining.single.variantId, _chai160);
      expect(remaining.single.quantity, 6);
    });

    test('removeShelvesForProduct clears both levels at once', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 9);
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai160,
        quantity: 6,
      );

      await repo.removeShelvesForProduct(shopId: _truck, productId: _chai);

      expect(await db.select(db.shopProductStock).get(), isEmpty);
      final stock = await repo.effectiveStock(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
      );
      expect(
        stock.source,
        StockSource.notCarried,
        reason: 'a removed product must not stay sellable via a variant row',
      );
    });
  });

  group('shop isolation', () {
    test('the Cafe and the truck hold independent shelves', () async {
      await seedCafeCatalogue();
      // One product, foreign to both businesses, stocked differently by each.
      // The Cafe also still reads its own product off the product row.
      await _product(db, 'p-loose', 'cat-chai', 'Loose Leaf', stock: 0);

      await repo.upsertShelf(
        shopId: _cafe,
        productId: 'p-loose',
        quantity: 100,
      );
      await repo.upsertShelf(
        shopId: _truck,
        productId: 'p-loose',
        quantity: 30,
      );

      expect(
        (await repo.effectiveStock(
          shopId: _cafe,
          productId: 'p-loose',
        )).quantity,
        100,
      );
      expect(
        (await repo.effectiveStock(
          shopId: _truck,
          productId: 'p-loose',
        )).quantity,
        30,
      );

      // And the Cafe's own product is still read from its own column, unaffected
      // by any of the overlay work above.
      final owned = await repo.effectiveStock(shopId: _cafe, productId: _chai);
      expect(owned.quantity, 100);
      expect(owned.source, StockSource.owned);
    });

    test('a truck deduction never touches the Cafe shelf', () async {
      await seedCafeCatalogue();
      // A product with no owning shop: it belongs to nobody, so both
      // businesses treat it as foreign and each carries its own overlay.
      await _product(db, 'p-loose', 'cat-chai', 'Loose Leaf', stock: 500);
      await repo.upsertShelf(
        shopId: _cafe,
        productId: 'p-loose',
        quantity: 100,
      );
      await repo.upsertShelf(
        shopId: _truck,
        productId: 'p-loose',
        quantity: 30,
      );

      await repo.deductShelf(shopId: _truck, productId: 'p-loose', delta: 12);

      expect(
        (await repo.effectiveStock(
          shopId: _truck,
          productId: 'p-loose',
        )).quantity,
        18,
      );
      expect(
        (await repo.effectiveStock(
          shopId: _cafe,
          productId: 'p-loose',
        )).quantity,
        100,
        reason: 'the Cafe shelf is a different row and must be untouched',
      );
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals('p-loose'))).getSingle();
      expect(
        product.stockQuantity,
        500,
        reason: "the owner's product row is never the overlay's business",
      );
    });

    test(
      'the same product can be carried by several businesses at once',
      () async {
        await seedCafeCatalogue();
        await _product(db, 'p-loose', 'cat-chai', 'Loose Leaf', stock: 0);

        await repo.upsertShelf(
          shopId: _truck,
          productId: 'p-loose',
          quantity: 30,
        );
        await repo.upsertShelf(
          shopId: _cafe,
          productId: 'p-loose',
          quantity: 7,
        );

        final rows = await db.select(db.shopProductStock).get();
        expect(rows, hasLength(2));
        expect(
          (await repo.effectiveStock(
            shopId: _truck,
            productId: 'p-loose',
          )).quantity,
          30,
        );
        expect(
          (await repo.effectiveStock(
            shopId: _cafe,
            productId: 'p-loose',
          )).quantity,
          7,
        );
      },
    );

    test(
      'removing one business shelf leaves the other business carrying',
      () async {
        await seedCafeCatalogue();
        await _product(db, 'p-loose', 'cat-chai', 'Loose Leaf', stock: 0);
        await repo.upsertShelf(
          shopId: _truck,
          productId: 'p-loose',
          quantity: 30,
        );
        await repo.upsertShelf(
          shopId: _cafe,
          productId: 'p-loose',
          quantity: 7,
        );

        await repo.removeShelf(shopId: _truck, productId: 'p-loose');

        expect(
          (await repo.effectiveStock(
            shopId: _truck,
            productId: 'p-loose',
          )).source,
          StockSource.notCarried,
        );
        expect(
          (await repo.effectiveStock(
            shopId: _cafe,
            productId: 'p-loose',
          )).quantity,
          7,
        );
      },
    );
  });

  group('variant safety', () {
    test('a matching product and variant pair is accepted', () async {
      await seedCafeCatalogue();

      final stock = await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );

      expect(stock.quantity, 4);
      expect(stock.variantId, _chai100);
      final row = await db.select(db.shopProductStock).getSingle();
      expect(row.productId, _chai);
      expect(row.variantId, _chai100);
    });

    test(
      'a variant of a different product is rejected and writes nothing',
      () async {
        await seedCafeCatalogue();
        await _product(db, 'p-tea', 'cat-chai', 'Masala Tea', stock: 50);

        await expectLater(
          repo.upsertShelf(
            shopId: _truck,
            productId: 'p-tea',
            variantId: _chai100,
            quantity: 4,
          ),
          throwsA(isA<VariantProductMismatchFailure>()),
        );

        expect(
          await db.select(db.shopProductStock).get(),
          isEmpty,
          reason: 'a mismatched pair must not leave a shelf behind',
        );
      },
    );

    test('a mismatched pair is rejected on every write path', () async {
      await seedCafeCatalogue();
      await _product(db, 'p-tea', 'cat-chai', 'Masala Tea', stock: 50);
      // A legitimate shelf first, so the rejection is proven to be the PAIR and
      // not merely the absence of a row.
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );

      await expectLater(
        repo.adjustShelf(
          shopId: _truck,
          productId: 'p-tea',
          variantId: _chai100,
          delta: 1,
        ),
        throwsA(isA<VariantProductMismatchFailure>()),
      );
      await expectLater(
        repo.deductShelf(
          shopId: _truck,
          productId: 'p-tea',
          variantId: _chai100,
          delta: 1,
        ),
        throwsA(isA<VariantProductMismatchFailure>()),
      );
      // A restore is a write too, and it is the one that is easy to forget:
      // without the pre-flight it would put units back onto a row that
      // describes another product's variant.
      await expectLater(
        repo.restoreShelf(
          shopId: _truck,
          productId: 'p-tea',
          variantId: _chai100,
          delta: 1,
        ),
        throwsA(isA<VariantProductMismatchFailure>()),
      );

      expect(
        (await db.select(db.shopProductStock).getSingle()).quantity,
        4,
        reason: 'the existing shelf is untouched by the rejected calls',
      );
    });

    test('an unknown variant is rejected, not treated as a mismatch', () async {
      await seedCafeCatalogue();

      await expectLater(
        repo.upsertShelf(
          shopId: _truck,
          productId: _chai,
          variantId: 'pv-does-not-exist',
          quantity: 4,
        ),
        throwsA(isA<UnknownVariantFailure>()),
      );
      expect(await db.select(db.shopProductStock).get(), isEmpty);
    });

    test('an unknown product is rejected', () async {
      await seedCafeCatalogue();

      await expectLater(
        repo.upsertShelf(
          shopId: _truck,
          productId: 'p-does-not-exist',
          quantity: 4,
        ),
        throwsA(isA<UnknownProductFailure>()),
      );
      expect(await db.select(db.shopProductStock).get(), isEmpty);
    });

    test(
      'a mismatch is rejected even when the quantity is also invalid',
      () async {
        await seedCafeCatalogue();
        await _product(db, 'p-tea', 'cat-chai', 'Masala Tea', stock: 50);

        await expectLater(
          repo.upsertShelf(
            shopId: _truck,
            productId: 'p-tea',
            variantId: _chai100,
            quantity: -1,
          ),
          throwsA(isA<NegativeShelfStockFailure>()),
        );
        expect(await db.select(db.shopProductStock).get(), isEmpty);
      },
    );
  });

  group('product-level and variant-level coexistence', () {
    test('both levels of the same product coexist for one business', () async {
      await seedCafeCatalogue();

      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 10);
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai160,
        quantity: 7,
      );

      final rows = await db.select(db.shopProductStock).get();
      expect(rows, hasLength(3));
      expect(
        (await repo.effectiveStock(shopId: _truck, productId: _chai)).quantity,
        10,
      );
      expect(
        (await repo.effectiveStock(
          shopId: _truck,
          productId: _chai,
          variantId: _chai100,
        )).quantity,
        4,
      );
      expect(
        (await repo.effectiveStock(
          shopId: _truck,
          productId: _chai,
          variantId: _chai160,
        )).quantity,
        7,
      );
    });

    test('a deduction at one level leaves the other level alone', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 10);
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );

      await repo.deductShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        delta: 4,
      );

      expect(
        (await repo.effectiveStock(shopId: _truck, productId: _chai)).quantity,
        10,
        reason: 'the product-level shelf is a different row',
      );
      expect(
        (await repo.effectiveStock(
          shopId: _truck,
          productId: _chai,
          variantId: _chai100,
        )).quantity,
        0,
      );
    });

    test('upserting one level does not create or touch the other', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );

      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 10);

      final rows = await db.select(db.shopProductStock).get();
      expect(rows, hasLength(2));
      expect(
        (await repo.effectiveStock(
          shopId: _truck,
          productId: _chai,
          variantId: _chai100,
        )).quantity,
        4,
      );
    });
  });

  group('v29 index protection through the repository', () {
    test('a duplicate product-level shelf is impossible via upsert', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 10);
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 20);

      final rows = await db.select(db.shopProductStock).get();
      expect(rows, hasLength(1));
      expect(rows.single.quantity, 20);
    });

    test('a raw duplicate insert is still refused by the index', () async {
      // The repository upserts rather than inserting blindly, so this proves
      // the DATABASE is the backstop rather than the repository being careful.
      await seedCafeCatalogue();
      await repo.upsertShelf(shopId: _truck, productId: _chai, quantity: 10);

      await expectLater(
        _overlay(db, id: 'dup', shopId: _truck, productId: _chai, qty: 99),
        throwsA(anything),
      );
      expect((await db.select(db.shopProductStock).get()).single.quantity, 10);
    });

    test('a raw duplicate variant-level insert is still refused', () async {
      await seedCafeCatalogue();
      await repo.upsertShelf(
        shopId: _truck,
        productId: _chai,
        variantId: _chai100,
        quantity: 4,
      );

      await expectLater(
        _overlay(
          db,
          id: 'dup',
          shopId: _truck,
          productId: _chai,
          variantId: _chai100,
          qty: 99,
        ),
        throwsA(anything),
      );
      expect((await db.select(db.shopProductStock).get()).single.quantity, 4);
    });

    test('the same product-level shelf in two businesses is allowed', () async {
      await seedCafeCatalogue();
      await _product(db, 'p-loose', 'cat-chai', 'Loose Leaf', stock: 0);

      await repo.upsertShelf(
        shopId: _truck,
        productId: 'p-loose',
        quantity: 30,
      );
      await repo.upsertShelf(
        shopId: _cafe,
        productId: 'p-loose',
        quantity: 100,
      );

      expect(await db.select(db.shopProductStock).get(), hasLength(2));
    });
  });

  group('cross-business reads are scoped in SQL', () {
    test(
      "the Cafe's variant shelves never appear in the truck's answer",
      () async {
        await seedCafeCatalogue();

        // A product shared in from elsewhere, so BOTH businesses carry it on
        // the overlay and each holds a number the other must never see. (The
        // Cafe's own product cannot be used here: it has no overlay at all.)
        await _product(db, 'p-shared', 'cat-chai', 'Shared Samosa', stock: 0);
        await _variant(db, 'pv-shared-s', 'p-shared', 'Small', stock: 0);
        await _variant(db, 'pv-shared-l', 'p-shared', 'Large', stock: 0);

        await repo.upsertShelf(
          shopId: _truck,
          productId: 'p-shared',
          variantId: 'pv-shared-s',
          quantity: 4,
        );
        await repo.upsertShelf(
          shopId: _cafe,
          productId: 'p-shared',
          variantId: 'pv-shared-s',
          quantity: 90,
        );

        final truck = await repo.effectiveStockForVariants(
          shopId: _truck,
          productId: 'p-shared',
        );
        final cafe = await repo.effectiveStockForVariants(
          shopId: _cafe,
          productId: 'p-shared',
        );

        expect(
          truck.firstWhere((e) => e.variantId == 'pv-shared-s').quantity,
          4,
          reason: "the Cafe's 90 must not satisfy the truck's shelf",
        );
        expect(
          cafe.firstWhere((e) => e.variantId == 'pv-shared-s').quantity,
          90,
        );
      },
    );

    test(
      'a variant the business does not carry is notCarried, not zero-stock',
      () async {
        await seedCafeCatalogue();
        await repo.upsertShelf(
          shopId: _truck,
          productId: _chai,
          variantId: _chai100,
          quantity: 4,
        );

        final rows = await repo.effectiveStockForVariants(
          shopId: _truck,
          productId: _chai,
        );
        final other = rows.firstWhere((e) => e.variantId == _chai160);

        expect(other.quantity, 0);
        expect(other.source, StockSource.notCarried);
        expect(other.isSellable, isFalse);
      },
    );
  });

  group('failures stay user-safe', () {
    test('every failure carries a display-ready message', () async {
      await seedCafeCatalogue();

      const failures = <ShopStockFailure>[
        VariantProductMismatchFailure(),
        UnknownVariantFailure(),
        UnknownProductFailure(),
        NegativeShelfStockFailure(),
        InsufficientShelfStockFailure(),
        ShelfNotCarriedFailure(),
        OwnedProductOverlayFailure(),
        UnexpectedShopStockFailure(),
      ];

      for (final failure in failures) {
        expect(failure.message, isNotEmpty);
        expect(
          failure.message,
          isNot(contains('constraint')),
          reason: 'a database detail must never reach the user',
        );
        expect(failure.toString(), failure.message);
      }
    });
  });
}

Future<void> _shop(AppDatabase db, String id, String name) async {
  await db
      .into(db.shops)
      .insert(ShopsCompanion.insert(id: Value(id), name: name));
}

Future<void> _category(AppDatabase db, String id, String name) async {
  await db
      .into(db.categories)
      .insert(CategoriesCompanion.insert(id: Value(id), name: name));
}

Future<void> _product(
  AppDatabase db,
  String id,
  String categoryId,
  String name, {
  required int stock,
  String? shopId,
}) async {
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: Value(id),
          categoryId: categoryId,
          name: name,
          sellingPricePaise: 6000,
          stockQuantity: Value(stock),
          shopId: Value(shopId),
        ),
      );
}

Future<void> _variant(
  AppDatabase db,
  String id,
  String productId,
  String name, {
  required int stock,
}) async {
  await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: Value(id),
          productId: productId,
          name: name,
          sellingPricePaise: 6000,
          stockQuantity: Value(stock),
        ),
      );
}

Future<void> _overlay(
  AppDatabase db, {
  required String id,
  required String shopId,
  required String productId,
  String? variantId,
  required int qty,
}) async {
  await db
      .into(db.shopProductStock)
      .insert(
        ShopProductStockCompanion.insert(
          id: Value(id),
          shopId: shopId,
          productId: productId,
          variantId: Value(variantId),
          quantity: Value(qty),
          createdAt: Value(_at),
          updatedAt: Value(_at),
        ),
      );
}
