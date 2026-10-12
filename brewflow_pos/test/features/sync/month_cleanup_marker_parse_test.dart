import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Month-cleanup marker wire-format regression tests.
///
/// The server writes `month_cleanup_markers.tables` as a JSON OBJECT
/// (`{"sales": true, ...}` via `jsonb_object_agg` in migration 0043), not a
/// JSON array. The pull parser used to cast it `as List`, so EVERY marker row
/// threw a Map-vs-List type-cast error, aborting each sync cycle inside
/// `_drainMonthCleanupMarkers` — before sales, sale items and customer
/// payments ever drained — and freezing `lastPulledAt`.
///
/// These tests pin the exact PostgREST payload shape (snake_case, object
/// `tables`) plus the defensive cases: empty `{}`, null, malformed values,
/// and the legacy array shape pushed by older clients.
/// ---------------------------------------------------------------------------

/// One marker row exactly as PostgREST returns it.
Map<String, dynamic> serverMarkerRow({
  Object? tables = const {'sales': true},
  Object? deletedCounts = const {'sales': 12},
}) => <String, dynamic>{
  'id': 'marker-1',
  'shop_id': 'shop-a',
  'month': '2026-09-01',
  'tables': tables,
  'deleted_counts': deletedCounts,
  'completed_at': '2026-10-08T16:20:00.000+00:00',
  'client_created_at': '2026-10-08T16:20:00.000+00:00',
  'created_at': '2026-10-08T16:20:00.000+00:00',
  'updated_at': '2026-10-08T16:20:01.000+00:00',
};

void main() {
  group('SyncMonthCleanupMarker.fromServerRow', () {
    test('parses the server object shape into affected-table keys', () {
      final marker = SyncMonthCleanupMarker.fromServerRow(
        serverMarkerRow(
          tables: const {
            'sales': true,
            'saleItems': true,
            'customerPayments': true,
          },
          deletedCounts: const {'sales': 12, 'saleItems': 30},
        ),
      );

      // Object key order is not contractual; the affected set is.
      expect(
        marker.tables,
        unorderedEquals(['sales', 'saleItems', 'customerPayments']),
      );
      expect(marker.deletedCounts, {'sales': 12, 'saleItems': 30});
      expect(marker.id, 'marker-1');
      expect(marker.shopId, 'shop-a');
      expect(marker.month, DateTime.utc(2026, 9));
      expect(marker.completedAt.isUtc, isTrue);
      expect(marker.createdAt.isUtc, isTrue);
    });

    test('empty object tables parse to an empty list', () {
      final marker = SyncMonthCleanupMarker.fromServerRow(
        serverMarkerRow(tables: const {}),
      );

      expect(marker.tables, isEmpty);
    });

    test('null tables and deleted_counts never throw', () {
      final marker = SyncMonthCleanupMarker.fromServerRow(
        serverMarkerRow(tables: null, deletedCounts: null),
      );

      expect(marker.tables, isEmpty);
      expect(marker.deletedCounts, isEmpty);
    });

    test('malformed tables shapes never throw', () {
      for (final bad in ['sales', 42, true]) {
        final marker = SyncMonthCleanupMarker.fromServerRow(
          serverMarkerRow(tables: bad),
        );
        expect(marker.tables, isEmpty, reason: 'tables=$bad');
      }
    });

    test('malformed deleted_counts shapes never throw', () {
      for (final bad in ['x', 42, true, null]) {
        final marker = SyncMonthCleanupMarker.fromServerRow(
          serverMarkerRow(deletedCounts: bad),
        );
        expect(marker.deletedCounts, isEmpty, reason: 'deletedCounts=$bad');
      }
    });

    test('non-numeric deleted_counts values are dropped, not thrown', () {
      final marker = SyncMonthCleanupMarker.fromServerRow(
        serverMarkerRow(
          deletedCounts: const {'sales': 12, 'bogus': 'many', 'nil': null},
        ),
      );

      expect(marker.deletedCounts, {'sales': 12});
    });

    test('legacy array tables still parse (client-pushed rows)', () {
      final marker = SyncMonthCleanupMarker.fromServerRow(
        serverMarkerRow(tables: ['sales', 'expenses']),
      );

      expect(marker.tables, ['sales', 'expenses']);
    });
  });

  group('SyncMonthCleanupMarker.fromJson', () {
    test('object tables parse via the shared helper', () {
      final marker = SyncMonthCleanupMarker.fromJson(<String, dynamic>{
        'id': 'marker-9',
        'shopId': 'shop-a',
        'month': '2026-09-01T00:00:00.000Z',
        'tables': const {'sales': true, 'expenses': true},
        'deletedCounts': const {'sales': 3},
        'completedAt': '2026-10-08T16:20:00.000Z',
        'createdAt': '2026-10-08T16:20:00.000Z',
      });

      expect(marker.tables, unorderedEquals(['sales', 'expenses']));
      expect(marker.deletedCounts, {'sales': 3});
    });
  });
}
