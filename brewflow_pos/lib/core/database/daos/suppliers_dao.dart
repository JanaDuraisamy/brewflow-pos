import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Suppliers DAO
///
/// All Drift access for the suppliers table lives here. Search and filtering
/// happen in SQL (never in memory); business rules (case-insensitive phone
/// uniqueness) live in the suppliers repository.
/// ---------------------------------------------------------------------------

final class SuppliersDao {
  SuppliersDao(this._db);

  final AppDatabase _db;

  /// Suppliers filtered and sorted in SQL.
  ///
  /// [search] matches name, phone or email (case-insensitive substring).
  /// [active] restricts to active/inactive suppliers when non-null.
  Future<List<Supplier>> query({String? search, bool? active}) {
    final query = _db.select(_db.suppliers)
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
    return query.get();
  }

  Future<Supplier?> byId(String id) => (_db.select(
    _db.suppliers,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Whether a supplier with this phone number already exists
  /// (case-insensitive).
  ///
  /// [exceptId] excludes one supplier so an edit can keep its own phone.
  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    final table = _db.suppliers;
    final query = _db.selectOnly(table)..addColumns([table.id]);
    final conditions = <Expression<bool>>[
      table.phone.lower().equals(phone.toLowerCase()),
    ];
    if (exceptId != null) {
      conditions.add(table.id.isNotValue(exceptId));
    }
    query.where(conditions.reduce((a, b) => a & b));
    query.limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<Supplier> insert(SuppliersCompanion companion) =>
      _db.into(_db.suppliers).insertReturning(companion);

  Future<void> update(String id, SuppliersCompanion companion) async {
    final updated = companion.copyWith(
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await (_db.update(
      _db.suppliers,
    )..where((t) => t.id.equals(id))).write(updated);
  }

  Future<void> updateActive(String id, bool isActive) async {
    await (_db.update(_db.suppliers)..where((t) => t.id.equals(id))).write(
      SuppliersCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Number of purchases referencing this supplier (the FK backstop for a
  /// hard delete); zero means the supplier has no receiving history.
  Future<int> countPurchases(String id) async {
    final table = _db.purchases;
    final query = _db.selectOnly(table)..addColumns([table.id.count()]);
    query.where(table.supplierId.equals(id));
    return query.map((row) => row.read(table.id.count())!).getSingle();
  }

  /// Permanently removes a supplier row.
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.suppliers)..where((t) => t.id.equals(id))).go();
  }
}
