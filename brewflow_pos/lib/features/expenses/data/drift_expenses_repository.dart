import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/expenses_dao.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Expenses Repository
///
/// Implements [ExpensesRepository] on the local Drift database. All SQL
/// access goes through [ExpensesDao]; all failures are translated into safe
/// [ExpensesFailure] values (details logged via [AppLog], never shown).
///
/// Sync: when a [SyncOutboxCoordinator] is provided, write operations append
/// their outbox rows in the SAME database transaction as the business change;
/// without one the repository behaves exactly as before (offline-first, tests,
/// signed-out usage).
///
/// Normalization: the expense name must be non-blank, the amount must be
/// non-negative, and a blank note is stored as NULL (never an empty string).
/// ---------------------------------------------------------------------------

final class DriftExpensesRepository implements ExpensesRepository {
  DriftExpensesRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
  }) : _expenses = ExpensesDao(database),
       _outbox = outboxCoordinator;

  static const String tag = 'Expenses';

  final ExpensesDao _expenses;
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<List<Expense>> expenses({
    String? search,
    ExpenseCategory? category,
    PaymentMethod? paymentMethod,
    DateTime? fromUtc,
    DateTime? toUtc,
    ExpenseStatusFilter status = ExpenseStatusFilter.all,
  }) async {
    try {
      final rows = await _expenses.query(
        search: search ?? '',
        category: category?.dbValue,
        paymentMethod: paymentMethod?.dbValue,
        fromUtc: fromUtc,
        toUtc: toUtc,
        active: switch (status) {
          ExpenseStatusFilter.all => null,
          ExpenseStatusFilter.active => true,
          ExpenseStatusFilter.inactive => false,
        },
      );
      return rows.map(_expenseFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load expenses', error, stackTrace);
    }
  }

  @override
  Future<Expense?> expenseById(String id) async {
    try {
      final row = await _expenses.byId(id);
      return row == null ? null : _expenseFromRow(row);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load expense', error, stackTrace);
    }
  }

  @override
  Future<Expense> createExpense({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    bool isActive = true,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
  }) async {
    final normalizedName = _requiredText(name, 'Expense name is required.');
    final normalizedPaise = _nonNegativePaise(amountPaise);
    final normalizedNote = _optionalText(note);
    try {
      final result = await (_outbox == null
          ? _insertExpense(
              name: normalizedName,
              amountPaise: normalizedPaise,
              category: category,
              paymentMethod: paymentMethod,
              expenseDate: expenseDate,
              note: normalizedNote,
              isActive: isActive,
              paymentStatus: paymentStatus,
            )
          : _outbox.run(
              write: () => _insertExpense(
                name: normalizedName,
                amountPaise: normalizedPaise,
                category: category,
                paymentMethod: paymentMethod,
                expenseDate: expenseDate,
                note: normalizedNote,
                isActive: isActive,
                paymentStatus: paymentStatus,
              ),
              snapshots: (row, ctx) async => [
                OutboxAppend(
                  entity: MasterEntity.expense,
                  entityId: row.id,
                  payload: SyncExpense(
                    id: row.id,
                    shopId: ctx.shopId,
                    name: row.name,
                    amountPaise: row.amountPaise,
                    category: row.category,
                    paymentMethod: row.paymentMethod,
                    paymentStatus: row.paymentStatus,
                    expenseDate: row.expenseDate,
                    note: row.note,
                    isActive: row.isActive,
                    createdAt: row.createdAt,
                  ).toJson(),
                ),
              ],
            ));
      return _expenseFromRow(result);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to create expense', error, stackTrace);
    }
  }

  Future<db.Expense> _insertExpense({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    required String? note,
    required bool isActive,
    required ExpensePaymentStatus paymentStatus,
  }) => _expenses.insert(
    db.ExpensesCompanion.insert(
      name: name,
      amountPaise: amountPaise,
      category: category.dbValue,
      paymentMethod: paymentMethod.dbValue,
      paymentStatus: Value(paymentStatus.dbValue),
      expenseDate: expenseDate,
      note: Value(note),
      isActive: Value(isActive),
    ),
  );

  @override
  Future<void> updateExpense({
    required String id,
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    required bool isActive,
    required ExpensePaymentStatus paymentStatus,
  }) async {
    final normalizedName = _requiredText(name, 'Expense name is required.');
    final normalizedPaise = _nonNegativePaise(amountPaise);
    final normalizedNote = _optionalText(note);
    try {
      if (_outbox == null) {
        await _expenses.update(
          id,
          db.ExpensesCompanion(
            name: Value(normalizedName),
            amountPaise: Value(normalizedPaise),
            category: Value(category.dbValue),
            paymentMethod: Value(paymentMethod.dbValue),
            paymentStatus: Value(paymentStatus.dbValue),
            expenseDate: Value(expenseDate),
            note: Value(normalizedNote),
            isActive: Value(isActive),
          ),
        );
      } else {
        await _outbox.run(
          write: () => _expenses.update(
            id,
            db.ExpensesCompanion(
              name: Value(normalizedName),
              amountPaise: Value(normalizedPaise),
              category: Value(category.dbValue),
              paymentMethod: Value(paymentMethod.dbValue),
              paymentStatus: Value(paymentStatus.dbValue),
              expenseDate: Value(expenseDate),
              note: Value(normalizedNote),
              isActive: Value(isActive),
            ),
          ),
          snapshots: (_, ctx) async {
            final row = await _expenses.byId(id);
            if (row == null) return [];
            return [
              OutboxAppend(
                entity: MasterEntity.expense,
                entityId: row.id,
                payload: SyncExpense(
                  id: row.id,
                  shopId: ctx.shopId,
                  name: row.name,
                  amountPaise: row.amountPaise,
                  category: row.category,
                  paymentMethod: row.paymentMethod,
                  paymentStatus: row.paymentStatus,
                  expenseDate: row.expenseDate,
                  note: row.note,
                  isActive: row.isActive,
                  createdAt: row.createdAt,
                ).toJson(),
              ),
            ];
          },
        );
      }
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update expense', error, stackTrace);
    }
  }

  @override
  Future<void> setExpenseActive(String id, bool isActive) async {
    try {
      if (_outbox == null) {
        await _expenses.updateActive(id, isActive);
      } else {
        await _outbox.run(
          write: () => _expenses.updateActive(id, isActive),
          snapshots: (_, ctx) async {
            final row = await _expenses.byId(id);
            if (row == null) return [];
            return [
              OutboxAppend(
                entity: MasterEntity.expense,
                entityId: row.id,
                payload: SyncExpense(
                  id: row.id,
                  shopId: ctx.shopId,
                  name: row.name,
                  amountPaise: row.amountPaise,
                  category: row.category,
                  paymentMethod: row.paymentMethod,
                  paymentStatus: row.paymentStatus,
                  expenseDate: row.expenseDate,
                  note: row.note,
                  isActive: row.isActive,
                  createdAt: row.createdAt,
                ).toJson(),
              ),
            ];
          },
        );
      }
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update expense activity', error, stackTrace);
    }
  }

  @override
  Future<int> payablePaise() async {
    try {
      return await _expenses.payablePaise();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payable total', error, stackTrace);
    }
  }

  @override
  Future<void> deleteExpense(String id) async {
    try {
      final existing = await _expenses.byId(id);
      if (existing == null) {
        throw const MissingExpenseFailure();
      }
      Future<void> deleteNow() => _expenses.deleteById(id);
      if (_outbox == null) {
        await deleteNow();
        return;
      }
      // Hard delete travels as a tombstone so every other device learns it.
      await _outbox.run<void>(
        write: deleteNow,
        snapshots: (_, ctx) async => [
          OutboxAppend(
            entity: MasterEntity.expense,
            entityId: id,
            operation: 'DELETE',
            payload: {'id': id, 'shopId': ctx.shopId},
          ),
        ],
      );
    } on ExpensesFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to delete expense', error, stackTrace);
    }
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedExpensesFailure();
  }

  /// Returns trimmed non-empty text, or null when blank — an empty note
  /// never stores a value.
  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _requiredText(String value, String message) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw UnexpectedExpensesFailure(message);
    }
    return normalized;
  }

  /// Guards against negative amounts; the expense form enforces > 0 and the
  /// database CHECK enforces >= 0 as the final backstop.
  static int _nonNegativePaise(int paise) {
    if (paise < 0) {
      throw const UnexpectedExpensesFailure('Amount must be at least zero.');
    }
    return paise;
  }

  static Expense _expenseFromRow(db.Expense row) => Expense(
    id: row.id,
    name: row.name,
    amountPaise: row.amountPaise,
    category: ExpenseCategory.fromDbValue(row.category)!,
    paymentMethod: PaymentMethod.fromDbValue(row.paymentMethod)!,
    paymentStatus: ExpensePaymentStatus.fromDbValue(row.paymentStatus)!,
    expenseDate: row.expenseDate,
    note: row.note,
    isActive: row.isActive,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
