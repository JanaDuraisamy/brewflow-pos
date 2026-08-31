// ---------------------------------------------------------------------------
// BrewFlow POS — create-staff Edge Function (Deno, Supabase Edge Runtime)
//
// Secure boundary for staff provisioning. The Flutter client NEVER holds
// service-role credentials; it invokes this function with the signed-in
// owner's JWT (supabase.functions.invoke adds the Authorization header).
//
// Responsibilities:
// 1. Verify the caller's JWT (must be a logged-in user).
// 2. Authorize the caller as OWNER using the `user_profiles` table in the
//    connected Postgres database (role = 'OWNER', is_active). The local
//    Drift store cannot be read server-side; this row is the cloud-side
//    source of truth and is created during bootstrap/sync (Step 3 wires the
//    automatic mirror of the local OWNER profile).
// 3. Create the staff auth identity with the service role (server-side env
//    SUPABASE_SERVICE_ROLE_KEY, injected by the platform — never shipped).
// 4. Return { id, email } matching the client contract
//    (SupabaseStaffProvisioning → AuthUser) or a typed error:
//      400 INVALID_INPUT | 401 UNAUTHENTICATED | 403 FORBIDDEN
//      409 DUPLICATE_EMAIL | 500 PROVISIONING_FAILED
//
// Deploy:
//   supabase functions deploy create-staff --project-ref <ref>
//   # No extra secrets required: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
//   # are provided to functions by the platform.
// ---------------------------------------------------------------------------

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface CreateStaffRequest {
  email?: string;
  password?: string;
  display_name?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const json = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  try {
    // --- Environment (platform-injected, never client-visible) -------------
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return json(500, { error: 'PROVISIONING_FAILED' });
    }

    // --- 1. Authenticate the caller ----------------------------------------
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return json(401, { error: 'UNAUTHENTICATED' });
    }
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return json(401, { error: 'UNAUTHENTICATED' });
    }

    // --- 2. Authorize the caller as an active OWNER ------------------------
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: callerProfile, error: profileError } = await adminClient
      .from('user_profiles')
      .select('role, is_active')
      .eq('auth_user_id', user.id)
      .single();
    if (
      profileError ||
      !callerProfile ||
      callerProfile.role !== 'OWNER' ||
      !callerProfile.is_active
    ) {
      return json(403, { error: 'FORBIDDEN' });
    }

    // --- 3. Validate input --------------------------------------------------
    const body = (await req.json().catch(() => null)) as
      | CreateStaffRequest
      | null;
    const email = body?.email?.trim().toLowerCase();
    const password = body?.password ?? '';
    const displayName = body?.display_name?.trim() || undefined;
    if (!email || !email.includes('@') || password.length < 6) {
      return json(400, { error: 'INVALID_INPUT' });
    }

    // --- 4. Create the staff auth identity (service role, server-side) -----
    const { data: created, error: createError } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: displayName ? { display_name: displayName } : undefined,
      });
    if (createError || !created.user) {
      const status = (createError as { status?: number })?.status;
      if (status === 422 || createError?.message.includes('already')) {
        return json(409, { error: 'DUPLICATE_EMAIL' });
      }
      return json(500, { error: 'PROVISIONING_FAILED' });
    }

    return json(200, { id: created.user.id, email: created.user.email });
  } catch (_error) {
    return json(500, { error: 'PROVISIONING_FAILED' });
  }
});
