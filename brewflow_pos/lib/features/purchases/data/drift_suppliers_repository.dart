import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/suppliers_dao.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Suppliers Repository
///
/// Implements [SuppliersRepository] on the local Drift database. All SQL
/// access goes through [SuppliersDao]; all failures are translated into safe
/// [SuppliersFailure] values (details logged via [AppLog], never shown).
///
/// Sync (Phase 6.1): when a [SyncOutboxCoordinator] is provided, supplier
/// writes append their outbox rows in the SAME database transaction; without
/// one behavior is unchanged (offline-first).
///
/// Uniqueness policy: the phone number is optional, but unique when present.
/// The repository enforces case-insensitive uniqueness before insert/update
/// ([SuppliersDao.phoneExists]); the SQLite UNIQUE index on the column is the
/// exact-match backstop, and it treats NULLs as distinct, so empty values
/// never collide.
///
/// Deactivation is soft ([setSupplierActive]): suppliers are never deleted,
/// so purchase history referencing a supplier stays readable after
/// deactivation (the receiving transaction itself re-validates activity,
/// Phase 10 Step 5).
/// ---------------------------------------------------------------------------

final class DriftSuppliersRepository implements SuppliersRepository {
  DriftSuppliersRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
  }) : _suppliers = SuppliersDao(database),
       _outbox = outboxCoordinator;

  static const String tag = 'Suppliers';

  final SuppliersDao _suppliers;

  /// Null when sync is not wired (tests / signed-out legacy flows).
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<List<Supplier>> suppliers({
    String? search,
    SupplierStatusFilter status = SupplierStatusFilter.all,
  }) async {
    try {
      final rows = await _suppliers.query(
        search: search,
        active: switch (status) {
          SupplierStatusFilter.all => null,
          SupplierStatusFilter.active => true,
          SupplierStatusFilter.inactive => false,
        },
      );
      return rows.map(_supplierFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load suppliers', error, stackTrace);
    }
  }

  @override
  Future<Supplier?> supplierById(String id) async {
    try {
      final row = await _suppliers.byId(id);
      return row == null ? null : _supplierFromRow(row);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load supplier', error, stackTrace);
    }
  }

  @override
  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    try {
      return await _suppliers.phoneExists(phone, exceptId: exceptId);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to check phone number', error, stackTrace);
    }
  }

  @override
  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool isActive = true,
  }) async {
    final normalizedName = _requiredText(name, 'Supplier name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    final normalizedNotes = _optionalText(notes);
    if (normalizedPhone != null &&
        await _suppliers.phoneExists(normalizedPhone)) {
      throw const DuplicateSupplierPhoneFailure();
    }
    try {
      Future<Supplier> doCreate() async {
        final row = await _suppliers.insert(
          db.SuppliersCompanion.insert(
            name: normalizedName,
            phone: Value(normalizedPhone),
            email: Value(normalizedEmail),
            address: Value(normalizedAddress),
            notes: Value(normalizedNotes),
            isActive: Value(isActive),
          ),
        );
        return _supplierFromRow(row);
      }

      final coordinator = _outbox;
      return coordinator == null
          ? doCreate()
          : coordinator.run(
              write: doCreate,
              snapshots: (supplier, context) async => [
                _supplierAppend(supplier, context),
              ],
            );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to create supplier', error, stackTrace);
    }
  }

  @override
  Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    required bool isActive,
  }) async {
    final normalizedName = _requiredText(name, 'Supplier name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    final normalizedNotes = _optionalText(notes);
    if (normalizedPhone != null &&
        await _suppliers.phoneExists(normalizedPhone, exceptId: id)) {
      throw const DuplicateSupplierPhoneFailure();
    }
    try {
      await _upsertWithSnapshot(
        id: id,
        write: () => _suppliers.update(
          id,
          db.SuppliersCompanion(
            name: Value(normalizedName),
            phone: Value(normalizedPhone),
            email: Value(normalizedEmail),
            address: Value(normalizedAddress),
            notes: Value(normalizedNotes),
            isActive: Value(isActive),
          ),
        ),
      );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update supplier', error, stackTrace);
    }
  }

  @override
  Future<void> setSupplierActive(String id, bool isActive) async {
    try {
      await _upsertWithSnapshot(
        id: id,
        write: () => _suppliers.updateActive(id, isActive),
      );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update supplier', error, stackTrace);
    }
  }

  @override
  Future<SupplierDeleteResult> deleteSupplier(String id) async {
    try {
      final existing = await _suppliers.byId(id);
      if (existing == null) {
        throw UnexpectedSuppliersFailure('Supplier not found.');
      }
      final hasPurchases = await _suppliers.countPurchases(id) > 0;
      if (hasPurchases) {
        // Purchase history must stay readable — degrade to a safe soft
        // deactivation rather than a hard delete that FK-restrict rejects.
        await _upsertWithSnapshot(
          id: id,
          write: () => _suppliers.updateActive(id, false),
        );
        return SupplierDeleteResult.deactivated;
      }
      final coordinator = _outbox;
      Future<void> deleteNow() => _suppliers.deleteById(id);
      if (coordinator == null) {
        await deleteNow();
      } else {
        await coordinator.run<void>(
          write: deleteNow,
          snapshots: (_, context) async => [
            OutboxAppend(
              entity: MasterEntity.supplier,
              entityId: id,
              operation: 'DELETE',
              payload: {'id': id, 'shopId': context.shopId},
            ),
          ],
        );
      }
      return SupplierDeleteResult.deleted;
    } on SuppliersFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to delete supplier', error, stackTrace);
    }
  }

  /// Writes, then snapshots the REAL row state — inside the outbox
  /// transaction when sync is wired; plain write otherwise.
  Future<void> _upsertWithSnapshot({
    required String id,
    required Future<void> Function() write,
  }) {
    final coordinator = _outbox;
    if (coordinator == null) return write();
    return coordinator.run<void>(
      write: write,
      snapshots: (_, context) async {
        final row = await _suppliers.byId(id);
        if (row == null) return const [];
        return [_supplierAppend(_supplierFromRow(row), context)];
      },
    );
  }

  static OutboxAppend _supplierAppend(
    Supplier supplier,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.supplier,
    entityId: supplier.id,
    payload: SyncSupplier(
      id: supplier.id,
      shopId: context.shopId,
      name: supplier.name,
      phone: supplier.phone,
      email: supplier.email,
      address: supplier.address,
      notes: supplier.notes,
      isActive: supplier.isActive,
      createdAt: supplier.createdAt,
    ).toJson(),
  );

  /// Returns trimmed non-empty text, or null when blank — an empty phone
  /// input never stores a value (keeps uniqueness clean).
  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _requiredText(String value, String message) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw UnexpectedSuppliersFailure(message);
    }
    return normalized;
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedSuppliersFailure();
  }

  static Supplier _supplierFromRow(db.Supplier row) => Supplier(
    id: row.id,
    name: row.name,
    phone: row.phone,
    email: row.email,
    address: row.address,
    notes: row.notes,
    isActive: row.isActive,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
