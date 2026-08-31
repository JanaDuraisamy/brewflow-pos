import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_stock_movement_repository.dart';

void main() {
  late FakeStockMovementRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [stockMovementRepositoryProvider.overrideWithValue(fake)],
  );

  final now = DateTime.now().toUtc();

  StockMovement movement(
    String id,
    String productId, {
    StockMovementType movementType = StockMovementType.adjustmentIn,
    int quantity = 5,
    int stockBefore = 0,
    int stockAfter = 5,
    StockAdjustmentReason? reason,
    String? note,
    DateTime? createdAt,
  }) => StockMovement(
    id: id,
    productId: productId,
    movementType: movementType,
    quantity: quantity,
    stockBefore: stockBefore,
    stockAfter: stockAfter,
    reason: reason,
    note: note,
    referenceType: null,
    referenceId: null,
    createdAt: createdAt ?? now,
    updatedAt: createdAt ?? now,
  );

  setUp(() => fake = FakeStockMovementRepository());

  /// Waits (in real async) for invalidation-triggered rebuilds to settle,
  /// since reading `.future` right after a mutation can race the rebuild.
  Future<void> awaitUntil(
    ProviderContainer container,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not met within the timeout');
  }

  group('productMovementsProvider', () {
    test('starts loading and resolves to the stored movements', () async {
      fake.storedMovements.addAll([
        movement(
          'm1',
          'p1',
          createdAt: DateTime.utc(2025, 1, 1),
          movementType: StockMovementType.adjustmentOut,
          quantity: -2,
        ),
        movement('m2', 'p1', createdAt: DateTime.utc(2025, 2, 1)),
        movement('m3', 'p2'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(
        container.read(productMovementsProvider('p1')),
        isA<AsyncLoading>(),
      );
      await container.read(productMovementsProvider('p1').future);

      final movements = container.read(productMovementsProvider('p1')).value!;
      // Newest first (repository ordering), only for this product.
      expect(movements.map((m) => m.id), ['m2', 'm1']);
    });

    test('resolves to empty when there are no movements', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(productMovementsProvider('p1').future);
      expect(container.read(productMovementsProvider('p1')).value, isEmpty);
    });

    test('surfaces StockMovementFailure without wrapping it', () async {
      fake.loadError = const ProductNotFoundFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(productMovementsProvider('p1'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(productMovementsProvider('p1'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ProductNotFoundFailure>());
    });

    test('maps unexpected errors to UnexpectedStockMovementFailure', () async {
      fake.loadError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(productMovementsProvider('p1'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(productMovementsProvider('p1'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedStockMovementFailure>());
    });
  });

  group('adjustStock', () {
    test('delegates to the repository and refreshes the history', () async {
      fake.productStock['p1'] = 10;
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productMovementsProvider('p1').future);
      expect(container.read(productMovementsProvider('p1')).value, isEmpty);

      final movement = await container
          .read(productMovementsProvider('p1').notifier)
          .adjustStock(
            delta: 5,
            reason: StockAdjustmentReason.purchase,
            note: 'Supplier delivery',
          );

      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(movement.stockBefore, 10);
      expect(movement.stockAfter, 15);
      expect(fake.productStock['p1'], 15);

      await awaitUntil(
        container,
        () =>
            (container.read(productMovementsProvider('p1')).value ??
                    const <StockMovement>[])
                .isNotEmpty,
      );
      final refreshed = container.read(productMovementsProvider('p1')).value!;
      expect(refreshed.single.id, movement.id);
      expect(refreshed.single.note, 'Supplier delivery');
    });

    test('surfaces the zero-delta rejection', () async {
      fake.productStock['p1'] = 10;
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('p1').notifier)
            .adjustStock(delta: 0, reason: StockAdjustmentReason.correction),
        throwsA(isA<InvalidAdjustmentQuantityFailure>()),
      );
    });

    test('surfaces the insufficient-stock rejection', () async {
      fake.productStock['p1'] = 4;
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('p1').notifier)
            .adjustStock(delta: -5, reason: StockAdjustmentReason.damage),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );
      expect(fake.productStock['p1'], 4);
    });

    test('surfaces the missing-product rejection', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('ghost').notifier)
            .adjustStock(delta: 5, reason: StockAdjustmentReason.purchase),
        throwsA(isA<ProductNotFoundFailure>()),
      );
    });

    test('maps unexpected errors to UnexpectedStockMovementFailure', () async {
      fake.adjustError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('p1').notifier)
            .adjustStock(delta: 5, reason: StockAdjustmentReason.purchase),
        throwsA(isA<UnexpectedStockMovementFailure>()),
      );
    });
  });

  group('stockMovementErrorMessage', () {
    test('returns safe messages for known failures', () {
      expect(
        stockMovementErrorMessage(const ProductNotFoundFailure()),
        'Product not found.',
      );
      expect(
        stockMovementErrorMessage(const InvalidAdjustmentQuantityFailure()),
        'Enter a quantity greater than zero.',
      );
      expect(
        stockMovementErrorMessage(const AdjustmentInsufficientStockFailure()),
        'Not enough stock for this reduction.',
      );
      expect(
        stockMovementErrorMessage(const UnexpectedStockMovementFailure()),
        'Something went wrong. Please try again.',
      );
    });

    test('falls back to a generic message for anything else', () {
      expect(
        stockMovementErrorMessage(StateError('boom')),
        'Something went wrong. Please try again.',
      );
      expect(
        stockMovementErrorMessage(StateError('boom'), fallback: 'Try again.'),
        'Try again.',
      );
    });
  });
}
