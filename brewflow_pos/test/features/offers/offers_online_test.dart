import 'dart:async';

import 'package:brewflow_pos/core/database/app_database.dart' as app;
import 'package:brewflow_pos/features/offers/data/drift_offers_repository.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_connectivity_service.dart';

/// Hand-rolled fake of the Supabase query chain that the repository awaits.
///
/// The repository's cloud statements chain `from(...).update/delete/upsert.eq`
/// and then `await` the final [PostgrestFilterBuilder] (a `Future`). The fake
/// mirrors that chain with one [SupabaseQueryBuilder] fake that records the
/// write and hands off a [PostgrestFilterBuilder] fake which records `eq` and
/// implements `then` so the `await` resolves with an empty result (the
/// repository discards the response). Everything is recorded into a shared
/// per-table [FakeBatchState] the tests can assert against.
class _NullFake {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}

class FakeBatchState {
  final List<(String, Object?)> eqCalls = [];
  Map<String, dynamic>? updateValues;
  Map<String, dynamic>? upsertValues;
  bool deleteCalled = false;
}

class _FakeSupabaseClient extends _NullFake implements SupabaseClient {
  final Map<String, FakeBatchState> states = {};

  FakeBatchState state(String table) => states[table]!;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #from) {
      final table = invocation.positionalArguments.first as String;
      return _FakeQueryBuilder(states.putIfAbsent(table, FakeBatchState.new));
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeQueryBuilder extends _NullFake implements SupabaseQueryBuilder {
  _FakeQueryBuilder(this._state);

  final FakeBatchState _state;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #update:
        _state.updateValues = Map<String, dynamic>.from(
          invocation.positionalArguments[0] as Map,
        );
        return _FakeFilterBuilder(_state);
      case #upsert:
        _state.upsertValues = Map<String, dynamic>.from(
          invocation.positionalArguments[0] as Map,
        );
        return _FakeFilterBuilder(_state);
      case #delete:
        _state.deleteCalled = true;
        return _FakeFilterBuilder(_state);
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeFilterBuilder extends _NullFake
    implements PostgrestFilterBuilder<dynamic> {
  _FakeFilterBuilder(this._state);

  final FakeBatchState _state;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #eq) {
      _state.eqCalls.add((
        invocation.positionalArguments[0] as String,
        invocation.positionalArguments[1],
      ));
      return _FakeFilterBuilder(_state);
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic) onValue, {
    Function? onError,
    void Function()? onWhenComplete,
  }) {
    return Future<R>.value(onValue(const <Map<String, dynamic>>[]));
  }
}

Offer _mutated(Offer o, {String? name, bool? isActive, String? configJson}) =>
    Offer(
      id: o.id,
      shopId: o.shopId,
      name: name ?? o.name,
      type: o.type,
      configJson: configJson ?? o.configJson,
      isActive: isActive ?? o.isActive,
      startAt: o.startAt,
      endAt: o.endAt,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt,
    );

