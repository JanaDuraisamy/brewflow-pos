import 'package:drift/drift.dart';

import '../drift_schemas/schema_versions.dart' as versions;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Database Migration Strategy
///
/// Schema v1 (users, categories, products) is created on first install via
/// [MigrationStrategy.onCreate] in `AppDatabase.migration`.
///
/// Upgrade path (v1 → v2+):
/// Every schema change bumps [AppConstants.databaseSchemaVersion] and follows
/// the drift versioned-schema workflow:
///
///   1. Update the table definitions and re-run build_runner.
///   2. Dump the new snapshot:
///        dart run drift_dev schema dump lib/core/database/app_database.dart
///          lib/core/database/drift_schemas
///   3. Generate the step functions:
///        dart run drift_dev schema steps lib/core/database/drift_schemas
///          lib/core/database/drift_schemas/schema_versions.dart
///   4. Wire the generated `stepByStep` into [AppMigrations.upgrade].
///
/// Rules:
/// - Append-only. Never modify a migration that has already been released.
/// - Additive changes only: new tables, columns and indexes.
/// - Never drop tables or columns that may hold data.
/// - Sync-related columns (server ids, sync status, soft delete) arrive as
///   additive migrations together with the sync engine.
/// ---------------------------------------------------------------------------

final class AppMigrations {
  AppMigrations._();

