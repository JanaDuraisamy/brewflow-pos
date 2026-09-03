import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// ProductImageSync — durable local queue of product-image cloud intents
///
/// One row per product image that still needs to reach (or be removed from,
/// or be fetched from) the cloud. Rows are binary-intent records — they hold
/// paths and metadata, never image bytes — so a device can go offline safely:
/// an UPLOAD / DOWNLOAD / DELETE is retried on later cycles exactly like the
/// row-sync outbox, and a crash never loses an intended image change.
///
/// Duplicate safety: the identity index (product_id, operation) collapses
/// replays of the same logical intent while it is still pending, so re-saving
/// a product image or re-running a download can never duplicate cloud work.
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_product_image_sync_identity',
  columns: {#productId, #operation},
)
@TableIndex(
  name: 'idx_product_image_sync_status',
  columns: {#status, #createdAt},
)
class ProductImageSync extends Table {
  /// Local UUID v4 identifier.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Shop scope of the image (isolation boundary for cloud path + RLS).
  TextColumn get shopId => text()();

  /// Stable UUID of the product the image belongs to.
  TextColumn get productId => text()();

  /// Operation: 'UPLOAD', 'DOWNLOAD' or 'DELETE'.
  TextColumn get operation => text()();

  /// Supabase Storage object path for this image (the destination of an
  /// UPLOAD, the source of a DOWNLOAD, or the object a DELETE removes).
  TextColumn get cloudPath => text().nullable()();

  /// Local relative image path involved in the intent: the local file an
  /// UPLOAD reads from, or the cache path a DOWNLOAD writes to.
  TextColumn get localPath => text().nullable()();

  /// PENDING → IN_FLIGHT → DONE / FAILED (FAILED keeps rows for inspection;
  /// retry counters live here too).
  TextColumn get status => text().withDefault(const Constant('PENDING'))();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
