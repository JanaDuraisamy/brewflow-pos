import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/customers_dao.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Customers Repository
///
/// Implements [CustomersRepository] on the local Drift database. All SQL
/// access goes through [CustomersDao]; all failures are translated into safe
/// [CustomersFailure] values (details logged via [AppLog], never shown).
///
/// Sync (Phase 6.1): when a [SyncOutboxCoordinator] is provided, customer
/// writes append their outbox rows in the SAME database transaction; without
/// one behavior is unchanged (offline-first). Phone stays canonical and
/// WhatsApp status travels verbatim — sync NEVER fabricates verification.
///
/// Uniqueness policy: the phone number is optional, but unique when present.
/// The repository enforces case-insensitive uniqueness before insert/update
/// ([CustomersDao.phoneExists]); the SQLite UNIQUE constraint on the column
/// is the exact-match backstop, and it treats NULLs as distinct, so empty
/// values never collide.
/// ---------------------------------------------------------------------------

final class DriftCustomersRepository implements CustomersRepository {
  DriftCustomersRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
  }) : _customers = CustomersDao(database),
       _outbox = outboxCoordinator;

  static const String tag = 'Customers';

  final CustomersDao _customers;

  /// Null when sync is not wired (tests / signed-out legacy flows).
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<List<Customer>> customers({
    String? search,
    CustomerStatusFilter status = CustomerStatusFilter.all,
  }) async {
    try {
      final rows = await _customers.query(
        search: search,
        active: switch (status) {
          CustomerStatusFilter.all => null,
          CustomerStatusFilter.active => true,
          CustomerStatusFilter.inactive => false,
        },
      );
      return rows.map(_customerFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load customers', error, stackTrace);
    }
  }

  @override
  Future<Customer?> customerById(String id) async {
    try {
      final row = await _customers.byId(id);
      return row == null ? null : _customerFromRow(row);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load customer', error, stackTrace);
    }
  }

  @override
  Future<bool> phoneExists(String phone, {String? exceptId}) async {
    try {
      return await _customers.phoneExists(phone, exceptId: exceptId);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to check phone number', error, stackTrace);
    }
  }

  @override
  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    bool isActive = true,
    bool membershipActive = false,
    int? membershipFeePaise,
    WhatsAppStatus whatsappStatus = WhatsAppStatus.unknown,
  }) async {
    final normalizedName = _requiredText(name, 'Customer name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    if (normalizedPhone != null &&
        await _customers.phoneExists(normalizedPhone)) {
      throw const DuplicatePhoneFailure();
    }
    try {
      Future<Customer> doCreate() async {
        final row = await _customers.insert(
          db.CustomersCompanion.insert(
            name: normalizedName,
            phone: Value(normalizedPhone),
            email: Value(normalizedEmail),
            address: Value(normalizedAddress),
            isActive: Value(isActive),
            membershipActive: Value(membershipActive),
            membershipFeePaise: Value(membershipFeePaise),
            whatsappStatus: Value(whatsappStatus.dbValue),
          ),
        );
        return _customerFromRow(row);
      }

      final coordinator = _outbox;
      return coordinator == null
          ? doCreate()
          : coordinator.run(
              write: doCreate,
              snapshots: (customer, context) async => [
                _customerAppend(customer, context),
              ],
            );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to create customer', error, stackTrace);
    }
  }

  @override
  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    required bool isActive,
    bool membershipActive = false,
    int? membershipFeePaise,
    WhatsAppStatus? whatsappStatus,
  }) async {
    final normalizedName = _requiredText(name, 'Customer name is required.');
    final normalizedPhone = _optionalText(phone);
    final normalizedEmail = _optionalText(email);
    final normalizedAddress = _optionalText(address);
    if (normalizedPhone != null &&
        await _customers.phoneExists(normalizedPhone, exceptId: id)) {
      throw const DuplicatePhoneFailure();
    }
    try {
      await _upsertWithSnapshot(
        id: id,
        write: () => _customers.update(
          id,
          db.CustomersCompanion(
            name: Value(normalizedName),
            phone: Value(normalizedPhone),
            email: Value(normalizedEmail),
            address: Value(normalizedAddress),
            isActive: Value(isActive),
            membershipActive: Value(membershipActive),
            membershipFeePaise: Value(membershipFeePaise),
            whatsappStatus: whatsappStatus != null
                ? Value(whatsappStatus.dbValue)
                : const Value.absent(),
          ),
        ),
      );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update customer', error, stackTrace);
    }
  }

  @override
  Future<void> setCustomerActive(String id, bool isActive) async {
    try {
      await _upsertWithSnapshot(
        id: id,
        write: () => _customers.updateActive(id, isActive),
      );
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update customer', error, stackTrace);
    }
  }

  @override
  Future<CustomerDeleteResult> deleteCustomer(String id) async {
    try {
      final existing = await _customers.byId(id);
      if (existing == null) {
        throw UnexpectedCustomersFailure('Customer not found.');
      }
      final hasHistory = await _customers.countReferences(id) > 0;
      if (hasHistory) {
        // Billed/ledger history must stay readable — degrade to a safe soft
        // deactivation rather than a hard delete that FK-restrict rejects.
        await _upsertWithSnapshot(
          id: id,
          write: () => _customers.updateActive(id, false),
        );
        return CustomerDeleteResult.deactivated;
      }
      final coordinator = _outbox;
      Future<void> deleteNow() => _customers.deleteById(id);
      if (coordinator == null) {
        await deleteNow();
      } else {
        await coordinator.run<void>(
          write: deleteNow,
          snapshots: (_, context) async => [
            OutboxAppend(
              entity: MasterEntity.customer,
              entityId: id,
              operation: 'DELETE',
              payload: {'id': id, 'shopId': context.shopId},
            ),
          ],
        );
      }
      return CustomerDeleteResult.deleted;
    } on CustomersFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to delete customer', error, stackTrace);
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
        final row = await _customers.byId(id);
        if (row == null) return const [];
        return [_customerAppend(_customerFromRow(row), context)];
      },
    );
  }

  static OutboxAppend _customerAppend(
    Customer customer,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.customer,
    entityId: customer.id,
    payload: SyncCustomer(
      id: customer.id,
      shopId: context.shopId,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      address: customer.address,
      isActive: customer.isActive,
      membershipActive: customer.membershipActive,
      membershipFeePaise: customer.membershipFeePaise,
      whatsappStatus: customer.whatsappStatus.dbValue,
      createdAt: customer.createdAt,
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
      throw UnexpectedCustomersFailure(message);
    }
    return normalized;
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedCustomersFailure();
  }

  static Customer _customerFromRow(db.Customer row) => Customer(
    id: row.id,
    name: row.name,
    phone: row.phone,
    email: row.email,
    address: row.address,
    isActive: row.isActive,
    membershipActive: row.membershipActive,
    membershipFeePaise: row.membershipFeePaise,
    whatsappStatus: WhatsAppStatus.fromDbValue(row.whatsappStatus),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
