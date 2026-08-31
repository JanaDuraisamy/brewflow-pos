# create-staff Edge Function

Secure server boundary for staff provisioning. The Flutter app never holds
service-role credentials; it calls this function with the signed-in owner's
JWT (`supabase.functions.invoke('create-staff', body: {...})`).

## Contract (matches `SupabaseStaffProvisioning` in the client)

Request body:
```json
{ "email": "staff@shop.co", "password": "temp-pass-6+", "display_name": "Ravi" }
```

Success `200`:
```json
{ "id": "<auth-user-uuid>", "email": "staff@shop.co" }
```

Typed errors: `400 INVALID_INPUT` · `401 UNAUTHENTICATED` · `403 FORBIDDEN`
(non-owner caller) · `409 DUPLICATE_EMAIL` · `500 PROVISIONING_FAILED`.

## Owner authorization

The function reads the cloud `user_profiles` table
(`auth_user_id, role, is_active`) with the service role and only proceeds when
the caller is an active OWNER. Until the Step-3 profile mirror exists, run the
one-time seed below for the shop owner (never ship credentials to clients):

```sql
create table if not exists user_profiles (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  role text not null check (role in ('OWNER', 'STAFF')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
-- insert the owner row once, after their first login:
-- insert into user_profiles (auth_user_id, email, role)
-- values ('<owner-auth-user-id>', 'owner@shop.co', 'OWNER');
```

## Deploy

```bash
supabase functions deploy create-staff --project-ref <project-ref>
# SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
```

## Client behavior on failure

Any non-200 response surfaces as a typed `ProvisioningFailure` in the app —
no partial local profile is written (local profile creation happens only
after this function returns the new identity).
