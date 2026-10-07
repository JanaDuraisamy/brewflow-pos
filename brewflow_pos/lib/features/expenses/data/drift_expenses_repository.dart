import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/expenses_dao.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';
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
      if (shopIds != null) {
        // Hard scope: an empty list means "this business has no shop of its
        // own" and must yield NOTHING rather than every shop's expenses.
        if (shopIds.isEmpty) return const [];
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
  Future<int> expensesCount({List<String>? shopIds}) async {
    try {
      // Honour the scope: an unscoped COUNT(*) leaks every other business's
      // expense count into the scoped list header.
      if (shopIds != null) {
        if (shopIds.isEmpty) return 0;
        var total = 0;
        for (final id in shopIds) {
          final scoped =
              await (_database.selectOnly(_database.expenses)
                    ..addColumns([_database.expenses.id.count()])
                    ..where(_database.expenses.shopId.equals(id)))
                  .getSingle();
          total += scoped.read(_database.expenses.id.count()) ?? 0;
        }
        return total;
      }
      final row = await _database
          .customSelect('SELECT COUNT(*) AS c FROM expenses')
          .getSingle();
      return row.read<int>('c');
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to count expenses', error, stackTrace);
    }
  }

  @override
  Future<Expense?> expenseById(String id, {List<String>? shopIds}) async {
    try {
      if (shopIds != null) {
        if (shopIds.isEmpty) return null;
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
      if (shopIds != null) {
        if (shopIds.isEmpty) return 0;
        int total = 0;
        for (final id in shopIds) {
          total += await _expenses.payablePaiseWithPayments(shopId: id);
        }
        return total;
      }
      return await _expenses.payablePaiseWithPayments();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payable total', error, stackTrace);
    }
  }

  @override
  Future<List<Expense>> payables({List<String>? shopIds}) async {
    try {
      if (shopIds != null) {
        if (shopIds.isEmpty) return const [];
        final allRows = <db.Expense>[];
        for (final id in shopIds) {
          allRows.addAll(await _expenses.payables(shopId: id));
        }
        return allRows.map(_expenseFromRow).toList();
      }
      return (await _expenses.payables()).map(_expenseFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payables', error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Shop payables — grouped unpaid expenses, and payments against them
  // ---------------------------------------------------------------------------

  @override
  Future<List<ShopPayable>> shopPayables({List<String>? shopIds}) async {
    try {
      final payables = <ShopPayable>[];
      if (shopIds != null) {
        if (shopIds.isEmpty) return const [];
        // Scoped per shop on purpose: summing across shops before grouping
        // would let a same-named payee in two businesses merge into one row.
        for (final id in shopIds) {
          payables.addAll(await _shopPayablesFor(shopId: id));
        }
      } else {
        payables.addAll(await _shopPayablesFor());
      }
      // Most pressing first: biggest remaining balance, then oldest expense.
      payables.sort((a, b) {
        final byRemaining = b.remainingPaise.compareTo(a.remainingPaise);
        if (byRemaining != 0) return byRemaining;
        return a.oldestExpenseDate.compareTo(b.oldestExpenseDate);
      });
      return payables;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load shop payables', error, stackTrace);
    }
  }

  /// One shop's grouped payables, built from unpaid expenses minus payments.
  Future<List<ShopPayable>> _shopPayablesFor({String? shopId}) async {
    final groups = await _expenses.payableGroups(shopId: shopId);
    final paid = await _expenses.paidTotalsByPayeeKey(shopId: shopId);
    final result = <ShopPayable>[];
    for (final group in groups.values) {
      result.add(
        ShopPayable(
          payeeKey: group.payeeKey,
          payeeName: group.payeeName,
          totalPaise: group.totalPaise,
          paidPaise: paid[group.payeeKey] ?? 0,
          expenseCount: group.expenseCount,
          oldestExpenseDate: group.oldestExpenseDate,
          lastPaidAt: group.lastPaidAt,
          shopId: shopId,
        ),
      );
    }
    return result;
  }

  @override
  Future<List<ExpensePayment>> payablePayments({
    String? payeeName,
    List<String>? shopIds,
  }) async {
    try {
      final key = payeeName == null ? null : PayeeKey.of(payeeName);
      Future<List<db.ExpensePayment>> read(String? shopId) =>
          _expenses.expensePayments(payeeKey: key, shopId: shopId);
      if (shopIds != null) {
        if (shopIds.isEmpty) return const [];
        final allRows = <db.ExpensePayment>[];
        for (final id in shopIds) {
          allRows.addAll(await read(id));
        }
        return allRows.map(_expensePaymentFromRow).toList();
      }
      return (await read(null)).map(_expensePaymentFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payable payments', error, stackTrace);
    }
  }

  @override
  Future<ExpensePayment> recordPayablePayment({
    required String payeeName,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    required DateTime paidAt,
    String? note,
    String? shopId,
  }) async {
    if (amountPaise <= 0) throw const InvalidPayablePaymentFailure();
    if (_connectivity != null) await _requireOnline();
    final normalizedNote = _optionalText(note);
    final trimmedName = PayeeKey.display(payeeName);
    if (trimmedName.isEmpty) throw const PayableNotFoundFailure();
    final payeeKey = PayeeKey.of(trimmedName);
    final resolvedShopId = await resolveWritableShopId(_database, shopId);

    if (_supabase != null) {
      try {
        final res = await _supabase!.rpc<dynamic>(
          'record_expense_payment_atomic',
          params: {
            'p_shop_id': resolvedShopId,
            'p_payee_key': payeeKey,
            'p_payee_name': trimmedName,
            'p_amount_paise': amountPaise,
            'p_payment_method': paymentMethod.dbValue,
            'p_paid_at': paidAt.toUtc().toIso8601String(),
            'p_note': normalizedNote,
          },
        );
        final map = res is Map<String, dynamic>
            ? res
            : Map<String, dynamic>.from(res as Map);
        final now = DateTime.now().toUtc();
        // Mirror the authoritative row locally so the balance moves at once;
        // the next sync reconciles if the mirror and the server ever differ.
        await _database.transaction(() async {
          await _expenses.insertExpensePayment(
            db.ExpensePaymentsCompanion.insert(
              id: Value(map['id'] as String),
              shopId: Value(resolvedShopId),
              payeeKey: payeeKey,
              payeeName: Value(trimmedName),
              amountPaise: amountPaise,
              paymentMethod: paymentMethod.dbValue,
              note: Value(normalizedNote),
              paidAt: paidAt.toUtc(),
              reversed: const Value(false),
              reversedAt: const Value(null),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        });
        return ExpensePayment(
          id: map['id'] as String,
          payeeKey: payeeKey,
          payeeName: trimmedName,
          amountPaise: amountPaise,
          paymentMethod: paymentMethod,
          paidAt: paidAt.toUtc(),
          note: normalizedNote,
          reversed: false,
          reversedAt: null,
          createdAt: now,
        );
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('SocketException') ||
            msg.contains('Failed host lookup')) {
          throw const OfflineException();
        }
        if (msg.contains('INVALID_AMOUNT')) {
          throw const InvalidPayablePaymentFailure();
        }
        if (msg.contains('PAYMENT_EXCEEDS_DUE')) {
          throw const PayablePaymentExceedsDueFailure();
        }
        if (msg.contains('PAYEE_NOT_FOUND')) {
          throw const PayableNotFoundFailure();
        }
        if (msg.contains('FORBIDDEN')) {
          throw const UnexpectedExpensesFailure(
            'Access denied for this business.',
          );
        }
        rethrow;
      }
    }

    try {
      // Validate against the same derived balance the UI shows, then insert
      // inside the business transaction so the check and the write cannot race.
      final write = () => _database.transaction(() async {
        final remaining =
            (await _expenses.remainingByPayeeKey(
              shopId: resolvedShopId,
            ))[payeeKey] ??
            0;
        if (remaining <= 0) throw const PayableNotFoundFailure();
        if (amountPaise > remaining) {
          throw const PayablePaymentExceedsDueFailure();
        }
        final now = DateTime.now().toUtc();
        return _expenses.insertExpensePayment(
          db.ExpensePaymentsCompanion.insert(
            shopId: Value(resolvedShopId),
            payeeKey: payeeKey,
            payeeName: Value(trimmedName),
            amountPaise: amountPaise,
            paymentMethod: paymentMethod.dbValue,
            note: Value(normalizedNote),
            paidAt: paidAt.toUtc(),
            reversed: const Value(false),
            reversedAt: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      });
      final db.ExpensePayment row;
      if (_outbox == null) {
        row = await write();
      } else {
        final result = await _outbox.run<db.ExpensePayment>(
          write: write,
          snapshots: (r, ctx) async => [
            OutboxAppend(
              entity: MasterEntity.expensePayment,
              entityId: r.id,
              payload: SyncExpensePayment(
                id: r.id,
                shopId: ctx.shopId,
                payeeKey: r.payeeKey,
                payeeName: r.payeeName,
                amountPaise: r.amountPaise,
                paymentMethod: r.paymentMethod,
                note: r.note,
                paidAt: r.paidAt,
                reversed: r.reversed,
                reversedAt: r.reversedAt,
                createdAt: r.createdAt,
              ).toJson(),
            ),
          ],
        );
        row = result;
      }
      return _expensePaymentFromRow(row);
    } on OfflineException catch (e) {
      throw UnexpectedExpensesFailure(e.message);
    } on ExpensesFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to record payment', error, stackTrace);
    }
  }

  ExpensePayment _expensePaymentFromRow(db.ExpensePayment row) =>
      ExpensePayment(
        id: row.id,
        payeeKey: row.payeeKey,
        payeeName: row.payeeName ?? PayeeKey.display(row.payeeKey),
        amountPaise: row.amountPaise,
        paymentMethod:
            PaymentMethod.fromDbValue(row.paymentMethod) ?? PaymentMethod.cash,
        paidAt: row.paidAt,
        note: row.note,
        reversed: row.reversed,
        reversedAt: row.reversedAt,
        createdAt: row.createdAt,
      );

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
    shopId: row.shopId,
  );
}
