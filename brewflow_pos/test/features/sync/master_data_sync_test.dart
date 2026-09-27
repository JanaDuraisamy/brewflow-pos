import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/customers/data/drift_customers_repository.dart';
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
// `show` avoids a clash with the Drift `Expense` row class exported by
// app_database.dart, which this file also needs.
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart'
    show ExpenseCategory, ExpensePaymentStatus;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart'
    show PaymentMethod;
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/purchases/data/drift_suppliers_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// Phase 6.1 — master-data synchronization tests.
///
/// Every scenario drives REAL repository writes through the atomic outbox
/// coordinator and REAL engine cycles against the in-memory cloud mirror
/// (RLS-modeled fakes bound per shop). Two/three "devices" share one
/// [FakeRemoteStore], proving actual A → cloud → B propagation.
/// ---------------------------------------------------------------------------

final class Device {
  Device._({
    required this.id,
    required this.shopId,
    required this.database,
    required this.sync,
    required this.gateway,
    required this.coordinator,
    required this.engine,
    required this.inventory,
    required this.suppliers,
    required this.customers,
    required this.expenses,
  });

  final String id;
  final String shopId;
  final AppDatabase database;
  final DriftSyncRepository sync;
  final FakeRemoteMasterDataGateway gateway;
  final SyncOutboxCoordinator coordinator;
  final SyncEngine engine;
  final DriftInventoryRepository inventory;
  final DriftSuppliersRepository suppliers;
  final DriftCustomersRepository customers;
  final DriftExpensesRepository expenses;

  Future<void> runCycle() => engine.runCycle(deviceId: id, shopId: shopId);

  Future<int> pending() => sync.pendingOutboxCount();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRemoteStore cloud;