  /// Runs the versioned, generated migration steps.
  ///
  /// - v1 → v2 adds the billing tables: sales, sale_items, sale_sequences.
  /// - v2 → v3 adds the customers table (v2 appends nothing else).
  /// - v3 → v4 adds the expenses table (v3 appends nothing else).
  /// - v4 → v5 links sales to customers (sales.customer_id + indexes) and
  ///   adds the customer_payments ledger table.
  /// - v5 → v6 adds the stock_movements audit table (one composite index);
  ///   nothing else changes.
  /// - v6 → v7 widens the stock_movements movement_type CHECK to accept
  ///   PURCHASE (table recreation, data copied in place) and adds the
  ///   purchase/receiving tables: suppliers, purchases, purchase_items,
  ///   purchase_sequences.
  ///   - v7 → v8 adds the product system v2: products gain image path, stock
  ///   unit, per-product low-stock policy, membership pricing and the new
  ///   product_variants table (its own stock, SKU, prices, low-stock policy
  ///   and membership tier); stock_movements, sale_items and purchase_items
  ///   gain nullable variant references so every stock event and every
  ///   receipt line can identify the exact variant.
  ///   - v8 → v9 adds the expenses payment status: a NOT NULL payment_status
  ///   column (PAID / NOT_PAID, default PAID) so existing expense records are
  ///   treated as settled and NOT_PAID expenses become shop payable.
  ///   - v9 → v10 adds the sales payment status: the sales table is
  ///   recreated in place (TableMigration, per the v6→v7 convention) so
  ///   payment_method becomes nullable — NULL for NOT_PAID credit sales, no
  ///   fake CASH/UPI/BANK value — and gains a NOT NULL payment_status column
  ///   (PAID / NOT_PAID, default PAID) so every existing sale stays PAID.
  ///   - v10 → v11 adds customer membership: customers gain a
  ///   membership_active flag (default false) and an optional
  ///   membership_fee_paise snapshot; purely additive, every existing
  ///   customer stays a non-member.
  ///   - v11 → v12 adds owner/staff access control: a shops table (the
  ///   single local business context, populated at owner bootstrap), users
  ///   gain auth_user_id (Supabase identity linkage, unique when present)
  ///   and shop_id (shop scope), and staff_permissions stores normalized
  ///   per-staff capability rows. Append-only; existing data untouched.
  ///
  /// Everything lives in the drift-generated [versions.stepByStep]; unknown
  /// versions fail loudly.
  static Future<void> upgrade(Migrator migrator, int from, int to) {
    return versions.stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.sales);
        await m.createTable(schema.saleItems);
        await m.createTable(schema.saleSequences);
        await m.createIndex(schema.idxSalesCreatedAt);
        await m.createIndex(schema.idxSaleItemsSaleId);
      },
      from2To3: (m, schema) async {
        await m.createTable(schema.customers);
        await m.createIndex(schema.idxCustomersName);
        await m.createIndex(schema.idxCustomersUpdatedAt);
      },
      from3To4: (m, schema) async {
        await m.createTable(schema.expenses);
        await m.createIndex(schema.idxExpensesExpenseDate);
        await m.createIndex(schema.idxExpensesCategory);
        await m.createIndex(schema.idxExpensesUpdatedAt);
      },
      from4To5: (m, schema) async {
        await m.addColumn(schema.sales, schema.sales.customerId);
        await m.createIndex(schema.idxSalesCustomerId);
        await m.createTable(schema.customerPayments);
        await m.createIndex(schema.idxCustomerPaymentsCustomerId);
        await m.createIndex(schema.idxCustomerPaymentsSaleId);
        await m.createIndex(schema.idxCustomerPaymentsPaidAt);
      },
      from5To6: (m, schema) async {
        await m.createTable(schema.stockMovements);
        await m.createIndex(schema.idxStockMovementsProductCreatedAt);
      },
      from6To7: (m, schema) async {
        // The movement_type CHECK gains 'PURCHASE'. SQLite cannot alter a
        // CHECK, so the table is recreated in place; [TableMigration] runs
        // the full rename→create→copy→drop sequence and re-creates the
        // index, preserving every existing row.
        // The v7 schema objects come from the frozen versioned schema (not
        // the live table definitions), so this step copies exactly the v7
        // columns and never leaks columns added in later versions.
        await m.alterTable(
          // ignore: experimental_member_use
          TableMigration(schema.stockMovements),
        );
        await m.createTable(schema.suppliers);
        await m.createIndex(schema.idxSuppliersName);
        await m.createIndex(schema.idxSuppliersUpdatedAt);
        await m.createTable(schema.purchases);
        await m.createIndex(schema.idxPurchasesCreatedAt);
        await m.createIndex(schema.idxPurchasesSupplierId);
        await m.createTable(schema.purchaseItems);
        await m.createIndex(schema.idxPurchaseItemsPurchaseId);
        await m.createTable(schema.purchaseSequences);
      },
      from7To8: (m, schema) async {
        // Product system v2 — purely additive columns on products (image,
        // stock unit, low-stock policy, membership pricing).
        await m.addColumn(schema.products, schema.products.imagePath);
        await m.addColumn(schema.products, schema.products.stockUnit);
        await m.addColumn(schema.products, schema.products.lowStockMode);
        await m.addColumn(schema.products, schema.products.lowStockThreshold);
        await m.addColumn(schema.products, schema.products.membershipEnabled);
        await m.addColumn(schema.products, schema.products.memberPricePaise);

        // Variants table with its indexes.
        await m.createTable(schema.productVariants);
        await m.createIndex(schema.idxProductVariantsProductId);
        await m.createIndex(schema.idxProductVariantsSku);
        await m.createIndex(schema.idxProductVariantsUpdatedAt);

        // Variant identity on the audit trail and receipt lines (nullable,
        // RESTRICT-ed to the never-deleted variants).
        await m.addColumn(
          schema.stockMovements,
          schema.stockMovements.variantId,
        );
        await m.createIndex(schema.idxStockMovementsVariantCreatedAt);
        await m.addColumn(schema.saleItems, schema.saleItems.variantId);
        await m.addColumn(schema.saleItems, schema.saleItems.variantName);
        await m.addColumn(schema.purchaseItems, schema.purchaseItems.variantId);
        await m.addColumn(
          schema.purchaseItems,
          schema.purchaseItems.variantName,
        );
      },
      from8To9: (m, schema) async {
        // Expense payment status — purely additive. The NOT NULL column
        // carries a DEFAULT 'PAID' (from the frozen v9 schema), so every
        // existing expense row is treated as settled after migration.
        await m.addColumn(schema.expenses, schema.expenses.paymentStatus);
      },
      from9To10: (m, schema) async {
        // Sales payment status — the sales table is recreated in place (the
        // v6→v7 convention) so payment_method can become nullable for
        // NOT_PAID credit sales. payment_status is a new column with a
        // DEFAULT 'PAID' (frozen v10 schema), so it is excluded from the
        // copy (newColumns) and every existing sale lands as PAID with its
        // payment method preserved. Drift's alterTable toggles
        // PRAGMA foreign_keys around the rename→create→copy→drop sequence,
        // so the RESTRICT FKs on sales stay intact.
        // ignore: experimental_member_use
        await m.alterTable(
          // ignore: experimental_member_use
          TableMigration(
            schema.sales,
            newColumns: [schema.sales.paymentStatus],
          ),
        );
      },
      from10To11: (m, schema) async {
        // Customer membership — purely additive columns with safe defaults,
        // so every existing customer stays a non-member after migration.
        await m.addColumn(schema.customers, schema.customers.membershipActive);
        await m.addColumn(
          schema.customers,
          schema.customers.membershipFeePaise,
        );
      },
      from13To14: (m, schema) async {
        // Sync foundation — devices (multi-device per user is valid; no
        // unique on user_id), the durable sync outbox with a logical-change
        // identity index, and per-device pull/push cursors. Purely additive.
        await m.createTable(schema.devices);
        await m.createTable(schema.syncOutbox);
        // Idempotent index creation: this step can run once (13→14) or as
        // part of a longer jump (12→14), so IF NOT EXISTS avoids clashes.
        const statements = [
          'CREATE INDEX IF NOT EXISTS idx_devices_shop ON devices (shop_id)',
          'CREATE INDEX IF NOT EXISTS idx_devices_updated_at ON devices'
              ' (updated_at)',
          'CREATE INDEX IF NOT EXISTS idx_sync_outbox_identity ON'
              ' sync_outbox (entity, entity_id, operation)',
          'CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox'
              ' (status, created_at)',
        ];
        for (final statement in statements) {
          await m.database.customStatement(statement);
        }
        await m.createTable(schema.syncState);
      },
      from14To15: (m, schema) async {
        // Sales full void — adds voided (default false) and nullable
        // voided_at columns to sales. Purely additive; every existing sale
        // stays active (not voided).
        await m.addColumn(schema.sales, schema.sales.voided);
        await m.addColumn(schema.sales, schema.sales.voidedAt);
      },
      from12To13: (m, schema) async {
        // WhatsApp status — purely additive; every existing customer lands
        // at the honest initial state UNKNOWN.
        await m.addColumn(schema.customers, schema.customers.whatsappStatus);
      },
      from11To12: (m, schema) async {
        // Owner/Staff access control. users gains auth_user_id (UNIQUE, so
        // SQLite cannot add it via ALTER TABLE) plus shop_id — the table is
        // recreated in place (TableMigration, per the v9→v10 convention),
        // copying every existing column so all rows survive untouched. The
        // shops table starts empty (populated at owner bootstrap) and
        // staff_permissions starts empty; nothing existing changes meaning.
        await m.createTable(schema.shops);
        await m.createIndex(schema.idxShopsUpdatedAt);
        // ignore: experimental_member_use
        await m.alterTable(
          // ignore: experimental_member_use
          TableMigration(
            schema.users,
            newColumns: [schema.users.authUserId, schema.users.shopId],
          ),
        );
        await m.createTable(schema.staffPermissions);
        await m.createIndex(schema.idxStaffPermissionsUser);
      },
    )(migrator, from, to);
  }
}
