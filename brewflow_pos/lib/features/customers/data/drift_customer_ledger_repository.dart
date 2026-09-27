import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/customer_ledger_dao.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Customer Ledger Repository
///
/// Implements [CustomerLedgerRepository] on the local Drift database.
///
/// All reads are SQL aggregations over the sales and customer_payments
/// tables (never whole-table loads); every due/outstanding value is derived,
/// never stored. Only NOT_PAID (credit) sales count toward debt — a PAID sale
/// is settled at the counter and never increases a customer's due. All
/// failures are translated into safe [CustomerLedgerFailure] values (details
/// logged via [AppLog], never shown).
///
/// Sync: when a [SyncOutboxCoordinator] is provided, recordPayment appends
/// its outbox row in the SAME database transaction as the business change;
/// without one the repository behaves exactly as before (offline-first, tests,
/// signed-out usage).
///
/// recordPayment runs inside a single transaction: the sale is re-read and
/// checked against the paying customer, then a database-level conditional
/// UPDATE re-validates the remaining due against the latest committed
/// payments before the payment row is inserted — everything commits together
/// or rolls back together. The guard mirrors the checkout stock-deduction
/// guard in the billing repository, so concurrent payments cannot
/// collectively exceed a sale's total.
/// ---------------------------------------------------------------------------

