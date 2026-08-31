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
  SupabaseStaffProvisioning(this._client);

  static const String tag = 'Staff';

  final SupabaseClient _client;

  @override
  Future<AuthUser> createStaffAuthUser(StaffCreateInput input) async {
    try {
      final response = await _client.functions.invoke(
        'create-staff',
        body: {
          'email': input.email,
          'password': input.password,
          if (input.displayName != null) 'display_name': input.displayName,
        },
      );
      final data = response.data;
      if (data is! Map || data['id'] is! String || data['email'] is! String) {
        throw const ProvisioningFailure();
      }
      return AuthUser(id: data['id'] as String, email: data['email'] as String);
    } on FunctionException catch (error) {
      AppLog.error('create-staff function failed', tag: tag, error: error);
      throw const ProvisioningFailure();
    } on Object {
      throw const ProvisioningFailure();
    }
  }
}

/// Composition root for the provisioning boundary. Tests override this with
/// an in-memory fake; production wires the real Supabase client.
final staffProvisioningServiceProvider = Provider<StaffProvisioningService>((
  ref,
) {
  return SupabaseStaffProvisioning(Supabase.instance.client);
});
