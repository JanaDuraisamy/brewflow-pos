import 'dart:async';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_stock_movement_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// Mirrors the single-database reality for widget tests: a successful
/// [adjustStock] also updates the product list the UI renders, and an
/// optional [gate] pauses the write so the loading state can be observed.
final class LinkedStockMovementFake implements StockMovementRepository {
  LinkedStockMovementFake(this.inventory);

  final FakeInventoryRepository inventory;
  final FakeStockMovementRepository inner = FakeStockMovementRepository();
  Completer<void>? gate;
  int adjustCalls = 0;

  Map<String, int> get productStock => inner.productStock;
  List<StockMovement> get storedMovements => inner.storedMovements;
  Object? get adjustError => inner.adjustError;
  set adjustError(Object? value) => inner.adjustError = value;

  @override
  Future<List<StockMovement>> movementsFor(
    String productId, {
    String? variantId,
  }) => inner.movementsFor(productId, variantId: variantId);

  @override
  Future<StockMovement> adjustStock({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    adjustCalls++;
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    final movement = await inner.adjustStock(
      productId: productId,
      variantId: variantId,
      delta: delta,
      reason: reason,
      note: note,
    );
    if (variantId != null) {
      return movement;
    }
    final stored = inventory.storedProducts;
    for (var i = 0; i < stored.length; i++) {
      if (stored[i].id == productId) {
        stored[i] = stored[i].copyWith(stockQuantity: movement.stockAfter);
        break;
      }
    }
    return movement;
  }

  @override
  Future<StockMovement> recordOpening({
    required String productId,
    required int quantity,
    String? note,
  }) =>
      inner.recordOpening(productId: productId, quantity: quantity, note: note);
}

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;
  late LinkedStockMovementFake fakeMovements;

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
    int stockQuantity = 0,
  }) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    sku: null,
    sellingPricePaise: 14950,
    costPricePaise: null,
    stockQuantity: stockQuantity,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
    fakeMovements = LinkedStockMovementFake(fakeInventory);
  });

  Widget app({StockMovementRepository? movements}) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      inventoryRepositoryProvider.overrideWithValue(fakeInventory),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      stockMovementRepositoryProvider.overrideWithValue(
        movements ?? fakeMovements,
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

  void seedProduct({int stockQuantity = 5}) {
    fakeInventory.storedCategories.add(category('c1', 'Beverages'));
    fakeInventory.storedProducts.add(
      product('p1', 'Milk 1L', stockQuantity: stockQuantity),
    );
    fakeMovements.productStock['p1'] = stockQuantity;
  }

  Future<void> openDialog(WidgetTester tester) async {
    final button = find.byTooltip('Adjust stock');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(StockAdjustmentDialog), findsOneWidget);
  }

  Future<void> enterQuantity(WidgetTester tester, String text) async {
    await tester.enterText(
      find
          .descendant(
            of: find.byType(StockAdjustmentDialog),
            matching: find.byType(TextFormField),
          )
          .at(0),
      text,
    );
    await tester.pump();
  }

  Future<void> enterNote(WidgetTester tester, String text) async {
    await tester.enterText(
      find
          .descendant(
            of: find.byType(StockAdjustmentDialog),
            matching: find.byType(TextFormField),
          )
          .at(1),
      text,
    );
    await tester.pump();
  }

  Future<void> selectDirection(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> selectReason(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(StockAdjustmentDialog),
        matching: find.byType(DropdownButtonFormField<StockAdjustmentReason>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Adjust'));
    await pumpAsync(tester);
  }

  String quantityText(WidgetTester tester) => tester
      .widget<EditableText>(
        find
            .descendant(
              of: find.byType(StockAdjustmentDialog),
              matching: find.byType(EditableText),
            )
            .at(0),
      )
      .controller
      .text;

  Future<void> dismissSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('adjust stock dialog', () {
    testWidgets('opens from a product card and shows the current stock', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);

      expect(find.byTooltip('Adjust stock'), findsOneWidget);
      await openDialog(tester);

      expect(
        find.descendant(
          of: find.byType(StockAdjustmentDialog),
          matching: find.text('Milk 1L'),
        ),
        findsOneWidget,
      );
      expect(find.text('Current stock: 5'), findsOneWidget);
      expect(find.text('Stock In'), findsOneWidget);
      expect(find.text('Stock Out'), findsOneWidget);
    });

    testWidgets('adds stock with an IN adjustment and refreshes the list', (
      tester,
    ) async {
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, '5');
      await selectReason(tester, 'Purchase');
      await submit(tester);

      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(find.text('Stock adjusted.'), findsOneWidget);
      expect(fakeMovements.productStock['p1'], 10);

      final movement = fakeMovements.storedMovements.single;
      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(movement.quantity, 5);
      expect(movement.stockBefore, 5);
      expect(movement.stockAfter, 10);
      expect(movement.reason, StockAdjustmentReason.purchase);

      expect(find.text('10'), findsOneWidget);

      await dismissSnackBar(tester);
    });

    testWidgets('removes stock with an OUT adjustment and records the reason', (
      tester,
    ) async {
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await selectDirection(tester, 'Stock Out');
      await enterQuantity(tester, '5');
      await selectReason(tester, 'Damage');
      await submit(tester);

      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(find.text('Stock adjusted.'), findsOneWidget);
      expect(fakeMovements.productStock['p1'], 0);

      final movement = fakeMovements.storedMovements.single;
      expect(movement.movementType, StockMovementType.adjustmentOut);
      expect(movement.quantity, -5);
      expect(movement.stockBefore, 5);
      expect(movement.stockAfter, 0);
      expect(movement.reason, StockAdjustmentReason.damage);

      expect(find.text('0'), findsOneWidget);

      await dismissSnackBar(tester);
    });

    testWidgets(
      'rejects empty and zero quantities without recording anything',
      (tester) async {
        seedProduct(stockQuantity: 5);
        await pumpAuthenticated(tester);
        await openInventory(tester);
        await openDialog(tester);

        await submit(tester);
        expect(
          find.text('Enter a quantity greater than zero.'),
          findsOneWidget,
        );
        expect(find.byType(StockAdjustmentDialog), findsOneWidget);

        await enterQuantity(tester, '0');
        await submit(tester);
        expect(
          find.text('Enter a quantity greater than zero.'),
          findsOneWidget,
        );
        expect(find.byType(StockAdjustmentDialog), findsOneWidget);

        expect(fakeMovements.storedMovements, isEmpty);
        expect(fakeMovements.productStock['p1'], 5);
      },
    );

    testWidgets('filters non-numeric input to digits only', (tester) async {
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, 'abc');
      expect(quantityText(tester), isEmpty);

      await enterQuantity(tester, '-5');
      expect(quantityText(tester), '5');

      await enterQuantity(tester, '1.5');
      expect(quantityText(tester), '15');
    });

    testWidgets('blocks an insufficient OUT adjustment with the safe message', (
      tester,
    ) async {
      seedProduct(stockQuantity: 3);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await selectDirection(tester, 'Stock Out');
      await enterQuantity(tester, '5');

      expect(find.text('New stock: -2'), findsOneWidget);
      expect(find.text('Not enough stock for this reduction.'), findsOneWidget);
      final adjust = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Adjust'),
      );
      expect(adjust.onPressed, isNull);

      expect(fakeMovements.storedMovements, isEmpty);
      expect(fakeMovements.productStock['p1'], 3);
    });

    testWidgets('surfaces a repository rejection with the safe message', (
      tester,
    ) async {
      seedProduct(stockQuantity: 5);
      fakeMovements.adjustError = const AdjustmentInsufficientStockFailure();
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await selectDirection(tester, 'Stock Out');
      await enterQuantity(tester, '2');
      await selectReason(tester, 'Correction');
      await submit(tester);

      expect(find.text('Not enough stock for this reduction.'), findsOneWidget);
      expect(find.byType(StockAdjustmentDialog), findsOneWidget);
      expect(fakeMovements.storedMovements, isEmpty);
      expect(fakeMovements.productStock['p1'], 5);
    });

    testWidgets('requires a reason before adjusting', (tester) async {
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, '5');
      await submit(tester);

      expect(find.text('Select a reason.'), findsOneWidget);
      expect(find.byType(StockAdjustmentDialog), findsOneWidget);
      expect(fakeMovements.storedMovements, isEmpty);
    });

    testWidgets('records the optional note', (tester) async {
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, '5');
      await selectReason(tester, 'Purchase');
      await enterNote(tester, 'Broken crate');
      await submit(tester);

      expect(find.text('Stock adjusted.'), findsOneWidget);
      expect(fakeMovements.storedMovements.single.note, 'Broken crate');

      await dismissSnackBar(tester);
    });

    testWidgets('keeps the dialog open on unexpected failures', (tester) async {
      seedProduct(stockQuantity: 5);
      fakeMovements.adjustError = const UnexpectedStockMovementFailure();
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, '5');
      await selectReason(tester, 'Purchase');
      await submit(tester);

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(StockAdjustmentDialog), findsOneWidget);
      expect(fakeMovements.storedMovements, isEmpty);
      expect(fakeMovements.productStock['p1'], 5);
    });

    testWidgets('cancel leaves stock and history untouched', (tester) async {
      seedProduct(stockQuantity: 5);
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, '5');
      await selectReason(tester, 'Purchase');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(fakeMovements.storedMovements, isEmpty);
      expect(fakeMovements.productStock['p1'], 5);
    });

    testWidgets('prevents double submission while saving', (tester) async {
      seedProduct(stockQuantity: 5);
      fakeMovements.gate = Completer<void>();
      await pumpAuthenticated(tester);
      await openInventory(tester);
      await openDialog(tester);

      await enterQuantity(tester, '5');
      await selectReason(tester, 'Purchase');
      await tester.tap(find.widgetWithText(FilledButton, 'Adjust'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(StockAdjustmentDialog),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final cancel = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancel.onPressed, isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(StockAdjustmentDialog),
          matching: find.byType(FilledButton),
        ),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(fakeMovements.adjustCalls, 1);

      fakeMovements.gate!.complete();
      await pumpAsync(tester);

      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(fakeMovements.storedMovements, hasLength(1));
      expect(fakeMovements.productStock['p1'], 10);
      expect(find.text('Stock adjusted.'), findsOneWidget);

      await dismissSnackBar(tester);
    });

    testWidgets('writes the adjustment to the real database through the UI', (
      tester,
    ) async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(() => database.close());
      final inventoryRepo = DriftInventoryRepository(database);
      final movementsRepo = DriftStockMovementRepository(database);

      final createdCategory = await inventoryRepo.createCategory('Beverages');
      final created = await inventoryRepo.createProduct(
        categoryId: createdCategory.id,
        name: 'Milk 1L',
        sellingPricePaise: 14950,
        stockQuantity: 5,
        isActive: true,
      );
      fakeInventory.storedCategories.add(
        category(createdCategory.id, 'Beverages'),
      );
      fakeInventory.storedProducts.add(
        product(
          created.id,
          'Milk 1L',
          categoryId: createdCategory.id,
          stockQuantity: 5,
        ),
      );

      await tester.pumpWidget(app(movements: movementsRepo));
      fakeAuth.emit(_owner);
      await tester.pumpAndSettle();
      await openInventory(tester);
      await openDialog(tester);

      await selectDirection(tester, 'Stock Out');
      await enterQuantity(tester, '2');
      await selectReason(tester, 'Damage');
      await submit(tester);

      expect(find.byType(StockAdjustmentDialog), findsNothing);
      expect(find.text('Stock adjusted.'), findsOneWidget);

      final movements = await movementsRepo.movementsFor(created.id);
      expect(movements, hasLength(2));
      expect(movements.first.movementType, StockMovementType.adjustmentOut);
      expect(movements.first.quantity, -2);
      expect(movements.first.stockBefore, 5);
      expect(movements.first.stockAfter, 3);
      expect(movements.first.reason, StockAdjustmentReason.damage);
      expect(movements.last.movementType, StockMovementType.opening);

      final rows = await database.select(database.products).get();
      expect(rows.single.stockQuantity, 3);

      await dismissSnackBar(tester);
    });
  });
}
