import 'dart:async';

import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/sale_items_dao.dart';
import 'package:brewflow_pos/core/database/daos/sales_dao.dart';
import 'package:brewflow_pos/core/database/daos/shop_product_stock_dao.dart';
import 'package:brewflow_pos/core/database/daos/stock_movements_dao.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/data/billing_cloud_gateway.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Billing Repository
///
/// Implements [BillingRepository] on the local Drift database.
///
/// Checkout runs inside a single transaction: stock entities (products, and
/// variants for variant lines) are re-validated against the database
/// (existence, active flag, stock), stock is deducted with a database-level
/// `WHERE stock_quantity >= ?` guard on the exact entity the line sells, the
/// receipt sequence is consumed with UPDATE ... RETURNING, the sale header
/// plus snapshot line items are inserted, and one SALE stock movement per
/// line (with `referenceType = 'SALE'`, the sale id and the variant id when
/// the line sells a variant) is appended to the audit trail — everything
/// commits together or rolls back together.
///
/// Sync: when a [SyncOutboxCoordinator] is provided, the sale and sale items
/// are appended to the durable outbox IN THE SAME TRANSACTION as the business
/// change; without one the repository behaves exactly as before.
///
/// Movement semantics follow Phase 9 conventions: [quantity] is the signed
/// delta (`-line.quantity`), [stockBefore]/[stockAfter] are the absolute
/// levels observed inside the transaction, and the invariant
/// `stockAfter = stockBefore + quantity` holds for every row.
/// ---------------------------------------------------------------------------

