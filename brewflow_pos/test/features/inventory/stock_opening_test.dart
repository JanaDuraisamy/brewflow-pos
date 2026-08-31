import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_stock_movement_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Opening Operation (Step 5)
///
/// Exercises the opening-stock business operation through the public
/// [ProductMovementsController.recordOpening] boundary (the same path a future
/// product-form integration would use), with the repository overridden by the
/// in-memory fake. Verifies the OPENING movement type, quantity, before/after
/// values, product stock synchronization, at-most-one-opening-per-product
/// protection, and that every rejection leaves stock and history untouched.
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

  group('stock opening operation', () {
    test('0 + 25 records an OPENING movement and updates stock', () async {
      fake.productStock['p1'] = 0;
      final container = buildContainer();
      addTearDown(container.dispose);

      final movement = await container
          .read(productMovementsProvider('p1').notifier)
          .recordOpening(quantity: 25, note: 'Initial stock');

      expect(movement.movementType, StockMovementType.opening);
      expect(movement.quantity, 25);
      expect(movement.stockBefore, 0);
      expect(movement.stockAfter, 25);
      expect(movement.reason, isNull);
      expect(movement.note, 'Initial stock');
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
      expect(recorded.movementType, StockMovementType.opening);
      expect(recorded.stockAfter, 25);
    });

    test(
      'opening history is retrievable through the movement provider',
      () async {
        fake.productStock['p1'] = 0;
        final container = buildContainer();
        addTearDown(container.dispose);

        await container
            .read(productMovementsProvider('p1').notifier)
            .recordOpening(quantity: 10);

        await awaitUntil(
          container,
          () =>
              (container.read(productMovementsProvider('p1')).value ??
                      const <StockMovement>[])
                  .isNotEmpty,
        );
        final recorded = (await history(container)).single;
        expect(recorded.movementType, StockMovementType.opening);
        expect(recorded.quantity, 10);
        expect(recorded.stockBefore, 0);
        expect(recorded.stockAfter, 10);
      },
    );

    test(
      'a duplicate opening is rejected without changing stock or history',
      () async {
        fake.productStock['p1'] = 0;
        final container = buildContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          productMovementsProvider('p1').notifier,
        );

        await notifier.recordOpening(quantity: 25);
        await expectLater(
          notifier.recordOpening(quantity: 5),
          throwsA(isA<DuplicateOpeningFailure>()),
        );

        expect(fake.productStock['p1'], 25);
        expect(
          fake.storedMovements
              .where(
                (m) =>
                    m.productId == 'p1' &&
                    m.movementType == StockMovementType.opening,
              )
              .length,
          1,
        );
      },
    );

    test('a zero opening quantity is rejected without touching stock or '
        'history', () async {
      fake.productStock['p1'] = 0;
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('p1').notifier)
            .recordOpening(quantity: 0),
        throwsA(isA<InvalidOpeningQuantityFailure>()),
      );

      expect(fake.productStock['p1'], 0);
      expect(fake.storedMovements, isEmpty);
    });

    test('a negative opening quantity is rejected without touching stock or '
        'history', () async {
      fake.productStock['p1'] = 0;
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('p1').notifier)
            .recordOpening(quantity: -25),
        throwsA(isA<InvalidOpeningQuantityFailure>()),
      );

      expect(fake.productStock['p1'], 0);
      expect(fake.storedMovements, isEmpty);
    });

    test('a missing product is rejected without creating anything', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(productMovementsProvider('ghost').notifier)
            .recordOpening(quantity: 25),
        throwsA(isA<ProductNotFoundFailure>()),
      );

      expect(fake.productStock.containsKey('ghost'), isFalse);
      expect(fake.storedMovements, isEmpty);
    });

    test(
      'an unexpected error is mapped to UnexpectedStockMovementFailure',
      () async {
        fake.openingError = StateError('boom');
        fake.productStock['p1'] = 0;
        final container = buildContainer();
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(productMovementsProvider('p1').notifier)
              .recordOpening(quantity: 25),
          throwsA(isA<UnexpectedStockMovementFailure>()),
        );

        expect(fake.productStock['p1'], 0);
        expect(fake.storedMovements, isEmpty);
      },
    );

    test(
      'a repository StockMovementFailure passes through unwrapped',
      () async {
        fake.openingError = const UnexpectedStockMovementFailure(
          'Opening failed at the database.',
        );
        fake.productStock['p1'] = 0;
        final container = buildContainer();
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(productMovementsProvider('p1').notifier)
              .recordOpening(quantity: 25),
          throwsA(
            isA<UnexpectedStockMovementFailure>().having(
              (e) => e.message,
              'message',
              'Opening failed at the database.',
            ),
          ),
        );

        expect(fake.productStock['p1'], 0);
        expect(fake.storedMovements, isEmpty);
      },
    );

    test('adjustment still works after an opening (regression)', () async {
      fake.productStock['p1'] = 0;
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(productMovementsProvider('p1').notifier);

      final opening = await notifier.recordOpening(quantity: 25);
      final adjustment = await notifier.adjustStock(
        delta: -5,
        reason: StockAdjustmentReason.damage,
      );

      expect(opening.movementType, StockMovementType.opening);
      expect(adjustment.movementType, StockMovementType.adjustmentOut);
      expect(adjustment.stockBefore, 25);
      expect(adjustment.stockAfter, 20);
      expect(fake.productStock['p1'], 20);
      expect(fake.storedMovements, hasLength(2));
    });
  });
}
