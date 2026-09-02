import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Secure Staff Provisioning Boundary (client side)
///
/// Creating a Supabase Auth user is a privileged operation. The client NEVER
/// holds service-role credentials: it invokes the deployed `create-staff`
/// Edge Function with the owner's own JWT; the function verifies that JWT,
/// checks the caller's OWNER claim server-side and uses the service role
/// (available only inside the Supabase runtime) to create the auth user.
///
/// Deployment requirement (documented in supabase/functions/create-staff/):
/// deploy `supabase/functions/create-staff` with
/// `supabase functions deploy create-staff` before Add Staff works against a
/// real backend. Until then the UI surfaces a typed, safe failure.
/// ---------------------------------------------------------------------------

abstract interface class StaffProvisioningService {
  /// Creates the Supabase Auth identity for a new staff member and returns
  /// it. Throws [ProvisioningFailure] on any failure — partial state is left
  /// to the function (auth-user creation is its single atomic step).
  Future<AuthUser> createStaffAuthUser(StaffCreateInput input);
}

final class SupabaseStaffProvisioning implements StaffProvisioningService {
  SupabaseStaffProvisioning(this._functions);

  static const String tag = 'Staff';

  final FunctionsClient _functions;

  @override
  Future<AuthUser> createStaffAuthUser(StaffCreateInput input) async {
    try {
      final response = await _functions.invoke(
        'create-staff',
        body: {
          'email': input.email,
          'password': input.password,
          if (input.displayName != null) 'display_name': input.displayName,
          if (input.shopId != null) 'shop_id': input.shopId,
        },
      );
      final data = response.data;
      if (data is! Map || data['id'] is! String || data['email'] is! String) {
        throw const ProvisioningFailure();
      }
      return AuthUser(id: data['id'] as String, email: data['email'] as String);
    } on FunctionsHttpException catch (error) {
      // The function answered with a typed error — report the exact cause.
      throw _mapFunctionError(error.status, error.details);
    } on FunctionsRelayException catch (error) {
      // The relay itself rejected the call (e.g. function not deployed yet).
      AppLog.error('create-staff relay error', tag: tag, error: error);
      throw const ProvisioningFailure(
        'The staff service is not deployed yet on this project.',
      );
    } on FunctionsFetchException catch (error) {
      // No response reached the client (network down / function unknown).
      AppLog.error('create-staff unreachable', tag: tag, error: error);
      throw const ProvisioningFailure(
        'The staff service could not be reached. Check your connection.',
      );
    } on FunctionException catch (error) {
      AppLog.error('create-staff function failed', tag: tag, error: error);
      throw _mapFunctionError(error.status, error.details);
    } on Object {
      throw const ProvisioningFailure();
    }
  }

  /// Maps a typed Edge-Function error onto the sealed [StaffFailure] family,
  /// keeping the cause user-safe without leaking server internals.
  StaffFailure _mapFunctionError(int status, dynamic details) {
    switch (status) {
      case 400:
        return const ProvisioningFailure(
          'That staff account is not valid. Please check the details.',
        );
      case 401:
        return const ProvisioningFailure(
          'Your session has expired. Please sign in again and retry.',
        );
      case 403:
        return const ProvisioningFailure(
          'Only an active shop owner can add staff members.',
        );
      case 409:
        if (_errorCode(details) == 'DUPLICATE_EMAIL') {
          return const DuplicateStaffEmailFailure();
        }
        return const ProvisioningFailure();
      case 500:
        return const ProvisioningFailure(
          'The staff service hit an error. Please try again.',
        );
      default:
        return const ProvisioningFailure();
    }
  }

  static String? _errorCode(dynamic details) {
    if (details is Map) {
      final code = details['error'];
      if (code is String) return code;
    }
    return null;
  }
}

/// Composition root for the provisioning boundary. Tests override this with
/// an in-memory fake; production wires the real Supabase functions client.
final staffProvisioningServiceProvider = Provider<StaffProvisioningService>((
  ref,
) {
  return SupabaseStaffProvisioning(Supabase.instance.client.functions);
});
