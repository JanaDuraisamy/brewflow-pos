import 'dart:async';

import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';

import 'fake_inventory_repository.dart';

/// In-memory [BillingRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI: it
/// re-validates lines against the shared [FakeInventoryRepository] (existence,
/// active flag, stock), deducts its stock, issues sequential receipt numbers
/// and can fail configured checkouts ([completeSaleError], [completeSaleGate]).
final class FakeBillingRepository implements BillingRepository {
  FakeBillingRepository(this.inventory);

  final FakeInventoryRepository inventory;

  final List<Sale> storedSales = [];
  final Map<String, List<SaleItem>> _storedItems = {};

  /// Receipt sequence shared by every checkout.
  int receiptsIssued = 0;

  /// Number of completed (accepted or rejected) checkout attempts.
  int checkouts = 0;

  /// Last payment method passed to a checkout (null for NOT_PAID credit
  /// sales).
  PaymentMethod? lastPaymentMethod;

  /// Last payment status passed to a checkout.
  PaymentStatus? lastPaymentStatus;

  /// Last customer id passed to a checkout (null for walk-ins).
  String? lastCustomerId;

  /// When set, every checkout throws this error before touching state.
  Object? completeSaleError;

  /// When set, checkouts wait until released (in-flight state tests).
  Completer<void>? completeSaleGate;

  @override
  Future<CompletedSale> completeSale({
    required List<CartLine> lines,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    PaymentMethod? paymentMethod,
    String? customerId,
    String? shopId,
  }) async {
    checkouts += 1;
    lastPaymentMethod = paymentMethod;
    lastPaymentStatus = paymentStatus;
    lastCustomerId = customerId;
    final gate = completeSaleGate;
    if (gate != null) {
      await gate.future;
    }
    final error = completeSaleError;
    if (error != null) {
      throw error;
    }
    if (lines.isEmpty) {
      throw const EmptyCartFailure();
    }
    if (paymentStatus == PaymentStatus.notPaid && customerId == null) {
      throw const MissingCustomerForCreditSaleFailure();
    }
    if (paymentStatus == PaymentStatus.paid && paymentMethod == null) {
      throw const InvalidPaymentFailure();
    }

    receiptsIssued += 1;
    final now = DateTime.now().toUtc();
    final items = <SaleItem>[];
    for (final line in lines) {
      final product = inventory.storedProducts.firstWhere(
        (p) => p.id == line.productId,
        orElse: () => throw UnavailableProductFailure(line.productName),
      );
      if (!product.isActive) {
        throw UnavailableProductFailure(line.productName);
      }
      if (product.stockQuantity < line.quantity) {
        throw InsufficientStockFailure(line.productName);
      }
      final lineTotal = Money.multiplyPaise(line.unitPricePaise, line.quantity);
      if (lineTotal == null) {
        throw const UnexpectedBillingFailure(
          'Line total exceeds the safe ceiling.',
        );
      }
      inventory.storedProducts[inventory.storedProducts.indexOf(
        product,
      )] = product.copyWith(
        stockQuantity: product.stockQuantity - line.quantity,
        updatedAt: now,
      );
      final offerDiscount = line.appliedOffer?.discountPaise ?? 0;
      items.add(
        SaleItem(
          id: 'item-${items.length + 1}',
          saleId: '',
          productId: line.productId,
          productName: line.productName,
          sku: line.sku,
          variantId: line.variantId,
          variantName: line.variantName,
          unitPricePaise: line.unitPricePaise,
          quantity: line.quantity,
          lineTotalPaise: lineTotal,
          offerDiscountPaise: offerDiscount,
          appliedOfferId: line.appliedOffer?.offerId,
          appliedOfferName: line.appliedOffer?.offerName,
          appliedOfferType: line.appliedOffer?.offerType,
        ),
      );
    }

    final subtotal = Money.sumPaise(items.map((i) => i.lineTotalPaise));
    final totalOfferDiscount = items.fold(
      0,
      (sum, item) => sum + item.offerDiscountPaise,
    );
    final total = subtotal == null
        ? null
        : (subtotal - totalOfferDiscount).clamp(0, subtotal);
    if (total == null) {
      throw const UnexpectedBillingFailure(
        'Sale total exceeds the safe ceiling.',
      );
    }
    final sale = Sale(
      id: 'sale-${storedSales.length + 1}',
      receiptNumber: 'BF-${receiptsIssued.toString().padLeft(6, '0')}',
      subtotalPaise: subtotal!,
      totalPaise: total,
      offerDiscountPaise: totalOfferDiscount,
      paymentStatus: paymentStatus,
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : paymentMethod,
      createdAt: now,
      updatedAt: now,
      customerId: customerId,
    );
    _storedItems[sale.id] = [
      for (final item in items)
        SaleItem(
          id: item.id,
          saleId: sale.id,
          productId: item.productId,
          productName: item.productName,
          sku: item.sku,
          variantId: item.variantId,
          variantName: item.variantName,
          unitPricePaise: item.unitPricePaise,
          quantity: item.quantity,
          lineTotalPaise: item.lineTotalPaise,
          offerDiscountPaise: item.offerDiscountPaise,
          appliedOfferId: item.appliedOfferId,
          appliedOfferName: item.appliedOfferName,
          appliedOfferType: item.appliedOfferType,
        ),
    ];
    storedSales.add(sale);
    return CompletedSale(sale: sale, items: _storedItems[sale.id]!);
  }

  @override
  Future<Sale?> saleById(String id) async {
    for (final sale in storedSales) {
      if (sale.id == id) return sale;
    }
    return null;
  }

  @override
  Future<List<SaleItem>> saleItemsFor(String saleId) async {
    return List.of(_storedItems[saleId] ?? const []);
  }

  @override
  Future<List<Sale>> sales() async {
    final sorted = List<Sale>.of(storedSales)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// Ids of sales that have been voided.
  final Set<String> voidedIds = {};

  @override
  Future<void> voidSale(String saleId) async {
    storedSales.firstWhere(
      (s) => s.id == saleId,
      orElse: () => throw const SaleNotFoundFailure(),
    );
    if (voidedIds.contains(saleId)) {
      throw const SaleAlreadyVoidedFailure();
    }
    voidedIds.add(saleId);
    final items = _storedItems[saleId] ?? const <SaleItem>[];
    for (final item in items) {
      final product = inventory.storedProducts.firstWhere(
        (p) => p.id == item.productId,
        orElse: () => throw const UnexpectedBillingFailure(),
      );
      inventory.storedProducts[inventory.storedProducts.indexOf(
        product,
      )] = product.copyWith(
        stockQuantity: product.stockQuantity + item.quantity,
        updatedAt: DateTime.now().toUtc(),
      );
    }
  }
}
