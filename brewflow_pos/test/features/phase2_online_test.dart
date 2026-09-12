import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/customers/data/drift_customers_repository.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/offers/data/drift_offers_repository.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/purchases/data/drift_suppliers_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_connectivity_service.dart';

void main() {
  group('Phase 2 online-only business writes', () {
    late AppDatabase db;

    Future<String> seedShop(String id, String name) async {
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value(id), name: name));
      return id;
    }

    Future<int> outboxPendingCount() async {
      final q = db.selectOnly(db.syncOutbox)
        ..addColumns([db.syncOutbox.id.count()])
        ..where(db.syncOutbox.status.equals('PENDING'));
      final r = await q
          .map((row) => row.read(db.syncOutbox.id.count())!)
          .getSingle();
      return r ?? 0;
    }

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      // Need at least one shop for resolveWritableShopId
      await seedShop('shop-1', 'Cafe');
    });

    tearDown(() async => db.close());

    test('offline category create is rejected and creates no outbox', () async {
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftInventoryRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      await expectLater(
        repo.createCategory('Beverages', shopId: 'shop-1'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      expect(await outboxPendingCount(), 0);
      // Ensure no category was created
      final cats = await repo.categories(shopIds: ['shop-1']);
      expect(cats, isEmpty);
    });

    test('online category create succeeds', () async {
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final repo = DriftInventoryRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      final cat = await repo.createCategory('Beverages', shopId: 'shop-1');
      expect(cat.name, 'Beverages');
      final cats = await repo.categories(shopIds: ['shop-1']);
      expect(cats.map((c) => c.name), contains('Beverages'));
    });

    test('offline customer create is rejected and no outbox', () async {
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftCustomersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      await expectLater(
        repo.createCustomer(
          name: 'Alice',
          phone: '9990001111',
          shopId: 'shop-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      expect(await outboxPendingCount(), 0);
    });

    test('online customer create succeeds', () async {
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final repo = DriftCustomersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      final c = await repo.createCustomer(
        name: 'Bob',
        phone: '9990002222',
        shopId: 'shop-1',
      );
      expect(c.name, 'Bob');
    });

    test('offline supplier create rejected', () async {
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftSuppliersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      await expectLater(
        repo.createSupplier(
          name: 'Supplier A',
          phone: '8881112222',
          shopId: 'shop-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      expect(await outboxPendingCount(), 0);
    });

    test('offline expense create rejected', () async {
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftExpensesRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      await expectLater(
        repo.createExpense(
          name: 'Milk',
          amountPaise: 5000,
          category: ExpenseCategory.supplies,
          paymentMethod: PaymentMethod.cash,
          expenseDate: DateTime.now().toUtc(),
          shopId: 'shop-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      expect(await outboxPendingCount(), 0);
    });

    test('offline offer create rejected', () async {
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftOffersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      await expectLater(
        repo.createOffer(
          shopId: 'shop-1',
          name: '10% off',
          type: OfferType.percentage,
          configJson: '{"pct":10}',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      expect(await outboxPendingCount(), 0);
    });

    test('business isolation: categories are shop-scoped', () async {
      await seedShop('shop-2', 'Food Truck');
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final repo = DriftInventoryRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      await repo.createCategory('Cafe Only', shopId: 'shop-1');
      await repo.createCategory('Truck Only', shopId: 'shop-2');
      final cafeCats = await repo.categories(shopIds: ['shop-1']);
      final truckCats = await repo.categories(shopIds: ['shop-2']);
      expect(cafeCats.map((c) => c.name), contains('Cafe Only'));
      expect(cafeCats.map((c) => c.name), isNot(contains('Truck Only')));
      expect(truckCats.map((c) => c.name), contains('Truck Only'));
    });

    test('offers remain correct after online write', () async {
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final repo = DriftOffersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: null,
      );
      final offer = await repo.createOffer(
        shopId: 'shop-1',
        name: 'Combo',
        type: OfferType.combo,
        configJson: '{"items":["a","b"]}',
        isActive: true,
      );
      expect(offer.name, 'Combo');
      expect(offer.type, OfferType.combo);
      expect(offer.isActive, isTrue);
      final all = await repo.allOffers();
      expect(all, hasLength(1));
    });

    test(
      'product image direct upload fallback does not fail product create',
      () async {
        // Seed category
        final catRepo = DriftInventoryRepository(
          db,
          connectivityService: fakeConnectivityServiceOnline()..init(),
          supabaseClient: null,
        );
        final cat = await DriftInventoryRepository(
          db,
        ).createCategory('Cat', shopId: 'shop-1');
        // Use online repo with supabase null (so it falls back to queue) – should still succeed
        final connectivity = fakeConnectivityServiceOnline();
        await connectivity.init();
        final repo = DriftInventoryRepository(
          db,
          connectivityService: connectivity,
          supabaseClient: null,
        );
        final product = await repo.createProduct(
          categoryId: cat.id,
          name: 'Latte',
          sellingPricePaise: 15000,
          stockQuantity: 10,
          isActive: true,
          shopId: 'shop-1',
          imagePath: 'product_images/fake.jpg',
        );
        expect(product.name, 'Latte');
        expect(product.imagePath, 'product_images/fake.jpg');
      },
    );
  });
}