final class DriftCustomerLedgerRepository implements CustomerLedgerRepository {
  DriftCustomerLedgerRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
    ConnectivityService? connectivityService,
    SupabaseClient? supabaseClient,
  }) : _dao = CustomerLedgerDao(database),
       _database = database,
       _outbox = outboxCoordinator,
       _connectivity = connectivityService,
       _supabase = supabaseClient;

  static const String tag = 'Ledger';

  /// Fixed row id in `sale_sequences` shared with billing checkout.
  static const String _receiptSequenceId = 'receipt';

  final CustomerLedgerDao _dao;
  final db.AppDatabase _database;
  final SyncOutboxCoordinator? _outbox;
  final ConnectivityService? _connectivity;
  final SupabaseClient? _supabase;

  Future<void> _requireOnline() async {
    if (_connectivity != null)
      await OnlineGuard(_connectivity!).requireOnline();
  }

  @override
  Future<CustomerLedgerSummary> summary(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final sales = await _dao.salesAggregateFor(customerId);
      final payments = await _dao.paymentsAggregateFor(customerId);
      final totalPurchases = sales?.totalPaise ?? 0;
      final totalPaid = payments?.totalPaise ?? 0;
      return CustomerLedgerSummary(
        customerId: customerId,
        totalPurchasesPaise: totalPurchases,
        totalPaidPaise: totalPaid,
        outstandingPaise: totalPurchases - totalPaid,
        purchaseCount: sales?.count ?? 0,
        paymentCount: payments?.count ?? 0,
      );
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load ledger summary', error, stackTrace);
    }
  }

  @override
  Future<List<CustomerPurchase>> purchases(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final sales = await _dao.salesFor(customerId);
      final paid = await _dao.paidPerSale(sales.map((sale) => sale.id));
      return [
        for (final sale in sales) _purchaseFrom(sale, paid[sale.id] ?? 0),
      ];
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load purchase history', error, stackTrace);
    }
  }

  @override
  Future<List<CustomerPayment>> payments(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final rows = await _dao.paymentsFor(customerId);
      return rows.map(_paymentFromRow).toList();
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payment history', error, stackTrace);
    }
  }

  @override
  Future<CustomerPayment> recordPayment({
    required String customerId,
    required String saleId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
    String? shopId,
  }) async {
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    if (_connectivity != null) {
      try {
        await _requireOnline();
      } catch (e) {
        throw UnexpectedLedgerFailure(
          'Internet connection required. Please check your connection and try again.',
        );
      }
    }
    final normalizedNote = _optionalText(note);
    final resolvedShopId = await resolveWritableShopId(_database, shopId);
    if (_supabase != null) {
      try {
        final res = await _supabase!.rpc<dynamic>(
          'record_customer_payment_atomic',
          params: {
            'p_shop_id': resolvedShopId,
            'p_customer_id': customerId,
            'p_sale_id': saleId,
            'p_amount_paise': amountPaise,
            'p_payment_method': paymentMethod.dbValue,
            'p_note': normalizedNote,
          },
        );
        final map = res is Map<String, dynamic>
            ? res
            : Map<String, dynamic>.from(res as Map);
        final paymentId = map['id'] as String;
        final paidAt = map['paid_at'] != null
            ? DateTime.parse(map['paid_at'] as String).toUtc()
            : DateTime.now().toUtc();
        // Mirror locally for cache (upsert)
        final now = DateTime.now().toUtc();
        await _database.transaction(() async {
          // Ensure sale exists locally for FK, if not, skip (cache may be stale)
          final sale = await _dao.saleById(saleId);
          if (sale != null) {
            // Update sale status if fully paid (check via RPC remaining)
            final remaining = map['remaining'] as int? ?? 0;
            if (remaining == 0 && sale.paymentStatus != 'PAID') {
              await (_database.update(
                _database.sales,
              )..where((t) => t.id.equals(saleId))).write(
                db.SalesCompanion(
                  paymentStatus: const Value('PAID'),
                  updatedAt: Value(now),
                ),
              );
            }
          }
          await _database
              .into(_database.customerPayments)
              .insertOnConflictUpdate(
                db.CustomerPaymentsCompanion.insert(
                  id: Value(paymentId),
                  shopId: Value(resolvedShopId),
                  customerId: customerId,
                  saleId: Value(saleId),
                  amountPaise: amountPaise,
                  paymentMethod: paymentMethod.dbValue,
                  note: Value(normalizedNote),
                  paidAt: paidAt,
                  reversed: const Value(false),
                  reversedAt: const Value(null),
                  createdAt: Value(paidAt),
                  updatedAt: Value(now),
                ),
              );
        });
        return CustomerPayment(
          id: paymentId,
          customerId: customerId,
          saleId: saleId,
          amountPaise: amountPaise,
          paymentMethod: paymentMethod,
          note: normalizedNote,
          paidAt: paidAt,
          reversed: false,
          reversedAt: null,
          createdAt: paidAt,
          updatedAt: now,
        );
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('SocketException') ||
            msg.contains('Failed host lookup'))
          throw UnexpectedLedgerFailure(
            'Internet connection required. Please check your connection and try again.',
          );
        if (msg.contains('INVALID_AMOUNT'))
          throw const InvalidPaymentAmountFailure();
        if (msg.contains('CUSTOMER_NOT_FOUND'))
          throw const CustomerNotFoundFailure();
        if (msg.contains('SALE_NOT_FOUND')) throw const SaleNotFoundFailure();
        if (msg.contains('PAYMENT_EXCEEDS_DUE'))
          throw const PaymentExceedsDueFailure();
        if (msg.contains('FORBIDDEN'))
          throw UnexpectedLedgerFailure('Access denied for this shop.');
        rethrow;
      }
    }
    try {
      final payment = await (_outbox == null
          ? _database.transaction(
              () => _recordPaymentCore(
                customerId,
                saleId,
                amountPaise,
                paymentMethod,
                normalizedNote,
                resolvedShopId,
              ),
            )
          : _outbox.run(
              write: () => _recordPaymentCore(
                customerId,
                saleId,
                amountPaise,
                paymentMethod,
                normalizedNote,
                resolvedShopId,
              ),
              snapshots: (payment, ctx) async => [
                OutboxAppend(
                  entity: MasterEntity.customerPayment,
                  entityId: payment.id,
                  payload: SyncCustomerPayment(
                    id: payment.id,
                    shopId: ctx.shopId,
                    customerId: payment.customerId,
                    saleId: payment.saleId,
                    amountPaise: payment.amountPaise,
                    paymentMethod: payment.paymentMethod.dbValue,
                    note: payment.note,
                    paidAt: payment.paidAt,
                    reversed: payment.reversed,
                    reversedAt: payment.reversedAt,
                    createdAt: payment.createdAt,
                  ).toJson(),
                ),
              ],
            ));
      return payment;
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to record payment', error, stackTrace);
    }
  }

  Future<CustomerPayment> _recordPaymentCore(
    String customerId,
    String saleId,
    int amountPaise,
    PaymentMethod paymentMethod,
    String? normalizedNote,
    String shopId,
  ) async {
    if (!await _dao.customerExists(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    final sale = await _dao.saleById(saleId);
    if (sale == null || sale.customerId != customerId) {
      throw const SaleNotFoundFailure();
    }

    final now = DateTime.now().toUtc();

    // Race-safe remaining-due guard: SQLite re-evaluates the subquery
    // against the latest committed payments at write time, so two
    // concurrent payments serialize — the loser matches zero rows here
    // and is rejected instead of overpaying the sale.
    final updated = await _database.customUpdate(
      'UPDATE sales SET updated_at = ? WHERE id = ? AND '
      'total_paise - (SELECT COALESCE(SUM(amount_paise), 0) '
      'FROM customer_payments WHERE sale_id = ? AND reversed = 0) >= ?',
      variables: [
        Variable.withDateTime(now),
        Variable.withString(saleId),
        Variable.withString(saleId),
        Variable.withInt(amountPaise),
      ],
      updateKind: UpdateKind.update,
    );
    if (updated != 1) {
      throw const PaymentExceedsDueFailure();
    }

    final id = const Uuid().v4();
    await _database
        .into(_database.customerPayments)
        .insert(
          db.CustomerPaymentsCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            customerId: customerId,
            saleId: Value(saleId),
            amountPaise: amountPaise,
            paymentMethod: paymentMethod.dbValue,
            note: Value(normalizedNote),
            paidAt: now,
            reversed: const Value(false),
            reversedAt: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Settle the AUTHORITATIVE bill state when this payment clears the
    // total: orders/receipt read sales.payment_status, so it must move
    // to PAID here — in the same transaction as the payment insert —
    // otherwise every derived view would keep showing a stale
    // "Not paid". Partial payments intentionally leave NOT_PAID (the
    // ledger already derives the partial amount from history), and a
    // fully-paid sale keeps its original receipt number and line items
    // untouched.
    final paidSoFar = await _database
        .customSelect(
          'SELECT COALESCE(SUM(amount_paise), 0) AS paid '
          'FROM customer_payments WHERE sale_id = ? AND reversed = 0',
          variables: [Variable.withString(saleId)],
        )
        .getSingle();
    final settled = (paidSoFar.data['paid'] as int? ?? 0) >= sale.totalPaise;
    if (settled && sale.paymentStatus != 'PAID') {
      await (_database.update(
        _database.sales,
      )..where((t) => t.id.equals(saleId))).write(
        db.SalesCompanion(
          paymentStatus: const Value('PAID'),
          paymentMethod: Value(paymentMethod.dbValue),
          updatedAt: Value(now),
        ),
      );
    }

    return CustomerPayment(
      id: id,
      customerId: customerId,
      saleId: saleId,
      amountPaise: amountPaise,
      paymentMethod: paymentMethod,
      note: normalizedNote,
      paidAt: now,
      reversed: false,
      reversedAt: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<List<CustomerPayment>> collectCustomerPayment({
    required String customerId,
    required String paymentGroupId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
    String? shopId,
  }) async {
    if (paymentGroupId.trim().isEmpty) {
      throw UnexpectedLedgerFailure('Payment group is required.');
    }
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    if (_connectivity != null) {
      try {
        await _requireOnline();
      } catch (e) {
        throw UnexpectedLedgerFailure(
          'Internet connection required. Please check your connection and try again.',
        );
      }
    }
    final normalizedNote = _optionalText(note);
    final resolvedShopId = await resolveWritableShopId(_database, shopId);
    if (_supabase != null) {
      try {
        final res = await _supabase!.rpc<dynamic>(
          'collect_customer_payment_atomic',
          params: {
            'p_shop_id': resolvedShopId,
            'p_customer_id': customerId,
            'p_group_id': paymentGroupId,
            'p_amount_paise': amountPaise,
            'p_payment_method': paymentMethod.dbValue,
            'p_note': normalizedNote,
          },
        );
        final map = res is Map<String, dynamic>
            ? res
            : Map<String, dynamic>.from(res as Map);
        final paymentsJson = map['payments'] as List? ?? const [];
        if (paymentsJson.isEmpty) {
          throw const PaymentExceedsDueFailure();
        }
        final now = DateTime.now().toUtc();
        // Mirror locally for cache (upsert). Replayed groups land on the same
        // rows thanks to insertOnConflictUpdate on the primary key.
        await _database.transaction(() async {
          for (final item in paymentsJson) {
            final paymentId = item['id'] as String;
            final saleId = item['sale_id'] as String;
            final paidAt = DateTime.parse(item['paid_at'] as String).toUtc();
            final saleStatus = item['sale_payment_status'] as String?;
            final sale = await _dao.saleById(saleId);
            if (sale != null && saleStatus == 'PAID') {
              if (sale.paymentStatus != 'PAID') {
                await (_database.update(
                  _database.sales,
                )..where((t) => t.id.equals(saleId))).write(
                  db.SalesCompanion(
                    paymentStatus: const Value('PAID'),
                    paymentMethod: Value(paymentMethod.dbValue),
                    updatedAt: Value(now),
                  ),
                );
              }
            }
            await _database
                .into(_database.customerPayments)
                .insertOnConflictUpdate(
                  db.CustomerPaymentsCompanion.insert(
                    id: Value(paymentId),
                    shopId: Value(resolvedShopId),
                    customerId: customerId,
                    saleId: Value(saleId),
                    paymentGroupId: Value(paymentGroupId),
                    amountPaise: item['amount_paise'] as int,
                    paymentMethod: paymentMethod.dbValue,
                    note: Value(normalizedNote),
                    paidAt: paidAt,
                    reversed: const Value(false),
                    reversedAt: const Value(null),
                    createdAt: Value(paidAt),
                    updatedAt: Value(now),
                  ),
                );
          }
        });
        return [
          for (final item in paymentsJson)
            CustomerPayment(
              id: item['id'] as String,
              customerId: customerId,
              saleId: item['sale_id'] as String,
              amountPaise: item['amount_paise'] as int,
              paymentMethod: paymentMethod,
              note: normalizedNote,
              paidAt: DateTime.parse(item['paid_at'] as String).toUtc(),
              reversed: false,
              reversedAt: null,
              paymentGroupId: paymentGroupId,
              createdAt: DateTime.parse(item['paid_at'] as String).toUtc(),
              updatedAt: now,
            ),
        ];
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('SocketException') ||
            msg.contains('Failed host lookup'))
          throw UnexpectedLedgerFailure(
            'Internet connection required. Please check your connection and try again.',
          );
        if (msg.contains('INVALID_AMOUNT'))
          throw const InvalidPaymentAmountFailure();
        if (msg.contains('CUSTOMER_NOT_FOUND'))
          throw const CustomerNotFoundFailure();
        if (msg.contains('PAYMENT_EXCEEDS_DUE'))
          throw const PaymentExceedsDueFailure();
        if (msg.contains('INVALID_PAYMENT_METHOD'))
          throw UnexpectedLedgerFailure('Invalid payment method.');
        if (msg.contains('FORBIDDEN'))
          throw UnexpectedLedgerFailure('Access denied for this shop.');
        rethrow;
      }
    }
    try {
      final payments = await (_outbox == null
          ? _database.transaction(
              () => _collectPaymentCore(
                customerId,
                paymentGroupId,
                amountPaise,
                paymentMethod,
                normalizedNote,
                resolvedShopId,
              ),
            )
          : _outbox.run(
              write: () => _collectPaymentCore(
                customerId,
                paymentGroupId,
                amountPaise,
                paymentMethod,
                normalizedNote,
                resolvedShopId,
              ),
              snapshots: (payments, ctx) async => [
                for (final payment in payments)
                  OutboxAppend(
                    entity: MasterEntity.customerPayment,
                    entityId: payment.id,
                    payload: SyncCustomerPayment(
                      id: payment.id,
                      shopId: ctx.shopId,
                      customerId: payment.customerId,
                      saleId: payment.saleId,
                      paymentGroupId: payment.paymentGroupId,
                      amountPaise: payment.amountPaise,
                      paymentMethod: payment.paymentMethod.dbValue,
                      note: payment.note,
                      paidAt: payment.paidAt,
                      reversed: payment.reversed,
                      reversedAt: payment.reversedAt,
                      createdAt: payment.createdAt,
                    ).toJson(),
                  ),
              ],
            ));
      return payments;
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to collect payment', error, stackTrace);
    }
  }

  /// Local persistence core for [collectCustomerPayment]. Runs inside one
  /// database transaction: the whole group commits or rolls back together.
  ///
  /// Allocations walk the customer's open bills oldest-first (the same queue
  /// the Receivables drill-down uses), so every collection clears debt from
  /// the oldest bill before touching the next. A bill fully cleared by the
  /// walk is flipped to PAID in the same transaction, keeping
  /// `sales.payment_status` authoritative everywhere.
  ///
  /// Replays are idempotent: if the [paymentGroupId] already has rows the
  /// collection was applied before, nothing is written and the existing rows
  /// are returned — a retried save can never double-charge a customer.
  Future<List<CustomerPayment>> _collectPaymentCore(
    String customerId,
    String paymentGroupId,
    int amountPaise,
    PaymentMethod paymentMethod,
    String? normalizedNote,
    String shopId,
  ) async {
    if (!await _dao.customerExists(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    final existing = await _dao.paymentsForGroup(paymentGroupId);
    if (existing.isNotEmpty) {
      return existing.map(_paymentFromRow).toList();
    }

    final openBills = await _dao.openCreditSalesFor(customerId);
    if (openBills.isEmpty) {
      throw const PaymentExceedsDueFailure();
    }
    final paidPerSale = await _dao.paidPerSale(openBills.map((s) => s.id));

    final now = DateTime.now().toUtc();
    var remainingTotal = 0;
    for (final sale in openBills) {
      remainingTotal += sale.totalPaise - (paidPerSale[sale.id] ?? 0);
    }
    if (amountPaise > remainingTotal) {
      throw const PaymentExceedsDueFailure();
    }

    var toAllocate = amountPaise;
    final created = <CustomerPayment>[];
    for (final sale in openBills) {
      if (toAllocate <= 0) break;
      final billRemaining = sale.totalPaise - (paidPerSale[sale.id] ?? 0);
      if (billRemaining <= 0) continue;
      final allocated = toAllocate < billRemaining ? toAllocate : billRemaining;
      final id = const Uuid().v4();
      await _database
          .into(_database.customerPayments)
          .insert(
            db.CustomerPaymentsCompanion.insert(
              id: Value(id),
              shopId: Value(shopId),
              customerId: customerId,
              saleId: Value(sale.id),
              paymentGroupId: Value(paymentGroupId),
              amountPaise: allocated,
              paymentMethod: paymentMethod.dbValue,
              note: Value(normalizedNote),
              paidAt: now,
              reversed: const Value(false),
              reversedAt: const Value(null),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      if (allocated >= billRemaining && sale.paymentStatus != 'PAID') {
        await (_database.update(
          _database.sales,
        )..where((t) => t.id.equals(sale.id))).write(
          db.SalesCompanion(
            paymentStatus: const Value('PAID'),
            paymentMethod: Value(paymentMethod.dbValue),
            updatedAt: Value(now),
          ),
        );
      }
      created.add(
        CustomerPayment(
          id: id,
          customerId: customerId,
          saleId: sale.id,
          amountPaise: allocated,
          paymentMethod: paymentMethod,
          note: normalizedNote,
          paidAt: now,
          reversed: false,
          reversedAt: null,
          paymentGroupId: paymentGroupId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      toAllocate -= allocated;
    }
    return created;
  }

  @override
  Future<void> recordOpeningDue({
    required String customerId,
    required int amountPaise,
    String? shopId,
  }) async {
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    if (!await _dao.customerExists(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    if (_connectivity != null) {
      try {
        await _requireOnline();
      } on OfflineException {
        throw const UnexpectedLedgerFailure(
          'Internet connection required. Please check your connection and try again.',
        );
      }
    }
    try {
      final resolvedShopId = await resolveWritableShopId(_database, shopId);
      final now = DateTime.now().toUtc();
      final supabase = _supabase;
      if (supabase != null) {
        // Cloud-authoritative: the atomic RPC validates the amount and
        // customer, mints the gapless cloud receipt and commits the flagged
        // row ON THE CLOUD first; the local mirror then copies the same
        // id/receipt so a later sync push can never race or duplicate it.
        try {
          final response = await supabase.rpc(
            'record_opening_due_atomic',
            params: <String, dynamic>{
              'p_shop_id': resolvedShopId,
              'p_customer_id': customerId,
              'p_amount_paise': amountPaise,
            },
          );
          final map = response as Map<String, dynamic>;
          await _database.transaction(
            () => _insertOpeningDue(
              resolvedShopId,
              customerId,
              amountPaise,
              now,
              id: map['id'] as String,
              receiptNumber: map['receipt_number'] as String,
              createdAt: DateTime.parse(map['created_at'] as String),
            ),
          );
          return;
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('SocketException') ||
              msg.contains('Failed host lookup')) {
            throw const UnexpectedLedgerFailure(
              'Internet connection required. Please check your connection and try again.',
            );
          }
          if (msg.contains('INVALID_AMOUNT')) {
            throw const InvalidPaymentAmountFailure();
          }
          if (msg.contains('CUSTOMER_NOT_FOUND')) {
            throw const CustomerNotFoundFailure();
          }
          if (msg.contains('INACTIVE_CUSTOMER')) {
            throw const UnexpectedLedgerFailure('This customer is inactive.');
          }
          if (msg.contains('FORBIDDEN')) {
            throw UnexpectedLedgerFailure('Access denied for this shop.');
          }
          rethrow;
        }
      }
      Future<db.Sale> insert() =>
          _insertOpeningDue(resolvedShopId, customerId, amountPaise, now);
      if (_outbox == null) {
        await _database.transaction(insert);
      } else {
        await _outbox.run(
          write: insert,
          // The entry is pushed with its opening-balance flag so the pulled
          // row stays a ledger entry (never a counter sale) on every device.
          snapshots: (sale, ctx) async => [
            OutboxAppend(
              entity: MasterEntity.sale,
              entityId: sale.id,
              payload: SyncSale(
                id: sale.id,
                shopId: ctx.shopId,
                customerId: sale.customerId,
                receiptNumber: sale.receiptNumber,
                subtotalPaise: sale.subtotalPaise,
                totalPaise: sale.totalPaise,
                paymentMethod: sale.paymentMethod,
                paymentStatus: sale.paymentStatus,
                createdAt: sale.createdAt,
                offerDiscountPaise: sale.offerDiscountPaise,
                isOpeningBalance: true,
              ).toJson(),
            ),
          ],
        );
      }
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to record opening due', error, stackTrace);
    }
  }

  Future<db.Sale> _insertOpeningDue(
    String shopId,
    String customerId,
    int amountPaise,
    DateTime now, {
    String? id,
    String? receiptNumber,
    DateTime? createdAt,
  }) async {
    final rowId = id ?? const Uuid().v4();
    final rowReceipt = receiptNumber ?? await _nextReceiptNumber(shopId);
    final rowCreated = createdAt ?? now;
    return _database
        .into(_database.sales)
        .insertReturning(
          db.SalesCompanion.insert(
            id: Value(rowId),
            shopId: Value(shopId),
            customerId: Value(customerId),
            receiptNumber: rowReceipt,
            subtotalPaise: amountPaise,
            totalPaise: amountPaise,
            offerDiscountPaise: const Value(0),
            paymentMethod: const Value(null),
            paymentStatus: const Value('NOT_PAID'),
            createdAt: Value(rowCreated),
            updatedAt: Value(now),
            voided: const Value(false),
            voidedAt: const Value(null),
            isOpeningBalance: const Value(true),
          ),
        );
  }

  @override
  Future<List<CustomerReceivable>> receivables({List<String>? shopIds}) async {
    try {
      return await _dao.receivables(shopIds);
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load receivables', error, stackTrace);
    }
  }

  @override
  Future<List<CustomerOutstandingBalance>> outstandingAsOf({
    required DateTime toUtc,
    List<String>? shopIds,
  }) async {
    try {
      return await _dao.outstandingAsOf(toUtc, shopIds);
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected(
        'Failed to load outstanding as of date',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<int> outstandingForCustomer(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final sales = await _dao.salesAggregateFor(customerId);
      final payments = await _dao.paymentsAggregateFor(customerId);
      return (sales?.totalPaise ?? 0) - (payments?.totalPaise ?? 0);
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected(
        'Failed to load outstanding balance',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<DueCustomersSummary> dueCustomersSummary() async {
    try {
      final sales = await _dao.salesTotalsByCustomer();
      final payments = await _dao.paymentsTotalByCustomer();
      var dueCustomerCount = 0;
      var totalOutstandingPaise = 0;
      for (final entry in sales.entries) {
        final outstanding = entry.value - (payments[entry.key] ?? 0);
        if (outstanding > 0) {
          dueCustomerCount += 1;
          totalOutstandingPaise += outstanding;
        }
      }
      return DueCustomersSummary(
        dueCustomerCount: dueCustomerCount,
        totalOutstandingPaise: totalOutstandingPaise,
      );
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected(
        'Failed to load due customers summary',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<String>> customerIdsWithDue() async {
    try {
      final sales = await _dao.salesTotalsByCustomer();
      final payments = await _dao.paymentsTotalByCustomer();
      return [
        for (final entry in sales.entries)
          if (entry.value - (payments[entry.key] ?? 0) > 0) entry.key,
      ]..sort();
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load due customers', error, stackTrace);
    }
  }

  /// Returns trimmed non-empty text, or null when blank.
  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Allocates a gapless, per-shop receipt reference for an opening-balance
  /// entry through the shared `sale_sequences` counter — the exact SQL the
  /// billing repository uses, so references never collide with counter
  /// receipts and the sequence heals over every existing `BF-` number.
  Future<String> _nextReceiptNumber(String shopId) async {
    await _database.customStatement(
      'INSERT OR IGNORE INTO sale_sequences (id, shop_id, next_value) VALUES (?, ?, 0)',
      [_receiptSequenceId, shopId],
    );
    final row = await _database
        .customSelect(
          'UPDATE sale_sequences SET next_value = ('
          '  SELECT MAX(x) FROM ('
          '    SELECT next_value + 1 AS x FROM sale_sequences WHERE id = ? AND shop_id = ?'
          '    UNION ALL'
          '    SELECT MAX(CAST(SUBSTR(receipt_number, ?) AS INTEGER)) + 1 AS x'
          '      FROM sales'
          '     WHERE receipt_number IS NOT NULL AND receipt_number LIKE ?'
          '       AND shop_id = ?'
          '    UNION ALL'
          '    SELECT 0 AS x'
          '  )'
          ') WHERE id = ? AND shop_id = ? RETURNING next_value',
          variables: [
            Variable.withString(_receiptSequenceId),
            Variable.withString(shopId),
            Variable.withInt(AppConstants.receiptPrefix.length + 1),
            Variable.withString('${AppConstants.receiptPrefix}%'),
            Variable.withString(shopId),
            Variable.withString(_receiptSequenceId),
            Variable.withString(shopId),
          ],
        )
        .getSingle();
    final nextValue = row.read<int>('next_value');
    return '${AppConstants.receiptPrefix}${nextValue.toString().padLeft(6, '0')}';
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedLedgerFailure();
  }

  static CustomerPurchase _purchaseFrom(db.Sale sale, int paidPaise) {
    // The authoritative `sales.payment_status` decides whether debt exists: a
    // PAID sale is settled at the counter and carries no due, regardless of
    // any ledger payment rows. Only NOT_PAID (credit) sales derive due from
    // their payments history.
    final isSettledAtCounter = sale.paymentStatus == 'PAID';
    final duePaise = isSettledAtCounter ? 0 : sale.totalPaise - paidPaise;
    final status = isSettledAtCounter
        ? SalePaymentStatus.paid
        : paidPaise <= 0
        ? SalePaymentStatus.unpaid
        : paidPaise >= sale.totalPaise
        ? SalePaymentStatus.paid
        : SalePaymentStatus.partial;
    return CustomerPurchase(
      saleId: sale.id,
      receiptNumber: sale.receiptNumber,
      customerId: sale.customerId!,
      createdAt: sale.createdAt,
      totalPaise: sale.totalPaise,
      paidPaise: isSettledAtCounter ? sale.totalPaise : paidPaise,
      duePaise: duePaise,
      status: status,
      isOpeningBalance: sale.isOpeningBalance,
    );
  }

  static CustomerPayment _paymentFromRow(db.CustomerPayment row) =>
      CustomerPayment(
        id: row.id,
        customerId: row.customerId,
        saleId: row.saleId!,
        amountPaise: row.amountPaise,
        paymentMethod: PaymentMethod.fromDbValue(row.paymentMethod)!,
        note: row.note,
        paidAt: row.paidAt,
        reversed: row.reversed,
        reversedAt: row.reversedAt,
        paymentGroupId: row.paymentGroupId,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
