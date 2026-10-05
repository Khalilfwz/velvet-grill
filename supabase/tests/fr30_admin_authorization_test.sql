-- ============================================================
-- Velvet Grill
-- FR-30: admin authorization is enforced server-side and by
-- database policy where applicable.
--
-- Cross-cutting authorization proof. Existing suites prove
-- CUSTOMER/anon denial per feature and that private.is_admin()
-- is false for an inactive admin (FR-08). This suite closes the
-- gap those leave open: an INACTIVE admin is denied across every
-- capability family, authorization follows current authoritative
-- DB state rather than a cached/authenticated session, RPC-only
-- resources are not directly writable, admin-only reads are
-- hidden, and every public.admin_* RPC is SECURITY DEFINER with
-- a pinned search_path and a restricted EXECUTE grant.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table
-- owner before switching to the `authenticated` role.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('f3000000-0000-4000-8000-0000000000a1', 'fr30-active-admin@test.local'),
  ('f3000000-0000-4000-8000-0000000000b2', 'fr30-inactive-admin@test.local'),
  ('f3000000-0000-4000-8000-0000000000c3', 'fr30-customer@test.local');

update public.profiles
set full_name = 'FR-30 Active Admin', role = 'ADMIN', is_active = true
where id = 'f3000000-0000-4000-8000-0000000000a1';

update public.profiles
set full_name = 'FR-30 Inactive Admin', role = 'ADMIN', is_active = false
where id = 'f3000000-0000-4000-8000-0000000000b2';

update public.profiles
set full_name = 'FR-30 Customer'
where id = 'f3000000-0000-4000-8000-0000000000c3';

-- One order to anchor the direct-write denial target in section C.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  'd3000000-0000-4000-8000-000000000030',
  'VG-FR30-001',
  'f3000000-0000-4000-8000-0000000000c3',
  'PICKUP',
  now() + interval '2 hours',
  'FR-30 Customer',
  '080000000030',
  100000,
  0,
  100000,
  'PAID',
  'CONFIRMED'
);

-- A visible audit row so "0 rows" for the inactive admin proves RLS, not an
-- empty table.
insert into public.admin_audit_logs (actor_user_id, action, entity_type)
values (
  'f3000000-0000-4000-8000-0000000000a1',
  'FR30_FIXTURE',
  'orders'
);

-- ============================================================
-- A. CURRENT AUTHORITATIVE DB STATE / STALE-ADMIN BEHAVIOR
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = 'f3000000-0000-4000-8000-0000000000a1';

-- A1 (control)
select is(
  (select private.is_admin()),
  true,
  'Active ADMIN passes private.is_admin()'
);

-- Owner flips the admin inactive while the session stays the same.
reset role;
update public.profiles
set is_active = false
where id = 'f3000000-0000-4000-8000-0000000000a1';

set local role authenticated;
set local request.jwt.claim.sub = 'f3000000-0000-4000-8000-0000000000a1';

-- A2
select is(
  (select private.is_admin()),
  false,
  'Previously-authenticated ADMIN is denied after is_active=false'
);

-- Owner restores the admin; authorization must follow the DB, not a cache.
reset role;
update public.profiles
set is_active = true
where id = 'f3000000-0000-4000-8000-0000000000a1';

set local role authenticated;
set local request.jwt.claim.sub = 'f3000000-0000-4000-8000-0000000000a1';

-- A3
select is(
  (select private.is_admin()),
  true,
  'Authorization reads current DB state, not a cached JWT claim'
);

-- ============================================================
-- B. INACTIVE-ADMIN DENIAL PER CAPABILITY FAMILY
-- One representative RPC per family; all share the same
-- private.is_admin() gate, so a representative set is sufficient.
-- ============================================================

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'f3000000-0000-4000-8000-0000000000b2';

-- B1 catalog
select throws_ok(
  $$ select public.admin_save_category(null, 'FR-30', 'fr-30', null, null, 0, true) $$,
  '42501',
  null,
  'Inactive ADMIN is denied the catalog admin RPC'
);

-- B2 operations
select throws_ok(
  $$ select public.admin_save_restaurant_table(null, 'FR-30-T1', 4, true) $$,
  '42501',
  null,
  'Inactive ADMIN is denied the operations admin RPC'
);

-- B3 order status
select throws_ok(
  $$ select public.update_order_status(
       'd3000000-0000-4000-8000-000000000030'::uuid, 'PREPARING'
     ) $$,
  '42501',
  null,
  'Inactive ADMIN is denied the order-status RPC'
);

-- B4 review moderation
select throws_ok(
  $$ select public.admin_moderate_review(
       'd3000000-0000-4000-8000-000000000030'::uuid, 'HIDDEN'
     ) $$,
  '42501',
  null,
  'Inactive ADMIN is denied the review-moderation RPC'
);

-- B5 analytics
select throws_ok(
  $$ select * from public.admin_operational_analytics() $$,
  '42501',
  null,
  'Inactive ADMIN is denied the analytics RPC'
);

-- ============================================================
-- C. DIRECT-WRITE DENIAL ON AN RPC-ONLY RESOURCE
-- ============================================================

-- C1
select throws_ok(
  $$ update public.orders
     set order_status = 'PREPARING'
     where id = 'd3000000-0000-4000-8000-000000000030' $$,
  '42501',
  null,
  'Inactive ADMIN cannot write the RPC-only order_status column directly'
);

-- ============================================================
-- D. ADMIN-ONLY READ DENIAL
-- ============================================================

-- D1
select is(
  (
    select count(*)
    from public.admin_audit_logs
  ),
  0::bigint,
  'Inactive ADMIN cannot read admin audit logs'
);

-- ============================================================
-- E. CROSS-CUTTING RPC HARDENING (all public.admin_* functions)
-- ============================================================

reset role;

-- E1
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~ '^admin_'
      and (
        not p.prosecdef
        or coalesce(array_to_string(p.proconfig, ','), '')
           not like '%search_path=%'
      )
  ),
  0::bigint,
  'Every public.admin_* RPC is SECURITY DEFINER with a pinned search_path'
);

-- E2
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~ '^admin_'
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'No public.admin_* RPC is executable by anon'
);

-- E3
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~ '^admin_'
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'Every public.admin_* RPC is executable by authenticated'
);

select * from finish();

rollback;
