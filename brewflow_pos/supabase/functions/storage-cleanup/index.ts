// ---------------------------------------------------------------------------
// BrewFlow POS — storage-cleanup Edge Function (Deno, Supabase Edge Runtime)
//
// Privileged Storage boundary for owner-only storage monitoring + monthly
// cleanup. The Flutter client NEVER holds service-role credentials; it invokes
// this function with the signed-in owner's JWT (supabase.functions.invoke adds
// the Authorization header).
//
// Actions:
//   scan   — read-only. Lists this shop's product-image objects, cross-checks
//            them against the authoritative reference set
//            (`public.products.cloud_image_path`), and returns usage stats +
//            orphan candidates. NEVER deletes anything.
//   delete — owner-confirmed. Takes explicit object paths; re-scans to confirm
//            each path is STILL an unreferenced orphan for this shop, then
//            permanently deletes only those objects. Never touches a path that
//            is referenced by any live product.
//
// Authorization:
//   Every action verifies the caller (JWT) is an active OWNER of the TARGET
//   shop via `user_shop_memberships` (Phase 2 authoritative source). Staff —
//   even with storage-adjacent permissions — are always rejected. The service
//   role performs listing/deletion with RLS bypass; the owner check IS the
//   whole authorization decision, preserving shop/business isolation.
//
// Errors: 400 INVALID_INPUT | 401 UNAUTHENTICATED | 403 FORBIDDEN | 500 FAILED
//
// Deploy:
//   supabase functions deploy storage-cleanup --project-ref <ref>
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

const STORAGE_BUCKET = 'product-images';

interface CleanupRequest {
  action?: 'scan' | 'delete';
  shop_id?: string;
  paths?: string[];
  storage_limit_bytes?: number | null;
}

interface StorageObjectRow {
  name: string;
  size: number | null;
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
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      return json(500, { error: 'FAILED' });
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
    const body = (await req.json().catch(() => null)) as CleanupRequest | null;
    const action = body?.action ?? null;
    const shopId = body?.shop_id?.trim() || null;
    if (!action || (action !== 'scan' && action !== 'delete') || !shopId) {
      return json(400, { error: 'INVALID_INPUT' });
    }

    // --- 3. Authorize caller as active OWNER of the target shop ------------
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: membership, error: membershipError } = await adminClient
      .from('user_shop_memberships')
      .select('auth_user_id')
      .eq('auth_user_id', user.id)
      .eq('shop_id', shopId)
      .eq('role', 'OWNER')
      .eq('is_active', true)
      .maybeSingle();
    if (membershipError || !membership) {
      return json(403, { error: 'FORBIDDEN' });
    }

    const prefix = `${shopId}/products/`;
    const { data: shop, error: shopError } = await adminClient
      .from('shops')
      .select('storage_limit_bytes')
      .eq('id', shopId)
      .maybeSingle();
    if (shopError) {
      return json(500, { error: 'FAILED' });
    }
    const storageLimitBytes =
      shop?.storage_limit_bytes ?? body.storage_limit_bytes ?? null;

    // --- Shared: enumerate this shop's objects + the reference set -------
    async function loadObjects(): Promise<StorageObjectRow[]> {
      const { data, error } = await adminClient
        .from('storage.objects')
        .select('name, size')
        .eq('bucket_id', STORAGE_BUCKET)
        .like('name', `${prefix}%`);
      if (error) throw error;
      return (data ?? []) as StorageObjectRow[];
    }

    async function loadReferencedPaths(): Promise<Set<string>> {
      const { data, error } = await adminClient
        .from('products')
        .select('cloud_image_path')
        .eq('shop_id', shopId)
        .not('cloud_image_path', 'is', null);
      if (error) throw error;
      return new Set(
        (data ?? [])
          .map((r) => (r as { cloud_image_path: string }).cloud_image_path)
          .filter((p): p is string => Boolean(p)),
      );
    }

    function orphaning(objects: StorageObjectRow[], referenced: Set<string>) {
      const totalBytes = objects.reduce((sum, o) => sum + (o.size ?? 0), 0);
      const orphans = objects.filter((o) => !referenced.has(o.name));
      const orphanBytes = orphans.reduce((sum, o) => sum + (o.size ?? 0), 0);
      return {
        usedBytes: totalBytes,
        imageCount: objects.length,
        orphanPaths: orphans.map((o) => o.name),
        orphanCount: orphans.length,
        reclaimableBytes: orphanBytes,
      };
    }

    try {
      if (action === 'scan') {
        const objects = await loadObjects();
        const referenced = await loadReferencedPaths();
        const stats = orphaning(objects, referenced);
        // Read-only scan — never deletes. `lastScanAt` helps the client show
        // when the snapshot was taken.
        return json(200, {
          ...stats,
          storageLimitBytes,
          lastScanAt: new Date().toISOString(),
        });
      }

      // --- action === 'delete' ---------------------------------------------
      const paths = (body?.paths ?? []).filter((p) => p?.startsWith(prefix));
      if (paths.length === 0) {
        return json(200, { deleted: [], deletedCount: 0 });
      }

      // Failsafe: recompute the orphan set right now and delete ONLY paths
      // that are confirmed unreferenced. A path that became referenced since
      // the scan is skipped — never deleted.
      const objects = await loadObjects();
      const referenced = await loadReferencedPaths();
      const stats = orphaning(objects, referenced);
      const orphanSet = new Set(stats.orphanPaths);
      const safeToDelete = paths.filter((p) => orphanSet.has(p));

      let deletedCount = 0;
      if (safeToDelete.length > 0) {
        const { error: removeError } = await adminClient.storage
          .from(STORAGE_BUCKET)
          .remove(safeToDelete);
        if (removeError) {
          return json(500, { error: 'FAILED' });
        }
        deletedCount = safeToDelete.length;
      }

      return json(200, { deleted: safeToDelete, deletedCount });
    } catch (_error) {
      return json(500, { error: 'FAILED' });
    }
  } catch (_error) {
    return json(500, { error: 'FAILED' });
  }
});
