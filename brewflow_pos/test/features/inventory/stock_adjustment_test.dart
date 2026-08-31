import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_stock_movement_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Adjustment Operation (Step 4)
///
/// Exercises the manual stock-adjustment business operation through the
/// public [ProductMovementsController.adjustStock] boundary (the same path a
/// future adjustment UI would use), with the repository overridden by the
/// in-memory fake. Verifies movement direction/type, quantity sign,
/// before/after values, product stock synchronization, and that every
/// rejection leaves stock and history untouched.
/// ---------------------------------------------------------------------------

void main() {
  late FakeStockMovementRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [stockMovementRepositoryProvider.overrideWithValue(fake)],
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

  Future<List<StockMovement>> history(ProviderContainer container) async {
    await container.read(productMovementsProvider('p1').future);
    return container.read(productMovementsProvider('p1')).value ??
        const <StockMovement>[];
  }

  group('stock adjustment operation', () {
    test('20 + 5 = 25 records an ADJUSTMENT_IN and updates stock', () async {
      fake.productStock['p1'] = 20;
      final container = buildContainer();
      addTearDown(container.dispose);

      final movement = await container
          .read(productMovementsProvider('p1').notifier)
          .adjustStock(
            delta: 5,
            reason: StockAdjustmentReason.purchase,
            note: 'Supplier delivery',
          );

      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(movement.quantity, 5);
      expect(movement.stockBefore, 20);
      expect(movement.stockAfter, 25);
      expect(movement.reason, StockAdjustmentReason.purchase);
      expect(fake.productStock['p1'], 25);

      await awaitUntil(
        container,
        () =>
            (container.read(productMovementsProvider('p1')).value ??
                    const <StockMovement>[])
                .isNotEmpty,
      );
      final recorded = (await history(container)).single;
      expect(recorded.id, movement.id);
      expect(recorded.stockAfter, 25);
    });

    test('20 - 5 = 15 records an ADJUSTMENT_OUT and updates stock', () async {
      fake.productStock['p1'] = 20;
      final container = buildContainer();
      addTearDown(container.dispose);

      final movement = await container
          .read(productMovementsProvider('p1').notifier)
          .adjustStock(delta: -5, reason: StockAdjustmentReason.damage);

      expect(movement.movementType, StockMovementType.adjustmentOut);
      expect(movement.quantity, -5);
      expect(movement.stockBefore, 20);
      expect(movement.stockAfter, 15);
      expect(movement.reason, StockAdjustmentReason.damage);
      expect(fake.productStock['p1'], 15);

      await awaitUntil(
        container,
        () =>
            (container.read(productMovementsProvider('p1')).value ??
                    const <StockMovement>[])
                .isNotEmpty,
      );
      final recorded = (await history(container)).single;
      expect(recorded.id, movement.id);
      expect(recorded.stockAfter, 15);
    });

    test(
      'a zero adjustment is rejected without changing stock or history',
      () async {
        fake.productStock['p1'] = 20;
        final container = buildContainer();
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(productMovementsProvider('p1').notifier)
              .adjustStock(delta: 0, reason: StockAdjustmentReason.correction),
          throwsA(isA<InvalidAdjustmentQuantityFailure>()),
        );

        expect(fake.productStock['p1'], 20);
        expect(fake.storedMovements, isEmpty);
      },
    );

    test('an adjustment below zero is rejected without touching stock or '
        'history', () async {
      fake.productStock['p1'] = 3;
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('p1').notifier)
            .adjustStock(delta: -5, reason: StockAdjustmentReason.damage),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );

      expect(fake.productStock['p1'], 3);
      expect(fake.storedMovements, isEmpty);
    });

    test('a missing product is rejected without creating anything', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('ghost').notifier)
            .adjustStock(delta: 5, reason: StockAdjustmentReason.purchase),
        throwsA(isA<ProductNotFoundFailure>()),
      );

      expect(fake.productStock.containsKey('ghost'), isFalse);
      expect(fake.storedMovements, isEmpty);
    });

    test(
      'a repository StockMovementFailure passes through unwrapped',
      () async {
        fake.adjustError = const UnexpectedStockMovementFailure(
          'Stock update failed at the database.',
        );
        fake.productStock['p1'] = 20;
        final container = buildContainer();
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(productMovementsProvider('p1').notifier)
              .adjustStock(delta: 5, reason: StockAdjustmentReason.purchase),
          throwsA(
            isA<UnexpectedStockMovementFailure>().having(
              (e) => e.message,
              'message',
              'Stock update failed at the database.',
            ),
          ),
        );

        expect(fake.productStock['p1'], 20);
        expect(fake.storedMovements, isEmpty);
      },
    );

    test(
      'an unexpected error is mapped to UnexpectedStockMovementFailure',
      () async {
        fake.adjustError = StateError('boom');
        fake.productStock['p1'] = 20;
        final container = buildContainer();
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(productMovementsProvider('p1').notifier)
              .adjustStock(delta: 5, reason: StockAdjustmentReason.purchase),
          throwsA(isA<UnexpectedStockMovementFailure>()),
        );

        expect(fake.productStock['p1'], 20);
        expect(fake.storedMovements, isEmpty);
      },
    );
  });
}
