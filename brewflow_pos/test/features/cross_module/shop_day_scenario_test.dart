import 'package:brewflow_pos/core/database/app_database.dart'
    as db
    hide Purchase, Sale, Supplier;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Complete Shop Day + Audit Trail (Phase 10 Step 9)
///
/// One product lives through a full trading day through the real Drift
/// repositories against a real in-memory SQLite database:
///
///   OPENING 20 -> PURCHASE +30 (50) -> SALE -8 (42)
///             -> ADJUSTMENT_OUT -2 (40) -> PURCHASE +10 (50)
///
/// Locked invariants:
/// - every stock change writes an audit movement (nothing changes silently)
/// - the trail is a perfect chain: each movement's stockBefore equals the
///   previous movement's stockAfter, and the newest stockAfter equals the
///   product's stock_quantity (closure)
/// - movement semantics: OPENING/PURCHASE/SALE carry no reason; PURCHASE and
///   SALE carry their document reference; ADJUSTMENT_OUT carries its reason
/// - purchase and sale item rows are immutable snapshots of the event
/// ---------------------------------------------------------------------------

void main() {
  late db.AppDatabase database;
  late DriftInventoryRepository inventory;
  late DriftStockMovementRepository movements;
  late DriftPurchaseRepository purchases;
  late DriftBillingRepository billing;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    inventory = DriftInventoryRepository(database);
    movements = DriftStockMovementRepository(database);
    purchases = DriftPurchaseRepository(database);
    billing = DriftBillingRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'a full trading day leaves an unbroken 5-movement audit trail',
    () async {
      await database
          .into(database.categories)
          .insert(
            db.CategoriesCompanion.insert(id: Value('c1'), name: 'Coffee'),
          );

      final product = await inventory.createProduct(
        categoryId: 'c1',
        name: 'Filter Coffee',
        sku: null,
        sellingPricePaise: 15000,
        costPricePaise: 8000,
        stockQuantity: 20,
        isActive: true,
      );
      final id = product.id;

      final purchaseOne = await purchases.receivePurchase(
        lines: [PurchaseLine(productId: id, quantity: 30, unitCostPaise: 8000)],
      );
      final sale = await billing.completeSale(
        lines: [
          CartLine(
            productId: id,
            productName: 'Filter Coffee',
            unitPricePaise: 15000,
            quantity: 8,
            maxQuantity: 50,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );
      await movements.adjustStock(
        productId: id,
        delta: -2,
        reason: StockAdjustmentReason.damage,
        note: 'spilled batch',
      );
      await purchases.receivePurchase(
        lines: [PurchaseLine(productId: id, quantity: 10, unitCostPaise: 8000)],
      );

      expect((await inventory.products()).single.stockQuantity, 50);

      final trail = await movements.movementsFor(id);
      expect(trail, hasLength(5));
      expect(trail.map((m) => m.movementType), [
        StockMovementType.purchase,
        StockMovementType.adjustmentOut,
        StockMovementType.sale,
        StockMovementType.purchase,
        StockMovementType.opening,
      ]);
      expect(trail.map((m) => m.quantity), [10, -2, -8, 30, 20]);
      expect(trail.map((m) => m.stockBefore), [40, 42, 50, 20, 0]);
      expect(trail.map((m) => m.stockAfter), [50, 40, 42, 50, 20]);

      final saleMovement = trail[2];
      expect(saleMovement.referenceType, 'SALE');
      expect(saleMovement.referenceId, sale.sale.id);
      expect(saleMovement.reason, isNull);

      final purchaseMovements = [trail[0], trail[3]];
      for (final movement in purchaseMovements) {
        expect(movement.referenceType, 'PURCHASE');
        expect(movement.reason, isNull);
      }
      expect(purchaseMovements[1].referenceId, purchaseOne.id);

      final adjustment = trail[1];
      expect(adjustment.referenceType, isNull);
      expect(adjustment.referenceId, isNull);
      expect(adjustment.reason, StockAdjustmentReason.damage);
      expect(adjustment.note, 'spilled batch');

      final opening = trail[4];
      expect(opening.referenceType, isNull);
      expect(opening.reason, isNull);

      expect((await purchases.purchases()).map((p) => p.purchaseNumber), [
        'PUR-000002',
        'PUR-000001',
      ]);
      expect((await billing.sales()).single.receiptNumber, 'BF-000001');
      expect(sale.sale.totalPaise, 120000);
      final saleItems = await billing.saleItemsFor(sale.sale.id);
      expect(saleItems.single.unitPricePaise, 15000);
      expect(saleItems.single.productName, 'Filter Coffee');
    },
  );
}
