/// ---------------------------------------------------------------------------
/// BrewFlow POS - Shop Product Stock repository (Drift implementation)
///
/// The ownership decision lives in [DriftShopProductStockRepository.effectiveStock]
/// and nowhere else, so there is exactly one place in the codebase that answers
/// "which shelf does this business sell from?".
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/domain/shop_product_stock_repository.dart';
import 'package:drift/drift.dart';

import '../../../core/database/daos/shop_product_stock_dao.dart';

final class DriftShopProductStockRepository
    implements ShopProductStockRepository {
  DriftShopProductStockRepository(this._db, [ShopProductStockDao? dao])
    : _dao = dao ?? ShopProductStockDao(_db);

  final AppDatabase _db;
  final ShopProductStockDao _dao;

  @override
  Future<EffectiveStock> effectiveStock({
    required String shopId,
    required String productId,
    String? variantId,
  }) async {
    try {
      // An OWNED product keeps the existing, audited stock path untouched. This
      // is the Cafe's normal behaviour and must behave exactly as it did before
      // the Food Truck existed.
      if (await _dao.isOwnedByShop(productId: productId, shopId: shopId)) {
        return EffectiveStock(
          productId: productId,
          shopId: shopId,
          variantId: variantId,
          quantity: await _ownedQuantity(productId, variantId),
          source: StockSource.owned,
        );
      }

      // FOREIGN product: the overlay is the only source. A missing row is
      // NOT SELLABLE — never the owner's number, never the sum of the owner's
      // variants.
      final row = await _dao.find(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
      );
      if (row == null) {
        return EffectiveStock(
          productId: productId,
          shopId: shopId,
          variantId: variantId,
          quantity: 0,
          source: StockSource.notCarried,
        );
      }
      return EffectiveStock(
        productId: productId,
        shopId: shopId,
        variantId: variantId,
        quantity: row.quantity,
        source: StockSource.overlay,
      );
    } on ShopStockFailure {
      rethrow;
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<List<EffectiveStock>> effectiveStockForVariants({
    required String shopId,
    required String productId,
  }) async {
    try {
      final variants =
          await (_db.select(_db.productVariants)
                ..where((t) => t.productId.equals(productId))
                ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
              .get();

      if (await _dao.isOwnedByShop(productId: productId, shopId: shopId)) {
        return [
          for (final variant in variants)
            EffectiveStock(
              productId: productId,
              shopId: shopId,
              variantId: variant.id,
              quantity: variant.stockQuantity,
              source: StockSource.owned,
            ),
        ];
      }

      // Shop-scoped in SQL, not filtered in Dart: the Cafe's variant shelves
      // are never fetched here, so they cannot leak into this business's answer.
      final overlay = await _dao.listVariantsForProduct(
        shopId: shopId,
        productId: productId,
      );
      final mine = {for (final row in overlay) row.variantId!: row.quantity};
      return [
        for (final variant in variants)
          EffectiveStock(
            productId: productId,
            shopId: shopId,
            variantId: variant.id,
            // No overlay row for this variant means this business does not
            // carry that size. SPL Milk Chai's 160ml must not be satisfied by
            // the 100ml shelf.
            quantity: mine[variant.id] ?? 0,
            source: mine.containsKey(variant.id)
                ? StockSource.overlay
                : StockSource.notCarried,
          ),
      ];
    } on ShopStockFailure {
      rethrow;
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<EffectiveStock> upsertShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int quantity,
  }) async {
    try {
      await _validateWrite(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        quantity: quantity,
      );

      // The read-then-insert-or-update below is only correct inside a
      // transaction. Outside one, two concurrent upserts of the same unit can
      // both see "no row" and both try to insert, and the loser surfaces as a
      // raw UNIQUE violation instead of a clean last-write-wins.
      await _db.transaction(() async {
        final now = DateTime.now().toUtc();
        final existing = await _dao.find(
          shopId: shopId,
          productId: productId,
          variantId: variantId,
        );

        if (existing == null) {
          await _dao.insert(
            ShopProductStockCompanion.insert(
              shopId: shopId,
              productId: productId,
              variantId: Value(variantId),
              quantity: Value(quantity),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        } else {
          final updated = await _dao.updateQuantity(
            shopId: shopId,
            productId: productId,
            variantId: variantId,
            quantity: quantity,
          );
          if (updated == 0) {
            throw const ShelfNotCarriedFailure();
          }
        }
      });

      return EffectiveStock(
        productId: productId,
        shopId: shopId,
        variantId: variantId,
        quantity: quantity,
        source: StockSource.overlay,
      );
    } on ShopStockFailure {
      rethrow;
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<EffectiveStock> adjustShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    try {
      await _validateWrite(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        quantity: null,
      );

      // Read-modify-write, so it needs the transaction for the same reason
      // upsertShelf does: without it a concurrent sale can slip between the
      // read and the write and the adjustment silently overwrites it.
      final next = await _db.transaction(() async {
        final current = await _dao.find(
          shopId: shopId,
          productId: productId,
          variantId: variantId,
        );
        if (current == null) {
          throw const ShelfNotCarriedFailure();
        }

        final adjusted = current.quantity + delta;
        if (adjusted < 0) {
          throw const NegativeShelfStockFailure();
        }

        final updated = await _dao.updateQuantity(
          shopId: shopId,
          productId: productId,
          variantId: variantId,
          quantity: adjusted,
        );
        if (updated == 0) {
          throw const ShelfNotCarriedFailure();
        }
        return adjusted;
      });

      return EffectiveStock(
        productId: productId,
        shopId: shopId,
        variantId: variantId,
        quantity: next,
        source: StockSource.overlay,
      );
    } on ShopStockFailure {
      rethrow;
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<EffectiveStock> deductShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    try {
      await _validateWrite(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        quantity: null,
      );
      if (delta < 0) {
        throw const NegativeShelfStockFailure();
      }

      final current = await _dao.find(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
      );
      if (current == null) {
        throw const ShelfNotCarriedFailure();
      }
      if (current.quantity < delta) {
        throw const InsufficientShelfStockFailure();
      }

      // The conditional UPDATE is the real guard against a concurrent double
      // sale: the pre-check above is only there to produce a good message, and
      // this returns null if the other sale won the race.
      final after = await _dao.deductQuantity(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        delta: delta,
      );
      if (after == null) {
        throw const InsufficientShelfStockFailure();
      }

      return EffectiveStock(
        productId: productId,
        shopId: shopId,
        variantId: variantId,
        quantity: after,
        source: StockSource.overlay,
      );
    } on ShopStockFailure {
      rethrow;
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<EffectiveStock> restoreShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    try {
      // A restore is a write, so it gets the same pre-flight as every other one.
      // Without this, `restoreShelf` was the one variant-level path that would
      // happily put units back onto a row describing another product's variant.
      await _validateWrite(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        quantity: null,
      );
      if (delta < 0) {
        throw const NegativeShelfStockFailure();
      }
      final after = await _dao.restoreQuantity(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        delta: delta,
      );
      if (after == null) {
        // A void must put a unit back where it came from. If the shelf is gone,
        // the sale history no longer matches the shelf and the caller has to
        // decide — inventing a quantity here would hide that.
        throw const ShelfNotCarriedFailure();
      }
      return EffectiveStock(
        productId: productId,
        shopId: shopId,
        variantId: variantId,
        quantity: after,
        source: StockSource.overlay,
      );
    } on ShopStockFailure {
      rethrow;
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<void> removeShelf({
    required String shopId,
    required String productId,
    String? variantId,
  }) async {
    try {
      await _dao.deleteShelf(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
      );
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  @override
  Future<void> removeShelvesForProduct({
    required String shopId,
    required String productId,
  }) async {
    try {
      await _dao.deleteShelvesForProduct(shopId: shopId, productId: productId);
    } catch (e) {
      throw UnexpectedShopStockFailure(_describe(e));
    }
  }

  /// The existing, authoritative stock number for a unit this business OWNS.
  ///
  /// A null [variantId] is the product's own recorded stock. A [variantId]
  /// reads the variant row, which is the source of truth for variant products.
  /// Nothing here knows about the overlay: the owner's shelf is the owner's
  /// shelf, exactly as it was before the Food Truck existed.
  Future<int> _ownedQuantity(String productId, String? variantId) async {
    if (variantId != null) {
      final row =
          await (_db.selectOnly(_db.productVariants)
                ..addColumns([_db.productVariants.stockQuantity])
                ..where(_db.productVariants.id.equals(variantId)))
              .getSingleOrNull();
      return row?.read(_db.productVariants.stockQuantity) ?? 0;
    }
    final row =
        await (_db.selectOnly(_db.products)
              ..addColumns([_db.products.stockQuantity])
              ..where(_db.products.id.equals(productId)))
            .getSingleOrNull();
    return row?.read(_db.products.stockQuantity) ?? 0;
  }

  /// Everything that must hold BEFORE any variant-level or product-level
  /// overlay write, in one place so no call site can skip a rule.
  ///
  /// Throws before any write happens, which is what makes "a mismatched pair
  /// writes nothing" true rather than aspirational.
  Future<void> _validateWrite({
    required String shopId,
    required String productId,
    String? variantId,
    required int? quantity,
  }) async {
    if (quantity != null && quantity < 0) {
      throw const NegativeShelfStockFailure();
    }

    // Variant safety first: a bad pair is the most dangerous input, and it must
    // be refused whether or not the rest of the arguments are valid.
    if (variantId != null) {
      final owner = await _dao.productIdOfVariant(variantId);
      if (owner == null) {
        throw const UnknownVariantFailure();
      }
      if (owner != productId) {
        // The v29 unique index keys on (shop_id, product_id, variant_id), so it
        // CANNOT catch this: pairing a real variant with the wrong product is
        // simply a different key. This check is the only thing standing between
        // a typo and a shelf that silently describes another product's variant.
        throw const VariantProductMismatchFailure();
      }
    }

    final owner =
        await (_db.selectOnly(_db.products)
              ..addColumns([_db.products.shopId])
              ..where(_db.products.id.equals(productId)))
            .getSingleOrNull();
    if (owner == null) {
      throw const UnknownProductFailure();
    }

    // An overlay row for a product the business OWNS would be a second,
    // contradictory number for the same shelf. Refuse it rather than let the
    // two disagree.
    if (owner.read(_db.products.shopId) == shopId) {
      throw const OwnedProductOverlayFailure();
    }
  }

  /// User-safe message from a low-level error. Never leaks a database detail.
  String _describe(Object e) {
    final msg = e.toString();
    if (msg.contains('CHECK constraint failed')) {
      return 'Stock quantity cannot be negative.';
    }
    if (msg.contains('UNIQUE constraint failed')) {
      return 'This business already has a stock entry for that item.';
    }
    if (msg.contains('FOREIGN KEY constraint failed')) {
      return 'That product no longer exists.';
    }
    return 'Something went wrong. Please try again.';
  }
}
