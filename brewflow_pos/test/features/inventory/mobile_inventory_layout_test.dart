import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;

  final now = DateTime.now().toUtc();

  Category category(String id, String name) => Category(
    id: id,
    name: name,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  Product product(
    String id,
    String name, {
    String categoryId = 'c1',
    String? sku,
    int sellingPricePaise = 14950,
    int? costPricePaise,
    int stockQuantity = 0,
    bool isActive = true,
  }) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    sku: sku,
    sellingPricePaise: sellingPricePaise,
    costPricePaise: costPricePaise,
    stockQuantity: stockQuantity,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      inventoryRepositoryProvider.overrideWithValue(fakeInventory),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openInventory(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.inventory);
    await pumpAsync(tester);
  }

  void seedCatalog() {
    fakeInventory.storedCategories.addAll([
      category('c1', 'Beverages'),
      category('c2', 'Snacks'),
      category('c3', 'Dairy & Eggs'),
      category('c4', 'Bakery & Confectionery'),
    ]);
    fakeInventory.storedProducts.addAll([
      product(
        'p1',
        'Milk 1L',
        sku: 'MILK-1L',
        sellingPricePaise: 14950,
        stockQuantity: 12,
      ),
      product(
        'p2',
        'Chai Latte',
        sku: 'CHAI-01',
        sellingPricePaise: 8950,
        costPricePaise: 6000,
        stockQuantity: 0,
      ),
      product(
        'p3',
        'Homemade Masala Chai Concentrate 1L Refill',
        categoryId: 'c3',
        sku: 'MASALA-CHAI-1L-REFILL-2026',
        sellingPricePaise: 24900,
        costPricePaise: 18000,
        stockQuantity: 4,
      ),
      product(
        'p4',
        'Old Tea',
        categoryId: 'c2',
        sellingPricePaise: 14950,
        stockQuantity: 3,
        isActive: false,
      ),
    ]);
  }

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpAuthenticated(tester);
    await openInventory(tester);
  }

  const widths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

  for (final width in widths) {
    testWidgets(
      'populated inventory renders without overflow at ${width.toInt()}dp',
      (tester) async {
        seedCatalog();
        await pumpAt(tester, width);

        expect(tester.takeException(), isNull);
        expect(find.byType(InventoryPage), findsOneWidget);
        expect(find.byType(DataTable), findsNothing);
        expect(find.text('Chai Latte'), findsOneWidget);
        expect(find.textContaining('SKU CHAI-01'), findsOneWidget);
        // Phone filter row is consolidated into a single trigger; the chips
        // live inside the filter sheet, not in a crowded inline row.
        expect(find.text('Filters'), findsOneWidget);
        expect(find.text('All Categories'), findsNothing);
        expect(find.text('Low Stock'), findsNothing);
      },
    );

    testWidgets('phone filter sheet consolidates product filters and updates '
        'the active count at ${width.toInt()}dp', (tester) async {
      seedCatalog();
      await pumpAt(tester, width);

      expect(find.text('Filters'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      // Sheet surfaces every product filter section.
      expect(find.text('Filter Products'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('All Categories'), findsOneWidget);
      expect(find.text('Low Stock'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);

      // Selecting a filter updates the trigger badge while the sheet stays
      // open (live filtering).
      await tester.tap(find.text('Low Stock'));
      await tester.pumpAndSettle();
      expect(find.text('Reset'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Filters (1)'), findsNothing);
    });

    testWidgets('bulk select mode deactivates selected products safely at '
        '${width.toInt()}dp', (tester) async {
      seedCatalog();
      await pumpAt(tester, width);

      // Phone-only: entering selection hides the add/search/filter row and
      // shows the selection bar with checkboxes.
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      expect(find.text('Add Product'), findsNothing);
      expect(find.text('Filters'), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsWidgets);

      // Select two products by tapping their cards.
      await tester.tap(
        find.ancestor(of: find.text('Milk 1L'), matching: find.byType(AppCard)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('Chai Latte'),
          matching: find.byType(AppCard),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      // The Deactivate action requires an explicit destructive confirmation.
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      expect(find.text('Deactivate products'), findsOneWidget);
      expect(find.text('2 products'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Deactivate'),
        ),
      );
      await tester.pumpAndSettle();

      final milk = fakeInventory.storedProducts.firstWhere(
        (product) => product.id == 'p1',
      );
      final chai = fakeInventory.storedProducts.firstWhere(
        (product) => product.id == 'p2',
      );
      expect(milk.isActive, isFalse);
      expect(chai.isActive, isFalse);
      // Selection exits back to the normal phone header.
      expect(find.text('0 selected'), findsNothing);
      expect(find.text('Add Product'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('bulk select mode cancels cleanly at ${width.toInt()}dp', (
      tester,
    ) async {
      seedCatalog();
      await pumpAt(tester, width);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(of: find.text('Milk 1L'), matching: find.byType(AppCard)),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Add Product'), findsOneWidget);
      // Milk stays untouched by cancelled selection.
      final milk = fakeInventory.storedProducts.firstWhere(
        (product) => product.id == 'p1',
      );
      expect(milk.isActive, isTrue);
    });

    testWidgets('empty inventory has no overflow at ${width.toInt()}dp', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAt(tester, width);

      expect(tester.takeException(), isNull);
      expect(find.text('No products yet'), findsOneWidget);
      expect(
        find.text('Add your first product to start managing stock.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'long-press on a product card opens the context sheet and deactivate '
      'confirms on ${width.toInt()}dp',
      (tester) async {
        seedCatalog();
        await pumpAt(tester, width);

        final card = find.ancestor(
          of: find.text('Chai Latte'),
          matching: find.byType(AppCard),
        );
        expect(card, findsOneWidget);
        await tester.longPress(card);
        await tester.pumpAndSettle();

        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Adjust Stock'), findsOneWidget);
        expect(find.text('Deactivate'), findsOneWidget);

        await tester.tap(find.text('Deactivate'));
        await tester.pumpAndSettle();

        expect(find.text('Deactivate product'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Chai Latte'),
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Deactivate'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
        await tester.pumpAndSettle();

        final chai = fakeInventory.storedProducts.firstWhere(
          (product) => product.id == 'p2',
        );
        expect(chai.isActive, isFalse);
      },
    );
  }
}
