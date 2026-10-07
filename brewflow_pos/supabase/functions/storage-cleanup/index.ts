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
//   db-metrics — read-only. Physical database size (pg_database_size) plus
//            per-table physical sizes for the shop's tables. DB-wide figures
//            are labeled as such: Postgres cannot attribute shared-table
//            physical bytes to one shop.
//   month-stats — computes one month's logical stats (exact row counts +
//            estimated logical bytes) and records them in the server-side
//            monthly ledger (`storage_monthly_snapshots`). Byte figures are
//            labeled logical/estimated, never physical attribution.
//   month-history — reads the monthly ledger for the shop, newest first.
//   month-preview — read-only counts for the month-cleanup confirmation
//            screen, from the same SQL the cleanup runs (guaranteed parity),
//            plus the orphan files created that month and the report/
//            already-cleaned status.
//   month-cleanup — owner-confirmed month-scoped HARD DELETE. Refuses months
//            without a report confirmation. Runs the atomic
//            `month_cleanup_atomic` RPC as the CALLER (user JWT, never service
//            role) so the function's own owner check and RLS stay meaningful;
//            deletes and the cleanup marker commit in one transaction.
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
  action?:
    | 'scan'
    | 'delete'
    | 'db-metrics'
    | 'month-stats'
    | 'month-history'
    | 'month-preview'
    | 'month-cleanup';
  shop_id?: string;
  paths?: string[];
  month?: string;
  marker_id?: string;
  storage_limit_bytes?: number | null;
}

interface StorageObjectRow {
  name: string;
  size: number | null;
}

Deno.env.get('SUPABASE_URL');

console.log('STORAGE_CLEANUP_BOOT');

