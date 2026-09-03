import 'package:brewflow_pos/features/storage_cleanup/data/storage_cleanup_gateway.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class _Canned {
  const _Canned({this.exception, this.data, this.status = 200, this.errorBody});

  factory _Canned.success(Map<String, dynamic> data) =>
      _Canned(data: data, status: 200);

  factory _Canned.error(int status, Map<String, dynamic> errorBody) =>
      _Canned(status: status, errorBody: errorBody);

  factory _Canned.throw_(Object exception) => _Canned(exception: exception);

  final Object? exception;
  final Map<String, dynamic>? data;
  final int status;
  final Map<String, dynamic>? errorBody;
}

final class _FakeFunctionsClient extends FunctionsClient {
  _FakeFunctionsClient(this.canned, [this.captured])
    : super('https://example.supabase.co', {});

  final _Canned canned;
  final List<Object?>? captured;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) async {
    captured?.add(body);
    if (canned.exception != null) throw canned.exception!;
    if (canned.errorBody != null) {
      throw FunctionsHttpException(
        status: canned.status,
        details: canned.errorBody,
      );
    }
    return FunctionResponse(data: canned.data, status: canned.status);
  }
}

const _shopId = 'shop-1';

void main() {
  group('SupabaseStorageCleanupGateway — scan', () {
    test('parses a valid scan response', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(
          _Canned.success({
            'usedBytes': 4096,
            'imageCount': 8,
            'orphanCount': 2,
            'reclaimableBytes': 1024,
            'orphanPaths': ['a.jpg', 'b.jpg'],
            'lastScanAt': '2026-06-01T00:00:00Z',
            'storageLimitBytes': 10000,
          }),
        ),
      );

      final report = await gw.scan(shopId: _shopId);
      expect(report.usedBytes, 4096);
      expect(report.imageCount, 8);
      expect(report.orphanCount, 2);
      expect(report.reclaimableBytes, 1024);
      expect(report.orphanPaths, ['a.jpg', 'b.jpg']);
      expect(report.storageLimitBytes, 10000);
    });

    test('parses scan response without storageLimitBytes', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(
          _Canned.success({
            'usedBytes': 2048,
            'imageCount': 4,
            'orphanCount': 0,
            'reclaimableBytes': 0,
            'orphanPaths': <String>[],
            'lastScanAt': '2026-06-01T00:00:00Z',
          }),
        ),
      );

      final report = await gw.scan(shopId: _shopId);
      expect(report.storageLimitBytes, isNull);
      expect(report.orphanCount, 0);
    });

    test('throws StorageCleanupServiceFailure on malformed response', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(_Canned.success({'unexpected': 'payload'})),
      );

      await expectLater(
        gw.scan(shopId: _shopId),
        throwsA(isA<StorageCleanupServiceFailure>()),
      );
    });

    test('throws StorageCleanupSessionFailure on 401', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(_Canned.error(401, {'error': 'UNAUTHORIZED'})),
      );

      await expectLater(
        gw.scan(shopId: _shopId),
        throwsA(isA<StorageCleanupSessionFailure>()),
      );
    });

    test('throws StorageCleanupForbiddenFailure on 403', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(_Canned.error(403, {'error': 'FORBIDDEN'})),
      );

      await expectLater(
        gw.scan(shopId: _shopId),
        throwsA(isA<StorageCleanupForbiddenFailure>()),
      );
    });

    test('throws StorageCleanupServiceFailure on 500', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(_Canned.error(500, {'error': 'INTERNAL'})),
      );

      await expectLater(
        gw.scan(shopId: _shopId),
        throwsA(isA<StorageCleanupServiceFailure>()),
      );
    });

    test(
      'throws StorageCleanupServiceFailure on FunctionsRelayException',
      () async {
        final gw = SupabaseStorageCleanupGateway(
          _FakeFunctionsClient(
            _Canned.throw_(FunctionsRelayException(status: 502)),
          ),
        );

        await expectLater(
          gw.scan(shopId: _shopId),
          throwsA(isA<StorageCleanupServiceFailure>()),
        );
      },
    );

    test(
      'throws StorageCleanupServiceFailure on FunctionsFetchException',
      () async {
        final gw = SupabaseStorageCleanupGateway(
          _FakeFunctionsClient(_Canned.throw_(FunctionsFetchException())),
        );

        await expectLater(
          gw.scan(shopId: _shopId),
          throwsA(isA<StorageCleanupServiceFailure>()),
        );
      },
    );

    test('sends correct body to edge function', () async {
      final captured = <Object?>[];
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(
          _Canned.success({
            'usedBytes': 0,
            'imageCount': 0,
            'orphanCount': 0,
            'reclaimableBytes': 0,
            'orphanPaths': <String>[],
            'lastScanAt': '2026-06-01T00:00:00Z',
          }),
          captured,
        ),
      );

      await gw.scan(shopId: _shopId);
      expect(captured, [
        {'action': 'scan', 'shop_id': _shopId},
      ]);
    });
  });

  group('SupabaseStorageCleanupGateway — deleteOrphans', () {
    test('parses a valid delete response', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(
          _Canned.success({
            'deleted': ['a.jpg'],
            'deletedCount': 1,
          }),
        ),
      );

      final result = await gw.deleteOrphans(shopId: _shopId, paths: ['a.jpg']);
      expect(result.deletedCount, 1);
      expect(result.deletedPaths, ['a.jpg']);
    });

    test('throws on malformed delete response', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(_Canned.success({'deleted': 'not-a-list'})),
      );

      await expectLater(
        gw.deleteOrphans(shopId: _shopId, paths: ['x.jpg']),
        throwsA(isA<StorageCleanupServiceFailure>()),
      );
    });

    test('sends correct body with paths', () async {
      final captured = <Object?>[];
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(
          _Canned.success({'deleted': <String>[], 'deletedCount': 0}),
          captured,
        ),
      );

      await gw.deleteOrphans(shopId: _shopId, paths: ['a.jpg', 'b.jpg']);
      expect(captured, [
        {
          'action': 'delete',
          'shop_id': _shopId,
          'paths': ['a.jpg', 'b.jpg'],
        },
      ]);
    });

    test('propagates HTTP errors', () async {
      final gw = SupabaseStorageCleanupGateway(
        _FakeFunctionsClient(_Canned.error(403, {'error': 'FORBIDDEN'})),
      );

      await expectLater(
        gw.deleteOrphans(shopId: _shopId, paths: ['a.jpg']),
        throwsA(isA<StorageCleanupForbiddenFailure>()),
      );
    });
  });
}
