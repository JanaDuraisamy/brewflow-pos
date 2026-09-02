import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

final class DriftOffersRepository {
  DriftOffersRepository(db.AppDatabase database, {this._outbox})
    : _db = database;

  static const String tag = 'Offers';
  final db.AppDatabase _db;
  final SyncOutboxCoordinator? _outbox;

  Future<List<Offer>> offersForShop(String shopId) async {
    final rows =
        await (_db.select(_db.offers)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows.map(_fromRow).toList();
  }

  Future<List<Offer>> allOffers() async {
    final rows = await (_db.select(
      _db.offers,
    )..orderBy([(t) => OrderingTerm.desc(_db.offers.createdAt)])).get();
    return rows.map(_fromRow).toList();
  }

  Future<Offer> createOffer({
    required String shopId,
    required String name,
    required OfferType type,
    required String configJson,
    bool isActive = true,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final row = db.OffersCompanion.insert(
      id: Value(id),
      shopId: Value(shopId),
      name: name,
      type: type.wire,
      configJson: configJson,
      isActive: Value(isActive),
      startAt: Value(startAt),
      endAt: Value(endAt),
      createdAt: Value(now),
      updatedAt: Value(now),
    );

    Future<void> write() => _db.into(_db.offers).insert(row);

    final outbox = _outbox;
    if (outbox == null) {
      await write();
    } else {
      await outbox.run(
        write: write,
        snapshots: (_, ctx) async => [
          OutboxAppend(
            entity: MasterEntity.offer,
            entityId: id,
            // Use the offer's actual business shopId, not the session's
            // shopId, so a Cafe offer never leaks to Food Truck via outbox.
            payload: SyncOffer(
              id: id,
              shopId: shopId,
              name: name,
              type: type.wire,
              configJson: configJson,
              isActive: isActive,
              startAt: startAt,
              endAt: endAt,
              createdAt: now,
              updatedAt: now,
            ).toJson(),
          ),
        ],
      );
    }
    final created = await (_db.select(
      _db.offers,
    )..where((t) => t.id.equals(id))).getSingle();
    return _fromRow(created);
  }

  Future<Offer> updateOffer(Offer offer) async {
    final now = DateTime.now().toUtc();
    Future<void> write() async {
      await (_db.update(_db.offers)..where((t) => t.id.equals(offer.id))).write(
        db.OffersCompanion(
          name: Value(offer.name),
          type: Value(offer.type.wire),
          configJson: Value(offer.configJson),
          isActive: Value(offer.isActive),
          startAt: Value(offer.startAt),
          endAt: Value(offer.endAt),
          updatedAt: Value(now),
        ),
      );
    }

    final outbox = _outbox;
    if (outbox == null) {
      await write();
    } else {
      await outbox.run(
        write: write,
        snapshots: (_, ctx) async => [
          OutboxAppend(
            entity: MasterEntity.offer,
            entityId: offer.id,
            payload: SyncOffer(
              id: offer.id,
              shopId: offer.shopId,
              name: offer.name,
              type: offer.type.wire,
              configJson: offer.configJson,
              isActive: offer.isActive,
              startAt: offer.startAt,
              endAt: offer.endAt,
              createdAt: offer.createdAt,
              updatedAt: now,
            ).toJson(),
          ),
        ],
      );
    }
    final updated = await (_db.select(
      _db.offers,
    )..where((t) => t.id.equals(offer.id))).getSingle();
    return _fromRow(updated);
  }

  Future<void> deleteOffer(String id) async {
    // Resolve the offer's actual business shopId for the tombstone so the
    // deletion is scoped correctly and does not leak across businesses.
    String? offerShopId;
    try {
      final existing = await (_db.select(
        _db.offers,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      offerShopId = existing?.shopId;
    } catch (_) {}

    Future<void> write() async {
      await (_db.delete(_db.offers)..where((t) => t.id.equals(id))).go();
    }

    final outbox = _outbox;
    if (outbox == null) {
      await write();
      return;
    }
    await outbox.run(
      write: write,
      snapshots: (_, ctx) async => [
        OutboxAppend(
          entity: MasterEntity.offer,
          entityId: id,
          payload: {'id': id, 'shopId': offerShopId ?? ctx.shopId},
          operation: 'DELETE',
        ),
      ],
    );
  }

  static Offer _fromRow(db.Offer row) => Offer(
    id: row.id,
    shopId: row.shopId!,
    name: row.name,
    type: OfferType.fromWire(row.type),
    configJson: row.configJson,
    isActive: row.isActive,
    startAt: row.startAt,
    endAt: row.endAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