Deno.serve(async (req: Request) => {
  console.log('STORAGE_CLEANUP_HANDLER_ENTER');
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
      console.error('STORAGE_ENV_MISSING');
      return json(500, { error: 'FAILED' });
    }
    console.log('STORAGE_ENV_OK');

    // --- 1. Authenticate the caller ----------------------------------------
    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      console.warn('STORAGE_AUTH_HEADER_MISSING');
      return json(401, { error: 'UNAUTHENTICATED' });
    }
    console.log('STORAGE_AUTH_HEADER_OK');
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    console.log('STORAGE_USER_CLIENT_CREATED');
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      console.warn('STORAGE_GET_USER_FAILED', {
        message: userError?.message,
        code: userError?.code,
      });
      return json(401, { error: 'UNAUTHENTICATED' });
    }
    console.log('STORAGE_GET_USER_OK', { userId: user.id });

    // --- 2. Parse + validate input -----------------------------------------
    const body = (await req.json().catch(() => null)) as CleanupRequest | null;
    console.log('STORAGE_BODY_PARSED', { hasBody: body != null });
    const action = body?.action ?? null;
    const shopId = body?.shop_id?.trim() || null;
    const monthActions = new Set([
      'month-stats',
      'month-preview',
      'month-cleanup',
    ]);
    const monthStr = body?.month?.trim() || null;
    const monthDate =
      monthStr && /^\d{4}-\d{2}-\d{2}$/.test(monthStr) ? monthStr : null;
    if (
      !action ||
      (action !== 'scan' &&
        action !== 'delete' &&
        action !== 'db-metrics' &&
        action !== 'month-history' &&
        !monthActions.has(action)) ||
      !shopId
    ) {
      console.warn('STORAGE_INPUT_INVALID', { action, hasShopId: !!shopId });
      return json(400, { error: 'INVALID_INPUT' });
    }
    if (monthActions.has(action) && !monthDate) {
      console.warn('STORAGE_INPUT_INVALID_MONTH', { action });
      return json(400, { error: 'INVALID_INPUT' });
    }
    console.log('STORAGE_INPUT_VALID', { action, shopId });

    // --- 3. Authorize caller as active OWNER of the target shop ------------
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    console.log('STORAGE_ADMIN_CLIENT_CREATED');
    const { data: membership, error: membershipError } = await adminClient
      .from('user_shop_memberships')
      .select('auth_user_id')
      .eq('auth_user_id', user.id)
      .eq('shop_id', shopId)
      .eq('role', 'OWNER')
      .eq('is_active', true)
      .maybeSingle();
    if (membershipError || !membership) {
      console.warn('STORAGE_MEMBERSHIP_DENIED', {
        userId: user.id,
        shopId,
        message: membershipError?.message,
        code: membershipError?.code,
      });
      return json(403, { error: 'FORBIDDEN' });
    }
    console.log('STORAGE_MEMBERSHIP_OK', { userId: user.id, shopId });

    const prefix = `${shopId}/products/`;
    console.log('STORAGE_SHOP_QUERY_START', { shopId });
    const { data: shop, error: shopError } = await adminClient
      .from('shops')
      .select('storage_limit_bytes')
      .eq('id', shopId)
      .maybeSingle();
    if (shopError) {
      console.error('STORAGE_SHOP_QUERY_FAILED', {
        shopId,
        message: shopError.message,
        code: shopError.code,
        details: shopError.details,
      });
      return json(500, { error: 'FAILED' });
    }
    console.log('STORAGE_SHOP_QUERY_OK', {
      shopId,
      hasLimit: shop?.storage_limit_bytes != null,
    });
    const storageLimitBytes =
      shop?.storage_limit_bytes ?? body.storage_limit_bytes ?? null;

    // --- Shared: enumerate this shop's objects + the reference set -------
    // Storage API only — PostgREST does not expose storage.objects (PGRST205).
    // list() returns at most 1000 per page; paginate with offset until a short
    // page is returned so every object under the prefix is enumerated.
    console.log('STORAGE_SCAN_ENTER', { shopId, action });
    async function loadObjects(): Promise<StorageObjectRow[]> {
      console.log('STORAGE_OBJECTS_QUERY_START', { shopId, prefix });
      const all: StorageObjectRow[] = [];
      const pageSize = 1000;
      var offset = 0;
      while (true) {
        const { data, error } = await adminClient.storage
          .from(STORAGE_BUCKET)
          .list(prefix.replace(/\/$/, ''), {
            limit: pageSize,
            offset,
            sortBy: { column: 'created_at', order: 'asc' },
          });
        if (error) {
          console.error('STORAGE_OBJECTS_QUERY_FAILED', {
            shopId,
            message: error.message,
            code: (error as { code?: string }).code,
            details: (error as { details?: string }).details,
          });
          throw error;
        }
        const page = (data ?? []) as Array<{
          name: string;
          metadata?: { size?: number | null } | null;
        }>;
        for (const item of page) {
          all.push({
            name: prefix + item.name,
            size: item.metadata?.size ?? null,
          });
        }
        if (page.length < pageSize) break;
        offset += pageSize;
      }
      console.log('STORAGE_OBJECTS_OK', {
        shopId,
        count: all.length,
      });
      return all;
    }

    async function loadReferencedPaths(): Promise<Set<string>> {
      console.log('STORAGE_REFERENCES_QUERY_START', { shopId });
      const { data, error } = await adminClient
        .from('products')
        .select('cloud_image_path')
        .eq('shop_id', shopId)
        .not('cloud_image_path', 'is', null);
      if (error) {
        console.error('STORAGE_REFERENCES_QUERY_FAILED', {
          shopId,
          message: error.message,
          code: error.code,
          details: error.details,
        });
        throw error;
      }
      console.log('STORAGE_REFERENCES_OK', {
        shopId,
        count: (data ?? []).length,
      });
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
        console.log('STORAGE_SCAN_RESULT', {
          shopId,
          usedBytes: stats.usedBytes,
          imageCount: stats.imageCount,
          orphanCount: stats.orphanCount,
          objectCount: objects.length,
          referencedCount: referenced.size,
        });
        // Read-only scan — never deletes. `lastScanAt` helps the client show
        // when the snapshot was taken.
        return json(200, {
          ...stats,
          storageLimitBytes,
          lastScanAt: new Date().toISOString(),
        });
      }

      if (action === 'delete') {
        // --- action === 'delete' -------------------------------------------
        const paths = (body?.paths ?? []).filter((p) =>
          p?.startsWith(prefix),
        );
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
      }
    } catch (_error) {
      return json(500, { error: 'FAILED' });
    }

    // --- Database + monthly actions ----------------------------------------
    // Read paths run through the SQL helpers below as the CALLER (user JWT),
    // so owns_shop() and RLS stay meaningful end to end. The destructive
    // month-cleanup runs the atomic RPC the same way.
    function rpcError(def: { message?: string; code?: string }) {
      const message = def.message ?? '';
      if (message.includes('NEEDS_REPORT') || def.code === 'NEEDS_REPORT') {
        return json(409, { error: 'NEEDS_REPORT' });
      }
      if (message.includes('OPEN_BILLS') || def.code === 'OPEN_BILLS') {
        return json(409, { error: 'OPEN_BILLS' });
      }
      if (message.includes('FORBIDDEN') || def.code === '42501') {
        return json(403, { error: 'FORBIDDEN' });
      }
      if (message.includes('ALREADY_CLEANED')) {
        return json(200, { alreadyCleaned: true, deleted: {} });
      }
      return json(500, { error: 'FAILED' });
    }

    try {
      if (action === 'db-metrics') {
        console.log('DB_METRICS_RPC_START', { shopId });
        const { data, error } = await userClient.rpc('storage_db_metrics', {
          p_shop_id: shopId,
        });
        if (error) {
          console.error('DB_METRICS_RPC_FAILED', {
            message: error.message,
            code: error.code,
            details: error.details,
            hint: error.hint,
          });
          return rpcError(error);
        }
        console.log('DB_METRICS_RPC_OK', {
          dbBytesTotal: (data as Record<string, unknown>)?.dbBytesTotal,
          tableCount: ((data as Record<string, unknown>)?.tables as unknown[])?.length,
        });
        return json(200, data as Record<string, unknown>);
      }

      if (action === 'month-history') {
        const { data, error } = await adminClient
          .from('storage_monthly_snapshots')
          .select('month, counts, logical_bytes_est, db_bytes_total, created_at')
          .eq('shop_id', shopId)
          .order('month', { ascending: false });
        if (error) throw error;
        return json(200, { snapshots: data ?? [] });
      }

      if (action === 'month-stats' && monthDate) {
        const { data, error } = await userClient.rpc('month_size_estimate', {
          p_shop_id: shopId,
          p_month: monthDate,
        });
        if (error) return rpcError(error);
        const stats = data as {
          counts: Record<string, number>;
          logicalBytesEst: number;
          dbBytesTotal: number;
        };
        // Record the server-side ledger row (service role): history survives
        // even if the scanning device is gone.
        const { start } = monthBounds(monthDate);
        const monthKey = start.substring(0, 10);
        const { error: ledgerError } = await adminClient
          .from('storage_monthly_snapshots')
          .upsert(
            {
              id: crypto.randomUUID(),
              shop_id: shopId,
              month: monthKey,
              counts: stats.counts,
              logical_bytes_est: stats.logicalBytesEst,
              db_bytes_total: stats.dbBytesTotal,
            },
            { onConflict: 'shop_id,month' },
          );
        if (ledgerError) throw ledgerError;
        return json(200, { ...stats, month: monthKey });
      }

      if (action === 'month-preview' && monthDate) {
        const { data, error } = await userClient.rpc('month_preview_counts', {
          p_shop_id: shopId,
          p_month: monthDate,
        });
        if (error) return rpcError(error);
        const preview = data as Record<string, unknown>;
        // Orphan files created that month, with sizes, for the confirmation
        // screen ("associated files that will be deleted").
        const { start, end } = monthBounds(monthDate);
        const prefix = `${shopId}/products/`;
        // Storage API only — PostgREST does not expose storage.objects.
        // list() returns at most 1000 per page; paginate with offset.
        const all: Array<{ name: string; size: number | null; created_at: string }> = [];
        const pageSize = 1000;
        var offset = 0;
        while (true) {
          const { data: page, error: pageError } = await adminClient.storage
            .from(STORAGE_BUCKET)
            .list(prefix.replace(/\/$/, ''), {
              limit: pageSize,
              offset,
              sortBy: { column: 'created_at', order: 'asc' },
            });
          if (pageError) {
            console.error('STORAGE_MONTH_OBJECTS_QUERY_FAILED', {
              shopId,
              message: pageError.message,
              code: (pageError as { code?: string }).code,
              details: (pageError as { details?: string }).details,
            });
            throw pageError;
          }
          const items = (page ?? []) as Array<{
            name: string;
            created_at: string;
            metadata?: { size?: number | null } | null;
          }>;
          for (const item of items) {
            all.push({
              name: prefix + item.name,
              size: item.metadata?.size ?? null,
              created_at: item.created_at,
            });
          }
          if (items.length < pageSize) break;
          offset += pageSize;
        }
        const monthObjects = all.filter(
          (o) => o.created_at >= start && o.created_at < end,
        );
        console.log('STORAGE_MONTH_OBJECTS_OK', {
          shopId,
          total: all.length,
          inMonth: monthObjects.length,
        });
        const referenced = await loadReferencedPaths();
        const monthOrphans = monthObjects
          .filter((o) => !referenced.has(o.name))
          .map((o) => ({
            path: o.name,
            sizeBytes: o.size ?? 0,
          }));
        return json(200, { ...preview, monthOrphans });
      }

      if (action === 'month-cleanup' && monthDate) {
        const markerId =
          typeof body?.marker_id === 'string' &&
          /^[0-9a-fA-F-]{36}$/.test(body.marker_id)
            ? body.marker_id
            : null;
        if (!markerId) return json(400, { error: 'INVALID_INPUT' });
        // Optional category selection: an array of category keys
        // (sales, purchases, expenses, stockMovements, dailyClosings,
        // staffAttendance, staffAdvances, staffDailySalaries,
        // staffMonthlySalaries). Absent/invalid = the full month scope.
        const rawCategories = Array.isArray(body?.categories)
          ? body.categories.filter((c): c is string => typeof c === 'string')
          : null;
        const categories =
          rawCategories && rawCategories.length > 0 ? rawCategories : null;
        const { data, error } = await userClient.rpc('month_cleanup_atomic', {
          p_shop_id: shopId,
          p_month: monthDate,
          p_marker_id: markerId,
          p_categories: categories,
        });
        if (error) return rpcError(error);
        return json(200, data as Record<string, unknown>);
      }

      return json(400, { error: 'INVALID_INPUT' });
    } catch (_error) {
      return json(500, { error: 'FAILED' });
    }
  } catch (_error) {
    return json(500, { error: 'FAILED' });
  }
});
