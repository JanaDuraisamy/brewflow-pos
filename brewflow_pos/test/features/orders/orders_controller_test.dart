import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_orders_repository.dart';

void main() {
  late FakeOrdersRepository repository;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [ordersRepositoryProvider.overrideWithValue(repository)],
  );

  OrderSummary summary(
    String receipt, {
    int itemCount = 1,
    DateTime? createdAt,
  }) => OrderSummary(
    id: 'id-$receipt',
    receiptNumber: receipt,
    itemCount: itemCount,
    totalPaise: 12000 * itemCount,
    paymentStatus: PaymentStatus.paid,
    paymentMethod: PaymentMethod.cash,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  );

  void seedFiftyFive() {
    for (var i = 1; i <= 55; i++) {
      repository.storedSummaries.add(
        summary('BF-${i.toString().padLeft(6, '0')}'),
      );
    }
  }

  setUp(() {
    repository = FakeOrdersRepository();
  });

  /// Waits (in real async) for rebuilds to settle, since reading `.future`
  /// right after a mutation can race the rebuild in Riverpod 3.
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

  group('ordersFilterProvider', () {
    test('starts with an inactive default filter', () {
      final container = buildContainer();
      addTearDown(container.dispose);

      final filter = container.read(ordersFilterProvider);
      expect(filter.query, '');
      expect(filter.paymentMethod, isNull);
      expect(filter.datePreset, OrdersDatePreset.all);
      expect(filter.fromUtc, isNull);
      expect(filter.toUtc, isNull);
      expect(filter.isActive, isFalse);
    });

    test('query and payment method updates stay independent', () {
      final container = buildContainer();
      addTearDown(container.dispose);

      final notifier = container.read(ordersFilterProvider.notifier);
      notifier.setQuery('coffee');
      notifier.setPaymentMethod(PaymentMethod.upi);
      final filter = container.read(ordersFilterProvider);
      expect(filter.query, 'coffee');
      expect(filter.paymentMethod, PaymentMethod.upi);
      expect(filter.isActive, isTrue);
    });

    test('presets compute inclusive UTC bounds around the current time', () {
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ordersFilterProvider.notifier);
      final now = DateTime.now();

      notifier.setPreset(OrdersDatePreset.today);
      var filter = container.read(ordersFilterProvider);
      expect(filter.datePreset, OrdersDatePreset.today);
      expect(filter.fromUtc!.isBefore(now.toUtc()), isTrue);
      expect(filter.toUtc!.isAfter(now.toUtc()), isTrue);
      expect(
        filter.toUtc!.difference(filter.fromUtc!),
        const Duration(days: 1) - const Duration(microseconds: 1),
      );

      notifier.setPreset(OrdersDatePreset.last7);
      filter = container.read(ordersFilterProvider);
      expect(
        filter.toUtc!.difference(filter.fromUtc!),
        const Duration(days: 7) - const Duration(microseconds: 1),
      );
      expect(
        filter.fromUtc!.isBefore(now.toUtc().subtract(const Duration(days: 7))),
        isFalse,
      );
      expect(
        filter.fromUtc!.isBefore(now.toUtc().subtract(const Duration(days: 5))),
        isTrue,
      );
    });

    test('all-time preset clears the bounds', () {
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ordersFilterProvider.notifier);

      notifier.setPreset(OrdersDatePreset.last30);
      notifier.setPreset(OrdersDatePreset.all);
      final filter = container.read(ordersFilterProvider);
      expect(filter.datePreset, OrdersDatePreset.all);
      expect(filter.fromUtc, isNull);
      expect(filter.toUtc, isNull);
      expect(filter.isActive, isFalse);
    });

    test('custom range keeps local day boundaries as UTC instants', () {
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ordersFilterProvider.notifier);

      notifier.setCustomRange(DateTime(2026, 2, 10), DateTime(2026, 2, 12));
      final filter = container.read(ordersFilterProvider);
      expect(filter.datePreset, OrdersDatePreset.custom);
      final expectedFrom = DateTime(2026, 2, 10).toUtc();
      final expectedTo = DateTime(2026, 2, 12, 23, 59, 59, 999, 999).toUtc();
      expect(filter.fromUtc, expectedFrom);
      expect(filter.toUtc, expectedTo);
    });

    test('clear resets everything', () {
      final container = buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(ordersFilterProvider.notifier);

      notifier.setQuery('coffee');
      notifier.setPaymentMethod(PaymentMethod.cash);
      notifier.setPreset(OrdersDatePreset.today);
      notifier.clear();
      expect(container.read(ordersFilterProvider), const OrdersFilter());
    });
  });

  group('ordersListProvider', () {
    test('loads an empty feed for empty history', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final feed = await container.read(ordersListProvider.future);
      expect(feed.items, isEmpty);
      expect(feed.hasMore, isFalse);
    });

    test('loads and sorts completed sales newest first', () async {
      repository.storedSummaries.addAll([
        summary('BF-000001', createdAt: DateTime.utc(2026, 1, 1)),
        summary('BF-000002', createdAt: DateTime.utc(2026, 1, 2)),
        summary('BF-000003', itemCount: 3, createdAt: DateTime.utc(2026, 1, 3)),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      final feed = await container.read(ordersListProvider.future);
      expect(feed.items.length, 3);
      expect(feed.items.map((o) => o.receiptNumber), [
        'BF-000003',
        'BF-000002',
        'BF-000001',
      ]);
      expect(feed.hasMore, isFalse);
    });

    test('exposes loading, then data for a stalled request', () async {
      repository.ordersGate = Completer<void>();
      final container = buildContainer();
      addTearDown(container.dispose);

      final initial = container.read(ordersListProvider);
      expect(initial.isLoading, isTrue);

      repository.ordersGate!.complete();
      final feed = await container.read(ordersListProvider.future);
      expect(feed.items, isEmpty);
    });

    test('surfaces repository failures as a safe error state', () async {
      repository.ordersError = const UnexpectedOrdersFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(ordersListProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(ordersListProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedOrdersFailure>());
    });

    test('loadMore appends pages without reloading the first one', () async {
      seedFiftyFive();
      final container = buildContainer();
      addTearDown(container.dispose);

      final first = await container.read(ordersListProvider.future);
      expect(first.items.length, OrdersListController.pageSize);
      expect(first.hasMore, isTrue);

      await container.read(ordersListProvider.notifier).loadMore();
      final second = await container.read(ordersListProvider.future);
      expect(second.items.length, 55);
      expect(second.hasMore, isFalse);
      expect(repository.pageRequests.last, (50, 50));
    });

    test('filter changes reset the feed to its first page', () async {
      seedFiftyFive();
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(ordersListProvider.future);
      container.read(ordersFilterProvider.notifier).setQuery('BF-000055');
      await awaitUntil(
        container,
        () =>
            (container.read(ordersListProvider).value?.items.length ?? 0) == 1,
      );

      final filtered = container.read(ordersListProvider).value!;
      expect(filtered.items.length, 1);
      expect(filtered.items.single.receiptNumber, 'BF-000055');
      expect(repository.pageRequests.last, (50, 0));
    });

    test(
      'discards a stale loadMore when the filter changed mid-flight',
      () async {
        seedFiftyFive();
        final container = buildContainer();
        addTearDown(container.dispose);

        await container.read(ordersListProvider.future);

        repository.ordersGate = Completer<void>();
        final loadMore = container.read(ordersListProvider.notifier).loadMore();
        container.read(ordersFilterProvider.notifier).setQuery('BF-888888');
        await Future<void>.delayed(Duration.zero);
        repository.ordersGate!.complete();
        await loadMore;

        await awaitUntil(
          container,
          () => (container.read(ordersListProvider).value?.items ?? const [])
              .isEmpty,
        );
        expect(
          container.read(ordersListProvider).value!.items,
          isEmpty,
          reason: 'stale append must be discarded',
        );
      },
    );

    test('loadMore rethrows failures without wiping loaded rows', () async {
      seedFiftyFive();
      final container = buildContainer();
      addTearDown(container.dispose);

      final first = await container.read(ordersListProvider.future);
      repository.ordersError = const UnexpectedOrdersFailure();
      await expectLater(
        container.read(ordersListProvider.notifier).loadMore(),
        throwsA(isA<UnexpectedOrdersFailure>()),
      );
      final after = container.read(ordersListProvider).value;
      expect(after!.items.length, first.items.length);
      expect(after.hasMore, isTrue);
    });
  });

  group('orderDetailProvider', () {
    test('loads a full order with snapshot items', () async {
      repository.add(
        receiptNumber: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        paymentMethod: PaymentMethod.bank,
        totalPaise: 24000,
        items: const [
          OrderItem(
            productName: 'Filter Coffee',
            sku: 'FC-1',
            unitPricePaise: 12000,
            quantity: 2,
            lineTotalPaise: 24000,
          ),
        ],
      );
      final container = buildContainer();
      addTearDown(container.dispose);

      final order = await container.read(orderDetailProvider('order-1').future);
      expect(order.receiptNumber, 'BF-000001');
      expect(order.items.single.productName, 'Filter Coffee');
      expect(order.items.single.sku, 'FC-1');
      expect(order.totalPaise, 24000);
    });

    test('maps missing ids to a safe failure', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(orderDetailProvider('missing'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(orderDetailProvider('missing'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<MissingOrderFailure>());
    });

    test('maps unexpected database errors to a safe failure', () async {
      repository.detailError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(orderDetailProvider('order-1'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(orderDetailProvider('order-1'));
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedOrdersFailure>());
    });
  });
}
