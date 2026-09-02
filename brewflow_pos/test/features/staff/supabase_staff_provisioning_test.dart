import 'package:brewflow_pos/features/staff/data/supabase_staff_provisioning.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Edge-function response canned by the fake [FunctionsClient].
final class _Canned {
  const _Canned({this.exception, this.data, this.status = 200, this.errorBody});

  /// A single concrete response: either a thrown exception, an error body,
  /// or a success payload.
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
    if (canned.exception != null) {
      throw canned.exception!;
    }
    if (canned.errorBody != null) {
      throw FunctionsHttpException(
        status: canned.status,
        details: canned.errorBody,
      );
    }
    return FunctionResponse(data: canned.data, status: canned.status);
  }
}

const _input = StaffCreateInput(
  email: 'ava@brewflow.example',
  password: 'secret123',
  displayName: 'Ava Stone',
);

void main() {
  group('SupabaseStaffProvisioning', () {
    test('returns the created AuthUser on a successful call', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(
          _Canned.success({'id': 'auth-1', 'email': 'ava@brewflow.example'}),
        ),
      );

      final user = await service.createStaffAuthUser(_input);

      expect(user.id, 'auth-1');
      expect(user.email, 'ava@brewflow.example');
    });

    test('maps an unauthenticated caller (401) to a safe failure', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(_Canned.error(401, {'error': 'UNAUTHENTICATED'})),
      );

      expect(
        service.createStaffAuthUser(_input),
        throwsA(isA<ProvisioningFailure>()),
      );
    });

    test('maps a non-owner caller (403) to a safe failure', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(_Canned.error(403, {'error': 'FORBIDDEN'})),
      );

      expect(
        service.createStaffAuthUser(_input),
        throwsA(isA<ProvisioningFailure>()),
      );
    });

    test(
      'maps a duplicate email (409 DUPLICATE_EMAIL) to the typed failure',
      () async {
        final service = SupabaseStaffProvisioning(
          _FakeFunctionsClient(
            _Canned.error(409, {'error': 'DUPLICATE_EMAIL'}),
          ),
        );

        expect(
          service.createStaffAuthUser(_input),
          throwsA(isA<DuplicateStaffEmailFailure>()),
        );
      },
    );

    test('maps invalid input (400) to a safe failure', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(_Canned.error(400, {'error': 'INVALID_INPUT'})),
      );

      expect(
        service.createStaffAuthUser(_input),
        throwsA(isA<ProvisioningFailure>()),
      );
    });

    test('maps a server-side failure (500) to a safe failure', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(
          _Canned.error(500, {'error': 'PROVISIONING_FAILED'}),
        ),
      );

      expect(
        service.createStaffAuthUser(_input),
        throwsA(isA<ProvisioningFailure>()),
      );
    });

    test('maps an unreachable (network) function to a safe failure', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(_Canned.throw_(FunctionsFetchException())),
      );

      expect(
        service.createStaffAuthUser(_input),
        throwsA(isA<ProvisioningFailure>()),
      );
    });

    test(
      'maps an undeployed function (relay error) to a safe failure',
      () async {
        final service = SupabaseStaffProvisioning(
          _FakeFunctionsClient(
            _Canned.throw_(
              FunctionsRelayException(
                status: 400,
                details: 'Function not found',
              ),
            ),
          ),
        );

        expect(
          service.createStaffAuthUser(_input),
          throwsA(isA<ProvisioningFailure>()),
        );
      },
    );

    test('rejects a malformed success payload as a failure', () async {
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(_Canned.success({'id': 'only-id'})),
      );

      expect(
        service.createStaffAuthUser(_input),
        throwsA(isA<ProvisioningFailure>()),
      );
    });

    test('forwards an explicit shop_id to the function body', () async {
      final captured = <Object?>[];
      final service = SupabaseStaffProvisioning(
        _FakeFunctionsClient(
          _Canned.success({'id': 'auth-1', 'email': 'ava@brewflow.example'}),
          captured,
        ),
      );

      await service.createStaffAuthUser(
        const StaffCreateInput(
          email: 'ava@brewflow.example',
          password: 'secret123',
          shopId: 'food-truck-shop',
        ),
      );

      expect(captured, hasLength(1));
      final body = captured.single as Map;
      expect(body['shop_id'], 'food-truck-shop');
    });

    test(
      'omits shop_id when not provided (single-shop compatibility)',
      () async {
        final captured = <Object?>[];
        final service = SupabaseStaffProvisioning(
          _FakeFunctionsClient(
            _Canned.success({'id': 'auth-1', 'email': 'ava@brewflow.example'}),
            captured,
          ),
        );

        await service.createStaffAuthUser(_input);

        final body = captured.single as Map;
        expect(body.containsKey('shop_id'), isFalse);
      },
    );
  });
}