void main() {
  group('Offers online-only cloud-authoritative update/delete', () {
    late app.AppDatabase db;

    Future<void> seedShop(String id, String name) async {
      await db
          .into(db.shops)
          .insert(app.ShopsCompanion.insert(id: Value(id), name: name));
    }

    Future<Offer> seedOffer(
      String shopId, {
      String name = '10% off',
      String configJson = '{"pct":10}',
    }) async {
      return DriftOffersRepository(db).createOffer(
        shopId: shopId,
        name: name,
        type: OfferType.percentage,
        configJson: configJson,
      );
    }

    Future<int> outboxPendingCount() async {
      final q = db.selectOnly(db.syncOutbox)
        ..addColumns([db.syncOutbox.id.count()])
        ..where(db.syncOutbox.status.equals('PENDING'));
      return q.map((row) => row.read(db.syncOutbox.id.count())!).getSingle();
    }

    SyncOutboxCoordinator wiredOutbox() => SyncOutboxCoordinator(
      DriftSyncRepository(db),
      () async => const SyncSessionContext(
        deviceId: 'dev-1',
        shopId: 'shop-1',
        userId: 'user-1',
      ),
    );

    setUp(() async {
      db = app.AppDatabase(NativeDatabase.memory());
      await seedShop('shop-1', 'Cafe');
    });

    tearDown(() async => db.close());

    test('online updateOffer sends a shop-scoped cloud update and mirrors '
        'locally', () async {
      final offer = await seedOffer('shop-1');
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = _FakeSupabaseClient();
      final repo = DriftOffersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: cloud,
      );

      final updated = await repo.updateOffer(
        _mutated(offer, name: '20% off', configJson: '{"pct":20}'),
      );

      expect(updated.name, '20% off');
      final batch = cloud.state('offers');
      expect(batch.updateValues?['name'], '20% off');
      expect(batch.updateValues?['config_json'], '{"pct":20}');
      expect(batch.eqCalls, [('id', offer.id), ('shop_id', 'shop-1')]);
      final row = await (db.select(
        db.offers,
      )..where((t) => t.id.equals(offer.id))).getSingle();
      expect(row.name, '20% off');
      expect(await outboxPendingCount(), 0);
    });

    test('online deleteOffer deletes on cloud, writes a tombstone and '
        'mirrors locally', () async {
      final offer = await seedOffer('shop-1');
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = _FakeSupabaseClient();
      final repo = DriftOffersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: cloud,
      );

      await repo.deleteOffer(offer.id);

      final offersBatch = cloud.state('offers');
      expect(offersBatch.deleteCalled, isTrue);
      expect(offersBatch.eqCalls, contains(('id', offer.id)));
      expect(cloud.state('master_deletions').upsertValues, {
        'entity': 'OFFER',
        'id': offer.id,
        'shop_id': 'shop-1',
      });
      final rows = await (db.select(
        db.offers,
      )..where((t) => t.id.equals(offer.id))).get();
      expect(rows, isEmpty);
      expect(await outboxPendingCount(), 0);
    });

    test('offline updateOffer is rejected and mutates nothing', () async {
      final offer = await seedOffer('shop-1');
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftOffersRepository(
        db,
        outbox: wiredOutbox(),
        connectivityService: connectivity,
        supabaseClient: null,
      );

      await expectLater(
        repo.updateOffer(_mutated(offer, name: 'should not apply')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      final row = await (db.select(
        db.offers,
      )..where((t) => t.id.equals(offer.id))).getSingle();
      expect(row.name, '10% off');
      expect(await outboxPendingCount(), 0);
    });

    test('offline deleteOffer is rejected and keeps the offer', () async {
      final offer = await seedOffer('shop-1');
      final connectivity = fakeConnectivityService();
      await connectivity.init();
      final repo = DriftOffersRepository(
        db,
        outbox: wiredOutbox(),
        connectivityService: connectivity,
        supabaseClient: null,
      );

      await expectLater(
        repo.deleteOffer(offer.id),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'msg',
            contains('Internet connection required'),
          ),
        ),
      );
      final rows = await (db.select(
        db.offers,
      )..where((t) => t.id.equals(offer.id))).get();
      expect(rows, hasLength(1));
      expect(await outboxPendingCount(), 0);
    });

    test('online update and delete never enqueue outbox entries', () async {
      final offer = await seedOffer('shop-1');
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final repo = DriftOffersRepository(
        db,
        outbox: wiredOutbox(),
        connectivityService: connectivity,
        supabaseClient: _FakeSupabaseClient(),
      );

      await repo.updateOffer(_mutated(offer, name: '15% off'));
      expect(await outboxPendingCount(), 0);

      await repo.deleteOffer(offer.id);
      expect(await outboxPendingCount(), 0);
    });

    test('business isolation: cloud calls and local mirror never leak '
        'across shops', () async {
      await seedShop('shop-2', 'Food Truck');
      final offer = await seedOffer('shop-1', name: 'Cafe Special');
      final connectivity = fakeConnectivityServiceOnline();
      await connectivity.init();
      final cloud = _FakeSupabaseClient();
      final repo = DriftOffersRepository(
        db,
        connectivityService: connectivity,
        supabaseClient: cloud,
      );

      final updated = await repo.updateOffer(_mutated(offer, name: 'Updated'));
      expect(cloud.state('offers').eqCalls, contains(('shop_id', 'shop-1')));
      expect(
        cloud.state('offers').eqCalls,
        isNot(contains(('shop_id', 'shop-2'))),
      );
      expect(await DriftOffersRepository(db).offersForShop('shop-2'), isEmpty);
      expect(
        (await DriftOffersRepository(db).offersForShop('shop-1')).single.name,
        'Updated',
      );

      await repo.deleteOffer(updated.id);
      expect(
        cloud.state('master_deletions').upsertValues?['shop_id'],
        'shop-1',
      );
      expect(await DriftOffersRepository(db).offersForShop('shop-1'), isEmpty);
    });

    test('local-only fallback still works when no cloud or connectivity is '
        'wired', () async {
      final offer = await seedOffer('shop-1');
      final repo = DriftOffersRepository(db);

      final updated = await repo.updateOffer(_mutated(offer, name: 'Renamed'));
      expect(updated.name, 'Renamed');

      await repo.deleteOffer(updated.id);
      expect(await repo.offersForShop('shop-1'), isEmpty);
    });
  });
}
