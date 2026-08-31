import 'package:brewflow_pos/core/database/app_database.dart' hide Supplier;
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/data/drift_suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSuppliersRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftSuppliersRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct({required String id, int stock = 10}) async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: 'Product $id',
            sellingPricePaise: 12000,
            stockQuantity: Value(stock),
          ),
        );
  }

  group('DriftSuppliersRepository', () {
    test(
      'creates a supplier with trimmed fields and blank-optional storage',
      () async {
        final created = await repository.createSupplier(
          name: '  Acme Supplies  ',
          phone: '  9845012345  ',
          email: '',
          address: '  Anna Nagar  ',
          notes: '   ',
        );

        expect(created.name, 'Acme Supplies');
        expect(created.phone, '9845012345');
        expect(created.email, isNull);
        expect(created.address, 'Anna Nagar');
        expect(created.notes, isNull);
        expect(created.isActive, isTrue);

        final loaded = await repository.supplierById(created.id);
        expect(loaded!.name, 'Acme Supplies');
        expect(loaded.email, isNull);
        expect(loaded.createdAt.isUtc, isTrue);
      },
    );

    test('search matches name, phone and email case-insensitively', () async {
      await repository.createSupplier(
        name: 'Acme Supplies',
        phone: '9845012345',
        email: 'acme@example.com',
      );
      await repository.createSupplier(
        name: 'Brew Traders',
        phone: '9000012345',
      );
      await repository.createSupplier(
        name: 'Old Mills',
        email: 'mills@example.com',
      );

      final byName = await repository.suppliers(search: 'acme');
      expect(byName.map((s) => s.name), ['Acme Supplies']);

      final byPhone = await repository.suppliers(search: '900001');
      expect(byPhone.map((s) => s.name), ['Brew Traders']);

      final byEmail = await repository.suppliers(search: 'MILLS@EXAMPLE');
      expect(byEmail.map((s) => s.name), ['Old Mills']);

      final all = await repository.suppliers();
      expect(all.map((s) => s.name), [
        'Acme Supplies',
        'Brew Traders',
        'Old Mills',
      ]);
    });

    test('status filter restricts active and inactive suppliers', () async {
      final first = await repository.createSupplier(name: 'Acme Supplies');
      await repository.createSupplier(name: 'Old Mills');
      await repository.setSupplierActive(first.id, false);

      final active = await repository.suppliers(
        status: SupplierStatusFilter.active,
      );
      expect(active.map((s) => s.name), ['Old Mills']);

      final inactive = await repository.suppliers(
        status: SupplierStatusFilter.inactive,
      );
      expect(inactive.map((s) => s.name), ['Acme Supplies']);
    });

    test(
      'rejects a duplicate phone on create but allows empty phones',
      () async {
        await repository.createSupplier(
          name: 'Acme Supplies',
          phone: '9845012345',
        );
        await repository.createSupplier(name: 'No Phone One');
        await repository.createSupplier(name: 'No Phone Two');

        await expectLater(
          repository.createSupplier(name: 'Brew Traders', phone: '9845012345'),
          throwsA(isA<DuplicateSupplierPhoneFailure>()),
        );
        await expectLater(
          repository.createSupplier(
            name: 'Brew Traders',
            phone: ' 9845012345 ',
          ),
          throwsA(isA<DuplicateSupplierPhoneFailure>()),
        );

        expect((await repository.suppliers()).length, 3);
      },
    );

    test(
      'update keeps its own phone and rejects another suppliers phone',
      () async {
        final first = await repository.createSupplier(
          name: 'Acme Supplies',
          phone: '9845012345',
        );
        final second = await repository.createSupplier(name: 'Brew Traders');

        // Editing a supplier with its own phone is allowed.
        await repository.updateSupplier(
          id: first.id,
          name: 'Acme Supplies Co',
          phone: '9845012345',
          isActive: true,
        );

        // Taking another supplier's phone is rejected.
        await expectLater(
          repository.updateSupplier(
            id: second.id,
            name: 'Brew Traders',
            phone: '9845012345',
            isActive: true,
          ),
          throwsA(isA<DuplicateSupplierPhoneFailure>()),
        );

        final loaded = await repository.supplierById(first.id);
        expect(loaded!.name, 'Acme Supplies Co');
        expect(loaded.phone, '9845012345');
        expect(loaded.createdAt, first.createdAt);
        expect(loaded.updatedAt.isAfter(first.updatedAt), isTrue);
      },
    );

    test('update trims and never stores whitespace-only notes', () async {
      final created = await repository.createSupplier(name: 'Acme Supplies');

      await repository.updateSupplier(
        id: created.id,
        name: '  Acme Supplies Co  ',
        email: '  ',
        notes: '   ',
        isActive: false,
      );

      final loaded = await repository.supplierById(created.id);
      expect(loaded!.name, 'Acme Supplies Co');
      expect(loaded.email, isNull);
      expect(loaded.notes, isNull);
      expect(loaded.isActive, isFalse);
    });

    test('deactivation is soft: the row stays with history intact', () async {
      final created = await repository.createSupplier(name: 'Acme Supplies');
      await repository.setSupplierActive(created.id, false);

      final loaded = await repository.supplierById(created.id);
      expect(loaded!.isActive, isFalse);

      // Re-activation restores it to active lists.
      await repository.setSupplierActive(created.id, true);
      expect((await repository.supplierById(created.id))!.isActive, isTrue);
      expect(
        (await repository.suppliers(
          status: SupplierStatusFilter.active,
        )).length,
        1,
      );
    });
  });

  group('supplier purchase integrity', () {
    test('deactivated supplier keeps purchase history readable and blocks '
        'future receiving', () async {
      await seedProduct(id: 'p1', stock: 5);
      final purchases = DriftPurchaseRepository(database);

      // 1. Create the supplier.
      final supplier = await repository.createSupplier(
        name: 'Acme Supplies',
        phone: '9845012345',
      );

      // 2. Receive a purchase linked to the supplier.
      final purchase = await purchases.receivePurchase(
        lines: const [
          PurchaseLine(productId: 'p1', quantity: 2, unitCostPaise: 12000),
        ],
        supplierId: supplier.id,
        notes: 'First delivery',
      );
      expect(purchase.supplierId, supplier.id);

      // 3. Deactivate the supplier.
      await repository.setSupplierActive(supplier.id, false);
      final after = await repository.supplierById(supplier.id);
      expect(after!.isActive, isFalse);

      // 4. The historical purchase remains fully readable.
      final loaded = await purchases.purchaseById(purchase.id);
      expect(loaded!.supplierId, supplier.id);
      expect(loaded.purchaseNumber, 'PUR-000001');
      expect(loaded.totalPaise, 24000);
      final items = await purchases.purchaseItems(purchase.id);
      expect(items.single.productId, 'p1');
      expect(items.single.productName, 'Product p1');
      expect(items.single.unitCostPaise, 12000);
      expect((await purchases.purchases()).single.supplierId, supplier.id);

      // 5. Receiving with the deactivated supplier is blocked exactly as
      //    Phase 10 Step 5 established.
      await expectLater(
        purchases.receivePurchase(
          lines: const [
            PurchaseLine(productId: 'p1', quantity: 1, unitCostPaise: 1000),
          ],
          supplierId: supplier.id,
        ),
        throwsA(isA<InactiveSupplierFailure>()),
      );

      // Nothing was written by the rejected receive.
      expect((await purchases.purchases()).length, 1);
      expect((await purchases.purchaseItems(purchase.id)).length, 1);
      final row = await (database.select(
        database.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(row.stockQuantity, 7);
    });
  });
}
