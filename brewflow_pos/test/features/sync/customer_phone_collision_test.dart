import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for FINAL E2E Failure 1:
/// `SqliteException(2067) UNIQUE constraint failed: customers.phone` aborted
/// the whole pull page, so the sync cycle never advanced.
///
/// The local column is globally unique while the cloud contract scopes phone
/// uniqueness per shop. A cloud row colliding with a different local UUID
/// must converge, never crash the cycle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalMasterDataApplier applier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    applier = LocalMasterDataApplier(db);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: const Value('shop-a'), name: 'Cafe'));
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(id: const Value('shop-b'), name: 'Food Truck'),
        );
  });

  tearDown(() async => db.close());

  SyncCustomer cloudRow({
    required String id,
    required String shopId,
    required String phone,
  }) => SyncCustomer(
    id: id,
    shopId: shopId,
    name: 'Naren',
    phone: phone,
    email: null,
    address: null,
    isActive: true,
    membershipActive: false,
    membershipFeePaise: null,
    whatsappStatus: 'UNKNOWN',
    createdAt: DateTime.utc(2026, 9, 1),
  );

  Future<void> seedLocal({
    required String id,
    required String shopId,
    required String? phone,
  }) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            name: 'Local $id',
            phone: Value(phone),
          ),
        );
  }

  Future<List<Customer>> allCustomers() => db.select(db.customers).get();

  test('same-shop phone collision converges without throwing', () async {
    await seedLocal(id: 'local-1', shopId: 'shop-a', phone: '9750468484');

    await applier.applyCustomerPage([
      cloudRow(id: 'cloud-1', shopId: 'shop-a', phone: '9750468484'),
    ], DateTime.utc(2026, 9, 12));

    final rows = await allCustomers();
    expect(rows.length, 2);
    final local = rows.firstWhere((r) => r.id == 'local-1');
    final cloud = rows.firstWhere((r) => r.id == 'cloud-1');
    // Cloud is canonical: keeps the phone; the stale local row keeps its
    // identity/history but frees the business key.
    expect(cloud.phone, '9750468484');
    expect(local.phone, isNull);
    expect(local.shopId, 'shop-a');
  });

  test('distinct phones apply normally', () async {
    await applier.applyCustomerPage([
      cloudRow(id: 'c-1', shopId: 'shop-a', phone: '111'),
      cloudRow(id: 'c-2', shopId: 'shop-a', phone: '222'),
    ], DateTime.utc(2026, 9, 12));
    expect((await allCustomers()).length, 2);
  });

  test('cross-shop collision preserves local and completes', () async {
    await seedLocal(id: 'local-b', shopId: 'shop-b', phone: '999');
    // Same phone, different shop: the local schema cannot hold both, so the
    // incoming row is skipped (local kept) instead of aborting the page.
    await applier.applyCustomerPage([
      cloudRow(id: 'cloud-a', shopId: 'shop-a', phone: '999'),
    ], DateTime.utc(2026, 9, 12));
    final rows = await allCustomers();
    expect(rows.length, 1);
    expect(rows.single.id, 'local-b');
    expect(rows.single.phone, '999');
  });

  test('null phones never collide', () async {
    await seedLocal(id: 'l-1', shopId: 'shop-a', phone: null);
    await applier.applyCustomerPage([
      SyncCustomer(
        id: 'c-null',
        shopId: 'shop-a',
        name: 'NoPhone',
        phone: null,
        email: null,
        address: null,
        isActive: true,
        membershipActive: false,
        membershipFeePaise: null,
        whatsappStatus: 'UNKNOWN',
        createdAt: DateTime.utc(2026, 9, 1),
      ),
    ], DateTime.utc(2026, 9, 12));
    expect((await allCustomers()).length, 2);
  });
}