final class DriftBillingRepository implements BillingRepository {
  DriftBillingRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
    ConnectivityService? connectivityService,
    BillingCloudGateway? cloudGateway,
  }) : _database = database,
       _sales = SalesDao(database),
       _saleItems = SaleItemsDao(database),
       _movements = StockMovementsDao(database),
       _shopStock = ShopProductStockDao(database),
       _outbox = outboxCoordinator,
       _connectivity = connectivityService,
       _cloud = cloudGateway;

  static const String tag = 'Billing';

  /// Fixed id of the single receipt-counter row in sale_sequences.
  static const String _receiptSequenceId = 'receipt';

  final db.AppDatabase _database;
  final SalesDao _sales;
  final SaleItemsDao _saleItems;
  final StockMovementsDao _movements;

  /// The per-business shelf overlay. Present so a Food Truck sale of a Cafe
  /// master product deducts the truck's own row instead of the Cafe's.
  final ShopProductStockDao _shopStock;
  final SyncOutboxCoordinator? _outbox;
  final ConnectivityService? _connectivity;
  final BillingCloudGateway? _cloud;

  @override
  Future<CompletedSale> completeSale({
    required List<CartLine> lines,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    PaymentMethod? paymentMethod,
    String? customerId,
    String? shopId,
    List<SalePayment>? payments,
  }) async {
    if (lines.isEmpty) {
      throw const EmptyCartFailure();
    }
    if (paymentStatus == PaymentStatus.notPaid && customerId == null) {
      throw const MissingCustomerForCreditSaleFailure();
    }
    if (paymentStatus == PaymentStatus.paid &&
        paymentMethod == null &&
        (payments == null || payments.isEmpty)) {
      // A split sale carries its payment in [payments] and has no single
      // [paymentMethod] by design, so requiring the method here rejected every
      // split with INVALID_PAYMENT even though the legs were valid. Mirrors the
      // guard in the controller.
      throw const InvalidPaymentFailure();
    }
    if (payments != null && payments.isNotEmpty) {
      final legSum = payments.fold<int>(0, (acc, p) => acc + p.amountPaise);
      final legTotal = Money.sumPaise(payments.map((p) => p.amountPaise));
      if (legTotal == null || legSum != legTotal) {
        // Defensive: `legSum` can only exceed the ceiling by overflowing the
        // per-leg range, but a split total above the ceiling is unrepresentable
        // and must be rejected rather than written.
        throw const UnexpectedBillingFailure(
          'Split payments exceed the safe ceiling.',
        );
      }
      if (payments.any((p) => p.amountPaise <= 0)) {
        // `sale_payments.amount_paise` has CHECK (> 0); a zero or negative leg
        // would abort the whole sale at the insert, so reject it with a reason.
        throw const InvalidPaymentFailure();
      }
      if (payments.length < SplitPaymentDraft.minLegs) {
        // A single instrument is an ordinary payment, not a split. Enforced
        // here as well as in the editor so a caller that bypasses the UI cannot
        // persist a one-row "split" and have it read back as split tender.
        throw const InvalidPaymentFailure();
      }
      if (payments.any(
        (p) =>
            p.paymentMethod != PaymentMethod.cash &&
            p.paymentMethod != PaymentMethod.upi,
      )) {
        // The counter takes CASH and UPI. BANK remains a valid historical value
        // on a single-method sale, but it is not a split instrument.
        throw const InvalidPaymentFailure();
      }
    }
    // Online-only guard: reject when internet is unavailable before any mutation.
    if (_connectivity != null) {
      try {
        await OnlineGuard(_connectivity!).requireOnline();
      } on OfflineException catch (e) {
        // Billing is online-only, so a "sale not completed" on a flaky Wi-Fi
        // is the single most common report; recorded before it is translated
        // into the user-safe message, which on its own hides the cause.
        AppTrace.warn('sale.offline_blocked', {'lines': lines.length});
        throw UnexpectedBillingFailure(e.message);
      }
    }
    try {
      // The cart carries product/variant ids but no shop scope (the domain
      // Product model drops shopId). Resolving the write shop purely from the
      // profile can therefore send a different shop_id than the one owning
      // the shelf products, and `create_sale_atomic` correctly rejects the
      // lines with UNAVAILABLE_PRODUCT. Derive the shop from the actual stock
      // entities instead: every line must agree on one shop, and that shop
      // becomes the RPC scope. An explicit [shopId] still wins (tests,
      // callers with context) and additionally permits lines the selling
      // business has been shared, which is what makes a Food Truck sale of a
      // Cafe master product legal.
      final entityShopId = await _shopIdForLines(lines, sellingShopId: shopId);
      final resolvedShopId = await resolveWritableShopId(
        _database,
        shopId ?? entityShopId,
      );
      // Traced at the repository boundary because this is the last point where
      // the sale's scope is still a variable: `is_shop_member()` receives
      // exactly this value, so a FORBIDDEN rejection is attributable from the
      // log alone. `route` is the other half of the question — whether a sale
      // went to the server or to local SQLite decides which failure a shop
      // owner should expect to see in the cloud at all.
      AppTrace.event('sale.route', {
        'route': _cloud == null ? 'local' : 'cloud',
        'shopRef': AppTrace.userRef(resolvedShopId),
        'requestedShopRef': AppTrace.userRef(shopId),
        'entityShopRef': AppTrace.userRef(entityShopId),
        'lines': lines.length,
      });
      if (entityShopId != null && entityShopId != resolvedShopId) {
        AppTrace.warn('sale.shop_mismatch', {
          'resolvedShopRef': AppTrace.userRef(resolvedShopId),
          'entityShopRef': AppTrace.userRef(entityShopId),
        });
        throw const UnexpectedBillingFailure(
          'Cart products belong to a different shop.',
        );
      }

      // Cloud-authoritative path when gateway is wired.
      if (_cloud != null) {
        return await _completeSaleViaCloud(
          lines: lines,
          paymentStatus: paymentStatus,
          paymentMethod: paymentMethod,
          customerId: customerId,
          shopId: resolvedShopId,
          payments: payments,
        );
      }

      if (_outbox == null) {
        return await _database.transaction(
          () => _checkoutCore(
            lines,
            paymentStatus,
            paymentMethod,
            customerId,
            resolvedShopId,
            payments: payments,
          ),
        );
      }
      return await _outbox.run(
        write: () => _checkoutCore(
          lines,
          paymentStatus,
          paymentMethod,
          customerId,
          resolvedShopId,
          payments: payments,
        ),
        snapshots: (result, ctx) async {
          final appends = <OutboxAppend>[
            OutboxAppend(
              entity: MasterEntity.sale,
              entityId: result.sale.id,
              payload: SyncSale(
                id: result.sale.id,
                shopId: ctx.shopId,
                customerId: result.sale.customerId,
                receiptNumber: result.sale.receiptNumber,
                subtotalPaise: result.sale.subtotalPaise,
                totalPaise: result.sale.totalPaise,
                paymentMethod: result.sale.paymentMethod?.dbValue,
                paymentStatus: result.sale.paymentStatus.dbValue,
                createdAt: result.sale.createdAt,
                offerDiscountPaise: result.sale.offerDiscountPaise,
              ).toJson(),
            ),
          ];
          for (final item in result.items) {
            appends.add(
              OutboxAppend(
                entity: MasterEntity.saleItem,
                entityId: item.id,
                payload: SyncSaleItem(
                  id: item.id,
                  shopId: ctx.shopId,
                  saleId: item.saleId,
                  productId: item.productId,
                  variantId: item.variantId,
                  productName: item.productName,
                  variantName: item.variantName,
                  sku: item.sku,
                  unitPricePaise: item.unitPricePaise,
                  quantity: item.quantity,
                  lineTotalPaise: item.lineTotalPaise,
                  offerDiscountPaise: item.offerDiscountPaise,
                  appliedOfferId: item.appliedOfferId,
                  appliedOfferName: item.appliedOfferName,
                  appliedOfferType: item.appliedOfferType?.wire,
                ).toJson(),
              ),
            );
          }

          // The checkout deducted inventory for every tracked line. Those
          // stock changes live only on this device unless a Product /
          // ProductVariant row is enqueued with the reduced levels, so append
          // them here — inside the same transaction — to propagate to the
          // cloud and, from there, to the other device. Untracked (NONE) lines
          // were never deducted and contribute nothing. Recipe lines deducted
          // their INGREDIENTS, not their own rows, so the enqueued rows are
          // the ingredients' — otherwise the deducted levels would never
          // reach the cloud.
          final plainProductIds = <String>{};
          final plainVariantIds = <String>{};
          final ingredientProductIds = <String>{};
          final ingredientVariantIds = <String>{};
          for (final item in result.items) {
            final recipes = await _recipesForSaleLine(
              productId: item.productId,
              variantId: item.variantId,
              shopId: ctx.shopId,
            );
            if (recipes.isEmpty) {
              plainProductIds.add(item.productId);
              if (item.variantId != null) {
                plainVariantIds.add(item.variantId!);
              }
            } else {
              for (final recipe in recipes) {
                ingredientProductIds.add(recipe.ingredientProductId);
                if (recipe.ingredientVariantId != null) {
                  ingredientVariantIds.add(recipe.ingredientVariantId!);
                }
              }
            }
          }
          final productIds = {...plainProductIds, ...ingredientProductIds};
          final affectedProducts = <String, db.Product>{
            for (final row in await (_database.select(
              _database.products,
            )..where((t) => t.id.isIn(productIds))).get())
              row.id: row,
          };
          final variantIds = {...plainVariantIds, ...ingredientVariantIds};
          final variants = variantIds.isEmpty
              ? const <db.ProductVariant>[]
              : await (_database.select(
                  _database.productVariants,
                )..where((t) => t.id.isIn(variantIds))).get();
          final variantsById = {for (final v in variants) v.id: v};

          for (final product in affectedProducts.values) {
            final tracked = product.stockUnit != StockUnit.none.dbValue;
            final hasVariants = variantsById.values.any(
              (v) => v.productId == product.id,
            );
            if (!tracked) {
              continue;
            }
            if (hasVariants) {
              for (final variant in variantsById.values.where(
                (v) => v.productId == product.id,
              )) {
                appends.add(_stockVariantAppend(variant, ctx));
              }
            } else {
              appends.add(_stockProductAppend(product, ctx));
            }
          }
          return appends;
        },
      );
    } on BillingFailure {
      rethrow;
    } on OfflineException catch (e) {
      throw UnexpectedBillingFailure(e.message);
    } on Exception catch (error, stackTrace) {
      AppLog.error(
        'Failed to complete sale',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedBillingFailure();
    }
  }

  Future<CompletedSale> _completeSaleViaCloud({
    required List<CartLine> lines,
    required PaymentStatus paymentStatus,
    PaymentMethod? paymentMethod,
    String? customerId,
    required String shopId,
    List<SalePayment>? payments,
  }) async {
    final cloud = _cloud!;
    // Compute money totals as in _checkoutCore to send to RPC
    final subtotal = Money.sumPaise(
      lines.map((l) => Money.multiplyPaise(l.unitPricePaise, l.quantity)!),
    );
    if (subtotal == null) {
      throw const UnexpectedBillingFailure(
        'Sale total exceeds the safe ceiling.',
      );
    }
    final totalOfferDiscount = lines.fold(
      0,
      (sum, line) => sum + (line.appliedOffer?.discountPaise ?? 0),
    );
    final totalPaise = (subtotal - totalOfferDiscount).clamp(0, subtotal);

    // Same re-check as the local path, before the RPC is called: a mismatched
    // split must not reach the server (and must not burn a receipt number).
    final cloudLegSum = payments == null || payments.isEmpty
        ? null
        : payments.fold<int>(0, (acc, p) => acc + p.amountPaise);
    if (cloudLegSum != null && cloudLegSum != totalPaise) {
      throw UnexpectedBillingFailure(
        cloudLegSum < totalPaise
            ? 'Split payments are ${Money.formatPaise(totalPaise - cloudLegSum)} short.'
            : 'Split payments exceed the total by '
                  '${Money.formatPaise(cloudLegSum - totalPaise)}.',
      );
    }

    final rpcLines = [
      for (final line in lines)
        {
          'product_id': line.productId,
          'variant_id': line.variantId,
          'product_name': line.productName,
          'variant_name': line.variantName,
          'sku': line.sku,
          'unit_price_paise': line.unitPricePaise,
          'quantity': line.quantity,
          'line_total_paise': Money.multiplyPaise(
            line.unitPricePaise,
            line.quantity,
          )!,
          'offer_discount_paise': line.appliedOffer?.discountPaise ?? 0,
          'applied_offer_id': line.appliedOffer?.offerId,
          'applied_offer_name': line.appliedOffer?.offerName,
          'applied_offer_type': line.appliedOffer?.offerType.wire,
        },
    ];

    // The RPC expects a single method OR a leg list. A split sale has legs and
    // no single method, so `paymentMethod!.dbValue` threw a null-check error
    // that bypassed every failure mapping below, and `payments` was never
    // passed at all — the server would have persisted a split with no
    // `sale_payments` rows. Send exactly one of the two shapes.
    final rpcPayments = payments == null || payments.isEmpty
        ? null
        : [
            for (final p in payments)
              {
                'payment_method': p.paymentMethod.dbValue,
                'amount_paise': p.amountPaise,
              },
          ];

    Map<String, dynamic> result;
    try {
      result = await cloud.createSaleAtomic(
        shopId: shopId,
        customerId: customerId,
        subtotalPaise: subtotal,
        totalPaise: totalPaise,
        offerDiscountPaise: totalOfferDiscount,
        paymentMethod: paymentStatus == PaymentStatus.notPaid
            ? null
            : (rpcPayments == null ? paymentMethod?.dbValue : null),
        paymentStatus: paymentStatus.dbValue,
        lines: rpcLines,
        payments: rpcPayments,
      );
    } catch (e) {
      if (e is TimeoutException) {
        throw const UnexpectedBillingFailure(
          'The server is taking too long to respond. Please try again.',
        );
      }
      final msg = e.toString();
      if (msg.contains('INSUFFICIENT_STOCK')) {
        final name = msg.split(':').length > 1
            ? msg.split(':')[1].trim()
            : 'Product';
        throw InsufficientStockFailure(name, msg);
      }
      if (msg.contains('UNAVAILABLE_PRODUCT')) {
        final name = msg.split(':').length > 1
            ? msg.split(':')[1].trim()
            : 'Product';
        throw UnavailableProductFailure(name);
      }
      if (msg.contains('MISSING_CUSTOMER'))
        throw const MissingCustomerForCreditSaleFailure();
      if (msg.contains('INVALID_PAYMENT')) throw const InvalidPaymentFailure();
      if (msg.contains('SPLIT_PAYMENT_MISMATCH')) {
        // The server re-checks the leg sum, so a mismatch here means the local
        // draft and the committed total disagreed — name it rather than
        // falling through to an opaque "something went wrong".
        throw const UnexpectedBillingFailure(
          'Split payments do not match the bill total.',
        );
      }
      if (msg.contains('EMPTY_CART')) throw const EmptyCartFailure();
      if (msg.contains('CUSTOMER_NOT_FOUND'))
        throw const CustomerNotFoundFailure();
      if (msg.contains('INACTIVE_CUSTOMER'))
        throw const InactiveCustomerFailure();
      if (msg.contains('FORBIDDEN'))
        throw const UnexpectedBillingFailure('Access denied for this shop.');
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Network is unreachable')) {
        throw const UnexpectedBillingFailure(
          'Internet connection required. Please check your connection and try again.',
        );
      }
      rethrow;
    }

    final saleId = result['id'] as String;
    final receiptNumber = result['receipt_number'] as String;
    final createdAt = result['created_at'] != null
        ? DateTime.parse(result['created_at'] as String).toUtc()
        : DateTime.now().toUtc();

    // Mirror to local Drift cache so existing UI (which reads Drift) stays consistent.
    final sale = Sale(
      id: saleId,
      receiptNumber: receiptNumber,
      subtotalPaise: subtotal,
      totalPaise: totalPaise,
      offerDiscountPaise: totalOfferDiscount,
      paymentStatus: paymentStatus,
      // A split has no single method; the legs live in `sale_payments`.
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : (payments != null && payments.isNotEmpty ? null : paymentMethod),
      createdAt: createdAt,
      updatedAt: createdAt,
      customerId: customerId,
      payments: payments ?? const [],
    );

    final saleItems = <SaleItem>[];
    final movementsToInsert = <db.StockMovementsCompanion>[];

    // Item ids are preallocated so the local cache failure path below can
    // still present the completed bill to the UI.
    final itemIds = [for (var _ in lines) const Uuid().v4()];

    try {
      await _database.transaction(() async {
        // Update stock locally to match server deduction (tracked only).
        // Each line is best-effort: a missing local row (product not yet
        // synced) or a stock-unit mismatch never blocks the sale or the
        // remaining lines. The server RPC is authoritative for stock; local
        // reconciliation happens via sync pull.
        for (final line in lines) {
          try {
            final isTracked = await _isTracked(line.productId);
            if (!isTracked) continue;
            int updated = 0;
            if (line.variantId != null) {
              updated = await _database.customUpdate(
                'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
                variables: [
                  Variable.withInt(line.quantity),
                  Variable.withString(createdAt.toIso8601String()),
                  Variable.withString(line.variantId!),
                ],
                updateKind: UpdateKind.update,
              );
            } else {
              updated = await _database.customUpdate(
                'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
                variables: [
                  Variable.withInt(line.quantity),
                  Variable.withString(createdAt.toIso8601String()),
                  Variable.withString(line.productId),
                ],
                updateKind: UpdateKind.update,
              );
            }
            if (updated == 0) {
              // Row not found locally — skip movement; sync pull will
              // bring the server-decremented stock on the next cycle.
              AppLog.info(
                'Local stock mirror skipped (row not found locally): ${line.productId}',
                tag: tag,
              );
              continue;
            }
            // Create local movement entry mirroring server.
            final stockBefore = await _localStockBefore(line);
            movementsToInsert.add(
              db.StockMovementsCompanion.insert(
                shopId: Value(shopId),
                productId: line.productId,
                variantId: Value(line.variantId),
                movementType: StockMovementType.sale.dbValue,
                quantity: -line.quantity,
                stockBefore: stockBefore,
                stockAfter: stockBefore - line.quantity,
                referenceType: Value(StockMovementType.sale.dbValue),
                referenceId: Value(saleId),
                createdAt: Value(createdAt),
                updatedAt: Value(createdAt),
              ),
            );
          } catch (error, stackTrace) {
            // Never let a single line's local stock failure abort the
            // entire mirror. The server RPC already committed the stock
            // deduction; the next sync pull reconciles any gap.
            AppLog.warning(
              'Local stock mirror failed for line ${line.productId}',
              tag: tag,
              error: error,
              stackTrace: stackTrace,
            );
          }
        }

        await _database
            .into(_database.sales)
            .insert(
              db.SalesCompanion.insert(
                id: Value(saleId),
                shopId: Value(shopId),
                receiptNumber: receiptNumber,
                customerId: Value(customerId),
                subtotalPaise: subtotal,
                totalPaise: totalPaise,
                offerDiscountPaise: Value(totalOfferDiscount),
                paymentMethod: Value(
                  paymentStatus == PaymentStatus.notPaid
                      ? null
                      : (payments != null && payments.isNotEmpty
                            ? null
                            : paymentMethod?.dbValue),
                ),
                paymentStatus: Value(paymentStatus.dbValue),
                createdAt: Value(createdAt),
                updatedAt: Value(createdAt),
              ),
            );

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final itemId = itemIds[i];
          await _database
              .into(_database.saleItems)
              .insert(
                db.SaleItemsCompanion.insert(
                  id: Value(itemId),
                  shopId: Value(shopId),
                  saleId: saleId,
                  productId: line.productId,
                  variantId: Value(line.variantId),
                  productName: line.productName,
                  variantName: Value(line.variantName),
                  sku: Value(line.sku),
                  unitPricePaise: line.unitPricePaise,
                  quantity: line.quantity,
                  lineTotalPaise: Money.multiplyPaise(
                    line.unitPricePaise,
                    line.quantity,
                  )!,
                  offerDiscountPaise: Value(
                    line.appliedOffer?.discountPaise ?? 0,
                  ),
                  appliedOfferId: Value(line.appliedOffer?.offerId),
                  appliedOfferName: Value(line.appliedOffer?.offerName),
                  appliedOfferType: Value(line.appliedOffer?.offerType.wire),
                ),
              );
          saleItems.add(
            SaleItem(
              id: itemId,
              saleId: saleId,
              productId: line.productId,
              productName: line.productName,
              unitPricePaise: line.unitPricePaise,
              quantity: line.quantity,
              lineTotalPaise: Money.multiplyPaise(
                line.unitPricePaise,
                line.quantity,
              )!,
              offerDiscountPaise: line.appliedOffer?.discountPaise ?? 0,
              sku: line.sku,
              variantId: line.variantId,
              variantName: line.variantName,
              appliedOfferId: line.appliedOffer?.offerId,
              appliedOfferName: line.appliedOffer?.offerName,
              appliedOfferType: line.appliedOffer?.offerType,
            ),
          );
        }

        if (movementsToInsert.isNotEmpty) {
          await _movements.insertAll(movementsToInsert);
        }

        // Mirror the legs too, so an offline read of this sale shows the same
        // split the server recorded rather than a header with no method.
        if (payments != null && payments.isNotEmpty) {
          await _database.batch((batch) {
            batch.insertAll(_database.salePayments, [
              for (final p in payments)
                db.SalePaymentsCompanion.insert(
                  saleId: saleId,
                  paymentMethod: p.paymentMethod.dbValue,
                  amountPaise: p.amountPaise,
                  createdAt: Value(createdAt),
                ),
            ]);
          });
        }
      });
    } catch (error, stackTrace) {
      // The cloud sale is already committed; the transaction rolled back
      // cleanly, so nothing partial was cached. A local cache failure must
      // never surface as a failed sale — a retry would duplicate the sale
      // server-side. Instead log and present the completed bill from the
      // server result; the next sync reconciles the cache.
      AppLog.warning(
        'Cloud sale $saleId committed but local cache mirror failed; sync will reconcile',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        saleItems.add(
          SaleItem(
            id: itemIds[i],
            saleId: saleId,
            productId: line.productId,
            productName: line.productName,
            unitPricePaise: line.unitPricePaise,
            quantity: line.quantity,
            lineTotalPaise: Money.multiplyPaise(
              line.unitPricePaise,
              line.quantity,
            )!,
            offerDiscountPaise: line.appliedOffer?.discountPaise ?? 0,
            sku: line.sku,
            variantId: line.variantId,
            variantName: line.variantName,
            appliedOfferId: line.appliedOffer?.offerId,
            appliedOfferName: line.appliedOffer?.offerName,
            appliedOfferType: line.appliedOffer?.offerType,
          ),
        );
      }
    }

    return CompletedSale(sale: sale, items: saleItems);
  }

  Future<bool> _isTracked(String productId) async {
    final row = await (_database.select(
      _database.products,
    )..where((t) => t.id.equals(productId))).getSingleOrNull();
    if (row == null) return false;
    return row.stockUnit != StockUnit.none.dbValue;
  }

  Future<int> _localStockBefore(CartLine line) async {
    // After deduction above, stock = before - qty, so before = after + qty
    if (line.variantId != null) {
      final row = await (_database.select(
        _database.productVariants,
      )..where((t) => t.id.equals(line.variantId!))).getSingleOrNull();
      final after = row?.stockQuantity ?? 0;
      return after + line.quantity;
    } else {
      final row = await (_database.select(
        _database.products,
      )..where((t) => t.id.equals(line.productId))).getSingleOrNull();
      final after = row?.stockQuantity ?? 0;
      return after + line.quantity;
    }
  }

  /// The selling business's own quantity for one shared sellable unit.
  ///
  /// Returns 0 when the business has no shelf row for it. That is the
  /// not-carried state, and it is deliberately indistinguishable from a real
  /// zero here: both mean the till must refuse the line, and neither may fall
  /// back to the owner's number.
  Future<int> _overlayStock({
    required String shopId,
    required String productId,
    String? variantId,
  }) async {
    final row = await _shopStock.find(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
    );
    return row?.quantity ?? 0;
  }

  /// Recipe rows applying to one sale line in the selling shop. A row with a
  /// null `variant_id` maps every variant of the product; a row naming a
  /// variant applies only to that variant's lines.
  Future<List<db.ProductRecipe>> _recipesForSaleLine({
    required String productId,
    required String? variantId,
    required String shopId,
  }) async {
    final rows =
        await (_database.select(_database.productRecipes)..where(
              (t) => t.productId.equals(productId) & t.shopId.equals(shopId),
            ))
            .get();
    return [
      for (final row in rows)
        if (row.variantId == null || row.variantId == variantId) row,
    ];
  }

  Future<CompletedSale> _checkoutCore(
    List<CartLine> lines,
    PaymentStatus paymentStatus,
    PaymentMethod? paymentMethod,
    String? customerId,
    String shopId, {
    List<SalePayment>? payments,
  }) async {
    final now = DateTime.now().toUtc();
    final saleId = const Uuid().v4();

    // Re-validate the customer before anything is written, so a bad
    // customer reference never consumes a receipt number or stock.
    await _validateCustomer(customerId);

    // Re-validate every line against the current database, never the cart.
    final entitiesByKey = await _entitiesById(lines);
    final ordered = <({CartLine line, int lineTotal})>[];
    final movements = <db.StockMovementsCompanion>[];
    // Aggregated ingredient needs across ALL lines: one menu product can
    // appear on several lines (Plain + Cheese + Egg + Veg Maggi sharing one
    // Maggi Packet), so ingredients are deducted once per ingredient AFTER
    // every line validates — never once per line.
    final recipeNeeds = <(String, String?), int>{};
    final recipeNames = <(String, String?), String>{};
    for (final line in lines) {
      final entity = entitiesByKey[line.keyId];
      final product = entity?.product;
      final variant = entity?.variant;
      if (product == null || !product.isActive) {
        throw UnavailableProductFailure(line.productName);
      }
      // A variant line must reference an existing, active variant; a plain
      // line must not be double-deducted through a stale variant reference.
      if (line.variantId != null && (variant == null || !variant.isActive)) {
        throw UnavailableProductFailure(line.productName);
      }
      // Shared-stock recipes: a line for a product WITH recipe rows consumes
      // ONLY its ingredients — its own `stock_quantity` is never touched,
      // however tracked it is. Rows are scoped to the selling shop; a
      // product with no rows here sells from its own stock exactly as before.
      final recipeRows = await _recipesForSaleLine(
        productId: line.productId,
        variantId: line.variantId,
        shopId: shopId,
      );
      for (final row in recipeRows) {
        final key = (row.ingredientProductId, row.ingredientVariantId);
        recipeNeeds[key] =
            (recipeNeeds[key] ?? 0) + row.quantity * line.quantity;
        recipeNames.putIfAbsent(key, () => line.productName);
      }
      // stockUnit NONE = made-to-order / untracked: never stock-guarded,
      // never deducted, never moved. The schema documents this semantic;
      // checkout simply skips the inventory leg for such products.
      // Recipe lines bypass it entirely through the ingredient leg below.
      final tracked =
          recipeRows.isEmpty && product.stockUnit != StockUnit.none.dbValue;
      // Which shelf this sale draws from. A product the selling business OWNS
      // deducts its own `stock_quantity` exactly as before. A product owned by
      // another business (a Cafe master the Cafe shared into the Food Truck)
      // must deduct the SELLING business's `shop_product_stock` row and leave
      // the owner's number untouched — that separation is the whole point of
      // the overlay, and deducting the Cafe's row here is precisely how a
      // truck sale would eat the Cafe's stock.
      final usesOverlay = product.shopId != null && product.shopId != shopId;
      final int stockEntityStock;
      if (tracked) {
        stockEntityStock = usesOverlay
            ? await _overlayStock(
                shopId: shopId,
                productId: line.productId,
                variantId: line.variantId,
              )
            : (variant?.stockQuantity ?? product.stockQuantity);
        if (stockEntityStock < line.quantity) {
          throw InsufficientStockFailure(line.productName);
        }
      } else {
        stockEntityStock = 0;
      }
      final lineTotal = Money.multiplyPaise(line.unitPricePaise, line.quantity);
      if (lineTotal == null) {
        throw const UnexpectedBillingFailure(
          'Line total exceeds the safe ceiling.',
        );
      }

      // Conditional, race-safe deduction on the exact stock entity the line
      // sells: the guard is re-evaluated by SQLite against the committed
      // value at write time. A concurrent change that leaves insufficient
      // stock makes this update match zero rows. Untracked (NONE) products
      // skip deduction and the SALE movement entirely — no artificial
      // inventory is ever created for made-to-order items.
      if (tracked) {
        if (usesOverlay) {
          // The selling business's own shelf, with the same conditional guard.
          // A missing row returns null, which the stock check above has already
          // turned into an InsufficientStockFailure — a business that does not
          // carry a unit cannot conjure one by selling it.
          final after = await _shopStock.deductQuantity(
            shopId: shopId,
            productId: line.productId,
            variantId: line.variantId,
            delta: line.quantity,
          );
          if (after == null) {
            throw InsufficientStockFailure(line.productName);
          }
        } else {
          final int updated;
          if (variant != null) {
            updated =
                await (_database.update(_database.productVariants)..where(
                      (t) =>
                          t.id.equals(variant.id) &
                          t.stockQuantity.isBiggerOrEqualValue(line.quantity),
                    ))
                    .write(
                      db.ProductVariantsCompanion(
                        stockQuantity: Value(
                          variant.stockQuantity - line.quantity,
                        ),
                        updatedAt: Value(now),
                      ),
                    );
          } else {
            updated =
                await (_database.update(_database.products)..where(
                      (t) =>
                          t.id.equals(line.productId) &
                          t.stockQuantity.isBiggerOrEqualValue(line.quantity),
                    ))
                    .write(
                      db.ProductsCompanion(
                        stockQuantity: Value(
                          product.stockQuantity - line.quantity,
                        ),
                        updatedAt: Value(now),
                      ),
                    );
          }
          if (updated != 1) {
            throw InsufficientStockFailure(line.productName);
          }
        }
      }

      ordered.add((line: line, lineTotal: lineTotal));

      // One SALE movement per tracked line, inside the same transaction.
      // stockBefore is the level read at validation (the cart guarantees each
      // stock entity appears in exactly one line), and stockAfter is the
      // value the deduction just committed to — so
      // `stockAfter = stockBefore + quantity` holds by construction. The sale
      // id links the movement to its sale for audit purposes (no FK by
      // design). Untracked lines record no movement at all.
      if (tracked) {
        movements.add(
          db.StockMovementsCompanion.insert(
            shopId: Value(shopId),
            productId: line.productId,
            variantId: Value(line.variantId),
            movementType: StockMovementType.sale.dbValue,
            quantity: -line.quantity,
            stockBefore: stockEntityStock,
            stockAfter: stockEntityStock - line.quantity,
            reason: const Value(null),
            note: const Value(null),
            referenceType: Value(StockMovementType.sale.dbValue),
            referenceId: Value(saleId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    }

    // Shared-stock ingredient leg: one conditional, race-safe deduction per
    // ingredient over the AGGREGATED need. The guard is re-evaluated by
    // SQLite at write time (same convention as the own-stock leg above),
    // so concurrent sales cannot drive a shared source negative: the loser
    // matches zero rows and the whole sale rolls back with
    // InsufficientStockFailure, leaving no partial deduction behind.
    for (final entry in recipeNeeds.entries) {
      final (ingredientProductId, ingredientVariantId) = entry.key;
      final need = entry.value;
      final name = recipeNames[entry.key] ?? 'Item';
      final int level;
      if (ingredientVariantId != null) {
        final row = await (_database.select(
          _database.productVariants,
        )..where((t) => t.id.equals(ingredientVariantId))).getSingleOrNull();
        if (row == null || !row.isActive) {
          throw UnavailableProductFailure(name);
        }
        level = row.stockQuantity;
      } else {
        final row = await (_database.select(
          _database.products,
        )..where((t) => t.id.equals(ingredientProductId))).getSingleOrNull();
        if (row == null || !row.isActive) {
          throw UnavailableProductFailure(name);
        }
        level = row.stockQuantity;
      }
      if (level < need) {
        throw InsufficientStockFailure(name);
      }
      final int updated;
      if (ingredientVariantId != null) {
        updated =
            await (_database.update(_database.productVariants)..where(
                  (t) =>
                      t.id.equals(ingredientVariantId) &
                      t.stockQuantity.isBiggerOrEqualValue(need),
                ))
                .write(
                  db.ProductVariantsCompanion(
                    stockQuantity: Value(level - need),
                    updatedAt: Value(now),
                  ),
                );
      } else {
        updated =
            await (_database.update(_database.products)..where(
                  (t) =>
                      t.id.equals(ingredientProductId) &
                      t.stockQuantity.isBiggerOrEqualValue(need),
                ))
                .write(
                  db.ProductsCompanion(
                    stockQuantity: Value(level - need),
                    updatedAt: Value(now),
                  ),
                );
      }
      if (updated != 1) {
        throw InsufficientStockFailure(name);
      }
      movements.add(
        db.StockMovementsCompanion.insert(
          shopId: Value(shopId),
          productId: ingredientProductId,
          variantId: Value(ingredientVariantId),
          movementType: StockMovementType.sale.dbValue,
          quantity: -need,
          stockBefore: level,
          stockAfter: level - need,
          reason: const Value(null),
          note: const Value(null),
          referenceType: Value(StockMovementType.sale.dbValue),
          referenceId: Value(saleId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    final subtotal = Money.sumPaise(ordered.map((e) => e.lineTotal));
    if (subtotal == null) {
      throw const UnexpectedBillingFailure(
        'Sale total exceeds the safe ceiling.',
      );
    }

    // Calculate total offer discount from cart lines
    final totalOfferDiscount = lines.fold(
      0,
      (sum, line) => sum + (line.appliedOffer?.discountPaise ?? 0),
    );
    final totalPaise = (subtotal - totalOfferDiscount).clamp(0, subtotal);

    // Last gate before any write: the legs must cover exactly the total this
    // method is about to commit. The controller checks first, but the
    // repository is what inserts `sale_payments`, so it re-checks against its
    // own total rather than trusting a caller-computed one.
    final legSum = payments == null || payments.isEmpty
        ? null
        : payments.fold<int>(0, (acc, p) => acc + p.amountPaise);
    if (legSum != null && legSum != totalPaise) {
      throw UnexpectedBillingFailure(
        legSum < totalPaise
            ? 'Split payments are ${Money.formatPaise(totalPaise - legSum)} short.'
            : 'Split payments exceed the total by '
                  '${Money.formatPaise(legSum - totalPaise)}.',
      );
    }

    final receiptNumber = await _nextReceiptNumber(shopId);
    // A split has no single method to put on the header — the legs live in
    // `sale_payments`. `paymentMethod!` here threw a null-check error on the
    // local write path, which is the default (offline-first) route, so a
    // perfectly valid split crashed the sale instead of saving.
    final headerMethod = switch (paymentStatus) {
      PaymentStatus.notPaid => null,
      _ when payments != null && payments.isNotEmpty => null,
      _ => paymentMethod?.dbValue,
    };

    await _database
        .into(_database.sales)
        .insert(
          db.SalesCompanion.insert(
            id: Value(saleId),
            shopId: Value(shopId),
            receiptNumber: receiptNumber,
            customerId: Value(customerId),
            subtotalPaise: subtotal,
            totalPaise: totalPaise,
            offerDiscountPaise: Value(totalOfferDiscount),
            // Credit sales persist no payment method — the debt lives in the
            // customer ledger, derived from this sale's total minus payments.
            paymentMethod: Value(headerMethod),
            paymentStatus: Value(paymentStatus.dbValue),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    await _database.batch((batch) {
      batch.insertAll(_database.saleItems, [
        for (final entry in ordered)
          db.SaleItemsCompanion.insert(
            id: Value(const Uuid().v4()),
            shopId: Value(shopId),
            saleId: saleId,
            productId: entry.line.productId,
            variantId: Value(entry.line.variantId),
            productName: entry.line.productName,
            variantName: Value(entry.line.variantName),
            sku: Value(entry.line.sku),
            unitPricePaise: entry.line.unitPricePaise,
            quantity: entry.line.quantity,
            lineTotalPaise: entry.lineTotal,
            offerDiscountPaise: Value(
              entry.line.appliedOffer?.discountPaise ?? 0,
            ),
            appliedOfferId: Value(entry.line.appliedOffer?.offerId),
            appliedOfferName: Value(entry.line.appliedOffer?.offerName),
            appliedOfferType: Value(entry.line.appliedOffer?.offerType.wire),
          ),
      ]);
    });

    await _movements.insertAll(movements);

    if (payments != null && payments.isNotEmpty) {
      await _database.batch((batch) {
        batch.insertAll(_database.salePayments, [
          for (final p in payments)
            db.SalePaymentsCompanion.insert(
              saleId: saleId,
              paymentMethod: p.paymentMethod.dbValue,
              amountPaise: p.amountPaise,
              createdAt: Value(now),
            ),
        ]);
      });
    }

    final sale = Sale(
      id: saleId,
      receiptNumber: receiptNumber,
      subtotalPaise: subtotal,
      totalPaise: totalPaise,
      offerDiscountPaise: totalOfferDiscount,
      paymentStatus: paymentStatus,
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : (payments != null && payments.isNotEmpty ? null : paymentMethod),
      createdAt: now,
      updatedAt: now,
      customerId: customerId,
      payments: payments ?? const [],
    );
    final persistedItems = (await _saleItems.bySale(
      saleId,
    )).map(_saleItemFromRow).toList();
    return CompletedSale(sale: sale, items: persistedItems);
  }

  /// Shop owning every cart line, derived from the actual stock entities.
  /// Variant lines are scoped by their variant row, plain lines by their
  /// product row. Returns null when no row carries a shop (legacy rows) so
  /// callers fall back to the profile resolver. Throws when lines span more
  /// than one shop — a mixed cart can never be a single atomic sale.
  /// The shop every line in the cart agrees on.
  ///
  /// Without a known selling shop this is the only interpretation available, so
  /// a cart spanning two businesses is rejected. With one, the cart is read as
  /// "a sale OF that business": its own products are fine, and a product owned
  /// by another business is only allowed when that owner has shared it
  /// ([Products.visibleInShops]). A shared line still deducts the selling
  /// business's overlay shelf, never the owner's own stock.
  Future<String?> _shopIdForLines(
    List<CartLine> lines, {
    String? sellingShopId,
  }) async {
    final productIds = lines.map((l) => l.productId).toSet();
    final productRows = productIds.isEmpty
        ? const <db.Product>[]
        : await (_database.select(
            _database.products,
          )..where((t) => t.id.isIn(productIds))).get();
    final productsById = {for (final row in productRows) row.id: row};

    final variantIds = lines
        .where((l) => l.variantId != null)
        .map((l) => l.variantId!)
        .toSet();
    final variantRows = variantIds.isEmpty
        ? const <db.ProductVariant>[]
        : await (_database.select(
            _database.productVariants,
          )..where((t) => t.id.isIn(variantIds))).get();
    final variantsById = {for (final row in variantRows) row.id: row};

    if (sellingShopId != null) {
      for (final line in lines) {
        final product = productsById[line.productId];
        if (product == null) continue;
        if (product.shopId == sellingShopId) continue;
        // A product with no shop of its own is scopeless, not stolen: it is
        // pinned to the selling business, which is the pre-sharing behaviour
        // and the reason `shopId` exists as an explicit override. Only a product
        // that NAMES a different owner has to have been shared to be sold.
        if (product.shopId == null) continue;
        if (!product.visibleInShops) {
          // Same failure the mixed-shop rejection uses, so a cart that reaches
          // for someone else's unshared product is indistinguishable from any
          // other cross-shop attempt.
          throw const UnexpectedBillingFailure(
            'Cart products belong to a different shop.',
          );
        }
      }
      return sellingShopId;
    }

    final shops = <String>{};
    for (final line in lines) {
      String? shop;
      final variant = line.variantId == null
          ? null
          : variantsById[line.variantId];
      if (variant != null && variant.shopId != null) {
        shop = variant.shopId;
      } else {
        shop = productsById[line.productId]?.shopId;
      }
      if (shop != null && shop.isNotEmpty) shops.add(shop);
    }
    if (shops.length > 1) {
      throw const UnexpectedBillingFailure(
        'Cart products belong to a different shop.',
      );
    }
    return shops.isEmpty ? null : shops.single;
  }

  /// Loads the stock entities behind every line in one round trip: the
  /// products and (for variant lines) the variants, keyed by the line's
  /// stock-entity id ([CartLine.keyId]). A missing product surfaces as a
  /// null entry so the caller can raise the domain failure.
  Future<Map<String, ({db.Product? product, db.ProductVariant? variant})>>
  _entitiesById(List<CartLine> lines) async {
    final productIds = lines.map((l) => l.productId).toSet();
    final productRows = await (_database.select(
      _database.products,
    )..where((t) => t.id.isIn(productIds))).get();
    final products = {for (final row in productRows) row.id: row};

    final variantIds = lines
        .where((l) => l.variantId != null)
        .map((l) => l.variantId!)
        .toSet();
    final variantRows = variantIds.isEmpty
        ? const <db.ProductVariant>[]
        : await (_database.select(
            _database.productVariants,
          )..where((t) => t.id.isIn(variantIds))).get();
    final variants = {for (final row in variantRows) row.id: row};

    return {
      for (final line in lines)
        line.keyId: (
          product: products[line.productId],
          variant: line.variantId == null ? null : variants[line.variantId],
        ),
    };
  }

  /// No-op for walk-in sales (null). For customer-linked sales the customer
  /// must still exist and be active; anything else fails the whole checkout.
  Future<void> _validateCustomer(String? customerId) async {
    if (customerId == null) {
      return;
    }
    final row = await (_database.select(
      _database.customers,
    )..where((t) => t.id.equals(customerId))).getSingleOrNull();
    if (row == null) {
      throw const CustomerNotFoundFailure();
    }
    if (!row.isActive) {
      throw const InactiveCustomerFailure();
    }
  }

  /// Builds the post-checkout Product outbox entry for a tracked, non-variant
  /// line whose stock was just deducted. Carries the reduced level so the
  /// cloud and the other device converge on the exact same stock.
  static OutboxAppend _stockProductAppend(
    db.Product product,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.product,
    entityId: product.id,
    payload: SyncProduct(
      id: product.id,
      shopId: context.shopId,
      categoryId: product.categoryId,
      name: product.name,
      sku: product.sku,
      sellingPricePaise: product.sellingPricePaise,
      costPricePaise: product.costPricePaise,
      stockQuantity: product.stockQuantity,
      stockUnit: switch (product.stockUnit) {
        'NONE' => SyncStockUnit.none,
        'ML' => SyncStockUnit.ml,
        'GRAM' => SyncStockUnit.gram,
        'KG' => SyncStockUnit.kg,
        _ => SyncStockUnit.count,
      },
      lowStockMode: switch (product.lowStockMode) {
        'CUSTOM' => SyncLowStockMode.custom,
        'OFF' => SyncLowStockMode.off,
        _ => SyncLowStockMode.useDefault,
      },
      lowStockThreshold: product.lowStockThreshold,
      membershipEnabled: product.membershipEnabled,
      memberPricePaise: product.memberPricePaise,
      isActive: product.isActive,
      createdAt: product.createdAt,
      cloudImagePath: product.cloudImagePath,
      isIngredient: product.isIngredient,
    ).toJson(),
  );

  /// Builds the post-checkout ProductVariant outbox entry for a tracked
  /// variant line whose stock was just deducted on the variant entity.
  static OutboxAppend _stockVariantAppend(
    db.ProductVariant variant,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.productVariant,
    entityId: variant.id,
    payload: SyncProductVariant(
      id: variant.id,
      shopId: context.shopId,
      productId: variant.productId,
      name: variant.name,
      sku: variant.sku,
      sellingPricePaise: variant.sellingPricePaise,
      costPricePaise: variant.costPricePaise,
      stockQuantity: variant.stockQuantity,
      lowStockMode: switch (variant.lowStockMode) {
        'CUSTOM' => SyncLowStockMode.custom,
        'OFF' => SyncLowStockMode.off,
        _ => SyncLowStockMode.useDefault,
      },
      lowStockThreshold: variant.lowStockThreshold,
      membershipEnabled: variant.membershipEnabled,
      memberPricePaise: variant.memberPricePaise,
      isActive: variant.isActive,
      createdAt: variant.createdAt,
    ).toJson(),
  );

  /// Reads the receipt LABEL for [shopId].
  ///
  /// The prefix is a property of the business, not of the app: Cafe receipts
  /// are `BF-`, Food Truck receipts are `FT-`. Falls back to the Cafe default
  /// only if the shop row is missing, so a receipt is never emitted
  /// unprefixed. The counter itself is already per-shop, so this is purely the
  /// label — the sequence is untouched.
  Future<String> _receiptPrefixFor(String shopId) async {
    final row = await _database
        .customSelect(
          'SELECT receipt_prefix FROM shops WHERE id = ?',
          variables: [Variable.withString(shopId)],
        )
        .getSingleOrNull();
    final prefix = row?.data['receipt_prefix'] as String?;
    if (prefix == null || prefix.trim().isEmpty) {
      return AppConstants.defaultShopReceiptPrefix;
    }
    return prefix;
  }

  /// Allocates a gapless receipt number scoped to [shopId].  The per-shop
  /// counter lives in `sale_sequences` with composite key `(id, shop_id)`.
  /// On first allocation we seed the counter and heal forward to the highest
  /// receipt number already in use.  Runs inside the checkout transaction,
  /// so a rolled-back checkout never consumes a value.
  ///
  /// The heal-forward scan is scoped to THIS shop's prefix as well as this
  /// shop's id, so the Food Truck never skips past numbers that Cafe already
  /// used (and vice versa) just because both share a counter.
  Future<String> _nextReceiptNumber(String shopId) async {
    final prefix = await _receiptPrefixFor(shopId);
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
            Variable.withInt(prefix.length + 1),
            Variable.withString('$prefix%'),
            Variable.withString(shopId),
            Variable.withString(_receiptSequenceId),
            Variable.withString(shopId),
          ],
        )
        .getSingle();
    final nextValue = row.read<int>('next_value');
    return '$prefix${nextValue.toString().padLeft(6, '0')}';
  }

  @override
  Future<Sale?> saleById(String id) async {
    try {
      final shopId = await resolveWritableShopId(_database);
      final row = await _sales.byId(id, shopId: shopId);
      return row == null ? null : _saleFromRow(row);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load sale', error, stackTrace);
    }
  }

  @override
  Future<List<SaleItem>> saleItemsFor(String saleId) async {
    try {
      final rows = await _saleItems.bySale(saleId);
      return rows.map(_saleItemFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load sale items', error, stackTrace);
    }
  }

  @override
  Future<List<Sale>> sales() async {
    try {
      final shopId = await resolveWritableShopId(_database);
      final rows = await _sales.all(shopId: shopId);
      return rows.map(_saleFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load sales', error, stackTrace);
    }
  }

  @override
  Future<List<String>> frequentlySoldProductIds({
    required DateTime sinceUtc,
    int limit = 10,
    String? shopId,
  }) async {
    try {
      final resolvedShopId = await resolveWritableShopId(_database, shopId);
      final rows = await _database
          .customSelect(
            'SELECT si.product_id AS product_id, '
            'SUM(si.quantity) AS sold '
            'FROM sale_items si '
            'JOIN sales s ON s.id = si.sale_id '
            'WHERE si.shop_id = ? AND s.is_opening_balance = ? '
            'AND s.voided = ? AND s.created_at >= ? '
            'GROUP BY si.product_id '
            'ORDER BY sold DESC, si.product_id ASC LIMIT ?',
            variables: [
              Variable.withString(resolvedShopId),
              Variable.withBool(false),
              Variable.withBool(false),
              Variable.withDateTime(sinceUtc),
              Variable.withInt(limit),
            ],
          )
          .get();
      return [for (final row in rows) row.read<String>('product_id')];
    } on Exception catch (error, stackTrace) {
      throw _unexpected(
        'Failed to load frequently sold products',
        error,
        stackTrace,
      );
    }
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedBillingFailure();
  }

  @override
  Future<void> voidSale(String saleId) async {
    if (_connectivity != null) {
      try {
        await OnlineGuard(_connectivity!).requireOnline();
      } on OfflineException catch (e) {
        throw UnexpectedBillingFailure(e.message);
      }
    }
    Future<void> write() async {
      final saleRow = await _sales.byId(saleId);
      if (saleRow == null) {
        throw const SaleNotFoundFailure();
      }
      if (saleRow.voided) {
        throw const SaleAlreadyVoidedFailure();
      }
      final now = DateTime.now().toUtc();
      final nowStr = now.toIso8601String();
      final items = await _saleItems.bySale(saleId);
      for (final item in items) {
        // Mirror the deduction's routing exactly. A line sold from a shelf the
        // seller did not own came out of that seller's `shop_product_stock`
        // row, so it must go back to the same row; crediting the owner's
        // `products.stock_quantity` here would invent Cafe stock the Cafe never
        // lost, which is how a void silently inflates the Cafe's shelf.
        final product = await (_database.select(
          _database.products,
        )..where((t) => t.id.equals(item.productId))).getSingleOrNull();
        final soldShopId = saleRow.shopId;
        final usedOverlay =
            product?.shopId != null &&
            soldShopId != null &&
            product!.shopId != soldShopId;
        if (usedOverlay) {
          final restored = await _shopStock.restoreQuantity(
            shopId: soldShopId!,
            productId: item.productId,
            variantId: item.variantId,
            delta: item.quantity,
          );
          // A null restore means the shelf row is gone. There is nothing to put
          // the units back onto, and inventing a row with a made-up number
          // would be worse than the loss, so the void leaves it alone.
          if (restored == null) continue;
          continue;
        }
        // Mirror the sale: a line that consumed recipe ingredients puts each
        // ingredient back (quantity per unit × line quantity). The menu
        // product's own stock was never touched by the sale, so it is never
        // restored here either.
        final recipeRows = soldShopId == null
            ? const <db.ProductRecipe>[]
            : await _recipesForSaleLine(
                productId: item.productId,
                variantId: item.variantId,
                shopId: soldShopId,
              );
        if (recipeRows.isNotEmpty) {
          for (final row in recipeRows) {
            final restore = row.quantity * item.quantity;
            if (row.ingredientVariantId != null) {
              await _database.customStatement(
                'UPDATE product_variants SET stock_quantity = '
                'stock_quantity + ?, updated_at = ? WHERE id = ?',
                [restore, nowStr, row.ingredientVariantId],
              );
            } else {
              await _database.customStatement(
                'UPDATE products SET stock_quantity = stock_quantity + ?, '
                'updated_at = ? WHERE id = ?',
                [restore, nowStr, row.ingredientProductId],
              );
            }
          }
          continue;
        }
        if (item.variantId != null) {
          await _database.customStatement(
            'UPDATE product_variants SET stock_quantity = '
            'stock_quantity + ?, updated_at = ? WHERE id = ?',
            [item.quantity, nowStr, item.variantId],
          );
        } else {
          await _database.customStatement(
            'UPDATE products SET stock_quantity = stock_quantity + ?, '
            'updated_at = ? WHERE id = ?',
            [item.quantity, nowStr, item.productId],
          );
        }
      }
      final payments =
          await (_database.select(_database.customerPayments)..where(
                (t) => t.saleId.equals(saleId) & t.reversed.equals(false),
              ))
              .get();
      for (final payment in payments) {
        await (_database.update(
          _database.customerPayments,
        )..where((t) => t.id.equals(payment.id))).write(
          db.CustomerPaymentsCompanion(
            reversed: const Value(true),
            reversedAt: Value(now),
          ),
        );
      }
      await (_database.update(
        _database.sales,
      )..where((t) => t.id.equals(saleId))).write(
        db.SalesCompanion(
          voided: const Value(true),
          voidedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    try {
      // Cloud-authoritative void when gateway wired
      if (_cloud != null) {
        try {
          await _cloud!.voidSaleAtomic(saleId);
        } catch (e) {
          if (e is TimeoutException) {
            throw const UnexpectedBillingFailure(
              'The server is taking too long to respond. Please try again.',
            );
          }
          final msg = e.toString();
          if (msg.contains('ALREADY_VOIDED'))
            throw const SaleAlreadyVoidedFailure();
          if (msg.contains('SALE_NOT_FOUND')) throw const SaleNotFoundFailure();
          if (msg.contains('FORBIDDEN'))
            throw const UnexpectedBillingFailure(
              'Access denied for this shop.',
            );
          if (msg.contains('SocketException') ||
              msg.contains('Failed host lookup')) {
            throw const UnexpectedBillingFailure(
              'Internet connection required. Please check your connection and try again.',
            );
          }
          rethrow;
        }
        // Mirror locally for cache
        await _database.transaction(write);
        return;
      }

      final outbox = _outbox;
      if (outbox == null) {
        await _database.transaction(write);
        return;
      }
      await outbox.run(
        write: () => _database.transaction(write),
        snapshots: (context, ctx) async {
          // Read the voided sale row and any reversed payments after the
          // transaction so the outbox payload reflects the committed state.
          final saleRow = await (_database.select(
            _database.sales,
          )..where((t) => t.id.equals(saleId))).getSingle();
          final salePayload = SyncSale(
            id: saleRow.id,
            shopId: ctx.shopId,
            customerId: saleRow.customerId,
            receiptNumber: saleRow.receiptNumber,
            subtotalPaise: saleRow.subtotalPaise,
            totalPaise: saleRow.totalPaise,
            paymentMethod: saleRow.paymentMethod,
            paymentStatus: saleRow.paymentStatus,
            createdAt: saleRow.createdAt,
            voided: saleRow.voided,
            voidedAt: saleRow.voidedAt,
            offerDiscountPaise: saleRow.offerDiscountPaise,
          ).toJson();
          final out = <OutboxAppend>[
            OutboxAppend(
              entity: MasterEntity.sale,
              entityId: saleId,
              payload: salePayload,
            ),
          ];
          final payments = await (_database.select(
            _database.customerPayments,
          )..where((t) => t.saleId.equals(saleId))).get();
          for (final p in payments.where((e) => e.reversed)) {
            out.add(
              OutboxAppend(
                entity: MasterEntity.customerPayment,
                entityId: p.id,
                payload: SyncCustomerPayment(
                  id: p.id,
                  shopId: ctx.shopId,
                  customerId: p.customerId,
                  saleId: p.saleId,
                  amountPaise: p.amountPaise,
                  paymentMethod: p.paymentMethod,
                  note: p.note,
                  paidAt: p.paidAt,
                  reversed: p.reversed,
                  reversedAt: p.reversedAt,
                  createdAt: p.createdAt,
                ).toJson(),
              ),
            );
          }
          return out;
        },
      );
    } on BillingFailure {
      rethrow;
    } on OfflineException catch (e) {
      throw UnexpectedBillingFailure(e.message);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to void sale', error, stackTrace);
    }
  }

  static Sale _saleFromRow(db.Sale row) => Sale(
    id: row.id,
    receiptNumber: row.receiptNumber,
    subtotalPaise: row.subtotalPaise,
    totalPaise: row.totalPaise,
    offerDiscountPaise: row.offerDiscountPaise,
    paymentStatus: PaymentStatus.fromDbValue(row.paymentStatus)!,
    paymentMethod: row.paymentMethod == null
        ? null
        : PaymentMethod.fromDbValue(row.paymentMethod!),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    customerId: row.customerId,
    voided: row.voided,
    voidedAt: row.voidedAt,
  );

  static SaleItem _saleItemFromRow(db.SaleItem row) => SaleItem(
    id: row.id,
    saleId: row.saleId,
    productId: row.productId,
    productName: row.productName,
    unitPricePaise: row.unitPricePaise,
    quantity: row.quantity,
    lineTotalPaise: row.lineTotalPaise,
    offerDiscountPaise: row.offerDiscountPaise,
    sku: row.sku,
    variantId: row.variantId,
    variantName: row.variantName,
    appliedOfferId: row.appliedOfferId,
    appliedOfferName: row.appliedOfferName,
    appliedOfferType: row.appliedOfferType == null
        ? null
        : OfferType.fromWire(row.appliedOfferType!),
  );
}
