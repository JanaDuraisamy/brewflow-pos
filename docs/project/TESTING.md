# Testing

Run from `brewflow_pos/`:

```bash
flutter test
```

Expected result on a clean mainline: `All tests passed!`

## Conventions

- Tests live under `test/` mirroring the feature folders
  (e.g. `test/features/billing/`, `test/features/orders/`, `test/helpers/`).
- Fakes live in `test/helpers/` (e.g. `fake_orders_repository.dart`) and are kept in
  lockstep with repository/domain model changes.
- Widget tests use `testWidgets`; unit/contract tests use `test`/`group`.
- Drift in-memory databases are used for repository tests.

## Coverage highlights

### Void-sale regression tests (`test/features/billing/billing_repository_test.dart`)

`group('voidSale')` covers:

1. Restores stock + keeps the row + marks it voided/voidedAt.
2. Double-void throws `SaleAlreadyVoidedFailure` (no double stock restore).
3. Unknown sale throws `SaleNotFoundFailure`.
4. Reverses a directly-inserted linked customer payment (`reversed` + `reversedAt`).

### POS stock-0 regression tests (`test/features/billing/billing_controller_test.dart`)

`group('POS zero-stock visibility')` covers the Bug 7.8E-B fix:

1. Active zero-stock product is **visible** on the shelf; inactive products stay hidden;
   stocked products are visible.
2. A shelf-visible zero-stock product blocks `add()` with `InsufficientStockFailure`,
   and the cart stays empty.

### Voided-badge test (`test/features/orders/orders_page_test.dart`)

- `'shows a Voided badge for voided sales'` — verifies a voided order surfaces the
  Voided badge. `seedOrder` supports `isVoided` / `voidedAt`.

### POS page tests (`test/features/billing/pos_page_test.dart`)

Updated to the corrected Bug 7.8E-B behavior:

- The shelf lists active products and keeps active zero-stock ones visible (as "Sold out").
- Cart totals and "Not Paid" due-preview counts account for a sold-out zero-stock shelf card.
- Category filtering shows an active zero-stock item in its category.

## Test pitfalls

- When a test imports both `package:drift/drift.dart` and
  `package:flutter_test/flutter_test.dart` (or `billing_models.dart`), avoid ambiguous
  `isNotNull` / `isA<Sale>()` matchers — use `loaded?.voided`, `isA<DateTime>()`.
- Drift `.insert()` companion constructors: required-no-default columns take raw values
  (`customerId: 'c1'`), nullable columns take `Value<T?>` (e.g. `saleId: Value<String?>(saleId)`),
  clientDefault columns take `Value<T>`.
- Private `_VoidedBadge` widgets must not use `super.key` (avoids the
  `unused_element_parameter` analyzer warning) — use `const _VoidedBadge();`.

## Analysis

```bash
flutter analyze
```

Expected: `No issues found!`