  Future<Device> makeDevice(String id, String shopId) async {
    final database = AppDatabase(NativeDatabase.memory());
    // Seed the canonical single-shop row exactly as owner bootstrap does, so
    // the local write path resolves the session shopId (not a random UUID),
    // outbox payloads and local FK agree, and pulled shop-scoped rows always
    // have a target `shops` row to reference.
    await database
        .into(database.shops)
        .insert(
          ShopsCompanion.insert(
            id: Value(shopId),
            name: 'BrewFlow POS',
            createdAt: Value(DateTime.utc(2026, 1, 1)),
          ),
        );
    final sync = DriftSyncRepository(database);
    final gateway = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopId);
    Future<SyncSessionContext> contextResolver() async =>
        SyncSessionContext(deviceId: id, shopId: shopId, userId: 'u-$id');
    final coordinator = SyncOutboxCoordinator(sync, contextResolver);
    final engine = SyncEngine(sync, gateway, LocalMasterDataApplier(database));
    return Device._(
      id: id,
      shopId: shopId,
      database: database,
      sync: sync,
      gateway: gateway,
      coordinator: coordinator,
      engine: engine,
      inventory: DriftInventoryRepository(
        database,
        outboxCoordinator: coordinator,
      ),
      suppliers: DriftSuppliersRepository(
        database,
        outboxCoordinator: coordinator,
      ),
      customers: DriftCustomersRepository(
        database,
        outboxCoordinator: coordinator,
      ),
      expenses: DriftExpensesRepository(
        database,
        outboxCoordinator: coordinator,
      ),
    );
  }

  setUp(() {
    cloud = FakeRemoteStore();
  });

  group('category sync', () {
    test('A creates → cloud → B receives', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      await a.inventory.createCategory('Beverages');
      expect(await a.pending(), 1);

      await a.runCycle();
      expect(await a.pending(), 0);
      expect(cloud.categories.values.single.row.name, 'Beverages');

      await b.runCycle();
      final categories = await b.inventory.categories();
      expect(categories.map((c) => c.name), ['Beverages']);
      // Same UUID identity across devices — the whole point.
      expect(categories.single.id, cloud.categories.values.single.row.id);
    });

    test('B updates → cloud → A receives (round-trip)', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final created = await a.inventory.createCategory('Snacks');
      await a.runCycle();
      await b.runCycle();

      await b.inventory.updateCategoryName(created.id, 'Munchies');
      await b.runCycle();
      await a.runCycle();

      final aNames = (await a.inventory.categories()).map((c) => c.name);
      expect(aNames, ['Munchies']);
    });

    test(
      'duplicate replay of one logical change collapses while pending',
      () async {
        final a = await makeDevice('A', 'shop-1');
        addTearDown(a.database.close);

        // Two rapid renames of the SAME unsynced category collapse onto one
        // deterministic outbox row carrying the latest snapshot.
        final created = await a.inventory.createCategory('Temp');
        await a.inventory.updateCategoryName(created.id, 'Temp 2');
        expect(await a.pending(), 1);
        await a.runCycle();
        expect(cloud.categories.values.single.row.name, 'Temp 2');
      },
    );

    test(
      'offline keeps data pending; retry succeeds when back online',
      () async {
        final a = await makeDevice('A', 'shop-1');
        final b = await makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        a.gateway.pushesFail = true;
        await a.inventory.createCategory('Offline cat');
        await a.runCycle();
        expect(await a.pending(), 1, reason: 'nothing may be lost offline');
        expect(cloud.categories, isEmpty);

        a.gateway.pushesFail = false;
        await a.runCycle();
        expect(await a.pending(), 0);
        await b.runCycle();
        expect((await b.inventory.categories()).single.name, 'Offline cat');
      },
    );

    test(
      'exhausted retries park as FAILED without blocking later changes',
      () async {
        final a = await makeDevice('A', 'shop-1');
        addTearDown(a.database.close);

        a.gateway.pushesFail = true;
        await a.inventory.createCategory('Doomed');
        for (var i = 0; i < SyncEngine.maxAttempts; i++) {
          await a.runCycle();
        }
        expect(await a.pending(), 0, reason: 'parked row left the PENDING set');

        // The queue head is free: a later change still syncs.
        a.gateway.pushesFail = false;
        await a.inventory.createCategory('Alive');
        await a.runCycle();
        expect(cloud.categories.values.last.row.name, 'Alive');

        // The doomed category still exists locally (never dropped silently).
        expect(
          (await a.inventory.categories()).map((c) => c.name),
          containsAll(['Doomed', 'Alive']),
        );
      },
    );

    test(
      'hard delete propagates as tombstone; other device deactivates',
      () async {
        final a = await makeDevice('A', 'shop-1');
        final b = await makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        final created = await a.inventory.createCategory('Kill me');
        await a.runCycle();
        await b.runCycle();
        expect((await b.inventory.categories()).length, 1);

        await a.inventory.deleteCategory(created.id);
        await a.runCycle();
        expect((await a.inventory.categories()).length, 0);
        expect(cloud.deletions.length, 1, reason: 'tombstone recorded');

        await b.runCycle();
        final bCategories = await b.inventory.categories();
        // Nothing referenced the category on B either, so it hard-deletes.
        expect(bCategories.where((c) => c.isActive), isEmpty);
      },
    );
  });

  group('product + variant sync', () {
    test('A creates product with variant → B receives parent first', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final category = await a.inventory.createCategory('Coffee');
      final product = await a.inventory.createProduct(
        categoryId: category.id,
        name: 'Latte',
        sellingPricePaise: 12000,
        stockQuantity: 0,
        variants: [
          const ProductVariantInput(
            name: '250ml',
            sellingPricePaise: 10000,
            stockQuantity: 4,
          ),
          const ProductVariantInput(
            name: '400ml',
            sellingPricePaise: 15000,
            stockQuantity: 2,
          ),
        ],
        isActive: true,
      );
      await a.runCycle();

      expect(cloud.products.length, 1);
      expect(cloud.productVariants.length, 2);

      await b.runCycle();
      final bProducts = await b.inventory.products();
      expect(bProducts.single.name, 'Latte');
      expect(bProducts.single.variants.length, 2);
      expect(
        {for (final v in bProducts.single.variants) v.name},
        {'250ml', '400ml'},
      );
      expect(bProducts.single.variants.first.productId, product.id);
    });

    test('product edit round-trips including variant changes', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final category = await a.inventory.createCategory('Tea');
      final product = await a.inventory.createProduct(
        categoryId: category.id,
        name: 'Chai',
        sellingPricePaise: 5000,
        stockQuantity: 9,
        isActive: true,
      );
      await a.runCycle();
      await b.runCycle();

      await a.inventory.updateProduct(
        id: product.id,
        categoryId: category.id,
        name: 'Masala Chai',
        sku: 'TEA-1',
        sellingPricePaise: 6000,
        stockQuantity: 9,
        membershipEnabled: true,
        memberPricePaise: 5500,
        isActive: true,
      );
      await a.runCycle();
      await b.runCycle();

      final seen = (await b.inventory.products()).single;
      expect(seen.id, product.id);
      expect(seen.name, 'Masala Chai');
      expect(seen.sellingPricePaise, 6000);
      expect(seen.membershipEnabled, isTrue);
      expect(seen.memberPricePaise, 5500);
    });
  });

  group('supplier sync', () {
    test('create + update round-trip preserves every field', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final created = await a.suppliers.createSupplier(
        name: 'Bean Bros',
        phone: '+91 98765 43210',
        email: 'sales@beanbros.in',
        address: 'Coorg',
        notes: 'Weekly delivery',
      );
      await a.runCycle();
      await b.runCycle();

      var received = await b.suppliers.supplierById(created.id);
      expect(received, isNotNull);
      expect(received!.phone, '+91 98765 43210');
      expect(received.email, 'sales@beanbros.in');
      expect(received.address, 'Coorg');
      expect(received.notes, 'Weekly delivery');

      await b.suppliers.updateSupplier(
        id: created.id,
        name: 'Bean Bros Ltd',
        phone: null,
        email: null,
        address: null,
        notes: null,
        isActive: false,
      );
      await b.runCycle();
      await a.runCycle();

      received = await a.suppliers.supplierById(created.id);
      expect(received!.name, 'Bean Bros Ltd');
      expect(received.phone, isNull);
      expect(received.isActive, isFalse);
    });
  });

  group('customer sync', () {
    test(
      'membership + WhatsApp status travel verbatim; phone canonical',
      () async {
        final a = await makeDevice('A', 'shop-1');
        final b = await makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        final created = await a.customers.createCustomer(
          name: 'Jana',
          phone: '9876500000',
          email: 'jana@brewflow.app',
          address: 'Chennai',
          membershipActive: true,
          membershipFeePaise: 50000,
          whatsappStatus: WhatsAppStatus.verified,
        );
        await a.runCycle();
        await b.runCycle();

        final received = await b.customers.customerById(created.id);
        expect(received!.name, 'Jana');
        expect(received.phone, '9876500000');
        expect(received.membershipActive, isTrue);
        expect(received.membershipFeePaise, 50000);
        expect(received.whatsappStatus, WhatsAppStatus.verified);
        // No fake verification ever happens in transit.
        expect(cloud.customers.values.single.row.whatsappStatus, 'VERIFIED');

        await b.customers.updateCustomer(
          id: created.id,
          name: 'Jana K',
          phone: '9876500000',
          isActive: true,
          membershipActive: true,
          membershipFeePaise: 50000,
        );
        await b.runCycle();
        await a.runCycle();
        final renamed = await a.customers.customerById(created.id);
        expect(renamed!.name, 'Jana K');
        expect(renamed.whatsappStatus, WhatsAppStatus.verified);
      },
    );
  });

  group('customer deletion sync', () {
    test(
      'a delete on A removes the customer on B and frees the unique phone',
      () async {
        final a = await makeDevice('A', 'shop-1');
        final b = await makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        final created = await a.customers.createCustomer(
          name: 'Jana',
          phone: '9876500000',
        );
        await a.runCycle();
        await b.runCycle();
        expect(
          (await b.customers.customerById(created.id))!.phone,
          '9876500000',
        );

        await a.customers.deleteCustomer(created.id);
        await a.runCycle();
        await b.runCycle();

        // A real delete, not a deactivate. The tombstone used to be applied as
        // `is_active = false`, which left a zombie row on every peer: invisible
        // in the list only because of the hidden filter, but still squatting on
        // the globally-unique `customers.phone` column.
        expect(await b.customers.customerById(created.id), isNull);
        expect(await b.database.select(b.database.customers).get(), isEmpty);
        expect(
          await (b.database.select(
            b.database.customers,
          )..where((t) => t.phone.equals('9876500000'))).get(),
          isEmpty,
        );

        // B can immediately reuse the freed phone, which a zombie row would
        // have blocked with SqliteException 2067.
        final reused = await b.customers.createCustomer(
          name: 'New Jana',
          phone: '9876500000',
        );
        expect(reused.phone, '9876500000');
        await b.runCycle();
        await a.runCycle();
        expect((await a.customers.customerById(reused.id))!.name, 'New Jana');
        expect(await a.customers.customerById(created.id), isNull);
      },
    );

    test(
      'the deleted customer leaves the cloud, not just this device',
      () async {
        final a = await makeDevice('A', 'shop-1');
        addTearDown(a.database.close);

        final created = await a.customers.createCustomer(
          name: 'Jana',
          phone: '9876500000',
        );
        await a.runCycle();
        expect(cloud.customers.containsKey(created.id), isTrue);

        await a.customers.deleteCustomer(created.id);
        await a.runCycle();

        // The row is gone from the cloud table itself, not merely tombstoned.
        // This is what stops every freshly provisioned device from re-pulling
        // it on every first sync, and stops deleted customers from piling up
        // invisibly in `customers`.
        expect(cloud.customers.containsKey(created.id), isFalse);

        // A device provisioned afterwards has nothing to resurrect. The
        // CUSTOMER tombstone drains last in the pull cycle, so even a row that
        // were still present would be removed again before the cycle ends.
        final fresh = await makeDevice('C', 'shop-1');
        addTearDown(fresh.database.close);
        await fresh.runCycle();
        expect(await fresh.customers.customerById(created.id), isNull);
        expect(
          await fresh.database.select(fresh.database.customers).get(),
          isEmpty,
        );
      },
    );

    test(
      'peer deletion keeps the ledger and its attribution on both devices',
      () async {
        final a = await makeDevice('A', 'shop-1');
        final b = await makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        final created = await a.customers.createCustomer(
          name: 'Jana',
          phone: '9876500000',
        );
        // A customer-linked sale on A, so the delete has real history behind it.
        final now = DateTime.now().toUtc();
        await a.database
            .into(a.database.sales)
            .insert(
              SalesCompanion.insert(
                id: const Value('sale-1'),
                receiptNumber: 'BF-000001',
                customerId: Value(created.id),
                subtotalPaise: 50000,
                totalPaise: 50000,
                paymentStatus: const Value('NOT_PAID'),
                paymentMethod: const Value('CASH'),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await a.runCycle();
        await b.runCycle();
        // NB: sales are transactional, not master data, so B legitimately has
        // no copy of this sale. What must travel is the CUSTOMER tombstone.

        await a.customers.deleteCustomer(created.id);
        await a.runCycle();
        await b.runCycle();

        // The deleting device keeps its ledger, still attributed, even though
        // the customer row is gone. Nothing is nulled and nothing cascades.
        final sale = await (a.database.select(
          a.database.sales,
        )..where((t) => t.id.equals('sale-1'))).getSingle();
        expect(sale.totalPaise, 50000);
        expect(sale.customerId, created.id);

        // And the peer ends up with no customer row at all.
        expect(await b.customers.customerById(created.id), isNull);
      },
    );
  });

  group('pull mechanics', () {
    test('applier never overwrites rows with pending local changes', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final category = await a.inventory.createCategory('Cloud version');
      await a.runCycle();
      await b.runCycle();

      // B queues its own local change (still PENDING — offline).
      b.gateway.pushesFail = true;
      await b.inventory.updateCategoryName(category.id, 'Local version');
      final cloudNameBefore = cloud.categories[category.id]!.row.name;
      expect(cloudNameBefore, 'Cloud version');

      // A pushes a NEWER cloud state; B pulls it while its edit is pending.
      await a.inventory.updateCategoryName(category.id, 'Newer cloud');
      await a.runCycle();
      await b.runCycle();

      // The pull must NOT revert B's locally-pending edit...
      expect((await b.inventory.categories()).single.name, 'Local version');
      // ...and once online, B's edit wins the arrival-order race.
      b.gateway.pushesFail = false;
      await b.runCycle();
      expect(cloud.categories[category.id]!.row.name, 'Local version');
    });

    test('cursor advances; subsequent pulls are incremental', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      await a.inventory.createCategory('C1');
      await a.runCycle();

      // Bootstrap pull grabs everything.
      await b.runCycle();
      final stateBefore = (await b.sync.stateFor('B'))!.lastPulledAt!;
      expect(stateBefore.isAfter(SyncEngine.initialCursor), isTrue);

      // Nothing changed remotely → nothing applied again (no-op pull).
      final countBefore = cloud.categories.length;
      await b.runCycle();
      expect(cloud.categories.length, countBefore);

      // One new row arrives → next pull picks up exactly the delta.
      await a.inventory.createCategory('C2');
      await a.runCycle();
      await b.runCycle();
      expect((await b.inventory.categories()).length, 2);
    });

    test(
      'replayed pulls are idempotent (duplicate application safe)',
      () async {
        final a = await makeDevice('A', 'shop-1');
        final b = await makeDevice('B', 'shop-1');
        addTearDown(a.database.close);
        addTearDown(b.database.close);

        await a.inventory.createCategory('Dup');
        await a.runCycle();
        await b.runCycle();
        await b.runCycle(); // full replay from scratch would double-insert if
        await b.runCycle(); // applies were not idempotent upserts

        expect((await b.inventory.categories()).length, 1);
      },
    );

    test('bootstrap: a brand-new device pulls the whole catalog', () async {
      final a = await makeDevice('A', 'shop-1');
      addTearDown(a.database.close);

      final category = await a.inventory.createCategory('Bakery');
      await a.inventory.createProduct(
        categoryId: category.id,
        name: 'Croissant',
        sellingPricePaise: 9000,
        stockQuantity: 5,
        isActive: true,
      );
      await a.suppliers.createSupplier(name: 'Flour Co');
      await a.customers.createCustomer(
        name: 'Walk-in Regular',
        membershipActive: true,
        membershipFeePaise: 20000,
      );
      await a.runCycle();

      final fresh = await makeDevice('NEW-TABLET', 'shop-1');
      addTearDown(fresh.database.close);
      await fresh.runCycle();

      expect((await fresh.inventory.categories()).length, 1);
      expect((await fresh.inventory.products()).single.name, 'Croissant');
      expect((await fresh.suppliers.suppliers()).single.name, 'Flour Co');
      expect(
        (await fresh.customers.customers()).single.name,
        'Walk-in Regular',
      );
    });
  });

  group('expense payment sync', () {
    // Return type is inferred on purpose: the domain `Expense` name collides
    // with the Drift row class this file already imports.
    seedUnpaidExpense(
      Device d,
      String name,
      int amountPaise, {
      String? shopId,
    }) => d.expenses.createExpense(
      name: name,
      amountPaise: amountPaise,
      category: ExpenseCategory.supplies,
      paymentMethod: PaymentMethod.cash,
      expenseDate: DateTime.utc(2026, 8, 10),
      paymentStatus: ExpensePaymentStatus.notPaid,
      shopId: shopId ?? d.shopId,
    );

    test('A records a payment → cloud → B derives the same balance', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      // Both devices see the same unpaid expense first.
      await seedUnpaidExpense(a, 'Milk', 160000);
      await a.runCycle();
      await b.runCycle();
      expect(
        (await b.expenses.shopPayables(
          shopIds: const ['shop-1'],
        )).single.totalPaise,
        160000,
      );

      await a.expenses.recordPayablePayment(
        payeeName: 'milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.upi,
        paidAt: DateTime.utc(2026, 8, 12),
        note: 'Part payment',
        shopId: 'shop-1',
      );
      expect(await a.pending(), 1);

      await a.runCycle();
      expect(await a.pending(), 0);
      expect(cloud.expensePayments, hasLength(1));

      await b.runCycle();

      // B never received a balance — it derived one from the same rows.
      final bPayable = (await b.expenses.shopPayables(
        shopIds: const ['shop-1'],
      )).single;
      expect(bPayable.payeeName, 'Milk');
      expect(bPayable.totalPaise, 160000);
      expect(bPayable.paidPaise, 100000);
      expect(bPayable.remainingPaise, 60000);

      final history = await b.expenses.payablePayments(payeeName: 'milk');
      expect(history, hasLength(1));
      expect(history.single.amountPaise, 100000);
      expect(history.single.note, 'Part payment');
    });

    test('the whole payment row round-trips, not just the balance', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      await seedUnpaidExpense(a, 'Milk', 160000);
      await a.runCycle();
      await b.runCycle();

      final paid = await a.expenses.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.bank,
        paidAt: DateTime.utc(2026, 8, 12, 10, 30),
        note: 'Paid in full for the week',
        shopId: 'shop-1',
      );
      await a.runCycle();
      await b.runCycle();

      final received = (await b.expenses.payablePayments(
        payeeName: 'milk',
      )).single;
      expect(received.id, paid.id, reason: 'same UUID identity across devices');
      expect(received.payeeKey, 'milk');
      expect(received.payeeName, 'Milk');
      expect(received.amountPaise, 100000);
      expect(received.paymentMethod, PaymentMethod.bank);
      expect(received.note, 'Paid in full for the week');
      expect(received.paidAt.toUtc(), DateTime.utc(2026, 8, 12, 10, 30));
    });

    test('partial payments accumulate on the receiving device', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      await seedUnpaidExpense(a, 'Milk', 160000);
      await a.runCycle();
      await b.runCycle();

      await a.expenses.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        shopId: 'shop-1',
      );
      await a.runCycle();
      await b.runCycle();
      expect(
        (await b.expenses.shopPayables(
          shopIds: const ['shop-1'],
        )).single.remainingPaise,
        60000,
      );

      // B pays the rest.
      await b.expenses.recordPayablePayment(
        payeeName: 'MILK',
        amountPaise: 60000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 13),
        shopId: 'shop-1',
      );
      await b.runCycle();
      await a.runCycle();

      final aPayable = (await a.expenses.shopPayables(
        shopIds: const ['shop-1'],
      )).single;
      expect(aPayable.remainingPaise, 0);
      expect(await a.expenses.payablePayments(payeeName: 'milk'), hasLength(2));
    });

    test('the original expense row is never edited by a payment', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final expense = await seedUnpaidExpense(a, 'Milk', 160000);
      await a.runCycle();
      await b.runCycle();

      await a.expenses.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 160000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        shopId: 'shop-1',
      );
      await a.runCycle();
      await b.runCycle();

      // Append-only: the expense keeps its own amount and still reads NOT_PAID.
      // Settling a payable is a derived fact, not a mutation of the expense.
      for (final repo in [a.expenses, b.expenses]) {
        final row = await repo.expenseById(expense.id);
        expect(row, isNotNull);
        expect(row!.amountPaise, 160000);
        expect(row.paymentStatus, ExpensePaymentStatus.notPaid);
        expect(row.isActive, isTrue);
      }
    });

    test('a foreign shop never sees another shop payable or payment', () async {
      final a = await makeDevice('A', 'shop-1');
      final intruder = await makeDevice('EVIL', 'shop-2');
      addTearDown(a.database.close);
      addTearDown(intruder.database.close);

      await seedUnpaidExpense(a, 'Milk', 160000, shopId: 'shop-1');
      await a.runCycle();
      await a.expenses.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        shopId: 'shop-1',
      );
      await a.runCycle();

      await intruder.runCycle();
      expect(
        await intruder.expenses.shopPayables(shopIds: const ['shop-2']),
        isEmpty,
      );
      expect(
        await intruder.expenses.payablePayments(payeeName: 'milk'),
        isEmpty,
      );
    });

    test('same-named payees in different shops stay separate', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-2');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      await seedUnpaidExpense(a, 'Milk', 160000, shopId: 'shop-1');
      await seedUnpaidExpense(b, 'Milk', 50000, shopId: 'shop-2');
      await a.runCycle();
      await b.runCycle();

      await a.expenses.recordPayablePayment(
        payeeName: 'Milk',
        amountPaise: 100000,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 8, 12),
        shopId: 'shop-1',
      );
      await a.runCycle();
      await b.runCycle();

      expect(
        (await a.expenses.shopPayables(
          shopIds: const ['shop-1'],
        )).single.remainingPaise,
        60000,
      );
      expect(
        (await b.expenses.shopPayables(
          shopIds: const ['shop-2'],
        )).single.remainingPaise,
        50000,
        reason: 'shop-1 payment must not reduce shop-2 dues for the same payee',
      );
    });
  });

  group('conflict policy + security', () {
    test('a foreign shop never sees another shop’s master data', () async {
      final a = await makeDevice('A', 'shop-1');
      final intruder = await makeDevice('EVIL', 'shop-2');
      addTearDown(a.database.close);
      addTearDown(intruder.database.close);

      await a.inventory.createCategory('Secret menu');
      await a.runCycle();

      // RLS-modeled pull: viewer scoped to shop-2 gets nothing of shop-1.
      await intruder.runCycle();
      expect(await intruder.inventory.categories(), isEmpty);

      // RLS-modeled push check: claiming shop-1 scope from a shop-2 viewer
      // is rejected outright (server-side WITH CHECK violation).
      expect(
        () => intruder.gateway.upsertCategories([
          SyncCategory(
            id: 'stolen-row',
            shopId: 'shop-1',
            name: 'Steal',
            isActive: true,
            createdAt: DateTime.utc(2026),
          ),
        ]),
        throwsStateError,
      );
    });

    test('pending local edits win over concurrent remote overwrites', () async {
      final a = await makeDevice('A', 'shop-1');
      final b = await makeDevice('B', 'shop-1');
      addTearDown(a.database.close);
      addTearDown(b.database.close);

      final category = await a.inventory.createCategory('Original');
      await a.runCycle();
      await b.runCycle();

      // B edits offline (change queued, not pushed yet).
      await b.inventory.updateCategoryName(category.id, 'B was here');
      // Meanwhile A pushes its own newer version to the cloud.
      await a.inventory.updateCategoryName(category.id, 'A moved on');
      await a.runCycle();

      // B's cycle PUSHES FIRST — its pending edit lands after A's, so the
      // arrival-order winner is B. The pull that follows can never revert a
      // still-pending local change (push-before-pull ordering).
      await b.runCycle();
      expect(cloud.categories[category.id]!.row.name, 'B was here');

      await a.runCycle();
      expect((await a.inventory.categories()).map((c) => c.name), [
        'B was here',
      ]);
    });
  });
}
