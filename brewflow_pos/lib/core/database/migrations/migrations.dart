import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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
      from15To16: (m, schema) async {
        await m.createTable(schema.offers);
      },
      from16To17: (m, schema) async {
        // Phase 1 multi-business foundation: add shopId to remaining
        // business-owned tables that lacked it. Existing legacy rows belong
        // to the existing Cafe shop; Food Truck starts empty.
        final existing = await m.database
            .customSelect('SELECT id FROM shops LIMIT 1')
            .get();
        String cafeId;
        if (existing.isEmpty) {
          cafeId = const Uuid().v4();
          await m.database.customStatement(
            "INSERT INTO shops (id, name, created_at, updated_at) VALUES ('$cafeId', 'Cafe', datetime('now'), datetime('now'))",
          );
        } else {
          cafeId = existing.first.data['id'] as String;
        }

        // Purchases, purchase_items, stock_movements gain shop_id.
        // Added as nullable for simple ALTER TABLE, then backfilled to Cafe.
        // Future version will enforce NOT NULL at application level; DB
        // constraint remains nullable to allow the ALTER without default.
        await m.addColumn(schema.purchases, schema.purchases.shopId);
        await m.addColumn(schema.purchaseItems, schema.purchaseItems.shopId);
        await m.addColumn(schema.stockMovements, schema.stockMovements.shopId);

        await m.database.customStatement(
          "UPDATE purchases SET shop_id = '$cafeId' WHERE shop_id IS NULL",
        );
        await m.database.customStatement(
          "UPDATE purchase_items SET shop_id = '$cafeId' WHERE shop_id IS NULL",
        );
        await m.database.customStatement(
          "UPDATE stock_movements SET shop_id = '$cafeId' WHERE shop_id IS NULL",
        );

        // Indexes for shop-scoped queries (created via custom SQL for idempotency).
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchases_shop ON purchases (shop_id)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_purchase_items_shop ON purchase_items (shop_id)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_stock_movements_shop ON stock_movements (shop_id)',
        );

        // Rebuild sale_sequences from global PK(id) to per-shop
        // PK(id, shop_id) with NOT NULL shop_id FK to shops.
        // TableMigration cannot handle this (adding NOT NULL to rows
        // without a default), so we use a raw rename/create/copy/drop.
        await m.database.customStatement(
          'ALTER TABLE sale_sequences RENAME TO sale_sequences_backup',
        );
        await m.database.customStatement(
          'CREATE TABLE sale_sequences ('
          '"id" TEXT NOT NULL, '
          '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
          '"next_value" INTEGER NOT NULL DEFAULT 0 CHECK (next_value >= 0), '
          'PRIMARY KEY ("id", "shop_id")'
          ')',
        );
        await m.database.customStatement(
          "INSERT INTO sale_sequences (id, shop_id, next_value) "
          "SELECT id, '$cafeId', next_value FROM sale_sequences_backup",
        );
        await m.database.customStatement('DROP TABLE sale_sequences_backup');

        // Rebuild purchase_sequences identically (same global → per-shop).
        await m.database.customStatement(
          'ALTER TABLE purchase_sequences RENAME TO purchase_sequences_backup',
        );
        await m.database.customStatement(
          'CREATE TABLE purchase_sequences ('
          '"id" TEXT NOT NULL, '
          '"shop_id" TEXT NOT NULL REFERENCES shops (id) ON DELETE CASCADE, '
          '"next_value" INTEGER NOT NULL DEFAULT 0 CHECK (next_value >= 0), '
          'PRIMARY KEY ("id", "shop_id")'
          ')',
        );
        await m.database.customStatement(
          "INSERT INTO purchase_sequences (id, shop_id, next_value) "
          "SELECT id, '$cafeId', next_value FROM purchase_sequences_backup",
        );
        await m.database.customStatement(
          'DROP TABLE purchase_sequences_backup',
        );

        // Scope the 9 legacy business tables to a shop. These tables never had
        // shop_id before v17 (frozen v16 snapshot has no such column), so each
        // must be recreated with shop_id as a genuinely NEW column: newColumns
        // tells the migrator not to copy it from the old table (which would
        // crash with "no such column"), and columnTransformer assigns every
        // existing row to the Cafe shop. The unique name/sku constraints also
        // change to (shop_id, name)/(shop_id, sku) here, which TableMigration
        // re-applies while preserving all existing data.
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.categories,
            newColumns: [schema.categories.shopId],
            columnTransformer: {
              schema.categories.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.customers,
            newColumns: [schema.customers.shopId],
            columnTransformer: {
              schema.customers.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.customerPayments,
            newColumns: [schema.customerPayments.shopId],
            columnTransformer: {
              schema.customerPayments.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.expenses,
            newColumns: [schema.expenses.shopId],
            columnTransformer: {
              schema.expenses.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.products,
            newColumns: [schema.products.shopId],
            columnTransformer: {
              schema.products.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.productVariants,
            newColumns: [schema.productVariants.shopId],
            columnTransformer: {
              schema.productVariants.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.sales,
            newColumns: [schema.sales.shopId],
            columnTransformer: {schema.sales.shopId: Constant<String>(cafeId)},
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.saleItems,
            newColumns: [schema.saleItems.shopId],
            columnTransformer: {
              schema.saleItems.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // ignore: experimental_member_use
        await m.alterTable(
          TableMigration(
            schema.suppliers,
            newColumns: [schema.suppliers.shopId],
            columnTransformer: {
              schema.suppliers.shopId: Constant<String>(cafeId),
            },
          ),
        );
        // offers already carried shop_id since v16 (created with the legacy
        // '000...' default), so its TableMigration copies the existing column;
        // no newColumns/transformer needed here.
        // ignore: experimental_member_use
        await m.alterTable(TableMigration(schema.offers));
        await m.database.customStatement(
          "UPDATE categories SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE customers SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE customer_payments SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE expenses SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE products SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE product_variants SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE sales SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE sale_items SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE suppliers SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
        await m.database.customStatement(
          "UPDATE offers SET shop_id = '$cafeId' WHERE shop_id = '00000000-0000-0000-0000-000000000000'",
        );
      },
      from17To18: (m, schema) async {
        // Product cloud image — purely additive. cloud_image_path is nullable
        // so every existing product stays at imagePath-only (no cloud ref).
        // product_image_sync is a new durable offline queue for image
        // upload/download/delete intents (binary-free: paths and metadata only).
        await m.addColumn(schema.products, schema.products.cloudImagePath);
        await m.createTable(schema.productImageSync);
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_product_image_sync_identity'
          ' ON product_image_sync (product_id, operation)',
        );
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_product_image_sync_status'
          ' ON product_image_sync (status, created_at)',
        );
        // Offer bookkeeping on receipts — the sale-level and line-level
        // discount columns shipped with the same schema bump but were never
        // added here, so a v17 -> v18 upgrade left every sale read crashing on
        // the missing NOT NULL offer_discount_paise. offer_discount_paise has a
        // DEFAULT 0 so pre-existing rows keep their exact totals; the applied
        // offer fields are nullable (no offer was applied before this schema).
        await m.addColumn(schema.sales, schema.sales.offerDiscountPaise);
        await m.addColumn(
          schema.saleItems,
          schema.saleItems.offerDiscountPaise,
        );
        await m.addColumn(schema.saleItems, schema.saleItems.appliedOfferId);
        await m.addColumn(schema.saleItems, schema.saleItems.appliedOfferName);
        await m.addColumn(schema.saleItems, schema.saleItems.appliedOfferType);
      },
      from18To19: (m, schema) async {
        // Storage monitoring + monthly cleanup — purely additive. Two new local
        // tables: a per-shop cleanup state row (last scan / cleanup timestamps)
        // and owner-only cleanup-available notifications. Neither holds Storage
        // object bytes; both are device-local bookkeeping.
        await m.createTable(schema.storageCleanupState);
        await m.createTable(schema.storageCleanupNotification);
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_storage_cleanup_notification'
          ' ON storage_cleanup_notification (shop_id, kind)',
        );
      },
      from19To20: (m, schema) async {
        // Customer collections — purely additive. customer_payments gains the
        // nullable payment_group_id that groups the split rows of one
        // customer-level collection (NULL for every legacy per-bill payment)
        // plus the partial unique index (payment_group_id, sale_id), which is
        // the idempotent-replay backstop: replaying the same group on any
        // device can never insert a duplicate row for the same bill.
        await m.addColumn(
          schema.customerPayments,
          schema.customerPayments.paymentGroupId,
        );
        await m.createIndex(schema.idxCustomerPaymentsGroup);
      },
      from20To21: (m, schema) async {
        // Opening balances — purely additive. sales gains the
        // is_opening_balance flag (DEFAULT false from the frozen v21 schema),
        // so every existing sale stays a real sale. New rows flagged true are
        // ledger-only entries (no sale items, no stock, no totals exposure);
        // everything else on the ledger derivation is untouched.
        await m.addColumn(schema.sales, schema.sales.isOpeningBalance);
      },
      from21To22: (m, schema) async {
        // Staff attendance, staff advances and daily closing records are
        // three new local-first tables (purely additive), and users gains the
        // owner-configured hourly salary rate (nullable, so every existing
        // profile stays unconfigured until the owner sets a rate).
        await m.createTable(schema.staffAttendance);
        await m.createIndex(schema.idxStaffAttendanceShopDate);
        await m.createIndex(schema.idxStaffAttendanceStaffDate);
        await m.createIndex(schema.idxStaffAttendanceUpdatedAt);
        await m.createTable(schema.staffAdvances);
        await m.createIndex(schema.idxStaffAdvancesShopDate);
        await m.createIndex(schema.idxStaffAdvancesStaffDate);
        await m.createIndex(schema.idxStaffAdvancesUpdatedAt);
        await m.createTable(schema.dailyClosings);
        await m.createIndex(schema.idxDailyClosingsShopDate);
        await m.createIndex(schema.idxDailyClosingsUpdatedAt);
        await m.addColumn(schema.users, schema.users.salaryPaisePerHour);
      },
      from22To23: (m, schema) async {
        // Owner-entered manual monthly salary per staff member (purely
        // additive). Salary is never derived from the legacy hourly rate:
        // attendance hours stay display-only and final payable is salary
        // minus advances. The legacy users.salaryPaisePerHour column is
        // left untouched for migration compatibility (never read anymore).
        await m.createTable(schema.staffMonthlySalaries);
        await m.createIndex(schema.idxStaffMonthlySalariesShopMonth);
        await m.createIndex(schema.idxStaffMonthlySalariesStaffMonth);
        await m.createIndex(schema.idxStaffMonthlySalariesUpdatedAt);
      },
      from23To24: (m, schema) async {
        // Daily salary amounts per staff per business day (purely additive).
        // The month's calculated salary is the SUM of these day-level rows
        // (split shifts on one day still carry a single salary); the owner's
        // manual monthly salary remains the overridable value. Device-local:
        // no Supabase schema change is required for v24.
        await m.createTable(schema.staffDailySalary);
        await m.createIndex(schema.idxStaffDailySalariesShopDate);
        await m.createIndex(schema.idxStaffDailySalariesStaffDate);
        await m.createIndex(schema.idxStaffDailySalariesUpdatedAt);
      },
      from24To25: (m, schema) async {
        // Quantity-tier offers ("buy X quantity for Rs.Y", e.g. 1 = 45,
        // 2 = 85, 3 = 120) add QUANTITY_TIER to two CHECK constraints:
        // `offers.type` and the `sale_items.applied_offer_type` snapshot.
        // SQLite cannot ALTER a CHECK, so both tables are rebuilt: values are
        // copied into a backup, the old table is dropped, the new definition
        // is created and the rows are restored.
        //
        // Safe without toggling PRAGMA foreign_keys because nothing in the
        // local schema references `offers` or `sale_items` (both are leaf
        // tables — the sale FKs point OUT to shops/sales/products and are
        // recreated by createTable). `PRAGMA foreign_keys` is also a no-op
        // inside drift's migration transaction, so it could not be used here
        // even if it were needed.
        await _rebuildTablePreservingRows(
          m,
          table: 'offers',
          backup: 'offers_bak_v25',
          columns: const [
            'id',
            'shop_id',
            'name',
            'type',
            'config_json',
            'is_active',
            'start_at',
            'end_at',
            'created_at',
            'updated_at',
          ],
          needsRebuild: await _checkLacksValue(
            m.database,
            'offers',
            'type',
            'QUANTITY_TIER',
          ),
          create: () async {
            await m.createTable(schema.offers);
            await m.createIndex(schema.idxOffersShop);
            await m.createIndex(schema.idxOffersShopActive);
          },
        );

        await _rebuildTablePreservingRows(
          m,
          table: 'sale_items',
          backup: 'sale_items_bak_v25',
          columns: const [
            'id',
            'shop_id',
            'sale_id',
            'product_id',
            'variant_id',
            'product_name',
            'variant_name',
            'sku',
            'unit_price_paise',
            'quantity',
            'line_total_paise',
            'offer_discount_paise',
            'applied_offer_id',
            'applied_offer_name',
            'applied_offer_type',
          ],
          needsRebuild: await _checkLacksValue(
            m.database,
            'sale_items',
            'applied_offer_type',
            'QUANTITY_TIER',
          ),
          create: () async {
            await m.createTable(schema.saleItems);
            await m.createIndex(schema.idxSaleItemsShop);
            await m.createIndex(schema.idxSaleItemsSaleId);
          },
        );
      },
      from25To26: (m, schema) async {
        // Customer true-delete. `sales.customer_id` and
        // `customer_payments.customer_id` carried `ON DELETE RESTRICT`, so a
        // customer with any billing history could never be deleted — the owner
        // was stuck with a "deleted" row the app had to fake. Both foreign keys
        // are removed and the id is kept as a plain column, so the ledger keeps
        // its attribution and a deleted customer simply leaves a dangling id.
        //
        // `sales` is a REFERENCED table (`sale_items.sale_id` and
        // `customer_payments.sale_id` both point at it with RESTRICT), and
        // `PRAGMA foreign_keys = OFF` is a no-op inside drift's migration
        // transaction — so enforcement is *deferred* instead of disabled and
        // re-checked at COMMIT, by which point the copy is complete. Verified
        // against a populated database in
        // `test/core/database/customer_delete_migration_test.dart`.
        await _rebuildTablePreservingRows(
          m,
          table: 'sales',
          backup: 'sales_bak_v26',
          columns: const [
            'id',
            'shop_id',
            'customer_id',
            'receipt_number',
            'subtotal_paise',
            'total_paise',
            'offer_discount_paise',
            'payment_method',
            'payment_status',
            'created_at',
            'updated_at',
            'voided',
            'voided_at',
            'is_opening_balance',
          ],
          needsRebuild: await _referencesTable(
            m.database,
            'sales',
            'customers',
          ),
          create: () async {
            await m.createTable(schema.sales);
            await m.createIndex(schema.idxSalesShop);
            await m.createIndex(schema.idxSalesCreatedAt);
            await m.createIndex(schema.idxSalesCustomerId);
          },
        );

        await _rebuildTablePreservingRows(
          m,
          table: 'customer_payments',
          backup: 'customer_payments_bak_v26',
          columns: const [
            'id',
            'shop_id',
            'customer_id',
            'sale_id',
            'payment_group_id',
            'amount_paise',
            'payment_method',
            'note',
            'paid_at',
            'reversed',
            'reversed_at',
            'created_at',
            'updated_at',
          ],
          needsRebuild: await _referencesTable(
            m.database,
            'customer_payments',
            'customers',
          ),
          create: () async {
            await m.createTable(schema.customerPayments);
            await m.createIndex(schema.idxCustomerPaymentsShop);
            await m.createIndex(schema.idxCustomerPaymentsCustomerId);
            await m.createIndex(schema.idxCustomerPaymentsSaleId);
            await m.createIndex(schema.idxCustomerPaymentsPaidAt);
            await m.createIndex(schema.idxCustomerPaymentsGroup);
          },
        );
      },
      from26To27: (m, schema) async {
        // Shop payables: money actually paid against what the shop owes.
        //
        // Purely additive — a new append-only table. No existing expense row is
        // read, rewritten or dropped, which is the whole point: a payment must
        // never disturb the expense history it settles. Balances are derived
        // from `expenses` minus this table at read time (no stored balance
        // column), so nothing here needs backfilling and every device reaches
        // the same number from the same rows.
        await m.createTable(schema.expensePayments);
        await m.createIndex(schema.idxExpensePaymentsShop);
        await m.createIndex(schema.idxExpensePaymentsPayee);
        await m.createIndex(schema.idxExpensePaymentsPaidAt);
      },
      from27To28: (m, schema) async {
        // Two additive columns, no data is rewritten or dropped.
        //
        // Both are guarded by a real existence check rather than a bare
        // `addColumn`. The `user_version` and the physical schema can disagree
        // on a device that ran a build where the table definition had already
        // moved ahead of the versioned schema — a bare `addColumn` then fails
        // with "duplicate column name" and the app is bricked on a version it
        // has effectively already applied. Skipping an existing column is the
        // behaviour a fresh `createAll` install already has.
        //
        // 1. `shops.receipt_prefix` — the receipt LABEL moves from a global
        //    constant onto the business row. The counter was already isolated
        //    per shop in `sale_sequences (id, shop_id)`; only the prefix was
        //    shared, so a Food Truck sale printed a `BF-` receipt that was
        //    indistinguishable from a Cafe one. The default is the historical
        //    Cafe prefix, so an existing install keeps every number it already
        //    issued and the self-healing `LIKE 'BF-%'` scan in the receipt
        //    allocator still finds them.
        if (!await _hasColumn(m.database, 'shops', 'receipt_prefix')) {
          await m.addColumn(schema.shops, schema.shops.receiptPrefix);
        }

        // 2. `products.visible_in_shops` — the column the master-data sync
        //    already reads and writes. The Drift table gained it without a
        //    versioned schema, so an EXISTING install may have the column
        //    physically present while still reporting version 27, and some
        //    installs have neither. Adding it here covers the installs that
        //    need it and leaves the ones that already have it untouched.
        //
        //    Defaults to false (not shared) so no product silently becomes
        //    visible in the Food Truck as a side effect of upgrading.
        if (!await _hasColumn(m.database, 'products', 'visible_in_shops')) {
          await m.addColumn(schema.products, schema.products.visibleInShops);
        }
      },
      from28To29: (m, schema) async {
        // A brand-new table, so nothing existing is read, rewritten or dropped.
        //
        // `shop_product_stock` is the second shelf. `products` stays the single
        // master definition (name, price, variants, category) and
        // `products.visible_in_shops` decides which OTHER businesses may sell
        // it, but the quantity each business sells from is per business and
        // lives here. Without it, a Food Truck sale of a shared Cafe product
        // would have to decrement the Cafe's own `stock_quantity`, so the two
        // businesses would silently share one shelf — Cafe 100, truck 30, and
        // a single truck sale takes the Cafe's count down to 99.
        await m.createTable(schema.shopProductStock);
        await m.createIndex(schema.idxShopProductStockShop);
        await m.createIndex(schema.idxShopProductStockProduct);

        // The two partial unique indexes are separate objects, NOT part of the
        // table definition, so they have to be created here explicitly. The old
        // comment here claimed the unique key "arrives with createTable" — that
        // was true while the table still carried a `uniqueKeys` entry, and it
        // stopped being true the moment the key became two partial indexes.
        // Creating the table and forgetting these two would leave a migrated
        // device with NO uniqueness at all: two overlay rows for the same
        // business and product would both insert, an overlay read would stop
        // being a single-row lookup, and the conditional
        // `UPDATE ... WHERE quantity >= n` deduction would lose the guarantee
        // that makes it race-safe. The defect would be invisible on a fresh
        // install (createAll emits them from the table definition) and would
        // only ever show up on an upgraded device — the exact population that
        // needs the second shelf to be correct.
        //
        // They cannot be a single `UNIQUE (shop_id, product_id, variant_id)`:
        // SQLite treats NULLs as distinct, so that would happily accept any
        // number of product-level rows for one business. Hence two partial
        // indexes, one per level.
        await m.createIndex(schema.uxShopProductStockProductLevel);
        await m.createIndex(schema.uxShopProductStockVariantLevel);
      },
      from29To30: (m, schema) async {
        // Split-payment legs. A brand-new table, so nothing existing is read,
        // rewritten or dropped. The sales.payment_method column stays for
        // backward compatibility — split sales leave it NULL and store the
        // individual Cash/UPI legs here.
        await m.createTable(schema.salePayments);
        await m.createIndex(schema.idxSalePaymentsSale);
      },
    )(migrator, from, to);
  }

  /// True when [table] already has a [column].
  ///
  /// Used to keep an additive migration genuinely idempotent: a device whose
  /// physical schema is ahead of its `user_version` must not be failed by a
  /// duplicate `ALTER TABLE ... ADD COLUMN`.
  static Future<bool> _hasColumn(
    GeneratedDatabase db,
    String table,
    String column,
  ) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  /// True when [table] still declares a foreign key pointing at [target], i.e.
  /// the rebuild is still needed.
  static Future<bool> _referencesTable(
    GeneratedDatabase db,
    String table,
    String target,
  ) async {
    final row = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable.withString(table)],
        )
        .getSingleOrNull();
    final ddl = row?.data['sql'] as String?;
    if (ddl == null) return false;
    return ddl.contains('REFERENCES $target');
  }

  /// True when [table]'s DDL does not already mention [value], i.e. the CHECK
  /// still needs widening. A device that already carries the widened CHECK is
  /// left completely alone — rebuilding a table rewrites every historical
  /// row, which is not something to do twice.
  static Future<bool> _checkLacksValue(
    GeneratedDatabase db,
    String table,
    String column,
    String value,
  ) async {
    final row = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable.withString(table)],
        )
        .getSingleOrNull();
    final ddl = row?.data['sql'] as String?;
    return ddl == null || !ddl.contains("'$value'");
  }

  /// Rebuilds [table] through [backup] so a CHECK constraint can be widened or
  /// a foreign key dropped. [create] recreates the table with the current
  /// definition plus its indexes.
  ///
  /// Two details make this safe on a real device:
  ///
  ///  * `PRAGMA defer_foreign_keys = ON` postpones foreign-key enforcement to
  ///    COMMIT instead of turning it off, because `PRAGMA foreign_keys = OFF`
  ///    is a no-op inside a transaction and drift runs every step inside one.
  ///    This is what lets a *referenced* table such as `sales` be dropped and
  ///    recreated while its children still point at it.
  ///  * The row copy names its columns explicitly and only carries the ones the
  ///    backup actually has, instead of `SELECT *`. A bare `SELECT *` aborts the
  ///    entire migration — leaving the app unable to open — the moment the
  ///    stored table has a different column set than the current definition.
  static Future<void> _rebuildTablePreservingRows(
    Migrator m, {
    required String table,
    required String backup,
    required List<String> columns,
    required bool needsRebuild,
    required Future<void> Function() create,
  }) async {
    if (!needsRebuild) return;

    await m.database.customStatement('PRAGMA defer_foreign_keys = ON');
    await m.database.customStatement(
      'CREATE TABLE $backup AS SELECT * FROM $table',
    );
    // Intersect with what the stored table really has so an older or newer
    // column set can never fail the copy.
    final info = await m.database
        .customSelect('PRAGMA table_info($backup)')
        .get();
    final present = info.map((r) => r.data['name'] as String).toSet();
    final shared = columns.where(present.contains).toList();

    await m.database.customStatement('DROP TABLE $table');
    await create();
    if (shared.isNotEmpty) {
      final list = shared.join(',');
      await m.database.customStatement(
        'INSERT INTO $table ($list) SELECT $list FROM $backup',
      );
    }
    await m.database.customStatement('DROP TABLE $backup');
  }
}
