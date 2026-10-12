/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Failure Inspection (domain)
///
/// Read model for outbox entries that parked as FAILED after exhausting their
/// retry attempts. The dashboard badge shows one entry per failure; the
/// failures sheet renders each entry with a human-readable reason and a safe
/// per-entry retry.
///
/// The raw gateway error is NEVER rendered directly: it may embed tokens,
/// URLs or internal identifiers. [reason] is the only user-facing text.
/// ---------------------------------------------------------------------------
library;

/// How a parked failure should be treated.
enum SyncFailureKind {
  /// Likely transient (network/timeout/server) — a manual retry is sensible.
  retryable,

  /// A validation, authorization or schema problem — retrying will not help
  /// until the underlying data or permission is fixed.
  blocked,
}

/// One FAILED outbox entry, shaped for the failures sheet.
final class SyncFailureEntry {
  const SyncFailureEntry({
    required this.id,
    required this.entity,
    required this.operation,
    required this.entityId,
    required this.lastError,
    required this.lastAttemptAt,
    required this.attemptCount,
  });

  final String id;
  final String entity;

  /// 'UPSERT' or 'DELETE'.
  final String operation;
  final String entityId;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final int attemptCount;

  /// Transient vs permanent (see [classifySyncFailure]).
  SyncFailureKind get kind => classifySyncFailure(lastError);

  /// Short, user-facing headline, e.g. "Product upload".
  String get title => describeSyncOperation(entity, operation);

  /// User-facing explanation of [kind] — never the raw error.
  String get reason => friendlyFailureReason(kind);
}

/// Classifies a raw gateway error string as transient or permanent.
///
/// Matches lowercase fragments against known permanent conditions (auth,
/// permissions, SQL constraint violations, missing relations/columns,
/// PostgREST errors). Everything else is treated as retryable so the owner can
/// at least attempt a manual retry.
SyncFailureKind classifySyncFailure(String? raw) {
  if (raw == null) return SyncFailureKind.retryable;
  final lower = raw.toLowerCase();
  const permanent = <String>[
    'unauthorized',
    'forbidden',
    'permission denied',
    'not authorized',
    'jwt',
    'token expired',
    'invalid api key',
    '23503', // foreign key violation
    '23505', // unique violation
    '23514', // check violation
    '22p02', // invalid text representation
    'pgrst',
    'relation "',
    'relation \'',
    'does not exist',
    'undefined_table',
    'undefined_column',
    'violates',
    'duplicate key',
  ];
  for (final fragment in permanent) {
    if (lower.contains(fragment)) return SyncFailureKind.blocked;
  }
  return SyncFailureKind.retryable;
}

/// Human-readable headline for a failed outbox operation.
String describeSyncOperation(String entity, String operation) {
  final noun = switch (entity) {
    'SHOP' => 'Shop',
    'CATEGORY' => 'Category',
    'PRODUCT' => 'Product',
    'PRODUCT_VARIANT' => 'Product variant',
    'SUPPLIER' => 'Supplier',
    'CUSTOMER' => 'Customer',
    'SALE' => 'Sale',
    'SALE_ITEM' => 'Sale item',
    'EXPENSE' => 'Expense',
    'CUSTOMER_PAYMENT' => 'Customer payment',
    'EXPENSE_PAYMENT' => 'Expense payment',
    'OFFER' => 'Offer',
    'STAFF_PROFILE' => 'Staff member',
    'STAFF_ATTENDANCE' => 'Staff attendance',
    'PRODUCT_RECIPE' => 'Product recipe',
    'MONTHLY_REPORT_CONFIRMATION' => 'Monthly report',
    'MONTH_CLEANUP' => 'Month cleanup',
    _ => entity,
  };
  return operation == 'DELETE' ? '$noun deletion' : '$noun upload';
}

/// User-facing explanation for a failure kind. Safe to render.
String friendlyFailureReason(SyncFailureKind kind) => switch (kind) {
  SyncFailureKind.retryable =>
    'Could not reach the server. Check the connection and try again.',
  SyncFailureKind.blocked =>
    'The server rejected this change (permission or data problem). '
        'Contact support if it keeps failing.',
};
