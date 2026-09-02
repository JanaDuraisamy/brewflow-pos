// ---------------------------------------------------------------------------
// BrewFlow POS — create-staff Edge Function (Deno, Supabase Edge Runtime)
//
// Secure boundary for staff provisioning. The Flutter client NEVER holds
// service-role credentials; it invokes this function with the signed-in
// owner's JWT (supabase.functions.invoke adds the Authorization header).
//
// Responsibilities:
// 1. Verify the caller's JWT (must be a logged-in user).
// 2. Authorize the caller as an active OWNER of the TARGET shop using the
//    `user_shop_memberships` table (Phase 2 authoritative authorization). The
//    target shop is supplied in the body (shop_id); when omitted it defaults
//    to the caller's sole active OWNER membership shop — a multi-shop owner
//    MUST pass shop_id explicitly (cross-business creation is otherwise
//    rejected).
// 3. Create the staff auth identity with the service role (server-side env
//    SUPABASE_SERVICE_ROLE_KEY, injected by the platform — never shipped).
// 4. Write the cloud identity: an active `user_shop_memberships` STAFF row for
//    the target shop, plus a matching `user_profiles` STAFF row so the
//    staff/bootstrap customer surface (`user_profiles.shop_id`) stays in sync.
// 5. Return { id, email } matching the client contract
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
  shop_id?: string;
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

    // --- 2. Parse + validate input -----------------------------------------
    const body = (await req.json().catch(() => null)) as
      | CreateStaffRequest
      | null;
    const email = body?.email?.trim().toLowerCase();
    const password = body?.password ?? '';
    const displayName = body?.display_name?.trim() || undefined;
    if (!email || !email.includes('@') || password.length < 6) {
      return json(400, { error: 'INVALID_INPUT' });
    }

    // --- 3. Authorize the caller as OWNER of the target shop ---------------
    // The service role reads memberships (RLS bypass); the caller's OWNER
    // claim for the target shop is the whole authorization decision.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const targetShopId = body?.shop_id?.trim() || null;

    const { data: memberships, error: membershipsError } = targetShopId
      ? await adminClient
          .from('user_shop_memberships')
          .select('shop_id, role, is_active')
          .eq('auth_user_id', user.id)
          .eq('shop_id', targetShopId)
          .eq('role', 'OWNER')
          .eq('is_active', true)
          .maybeSingle()
      : await adminClient
          .from('user_shop_memberships')
          .select('shop_id, role, is_active')
          .eq('auth_user_id', user.id)
          .eq('role', 'OWNER')
          .eq('is_active', true);

    if (membershipsError) {
      return json(500, { error: 'PROVISIONING_FAILED' });
    }

    let resolvedShopId: string;
    if (memberships) {
      resolvedShopId = memberships.shop_id;
    } else if (!targetShopId) {
      // No explicit shop: caller must own EXACTLY one shop to create staff.
      const { data: owned, error: ownedError } = await adminClient
        .from('user_shop_memberships')
        .select('shop_id')
        .eq('auth_user_id', user.id)
        .eq('role', 'OWNER')
        .eq('is_active', true);
      if (ownedError || !owned || owned.length !== 1) {
        return json(400, { error: 'INVALID_INPUT' });
      }
      resolvedShopId = owned[0].shop_id;
    } else {
      // Explicit shop but the caller is not an active OWNER of it.
      return json(403, { error: 'FORBIDDEN' });
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

    // --- 5. Write cloud identity: STAFF membership + profile ---------------
    // Idempotent upserts keyed on natural/primary keys. The membership row is
    // the Phase 2 authorization source; the profile keeps user_profiles in
    // sync for the existing bootstrap/read path.
    const { error: membershipError } = await adminClient
      .from('user_shop_memberships')
      .upsert(
        {
          auth_user_id: created.user.id,
          shop_id: resolvedShopId,
          role: 'STAFF',
          is_active: true,
        },
        { onConflict: 'auth_user_id,shop_id' },
      );
    if (membershipError) {
      return json(500, { error: 'PROVISIONING_FAILED' });
    }

    const { error: profileError } = await adminClient
      .from('user_profiles')
      .upsert(
        {
          auth_user_id: created.user.id,
          email: created.user.email,
          role: 'STAFF',
          shop_id: resolvedShopId,
          display_name: displayName ?? null,
          is_active: true,
        },
        { onConflict: 'auth_user_id' },
      );
    if (profileError) {
      return json(500, { error: 'PROVISIONING_FAILED' });
    }

    return json(200, { id: created.user.id, email: created.user.email });
  } catch (_error) {
    return json(500, { error: 'PROVISIONING_FAILED' });
  }
});
