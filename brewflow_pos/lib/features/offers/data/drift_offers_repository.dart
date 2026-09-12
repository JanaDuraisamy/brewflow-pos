import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/offers/domain/offers_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final class DriftOffersRepository implements OffersRepository {
  DriftOffersRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outbox,
    ConnectivityService? connectivityService,
    SupabaseClient? supabaseClient,
  }) : _db = database,
       _outbox = outbox,
       _connectivity = connectivityService,
       _supabase = supabaseClient;

  static const String tag = 'Offers';
  final db.AppDatabase _db;
  final SyncOutboxCoordinator? _outbox;
  final ConnectivityService? _connectivity;
  final SupabaseClient? _supabase;

  Future<void> _requireOnline() async {
    if (_connectivity != null)
      await OnlineGuard(_connectivity!).requireOnline();
  }

  @override
  Future<List<Offer>> offersForShop(String shopId) async {
    final rows =
        await (_db.select(_db.offers)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<Offer>> allOffers() async {
    final rows = await (_db.select(
      _db.offers,
    )..orderBy([(t) => OrderingTerm.desc(_db.offers.createdAt)])).get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Offer> createOffer({
    required String shopId,
    required String name,
    required OfferType type,
    required String configJson,
    bool isActive = true,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    if (_connectivity != null || _supabase != null) {
      try {
        await _requireOnline();
      } catch (e) {
        throw Exception(
          'Internet connection required. Please check your connection and try again.',
        );
      }
    }
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
    if (_supabase != null) {
      await write();
      try {
        await _supabase!.from('offers').upsert({
          'id': id,
          'shop_id': shopId,
          'name': name,
          'type': type.wire,
          'config_json': configJson,
          'is_active': isActive,
          'start_at': startAt?.toIso8601String(),
          'end_at': endAt?.toIso8601String(),
          'client_created_at': now.toIso8601String(),
        }, onConflict: 'id');
      } catch (e) {
        if (e.toString().contains('SocketException'))
          throw Exception(
            'Internet connection required. Please check your connection and try again.',
          );
        rethrow;
      }
    } else if (outbox == null) {
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

  @override
  Future<Offer> updateOffer(Offer offer) async {
    if (_connectivity != null || _supabase != null) {
      try {
        await _requireOnline();
      } catch (e) {
        throw Exception(
          'Internet connection required. Please check your connection and try again.',
        );
      }
    }
    final now = DateTime.now().toUtc();

    if (_supabase != null) {
      try {
        // Cloud-authoritative update, scoped to the offer's own business so a
        // tampered shopId can never leak to another shop.
        await _supabase!
            .from('offers')
            .update({
              'name': offer.name,
              'type': offer.type.wire,
              'config_json': offer.configJson,
              'is_active': offer.isActive,
              'start_at': offer.startAt?.toIso8601String(),
              'end_at': offer.endAt?.toIso8601String(),
            })
            .eq('id', offer.id)
            .eq('shop_id', offer.shopId);
      } catch (e) {
        if (e.toString().contains('SocketException'))
          throw Exception(
            'Internet connection required. Please check your connection and try again.',
          );
        rethrow;
      }
    }

    // Mirror the authoritative state locally (cache for offline reads).
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
    final updated = await (_db.select(
      _db.offers,
    )..where((t) => t.id.equals(offer.id))).getSingle();
    return _fromRow(updated);
  }

  @override
  Future<void> deleteOffer(String id) async {
    if (_connectivity != null || _supabase != null) {
      try {
        await _requireOnline();
      } catch (e) {
        throw Exception(
          'Internet connection required. Please check your connection and try again.',
        );
      }
    }
    // Resolve the offer's actual business shopId for the tombstone so the
    // deletion is scoped correctly and does not leak across businesses.
    String? offerShopId;
    try {
      final existing = await (_db.select(
        _db.offers,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      offerShopId = existing?.shopId;
    } catch (_) {}

    if (_supabase != null) {
      try {
        await _supabase!.from('offers').delete().eq('id', id);
        // Tombstone so pulled-in peers do not resurrect the offer.
        await _supabase!.from('master_deletions').upsert({
          'entity': 'OFFER',
          'id': id,
          'shop_id': offerShopId,
        }, onConflict: 'entity,id');
      } catch (e) {
        if (e.toString().contains('SocketException'))
          throw Exception(
            'Internet connection required. Please check your connection and try again.',
          );
        rethrow;
      }
    }

    // Mirror the authoritative delete locally.
    await (_db.delete(_db.offers)..where((t) => t.id.equals(id))).go();
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
