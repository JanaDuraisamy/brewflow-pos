import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/expenses_dao.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
    ConnectivityService? connectivityService,
    SupabaseClient? supabaseClient,
  }) : _database = database,
       _expenses = ExpensesDao(database),
       _outbox = outboxCoordinator,
       _connectivity = connectivityService,
       _supabase = supabaseClient;

  static const String tag = 'Expenses';

  final db.AppDatabase _database;
  final ExpensesDao _expenses;
  final SyncOutboxCoordinator? _outbox;
  final ConnectivityService? _connectivity;
  final SupabaseClient? _supabase;

  Future<void> _requireOnline() async {
    if (_connectivity != null)
      await OnlineGuard(_connectivity!).requireOnline();
  }

  @override
  Future<List<Expense>> expenses({
    String? search,
    ExpenseCategory? category,
    PaymentMethod? paymentMethod,
    DateTime? fromUtc,
    DateTime? toUtc,
    ExpenseStatusFilter status = ExpenseStatusFilter.all,
    List<String>? shopIds,
  }) async {
    try {
      if (shopIds != null && shopIds.isNotEmpty) {
        final allRows = <db.Expense>[];
        for (final id in shopIds) {
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
            shopId: id,
          );
          allRows.addAll(rows);
        }
        return allRows.map(_expenseFromRow).toList();
      }
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
  Future<Expense?> expenseById(String id, {List<String>? shopIds}) async {
    try {
      if (shopIds != null && shopIds.isNotEmpty) {
        for (final sid in shopIds) {
          final row = await _expenses.byId(id, shopId: sid);
          if (row != null) return _expenseFromRow(row);
        }
        return null;
      }
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
    String? shopId,
  }) async {
    final normalizedName = _requiredText(name, 'Expense name is required.');
    final normalizedPaise = _nonNegativePaise(amountPaise);
    final normalizedNote = _optionalText(note);
    try {
      if (_connectivity != null) await _requireOnline();
      final resolvedShopId = await resolveWritableShopId(_database, shopId);
      if (_supabase != null) {
        final id = const Uuid().v4();
        final now = DateTime.now().toUtc();
        try {
          await _supabase!.from('expenses').upsert({
            'id': id,
            'shop_id': resolvedShopId,
            'name': normalizedName,
            'amount_paise': normalizedPaise,
            'category': category.dbValue,
            'payment_method': paymentMethod.dbValue,
            'payment_status': paymentStatus.dbValue,
            'expense_date': expenseDate.toIso8601String(),
            'note': normalizedNote,
            'is_active': isActive,
            'client_created_at': now.toIso8601String(),
          }, onConflict: 'id');
        } catch (e) {
          if (e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup'))
            throw const OfflineException();
          rethrow;
        }
        final row = await _expenses.insert(
          db.ExpensesCompanion.insert(
            id: Value(id),
            shopId: Value(resolvedShopId),
            name: normalizedName,
            amountPaise: normalizedPaise,
            category: category.dbValue,
            paymentMethod: paymentMethod.dbValue,
            paymentStatus: Value(paymentStatus.dbValue),
            expenseDate: expenseDate,
            note: Value(normalizedNote),
            isActive: Value(isActive),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return _expenseFromRow(row);
      }
      final result = await (_outbox == null
          ? _insertExpense(
              shopId: resolvedShopId,
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
                shopId: resolvedShopId,
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
    } on OfflineException catch (e) {
      throw UnexpectedExpensesFailure(e.message);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to create expense', error, stackTrace);
    }
  }

  Future<db.Expense> _insertExpense({
    required String shopId,
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
      shopId: Value(shopId),
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
      if (_connectivity != null) await _requireOnline();
      if (_supabase != null) {
        try {
          await _supabase!
              .from('expenses')
              .update({
                'name': normalizedName,
                'amount_paise': normalizedPaise,
                'category': category.dbValue,
                'payment_method': paymentMethod.dbValue,
                'payment_status': paymentStatus.dbValue,
                'expense_date': expenseDate.toIso8601String(),
                'note': normalizedNote,
                'is_active': isActive,
              })
              .eq('id', id);
        } catch (e) {
          if (e.toString().contains('SocketException'))
            throw const OfflineException();
          rethrow;
        }
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
        return;
      }
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
    } on OfflineException catch (e) {
      throw UnexpectedExpensesFailure(e.message);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update expense', error, stackTrace);
    }
  }

  @override
  Future<void> setExpenseActive(String id, bool isActive) async {
    try {
      if (_connectivity != null) await _requireOnline();
      if (_supabase != null) {
        try {
          await _supabase!
              .from('expenses')
              .update({'is_active': isActive})
              .eq('id', id);
        } catch (e) {
          if (e.toString().contains('SocketException'))
            throw const OfflineException();
          rethrow;
        }
        await _expenses.updateActive(id, isActive);
        return;
      }
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
    } on OfflineException catch (e) {
      throw UnexpectedExpensesFailure(e.message);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update expense activity', error, stackTrace);
    }
  }

  @override
  Future<int> payablePaise({List<String>? shopIds}) async {
    try {
      if (shopIds != null && shopIds.isNotEmpty) {
        int total = 0;
        for (final id in shopIds) {
          total += await _expenses.payablePaise(shopId: id);
        }
        return total;
      }
      return await _expenses.payablePaise();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payable total', error, stackTrace);
    }
  }

  @override
  Future<void> deleteExpense(String id) async {
    try {
      if (_connectivity != null) await _requireOnline();
      final existing = await _expenses.byId(id);
      if (existing == null) {
        throw const MissingExpenseFailure();
      }
      if (_supabase != null) {
        try {
          await _supabase!.from('expenses').delete().eq('id', id);
          await _supabase!.from('master_deletions').upsert({
            'entity': 'EXPENSE',
            'id': id,
            'shop_id': existing.shopId,
          }, onConflict: 'entity,id');
        } catch (e) {
          if (e.toString().contains('SocketException'))
            throw const OfflineException();
          rethrow;
        }
        await _expenses.deleteById(id);
        return;
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
    } on OfflineException catch (e) {
      throw UnexpectedExpensesFailure(e.message);
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
