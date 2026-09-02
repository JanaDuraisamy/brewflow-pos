import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/category_management_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_form_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;

  final now = DateTime.now().toUtc();

  Category category(String id, String name, {bool isActive = true}) => Category(
    id: id,
    name: name,
    isActive: isActive,
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

  /// Pumps a few frames and settles. Provider rebuilds scheduled after an
  /// invalidation need more than a single settle to become visible.
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

  Finder inSegmented(String label) => find.descendant(
    of: find.byType(SegmentedButton<ProductStatusFilter>),
    matching: find.text(label),
  );

  Finder inForm(String text) => find.descendant(
    of: find.byType(ProductFormPage),
    matching: find.text(text),
  );

  /// The product form is a lazy ListView, so its action buttons only exist in
  /// the tree once scrolled into view.
  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final list = find.descendant(
      of: find.byType(ProductFormPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(finder, 120, scrollable: list.first);
    await tester.pump();
  }

  group('inventory landing page', () {
    testWidgets('shows the empty state when there are no products', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(find.byType(InventoryPage), findsOneWidget);
      expect(find.text('No products yet'), findsOneWidget);
      expect(
        find.text('Add your first product to start managing stock.'),
        findsOneWidget,
      );
    });

    testWidgets('lists products with paise-formatted prices', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.addAll([
        product('p1', 'Milk 1L', sku: 'MILK-1L', sellingPricePaise: 14950),
        product(
          'p2',
          'Chai Latte',
          sellingPricePaise: 8950,
          costPricePaise: 6000,
          stockQuantity: 2,
        ),
      ]);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(find.text('Milk 1L'), findsOneWidget);
      expect(find.text('Chai Latte'), findsOneWidget);
      expect(find.textContaining('₹149.50'), findsOneWidget);
      expect(find.textContaining('₹89.50'), findsOneWidget);
      // One segment label plus one badge per product.
      expect(find.text('Active'), findsNWidgets(3));
      expect(find.text('Inactive'), findsNWidgets(1));
    });

    testWidgets('search narrows the list by name and SKU', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.addAll([
        product('p1', 'Milk 1L', sku: 'MILK-1L'),
        product('p2', 'Chai Latte', sku: 'CHAI-01'),
      ]);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      await tester.enterText(find.byType(TextField), 'chai');
      await pumpAsync(tester);

      expect(find.text('Chai Latte'), findsOneWidget);
      expect(find.text('Milk 1L'), findsNothing);
    });

    testWidgets('status filter narrows the list', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.addAll([
        product('p1', 'Milk 1L', isActive: true),
        product('p2', 'Old Tea', isActive: false),
      ]);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      await tester.tap(inSegmented('Inactive'));
      await pumpAsync(tester);

      expect(find.text('Old Tea'), findsOneWidget);
      expect(find.text('Milk 1L'), findsNothing);
    });

    testWidgets('category filter narrows the list', (tester) async {
      fakeInventory.storedCategories.addAll([
        category('c1', 'Beverages'),
        category('c2', 'Snacks'),
      ]);
      fakeInventory.storedProducts.addAll([
        product('p1', 'Milk 1L', categoryId: 'c1'),
        product('p2', 'Chips', categoryId: 'c2'),
      ]);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snacks').last);
      await pumpAsync(tester);

      expect(find.text('Chips'), findsOneWidget);
      expect(find.text('Milk 1L'), findsNothing);
    });

    testWidgets('clearing a dead-end filter restores the full list', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(product('p1', 'Milk 1L'));
      await pumpAuthenticated(tester);
      await openInventory(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await pumpAsync(tester);

      expect(find.text('No products match your filters'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await pumpAsync(tester);

      expect(find.text('Milk 1L'), findsOneWidget);
      expect(find.text('No products match your filters'), findsNothing);
    });

    testWidgets('load failures show an error state that can retry', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.loadError = const UnexpectedInventoryFailure();
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(find.text('Could not load products'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );

      fakeInventory.loadError = null;
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);

      expect(find.text('No products yet'), findsOneWidget);
    });
  });

  group('product form', () {
    Future<void> openNewProductForm(WidgetTester tester) async {
      await openInventory(tester);
      await tester.tap(find.text('Add Product').first);
      await pumpAsync(tester);
      expect(find.byType(ProductFormPage), findsOneWidget);
    }

    Future<void> selectCategory(WidgetTester tester) async {
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beverages').last);
      await tester.pumpAndSettle();
    }

    testWidgets('add product button opens the form and cancel returns', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);
      await openNewProductForm(tester);

      expect(find.text('New Product'), findsOneWidget);

      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await scrollFormTo(tester, cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(ProductFormPage), findsNothing);
      expect(find.byType(InventoryPage), findsOneWidget);
    });

    testWidgets('saves a new product and returns to a refreshed list', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);
      await openNewProductForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Green Tea');
      await tester.enterText(find.byType(TextFormField).at(1), 'TEA-01');
      await tester.enterText(find.byType(TextFormField).at(2), '180');
      await tester.enterText(find.byType(TextFormField).at(3), '120');
      await tester.enterText(find.byType(TextFormField).at(4), '5');
      await selectCategory(tester);

      final save = find.widgetWithText(FilledButton, 'Save Product');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(ProductFormPage), findsNothing);
      expect(find.text('Green Tea'), findsOneWidget);
      expect(find.textContaining('₹180.00'), findsOneWidget);
      expect(find.text('Product added.'), findsOneWidget);

      final saved = fakeInventory.storedProducts.single;
      expect(saved.sku, 'TEA-01');
      expect(saved.sellingPricePaise, 18000);
      expect(saved.costPricePaise, 12000);
      expect(saved.stockQuantity, 5);
      expect(saved.isActive, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('validates required fields before saving', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);
      await openNewProductForm(tester);

      final save = find.widgetWithText(FilledButton, 'Save Product');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await tester.pump();

      expect(find.text('Product name is required.'), findsOneWidget);
      expect(find.text('Select a category.'), findsOneWidget);
      expect(find.text('Enter a valid price (e.g. 149.50)'), findsOneWidget);
      expect(find.byType(ProductFormPage), findsOneWidget);
      expect(fakeInventory.storedProducts, isEmpty);
    });

    testWidgets('rejects a duplicate SKU inline without leaving the form', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(
        product('p1', 'Green Tea', sku: 'TEA-01'),
      );
      await pumpAuthenticated(tester);
      await openNewProductForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Black Tea');
      await tester.enterText(find.byType(TextFormField).at(1), 'tea-01');
      await tester.enterText(find.byType(TextFormField).at(2), '100');
      await tester.enterText(find.byType(TextFormField).at(4), '1');
      await selectCategory(tester);

      final save = find.widgetWithText(FilledButton, 'Save Product');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(
        find.text('A product with this SKU already exists.'),
        findsOneWidget,
      );
      expect(find.byType(ProductFormPage), findsOneWidget);
      expect(fakeInventory.storedProducts, hasLength(1));
    });

    testWidgets('edit flow pre-fills values and saves changes', (tester) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Milk 1L',
          sku: 'MILK-1L',
          sellingPricePaise: 14950,
          costPricePaise: 12000,
          stockQuantity: 4,
        ),
      );
      await pumpAuthenticated(tester);
      await openInventory(tester);

      await tester.tap(find.text('Milk 1L'));
      await pumpAsync(tester);

      expect(find.byType(ProductFormPage), findsOneWidget);
      expect(find.text('Edit Product'), findsOneWidget);
      expect(inForm('Milk 1L'), findsOneWidget);
      expect(inForm('149.50'), findsOneWidget);
      expect(inForm('120.00'), findsOneWidget);
      expect(inForm('4'), findsOneWidget);

      // Stock is read-only when editing: it can only change through stock
      // operations, never silently through the form.
      final stockField = tester.widget<TextFormField>(
        find.byType(TextFormField).at(4),
      );
      expect(stockField.enabled, isFalse);
      expect(
        find.text(
          'Managed through stock operations — use a stock adjustment to '
          'correct levels.',
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).at(2), '199');
      final save = find.widgetWithText(FilledButton, 'Save Changes');
      await scrollFormTo(tester, save);
      await tester.tap(save);
      await pumpAsync(tester);

      expect(find.byType(ProductFormPage), findsNothing);
      expect(find.textContaining('₹199.00'), findsOneWidget);
      expect(find.text('Product updated.'), findsOneWidget);
      expect(fakeInventory.storedProducts.single.sellingPricePaise, 19900);
      expect(fakeInventory.storedProducts.single.stockQuantity, 4);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('prompts for a category when none exist', (tester) async {
      await pumpAuthenticated(tester);
      await openInventory(tester);

      await tester.tap(find.text('Add Product').first);
      await pumpAsync(tester);

      expect(find.byType(ProductFormPage), findsOneWidget);
      expect(find.text('No categories yet'), findsOneWidget);
      expect(
        find.text('Add a category before creating products.'),
        findsOneWidget,
      );
    });
  });

  group('category management', () {
    Future<void> openCategories(WidgetTester tester) async {
      await openInventory(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Categories'));
      await pumpAsync(tester);
      expect(find.byType(CategoryManagementPage), findsOneWidget);
    }

    Future<void> tapAddCategory(WidgetTester tester) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
    }

    testWidgets('creates a category through the dialog', (tester) async {
      await pumpAuthenticated(tester);
      await openCategories(tester);

      expect(find.text('No categories yet'), findsOneWidget);

      await tapAddCategory(tester);
      await tester.enterText(find.byType(TextField), 'Beverages');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpAsync(tester);

      expect(find.text('Beverages'), findsOneWidget);
      expect(fakeInventory.storedCategories, hasLength(1));
      expect(fakeInventory.storedCategories.single.name, 'Beverages');
    });

    testWidgets('empty category names show the inline error', (tester) async {
      await pumpAuthenticated(tester);
      await openCategories(tester);

      await tapAddCategory(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(find.text('Category name is required.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('duplicate category names show the safe message', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);
      await openCategories(tester);

      await tapAddCategory(tester);
      await tester.enterText(find.byType(TextField), 'beverages');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await pumpAsync(tester);

      expect(
        find.text('A category with this name already exists.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('toggling the active switch updates the category', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      await pumpAuthenticated(tester);
      await openCategories(tester);

      await tester.tap(find.byType(Switch));
      await pumpAsync(tester);

      expect(fakeInventory.storedCategories.single.isActive, isFalse);
    });

    testWidgets('deleting an in-use category is rejected with a message', (
      tester,
    ) async {
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(
        product('p1', 'Milk 1L', categoryId: 'c1'),
      );
      await pumpAuthenticated(tester);
      await openCategories(tester);

      await tester.tap(find.byTooltip('Delete category'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpAsync(tester);

      expect(
        find.text('This category is used by products and cannot be deleted.'),
        findsOneWidget,
      );
      expect(fakeInventory.storedCategories, hasLength(1));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('responsive layout', () {
    testWidgets('renders cards on mobile and a data table when wide', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(product('p1', 'Milk 1L'));

      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Milk 1L'), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Milk 1L'), findsOneWidget);
    });

    testWidgets(
      'tablet table scrolls vertically to reach rows below the fold',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.resetPhysicalSize);
        fakeInventory.storedCategories.add(category('c1', 'Beverages'));
        // Enough rows that the table is far taller than the 900dp viewport.
        fakeInventory.storedProducts.addAll([
          for (var i = 0; i < 40; i++)
            product('p$i', 'Product ${i.toString().padLeft(2, '0')}'),
        ]);
        await pumpAuthenticated(tester);
        await openInventory(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(DataTable), findsOneWidget);

        // The first row is visible; the last row starts below the fold.
        expect(find.text('Product 00').hitTestable(), findsOneWidget);
        expect(find.text('Product 39').hitTestable(), findsNothing);

        final verticalScrollable = find
            .ancestor(
              of: find.byType(DataTable),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first;
        expect(verticalScrollable, findsOneWidget);

        for (
          var i = 0;
          i < 30 && find.text('Product 39').hitTestable().evaluate().isEmpty;
          i++
        ) {
          await tester.drag(verticalScrollable, const Offset(0, -400));
          await tester.pump();
        }

        expect(find.text('Product 39').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tablet table still scrolls horizontally', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      // A moderately narrow tablet where the seven-column table overflows.
      tester.view.physicalSize = const Size(820, 900);
      addTearDown(tester.view.resetPhysicalSize);
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.add(
        product(
          'p1',
          'Very Long Product Name That Forces Wide Columns',
          sku: 'EXTREMELY-LONG-SKU-IDENTIFIER-999999999',
        ),
      );
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);

      final horizontalScrollable = find
          .ancestor(
            of: find.byType(DataTable),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.right,
            ),
          )
          .first;
      expect(horizontalScrollable, findsOneWidget);

      // Dragging a wide table leftward must not throw and must move the
      // horizontal scroll position.
      await tester.drag(horizontalScrollable, const Offset(-400, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone inventory still shows cards and scrolls the list', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 900);
      addTearDown(tester.view.resetPhysicalSize);
      fakeInventory.storedCategories.add(category('c1', 'Beverages'));
      fakeInventory.storedProducts.addAll([
        for (var i = 0; i < 25; i++)
          product('p$i', 'Phone Product ${i.toString().padLeft(2, '0')}'),
      ]);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);

      // The phone layout is a single vertically scrolling card list, so the
      // last card is reachable by scrolling the list.
      final listScrollable = find
          .descendant(
            of: find.byType(InventoryPage),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      expect(listScrollable, findsOneWidget);
      for (
        var i = 0;
        i < 30 &&
            find.text('Phone Product 24').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(listScrollable, const Offset(0, -400));
        await tester.pump();
      }
      expect(find.text('Phone Product 24').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
