import 'dart:convert';

import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_page.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_staff_repository.dart';

/// Records the shop ids passed to [InventoryRepository.products] so tests can
/// assert the offer dialog scopes its product selector to a single business.
final class _RecordingInventoryRepository implements InventoryRepository {
  _RecordingInventoryRepository(this.storedProducts);

  final List<Product> storedProducts;
  final List<List<String>> productShopIdCalls = [];

  @override
  Future<List<Product>> products({
    String? search,
    String? categoryId,
    ProductStatusFilter status = ProductStatusFilter.all,
    List<String>? shopIds,
  }) async {
    productShopIdCalls.add(shopIds ?? const []);
    return storedProducts;
  }

  @override
  Future<List<Category>> categories({List<String>? shopIds}) async => [];

  @override
  Future<bool> skuExists(String sku, {String? exceptId}) async => false;

  @override
  Future<Category> createCategory(String name, {String? shopId}) =>
      throw UnimplementedError();

  @override
  Future<void> updateCategoryName(String id, String name) =>
      throw UnimplementedError();

  @override
  Future<void> setCategoryActive(String id, bool isActive) =>
      throw UnimplementedError();

  @override
  Future<void> deleteCategory(String id) => throw UnimplementedError();

  @override
  Future<Product> createProduct({
    required String categoryId,
    required String name,
    String? sku,
    required int sellingPricePaise,
    int? costPricePaise,
    required int stockQuantity,
    String? imagePath,
    StockUnit stockUnit = StockUnit.count,
    LowStockMode lowStockMode = LowStockMode.useDefault,
    int? lowStockThreshold,
    bool membershipEnabled = false,
    int? memberPricePaise,
    required bool isActive,
    List<ProductVariantInput> variants = const [],
    String? shopId,
  }) => throw UnimplementedError();

  @override
  Future<void> updateProduct({
    required String id,
    required String categoryId,
    required String name,
    String? sku,
    required int sellingPricePaise,
    int? costPricePaise,
    required int stockQuantity,
    String? imagePath,
    StockUnit stockUnit = StockUnit.count,
    LowStockMode lowStockMode = LowStockMode.useDefault,
    int? lowStockThreshold,
    bool membershipEnabled = false,
    int? memberPricePaise,
    required bool isActive,
    List<ProductVariantInput> variants = const [],
    String? shopId,
  }) => throw UnimplementedError();

  @override
  Future<void> setProductActive(String id, bool isActive) =>
      throw UnimplementedError();

  @override
  Future<ProductDeleteResult> deleteProduct(String id) =>
      throw UnimplementedError();
}

Product _product(String id, String name, int paise) => Product(
  id: id,
  categoryId: 'c1',
  name: name,
  sellingPricePaise: paise,
  stockQuantity: 10,
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

late _RecordingInventoryRepository _inventory;
late FakeOffersRepository _offers;

Widget _app() => ProviderScope(
  overrides: [
    staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
    inventoryRepositoryProvider.overrideWithValue(_inventory),
    offersRepositoryProvider.overrideWithValue(_offers),
  ],
  child: const MaterialApp(home: Scaffold(body: OffersPage())),
);

Future<ProviderContainer> _openNewOfferDialog(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.tap(find.text('New Offer'));
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(OffersPage)));
}

Future<void> _selectType(WidgetTester tester, String label) async {
  // The offer dialog opens on the percentage type; open its type dropdown and
  // choose the target type (dropdown + menu item share the same text, so pick
  // the last match after the menu opens).
  await tester.tap(find.byType(DropdownButtonFormField<OfferType>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _inventory = _RecordingInventoryRepository([
      _product('p1', 'Latte', 14900),
      _product('p2', 'Croissant', 9900),
    ]);
    _offers = FakeOffersRepository();
  });

  group('Offer dialog product selector', () {
    testWidgets('does not expose raw product ids', (tester) async {
      await _openNewOfferDialog(tester);

      expect(find.text('Product IDs (comma separated)'), findsNothing);
      expect(find.text('Product ID *'), findsNothing);

      // The product picker is a searchable name + price selector.
      await _selectType(tester, 'Combo');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Search') ?? false),
        ),
        findsOneWidget,
      );
    });

    testWidgets('scopes products to the resolved business shop', (
      tester,
    ) async {
      await _openNewOfferDialog(tester);
      await _selectType(tester, 'Combo');

      // Default context = Cafe, resolved via FakeStaffRepository -> shop-1.
      expect(_inventory.productShopIdCalls, isNotEmpty);
      expect(_inventory.productShopIdCalls.first, ['shop-1']);
    });

    testWidgets(
      'Buy X Get Y single-select stores the internal product id on create',
      (tester) async {
        final container = await _openNewOfferDialog(tester);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Name *'),
          'B1G1',
        );
        await _selectType(tester, 'Buy X Get Y');

        // Shows name + formatted price, never the id.
        expect(find.text('Latte'), findsOneWidget);
        expect(find.text('₹149.00'), findsOneWidget);

        await tester.tap(find.text('Latte'));
        await tester.pump();

        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();

        final offers = await container.read(offersProvider.future);
        final offer = offers.single;
        final cfg = jsonDecode(offer.configJson) as Map<String, dynamic>;
        expect(cfg['productId'], 'p1');
      },
    );

    testWidgets('Combo multi-select stores internal product ids', (
      tester,
    ) async {
      final container = await _openNewOfferDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name *'),
        'Combo',
      );
      await _selectType(tester, 'Combo');

      await tester.tap(find.text('Latte'));
      await tester.pump();
      await tester.tap(find.text('Croissant'));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Combo price (paise) *'),
        '19900',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final offers = await container.read(offersProvider.future);
      final offer = offers.single;
      final cfg = jsonDecode(offer.configJson) as Map<String, dynamic>;
      expect((cfg['productIds'] as List).toSet(), {'p1', 'p2'});
    });
  });
}
