# create-staff Edge Function

Secure server boundary for staff provisioning. The Flutter app never holds
service-role credentials; it calls this function with the signed-in owner's
JWT (`supabase.functions.invoke('create-staff', body: {...})`).

## Contract (matches `SupabaseStaffProvisioning` in the client)

Request body:
```json
{
  "email": "staff@shop.co",
  "password": "temp-pass-6+",
  "display_name": "Ravi",
  "shop_id": "<target-shop-uuid>"
}
```

`shop_id` (Phase 2) is the target business the new staff member is scoped to.
It is optional for backward compatibility: when omitted, the function requires
the caller to own **exactly one** shop and scopes the member to it. A
multi-shop owner MUST pass `shop_id` explicitly.

Success `200`:
```json
{ "id": "<auth-user-uuid>", "email": "staff@shop.co" }
```

Typed errors: `400 INVALID_INPUT` · `401 UNAUTHENTICATED` · `403 FORBIDDEN`
(caller is not an active OWNER of the target shop) · `409 DUPLICATE_EMAIL` ·
`500 PROVISIONING_FAILED`.

## Owner authorization (Phase 2)

The function reads the caller's rows in the authoritative
`user_shop_memberships` table (service role, RLS bypass) and only proceeds
when they hold an **active OWNER membership for the target shop**. A caller
who owns shop A cannot provision staff for shop B — cross-business creation is
rejected with `403 FORBIDDEN`.

On success the function also writes the cloud identity for the new staff
member, keeping both authorization surfaces in sync:
- `user_shop_memberships`: active `STAFF` row for the target shop (Phase 2
  authorization source).
- `user_profiles`: `STAFF` row with `shop_id` = target shop (existing
  single-shop bootstrap/read path).

Both writes are idempotent upserts. Member `role` and `is_active` for existing
profiles are refreshed on re-provision.

## One-time seed (owner bootstrap)

Until the Phase-2 seed runs (migration 0007 backfills memberships from
existing profiles), ensure the cloud owner has an OWNER row:

```sql
-- membership (authoritative, Phase 2):
insert into user_shop_memberships (auth_user_id, shop_id, role)
values ('<owner-auth-user-id>', '<shop-uuid>', 'OWNER');
-- legacy profile mirror (single-shop read path):
insert into user_profiles (auth_user_id, email, role, shop_id)
values ('<owner-auth-user-id>', 'owner@shop.co', 'OWNER', '<shop-uuid>');
```

## Deploy

```bash
supabase functions deploy create-staff --project-ref <project-ref>
# SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
```

## Client behavior on failure

Any non-200 response surfaces as a typed `ProvisioningFailure` in the app —
no partial local profile is written (local profile creation happens only
after this function returns the new identity). The full identity write
(auth user + membership + profile) is the function's atomic boundary: if any
step fails the whole call returns `500` and the caller may safely retry.
