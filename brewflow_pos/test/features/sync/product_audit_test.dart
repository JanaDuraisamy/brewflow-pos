import 'package:flutter_test/flutter_test.dart';

/// Audit helper used by the Phase 7.7 product audit — mirrors the cloud
/// UNIQUE constraints: categories on (shop_id, name), products/variants on
/// (shop_id, sku) where NULL is distinct, customers/suppliers on (shop_id, phone).
bool isSameLogicalProduct({
  required String? skuA,
  required String? skuB,
  required String shopA,
  required String shopB,
  required String nameA,
  required String nameB,
}) {
  if (shopA != shopB) return false;
  // Products are identified by SKU when present; NULL SKU means name is not a business key
  if (skuA != null || skuB != null) {
    return skuA == skuB && skuA != null;
  }
  // Both NULL sku — same name does NOT imply same logical product per current schema
  return false;
}

void main() {
  group('product audit', () {
    test('same shop, same name, both SKU NULL → not same logical product', () {
      expect(
        isSameLogicalProduct(
          skuA: null,
          skuB: null,
          shopA: 'shop-1',
          shopB: 'shop-1',
          nameA: 'Plain Milk',
          nameB: 'Plain Milk',
        ),
        isFalse,
      );
    });
    test('same shop, same SKU → same logical product', () {
      expect(
        isSameLogicalProduct(
          skuA: 'SKU123',
          skuB: 'SKU123',
          shopA: 'shop-1',
          shopB: 'shop-1',
          nameA: 'A',
          nameB: 'B',
        ),
        isTrue,
      );
    });
    test('different shops, same SKU → not same (isolated)', () {
      expect(
        isSameLogicalProduct(
          skuA: 'SKU123',
          skuB: 'SKU123',
          shopA: 'shop-1',
          shopB: 'shop-2',
          nameA: 'A',
          nameB: 'A',
        ),
        isFalse,
      );
    });
    test('same shop, different SKU → not same', () {
      expect(
        isSameLogicalProduct(
          skuA: 'SKU1',
          skuB: 'SKU2',
          shopA: 'shop-1',
          shopB: 'shop-1',
          nameA: 'Same',
          nameB: 'Same',
        ),
        isFalse,
      );
    });
  });
}
