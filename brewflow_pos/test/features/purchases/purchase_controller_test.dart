import 'dart:async';

import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_purchases_repository.dart';
import '../../helpers/fake_suppliers_repository.dart';

void main() {
  late FakePurchasesRepository fakePurchases;
  late FakeSuppliersRepository fakeSuppliers;

  final now = DateTime.now().toUtc();

  Purchase purchase(
    String id,
    String number, {
    String? supplierId,
    int totalPaise = 0,
  }) => Purchase(
    id: id,
    supplierId: supplierId,
    purchaseNumber: number,
    subtotalPaise: totalPaise,
    totalPaise: totalPaise,
    createdAt: now,
    updatedAt: now,
  );

  Supplier supplier(String id, String name) => Supplier(
    id: id,
    name: name,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  Product product(String id, String name, {int? costPaise, int stock = 20}) =>
      Product(
        id: id,
        categoryId: 'c1',
        name: name,
        sku: 'SKU-$id',
        sellingPricePaise: 12000,
        costPricePaise: costPaise,
        stockQuantity: stock,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      purchasesRepositoryProvider.overrideWithValue(fakePurchases),
      suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
    ],
  );

  setUp(() {
    fakePurchases = FakePurchasesRepository();
    fakeSuppliers = FakeSuppliersRepository();
  });

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

  group('purchasesProvider', () {
    test(
      'loads purchases newest first with resolved supplier labels',
      () async {
        fakeSuppliers.storedSuppliers.addAll([
          supplier('s1', 'Acme Supplies'),
          supplier('s2', 'Brew Traders'),
        ]);
        fakePurchases.storedPurchases.addAll([
          purchase('p1', 'PUR-000001', supplierId: 's1', totalPaise: 5000),
          purchase('p2', 'PUR-000002', totalPaise: 12000),
        ]);
        final container = buildContainer();
        addTearDown(container.dispose);

        expect(container.read(purchasesProvider), isA<AsyncLoading>());
        await container.read(purchasesProvider.future);

        final rows = container.read(purchasesProvider).value!;
        expect(rows.map((row) => row.purchase.purchaseNumber), [
          'PUR-000001',
          'PUR-000002',
        ]);
        expect(rows[0].supplierName, 'Acme Supplies');
        expect(rows[1].supplierName, isNull);
      },
    );

    test('search narrows the list by purchase number and supplier', () async {
      fakeSuppliers.storedSuppliers.addAll([supplier('s1', 'Acme Supplies')]);
      fakePurchases.storedPurchases.addAll([
        purchase('p1', 'PUR-000001', supplierId: 's1'),
        purchase('p2', 'PUR-000012'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(purchasesProvider.future);

      container.read(purchasesFilterProvider.notifier).setQuery('PUR-000001');
      await awaitUntil(
        container,
        () => container.read(purchasesProvider).value?.length == 1,
      );
      expect(container.read(purchasesProvider).value!.single.purchase.id, 'p1');

      container.read(purchasesFilterProvider.notifier).setQuery('acme');
      await awaitUntil(
        container,
        () => container.read(purchasesProvider).value?.length == 1,
      );
      expect(container.read(purchasesProvider).value!.single.purchase.id, 'p1');

      container.read(purchasesFilterProvider.notifier).setQuery('nope');
      await awaitUntil(
        container,
        () => container.read(purchasesProvider).value?.isEmpty ?? false,
      );
    });
  });

  group('purchase form cart', () {
    test('add line appends the product to the cart', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);

      final added = controller.addLine(
        product: product('p1', 'Coffee Beans', costPaise: 10000),
        quantity: 1,
        unitCostPaise: 10000,
      );
      expect(added, isTrue);
      final line = container.read(purchaseFormProvider).lines.single;
      expect(line.productId, 'p1');
      expect(line.productName, 'Coffee Beans');
      expect(line.sku, 'SKU-p1');
      expect(line.stockQuantity, 20);
      expect(line.quantity, 1);
      expect(line.unitCostPaise, 10000);
    });

    test('duplicate line rejection keeps one line and reports false', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);

      expect(
        controller.addLine(
          product: product('p1', 'Coffee Beans'),
          quantity: 1,
          unitCostPaise: 10000,
        ),
        isTrue,
      );
      expect(
        controller.addLine(
          product: product('p1', 'Coffee Beans'),
          quantity: 2,
          unitCostPaise: 12000,
        ),
        isFalse,
      );
      expect(container.read(purchaseFormProvider).lines, hasLength(1));
    });

    test('quantity update changes the line quantity', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);
      controller.addLine(
        product: product('p1', 'Coffee Beans'),
        quantity: 1,
        unitCostPaise: 10000,
      );

      controller.updateQuantity('p1', 5);
      expect(container.read(purchaseFormProvider).lines.single.quantity, 5);
    });

    test('cost update changes the line unit cost in paise', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);
      controller.addLine(
        product: product('p1', 'Coffee Beans'),
        quantity: 1,
        unitCostPaise: 10000,
      );

      controller.updateCost('p1', 12550);
      expect(
        container.read(purchaseFormProvider).lines.single.unitCostPaise,
        12550,
      );
    });

    test('remove line drops the product from the cart', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);
      controller.addLine(
        product: product('p1', 'Coffee Beans'),
        quantity: 1,
        unitCostPaise: 10000,
      );
      controller.addLine(
        product: product('p2', 'Filter Paper'),
        quantity: 1,
        unitCostPaise: 5000,
      );

      controller.removeLine('p1');
      final lines = container.read(purchaseFormProvider).lines;
      expect(lines.map((line) => line.productId), ['p2']);
    });

    test('supplier selection stores the id and walk-in clears it', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);

      controller.setSupplier('s1');
      expect(container.read(purchaseFormProvider).supplierId, 's1');

      controller.setSupplier(null);
      expect(container.read(purchaseFormProvider).supplierId, isNull);
    });
  });

  group('purchase form submit', () {
    test('submit success receives the purchase and clears the cart', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);
      controller.setSupplier('s1');
      controller.addLine(
        product: product('p1', 'Coffee Beans'),
        quantity: 5,
        unitCostPaise: 10000,
      );
      controller.addLine(
        product: product('p2', 'Filter Paper'),
        quantity: 2,
        unitCostPaise: 5000,
      );

      final purchase = await controller.submit(notes: 'Morning delivery');

      expect(purchase!.purchaseNumber, 'PUR-000001');
      expect(purchase.supplierId, 's1');
      expect(purchase.totalPaise, 60000);
      expect(fakePurchases.receiveCalls, 1);
      expect(fakePurchases.lastLines.map((l) => l.productId), ['p1', 'p2']);
      expect(fakePurchases.lastLines.first.quantity, 5);
      expect(fakePurchases.lastLines.first.unitCostPaise, 10000);
      expect(fakePurchases.lastSupplierId, 's1');
      expect(fakePurchases.lastNotes, 'Morning delivery');

      final state = container.read(purchaseFormProvider);
      expect(state.lines, isEmpty);
      expect(state.submitting, isFalse);
    });

    test(
      'submit failure surfaces the failure and preserves the cart',
      () async {
        fakePurchases.receiveError = const InactiveSupplierFailure();
        final container = buildContainer();
        addTearDown(container.dispose);
        final controller = container.read(purchaseFormProvider.notifier);
        controller.setSupplier('s1');
        controller.addLine(
          product: product('p1', 'Coffee Beans'),
          quantity: 5,
          unitCostPaise: 10000,
        );

        await expectLater(
          controller.submit(),
          throwsA(isA<InactiveSupplierFailure>()),
        );

        final state = container.read(purchaseFormProvider);
        expect(state.submitting, isFalse);
        expect(state.supplierId, 's1');
        expect(state.lines, hasLength(1));
        expect(state.lines.single.quantity, 5);
        expect(fakePurchases.receiveCalls, 1);
      },
    );

    test(
      'submit rejects an empty cart before touching the repository',
      () async {
        final container = buildContainer();
        addTearDown(container.dispose);

        await expectLater(
          container.read(purchaseFormProvider.notifier).submit(),
          throwsA(isA<EmptyPurchaseFailure>()),
        );
        expect(fakePurchases.receiveCalls, 0);
      },
    );

    test(
      'submit rejects a zero quantity before touching the repository',
      () async {
        final container = buildContainer();
        addTearDown(container.dispose);
        final controller = container.read(purchaseFormProvider.notifier);
        controller.addLine(
          product: product('p1', 'Coffee Beans'),
          quantity: 1,
          unitCostPaise: 10000,
        );
        controller.updateQuantity('p1', 0);

        await expectLater(
          controller.submit(),
          throwsA(isA<InvalidPurchaseQuantityFailure>()),
        );
        expect(fakePurchases.receiveCalls, 0);
      },
    );

    test(
      'provider invalidation refreshes the purchase history after success',
      () async {
        final container = buildContainer();
        addTearDown(container.dispose);
        await container.read(purchasesProvider.future);
        expect(container.read(purchasesProvider).value, isEmpty);
        final callsBefore = fakePurchases.purchasesCalls;

        final controller = container.read(purchaseFormProvider.notifier);
        controller.addLine(
          product: product('p1', 'Coffee Beans'),
          quantity: 1,
          unitCostPaise: 10000,
        );
        await controller.submit();

        await awaitUntil(
          container,
          () => container.read(purchasesProvider).value?.isNotEmpty ?? false,
        );
        expect(fakePurchases.purchasesCalls, greaterThan(callsBefore));
        expect(
          container
              .read(purchasesProvider)
              .value!
              .single
              .purchase
              .purchaseNumber,
          'PUR-000001',
        );
      },
    );

    test(
      'double submission is guarded: only one receive call happens',
      () async {
        fakePurchases.receiveGate = Completer<void>();
        final container = buildContainer();
        addTearDown(container.dispose);
        final controller = container.read(purchaseFormProvider.notifier);
        controller.addLine(
          product: product('p1', 'Coffee Beans'),
          quantity: 1,
          unitCostPaise: 10000,
        );

        final first = controller.submit();
        final second = controller.submit();
        expect(await second, isNull);
        await Future<void>.delayed(Duration.zero);
        expect(fakePurchases.receiveCalls, 1);

        fakePurchases.receiveGate!.complete();
        final received = await first;
        expect(received!.purchaseNumber, 'PUR-000001');
        expect(fakePurchases.receiveCalls, 1);
      },
    );

    test('cart edits are blocked while a submission is in flight', () async {
      fakePurchases.receiveGate = Completer<void>();
      final container = buildContainer();
      addTearDown(container.dispose);
      final controller = container.read(purchaseFormProvider.notifier);
      controller.addLine(
        product: product('p1', 'Coffee Beans'),
        quantity: 1,
        unitCostPaise: 10000,
      );

      final first = controller.submit();
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.addLine(
          product: product('p2', 'Filter Paper'),
          quantity: 1,
          unitCostPaise: 5000,
        ),
        isFalse,
      );
      controller.updateQuantity('p1', 9);
      controller.removeLine('p1');
      controller.setSupplier('s9');
      expect(container.read(purchaseFormProvider).lines, hasLength(1));
      expect(container.read(purchaseFormProvider).lines.single.quantity, 1);

      fakePurchases.receiveGate!.complete();
      await first;
    });
  });
}
