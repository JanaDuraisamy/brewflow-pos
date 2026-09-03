-- ---------------------------------------------------------------------------
-- BrewFlow POS — Phase: Product Image Cloud Sync
--
-- Adds a `cloud_image_path` metadata column to `public.products` and creates a
-- shop-scoped Supabase Storage bucket for product images.
--
-- Contract (deliberate, do not "simplify"):
--
-- 1. BINARY NEVER LIVES IN A ROW. `cloud_image_path` is metadata only — the
--    object key in the `product-images` bucket. Binary is transferred directly
--    via the client's Storage API (owner upload, other devices download).
-- 2. BUSINESS-SCOPED PATHS. Every object lives under a shop-scoped prefix:
--      product-images/<shopId>/products/<productId>.jpg
--    RLS on storage.objects authorizes a caller by comparing the object's
--    first path segment against the authenticated user's shops
--    (`is_shop_member`). A staff member for shop A can never read/write shop
--    B's images, and an owner holding OWNER membership for multiple shops can
--    access all of their own shops. The product row itself is already gated by
--    `products_all_own_shop`, so `cloud_image_path` never leaks a foreign key.
-- 3. NO SERVICE-ROLE KEY ON DEVICES. The client uses the anon/user JWT through
--    standard Supabase Storage RLS — the service-role key stays server-side.
-- 4. SAFE REPLACEMENT + DELETE CLEANUP. Uploads upsert the same deterministic
--    object key (`.../<productId>.jpg`), so re-saving an image replaces the old
--    object in place (no orphan accumulation from idempotent retries). Product
--    delete removes the row AND (via the client's image queue) the cloud object.
--
-- Append-only: never edit released migrations. Apply with:
--   supabase db execute --file supabase/migrations/0008_product_images.sql
-- ---------------------------------------------------------------------------

-- Products gain metadata only; the column is nullable so existing rows
-- (no uploaded image) keep working.
alter table public.products
  add column if not exists cloud_image_path text;

-- Storage bucket (idempotent). `public` here refers to the file access level
-- inside Supabase Storage (not the Postgres schema).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  false,
  1048576, -- 1 MB max per image
  array['image/jpeg', 'image/webp']
)
on conflict (id) do update
  set file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Storage RLS is a separate enforcement realm; enable it so no anon path leaks.
alter table storage.objects enable row level security;

-- READ: any authenticated member of the shop owning the object's prefix may
-- download that shop's product images. The first path segment is the shopId.
drop policy if exists "product_images_read_own_shop" on storage.objects;
create policy "product_images_read_own_shop"
  on storage.objects for select
  using (
    bucket_id = 'product-images'
    and (public.is_shop_member((storage.foldername(name))[1]::uuid))
  );

-- WRITE (insert/update): members of the owning shop may upload/replace the
-- deterministic object key for their own products. Replacing uses the same
-- key, so this doubles as safe replacement.
drop policy if exists "product_images_write_own_shop" on storage.objects;
create policy "product_images_write_own_shop"
  on storage.objects for insert
  with check (
    bucket_id = 'product-images'
    and (public.is_shop_member((storage.foldername(name))[1]::uuid))
  );

drop policy if exists "product_images_update_own_shop" on storage.objects;
create policy "product_images_update_own_shop"
  on storage.objects for update
  using (
    bucket_id = 'product-images'
    and (public.is_shop_member((storage.foldername(name))[1]::uuid))
  )
  with check (
    bucket_id = 'product-images'
    and (public.is_shop_member((storage.foldername(name))[1]::uuid))
  );

-- DELETE: members of the owning shop may remove their own product images.
drop policy if exists "product_images_delete_own_shop" on storage.objects;
create policy "product_images_delete_own_shop"
  on storage.objects for delete
  using (
    bucket_id = 'product-images'
    and (public.is_shop_member((storage.foldername(name))[1]::uuid))
  );

-- Pull ordering: `cloud_image_path` is mastered by whoever uploaded it; keep
-- the existing pull index lean by including it so the gateway selects it with
-- the row. No separate index needed (the column is only read via the product
-- row pull).
