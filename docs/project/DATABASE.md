# Database

Drift (typed SQLite) drives all local persistence. Schema version: **15**.

## Key tables

| Table | Purpose |
| --- | --- |
| `categories` | Product categories, `isActive` |
| `products` | Products, unit/price/cost, `isActive`, low-stock mode |
| `product_variants` | Variants of a product with own price/stock |
| `stock_movements` | Immutable stock ledger (additions/removals) |
| `customers` | Customer profiles, `isActive` |
| `customer_payments` | Payments against sales (customer ledger), append-only, `reversed` flag |
| `sales` | Completed sales incl. `voided` / `voidedAt`, `payment_status` |
| `sale_items` | Line items per sale |
| `suppliers` | Supplier profiles |
| `purchases` / `purchase_items` | Purchase orders and their lines |
| `expenses` | Expense records |
| `sale_sequences` / `purchase_sequences` | Receipt number generation |
| `users` | User profiles (role, isActive) |
| `staff_permissions` | Composite PK (`userId`, `permission`), `enabled` |
| `shops` | Shop identity used across devices |
| `devices` | Registered devices for sync |
| `sync_outbox` | Offline-first outbox (see SYNC.md) |

## Schema migration 14 -> 15 (Phase 7.8E)

Adds voided-sale support to the `sales` table:

- `sales.voided` — bool, default false.
- `sales.voidedAt` — nullable DateTime, set when voided.

## Void-sale behavior (schema + logic)

Voiding a sale (see `BillingRepository.voidSale` in
`lib/features/billing/data/drift_billing_repository.dart`):

1. Restores stock for each line item through the stock-movement ledger (custom SQL).
2. Keeps the sale row (packaging/ability to reprint) but flips `voided = true` and sets `voidedAt`.
3. Reverses any linked `customer_payments` rows (`reversed = true` + `reversedAt`), so due totals stay correct.
4. A second void of the same sale throws `SaleAlreadyVoidedFailure`; an unknown sale throws `SaleNotFoundFailure`.

The orders layer surfaces this via `OrderSummary.isVoided` / `Order.isVoided`
(`lib/features/orders/domain/orders_models.dart`), populated from `sales.voided` /
`sales.voidedAt` in `DriftOrdersRepository`, and rendered with a Voided badge.

## POS stock guard

Checkout uses a `WHERE stock_quantity >= ?` SQL guard plus `InsufficientStockFailure` in
`_checkoutCore`, so a zero-stock product blocked at the cart (`add()` throws
`InsufficientStockFailure`) can never be sold even under concurrency.

## Money

- All amounts are integer paise. Format via `Money` helpers (e.g. `Money.formatPaise`).
- Receipt prices render from paise, never float.

## Customer ledger

- Due/outstanding values are derived at read time: `totalPurchasesPaise - totalPaidPaise`.
- `recordPayment` runs in a transaction with a conditional SQLite UPDATE
  (`total_paise - SUM(non-reversed payments) >= amountPaise`) for race-safe serialization.
- Full settlement flips `sales.payment_status` to `PAID` in the same transaction.
