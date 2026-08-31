import 'dart:io';

import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Persistence Across Restart (Phase 10 Step 9)
///
/// The database is a real file on disk in production. Everything the app
/// commits — products, movements, purchases, sales, expenses — must survive a
/// close/reopen cycle, and the document number sequences must continue where
/// they left off (a restart must never reissue PUR-000001 / BF-000001).
///
/// This test opens a genuine SQLite file in a temp directory, writes business
/// data through the real Drift repositories, closes the connection and opens
/// a brand-new [AppDatabase] on the same file (exactly what a restarted app
/// does), then re-reads everything through fresh repositories.
/// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('brewflow_persistence_');
    dbFile = File(p.join(tempDir.path, 'brewflow_test.sqlite'));
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'all committed business data and number sequences survive a restart',
    () async {
      final first = db.AppDatabase(NativeDatabase.createInBackground(dbFile));
      await first
          .into(first.categories)
          .insert(
            db.CategoriesCompanion.insert(id: Value('c1'), name: 'Coffee'),
          );

      final inventory = DriftInventoryRepository(first);
      final movements = DriftStockMovementRepository(first);
      final purchases = DriftPurchaseRepository(first);
      final billing = DriftBillingRepository(first);
      final expenses = DriftExpensesRepository(first);

      final created = await inventory.createProduct(
        categoryId: 'c1',
        name: 'Filter Coffee',
        sku: null,
        sellingPricePaise: 15000,
        costPricePaise: 8000,
        stockQuantity: 20,
        isActive: true,
      );
      final productId = created.id;

      await purchases.receivePurchase(
        lines: [
          PurchaseLine(productId: productId, quantity: 30, unitCostPaise: 8000),
        ],
      );
      await billing.completeSale(
        lines: [
          CartLine(
            productId: productId,
            productName: 'Filter Coffee',
            unitPricePaise: 15000,
            quantity: 8,
            maxQuantity: 50,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );
      await expenses.createExpense(
        name: 'Rent',
        amountPaise: 250000,
        category: ExpenseCategory.rent,
        paymentMethod: PaymentMethod.bank,
        expenseDate: DateTime.now(),
      );

      expect((await inventory.products()).single.stockQuantity, 42);
      expect(await movements.movementsFor(productId), hasLength(3));
      expect((await purchases.purchases()).single.purchaseNumber, 'PUR-000001');
      expect((await billing.sales()).single.receiptNumber, 'BF-000001');
      expect(
        await expenses.expenses(status: ExpenseStatusFilter.all),
        hasLength(1),
      );

      await first.close();

      final second = db.AppDatabase(NativeDatabase.createInBackground(dbFile));
      addTearDown(second.close);

      final inventory2 = DriftInventoryRepository(second);
      final movements2 = DriftStockMovementRepository(second);
      final purchases2 = DriftPurchaseRepository(second);
      final billing2 = DriftBillingRepository(second);
      final expenses2 = DriftExpensesRepository(second);

      final products = await inventory2.products();
      expect(products.single.stockQuantity, 42);
      expect(products.single.name, 'Filter Coffee');
      expect(products.single.sellingPricePaise, 15000);

      final trail = await movements2.movementsFor(productId);
      expect(trail, hasLength(3));
      expect(trail.map((m) => m.movementType), [
        StockMovementType.sale,
        StockMovementType.purchase,
        StockMovementType.opening,
      ]);
      expect(trail.map((m) => m.stockAfter), [42, 50, 20]);

      expect(
        (await purchases2.purchases()).single.purchaseNumber,
        'PUR-000001',
      );
      final sale = (await billing2.sales()).single;
      expect(sale.receiptNumber, 'BF-000001');
      expect(sale.totalPaise, 120000);
      expect(
        (await expenses2.expenses(status: ExpenseStatusFilter.all)).single.name,
        'Rent',
      );

      final nextPurchase = await purchases2.receivePurchase(
        lines: [
          PurchaseLine(productId: productId, quantity: 10, unitCostPaise: 8000),
        ],
      );
      expect(nextPurchase.purchaseNumber, 'PUR-000002');

      final nextSale = await billing2.completeSale(
        lines: [
          CartLine(
            productId: productId,
            productName: 'Filter Coffee',
            unitPricePaise: 15000,
            quantity: 1,
            maxQuantity: 52,
          ),
        ],
        paymentMethod: PaymentMethod.upi,
      );
      expect(nextSale.sale.receiptNumber, 'BF-000002');
      expect((await inventory2.products()).single.stockQuantity, 51);
    },
  );
}
