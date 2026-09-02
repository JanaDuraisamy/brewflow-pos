import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customers DAO
///
/// All Drift access for the customers table lives here. Search and filtering
/// happen in SQL (never in memory); business rules (case-insensitive phone
/// uniqueness) live in the customers repository.
/// ---------------------------------------------------------------------------

final class CustomersDao {
  CustomersDao(this._db);

  final AppDatabase _db;

  /// Customers filtered and sorted in SQL.
  ///
  /// [search] matches name, phone or email (case-insensitive substring).
  /// [active] restricts to active/inactive customers when non-null.
  Future<List<Customer>> query({String? search, bool? active, String? shopId}) {
    final query = _db.select(_db.customers)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    final text = search?.trim();
    if (text != null && text.isNotEmpty) {
      query.where(
        (t) =>
            t.name.contains(text) |
            t.phone.contains(text) |
            t.email.contains(text),
      );
    }
    if (active != null) {
      query.where((t) => t.isActive.equals(active));
    }
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  Future<Customer?> byId(String id, {String? shopId}) {
    final query = _db.select(_db.customers)..where((t) => t.id.equals(id));
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.getSingleOrNull();
  }

  /// Whether a customer with this phone number already exists
  /// (case-insensitive).
  ///
  /// [exceptId] excludes one customer so an edit can keep its own phone.
  /// When [shopId] is provided the check is scoped to that business.
  Future<bool> phoneExists(
    String phone, {
    String? exceptId,
    String? shopId,
  }) async {
    final table = _db.customers;
    final query = _db.selectOnly(table)..addColumns([table.id]);
    final conditions = <Expression<bool>>[
      table.phone.lower().equals(phone.toLowerCase()),
    ];
    if (exceptId != null) {
      conditions.add(table.id.isNotValue(exceptId));
    }
    if (shopId != null) {
      conditions.add(table.shopId.equals(shopId));
    }
    query.where(conditions.reduce((a, b) => a & b));
    query.limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<Customer> insert(CustomersCompanion companion) =>
      _db.into(_db.customers).insertReturning(companion);

  Future<void> update(String id, CustomersCompanion companion) async {
    final updated = companion.copyWith(
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await (_db.update(
      _db.customers,
    )..where((t) => t.id.equals(id))).write(updated);
  }

  Future<void> updateActive(String id, bool isActive) async {
    await (_db.update(_db.customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Number of sales + customer payments referencing this customer (the FK
  /// backstop for a hard delete); zero means the customer has no billing or
  /// ledger history.
  Future<int> countReferences(String id) async {
    final salesCount = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.id.count()])
      ..where(_db.sales.customerId.equals(id));
    final paymentsCount = _db.selectOnly(_db.customerPayments)
      ..addColumns([_db.customerPayments.id.count()])
      ..where(_db.customerPayments.customerId.equals(id));
    final sales = await salesCount
        .map((row) => row.read(_db.sales.id.count())!)
        .getSingle();
    final payments = await paymentsCount
        .map((row) => row.read(_db.customerPayments.id.count())!)
        .getSingle();
    return sales + payments;
  }

  /// Permanently removes a customer row.
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.customers)..where((t) => t.id.equals(id))).go();
  }
}
