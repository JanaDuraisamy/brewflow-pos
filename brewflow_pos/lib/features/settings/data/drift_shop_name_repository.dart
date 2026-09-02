import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/settings/domain/shop_name_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Shop-Name Repository
///
/// The authoritative local shop display name lives in the `shops` table. This
/// repository reads it (for settings load) and persists a rename ATOMICALLY
/// with a SHOP outbox append when a sync session is available.
///
/// Offline-first: when no sync session context resolves — or no shop row
/// exists yet — [persist] degrades to a plain local write with no queue
/// entry, exactly like every other master-data repository in the app. When no
/// `shops` row exists at all (e.g. a tablet whose shop row was never
/// bootstrapped), [persist] CREATES one so a manual rename is never dropped.
/// ---------------------------------------------------------------------------

final class DriftShopNameRepository implements ShopNameRepository {
  DriftShopNameRepository(this._database, [this._outbox]);

  static const String tag = 'ShopName';

  final db.AppDatabase _database;
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<String?> currentName() async {
    try {
      final row = await _database.select(_database.shops).getSingleOrNull();
      return row?.name;
    } on Exception catch (error, stackTrace) {
      AppLog.warning(
        'Could not read current shop name',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<void> persist(String name) async {
    final trimmed = name.trim();
    final row = await _database.select(_database.shops).getSingleOrNull();
    if (row != null && row.name == trimmed) return;

    final now = DateTime.now().toUtc();

    // Authoritative rename target. When a `shops` row already exists (normal
    // owner-bootstrap / synced tablet) reuse its id — the single-shop contract
    // means the id must never change. When no row exists yet (e.g. a tablet
    // whose shop row was never bootstrapped), CREATE it here so the manual
    // save is never silently dropped. `getSingleOrNull` guards against
    // duplicates by construction (we only insert when the table is empty).
    final String shopRowId;
    final DateTime createdAt;
    if (row != null) {
      shopRowId = row.id;
      createdAt = row.createdAt;
    } else {
      shopRowId = const Uuid().v4();
      createdAt = now;
    }

    Future<void> write() => _database.transaction(() async {
      if (row == null) {
        await _database
            .into(_database.shops)
            .insert(
              db.ShopsCompanion.insert(
                id: Value(shopRowId),
                name: trimmed,
                createdAt: Value(createdAt),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (_database.update(
          _database.shops,
        )..where((t) => t.id.equals(row.id))).write(
          db.ShopsCompanion(name: Value(trimmed), updatedAt: Value(now)),
        );
      }
    });

    final outbox = _outbox;
    if (outbox == null) {
      await write();
      return;
    }

    await outbox.run(
      write: write,
      snapshots: (_, context) async => [
        OutboxAppend(
          entity: MasterEntity.shop,
          entityId: shopRowId,
          payload: SyncShop(
            id: shopRowId,
            shopId: context.shopId,
            name: trimmed,
            createdAt: createdAt,
          ).toJson(),
        ),
      ],
    );
  }
}
