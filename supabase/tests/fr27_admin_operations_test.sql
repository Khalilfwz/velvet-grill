-- ============================================================
-- Velvet Grill
-- FR-27: admins manage business hours, tables, and restaurant settings.
--
-- Direct writes on the three tables are revoked from authenticated;
-- admin mutations flow through three authoritative SECURITY DEFINER
-- RPCs (migration 20261002000004) that re-check private.is_admin(),
-- normalize persisted values, validate bounds, and scope the target.
-- This suite asserts:
--   * direct table writes are denied for an authorized admin too;
--   * the admin_* RPCs require an active ADMIN (explicit in-RPC);
--   * in-RPC validation/normalization rejects bad input;
--   * DB constraints/FKs remain the final backstop;
--   * FR-25 audit triggers receive the real auth.uid() and record
--     exactly one row per successful admin write (none when denied or
--     rejected);
--   * public/customer reads stay compatible and historical order
--     references are preserved by deactivate-not-delete.
--
-- Verification context matters: "no audit row" proofs are taken from
-- the owner context (reset role) after executing the action in the
-- actor context. Fixtures are inserted as the table owner. The days
-- under test are normalized so the suite is independent of seed data.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('f2700000-0000-4000-8000-000000000001', 'fr27-admin@test.local'),
  ('f2700000-0000-4000-8000-000000000002', 'fr27-customer@test.local');

update public.profiles
set full_name = 'FR-27 Admin', role = 'ADMIN', is_active = true
where id = 'f2700000-0000-4000-8000-000000000001';

update public.profiles
set full_name = 'FR-27 Customer'
where id = 'f2700000-0000-4000-8000-000000000002';

insert into public.restaurant_tables (id, table_number, capacity, is_active)
values (
  'b2700000-0000-4000-8000-000000000001',
  'FR27-T1',
  4,
  true
);

-- Normalize the days under test (seed may already define them).
delete from public.business_hours where day_of_week in (2, 3);

insert into public.business_hours (
  id, day_of_week, opens_at, closes_at, is_closed
)
values (
  'c2700000-0000-4000-8000-000000000003',
  3,
  '11:00',
  '22:00',
  false
);

insert into public.restaurant_settings (id, restaurant_name)
values (1, 'Velvet Grill')
on conflict (id) do nothing;

-- Historical DINE_IN order referencing FR27-T1.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  restaurant_table_id, table_number_snapshot,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  'd2700000-0000-4000-8000-000000000001',
  'VG-FR27-001',
  'f2700000-0000-4000-8000-000000000002',
  'DINE_IN',
  null,
  'b2700000-0000-4000-8000-000000000001',
  'FR27-T1',
  'FR-27 Customer',
  '080000000027',
  0, 0, 0,
  'UNPAID',
  'PENDING_PAYMENT'
);

-- ============================================================
-- A. DIRECT TABLE WRITES ARE DENIED (admin identity included)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'f2700000-0000-4000-8000-000000000001';

-- TEST 1
select throws_ok(
  $$
    insert into public.restaurant_tables (table_number, capacity)
    values ('FR27-DIRECT', 2)
  $$,
  '42501', null,
  'Admin direct restaurant table insert is denied'
);

-- TEST 2
select throws_ok(
  $$
    update public.restaurant_tables
    set capacity = 1
    where id = 'b2700000-0000-4000-8000-000000000001'
  $$,
  '42501', null,
  'Admin direct restaurant table update is denied'
);

-- TEST 3
select throws_ok(
  $$
    insert into public.business_hours (day_of_week, is_closed)
    values (6, true)
  $$,
  '42501', null,
  'Admin direct business hours insert is denied'
);

-- TEST 4
select throws_ok(
  $$
    update public.business_hours
    set is_closed = true
    where day_of_week = 3
  $$,
  '42501', null,
  'Admin direct business hours update is denied'
);

-- TEST 5
select throws_ok(
  $$
    update public.restaurant_settings
    set restaurant_name = 'Direct'
    where id = 1
  $$,
  '42501', null,
  'Admin direct restaurant settings update is denied'
);

-- ============================================================
-- B. RPC AUTHORIZATION
-- ============================================================

-- TEST 6: customer cannot invoke an admin RPC
set local request.jwt.claim.sub =
  'f2700000-0000-4000-8000-000000000002';

select throws_ok(
  $$
    select public.admin_save_restaurant_table(null, 'FR27-HACK', 2, true)
  $$,
  '42501', null,
  'Customer cannot invoke admin_save_restaurant_table'
);

-- TEST 7: anon cannot invoke an admin RPC
reset role;
set local role anon;

select throws_ok(
  $$
    select public.admin_save_business_hours(2, false, '10:00', '20:00')
  $$,
  '42501', null,
  'Anon cannot invoke admin_save_business_hours'
);

-- TEST 8: customer cannot invoke the settings RPC
reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'f2700000-0000-4000-8000-000000000002';

select throws_ok(
  $$
    select public.admin_save_restaurant_settings(
      'Hack', null, null, 'Asia/Jakarta'
    )
  $$,
  '42501', null,
  'Customer cannot invoke admin_save_restaurant_settings'
);

-- ============================================================
-- C. ADMIN MUTATIONS VIA RPC
-- ============================================================

set local request.jwt.claim.sub =
  'f2700000-0000-4000-8000-000000000001';

-- TEST 9
select is(
  (
    select public.admin_save_restaurant_table(null, 'FR27-T2', 6, true)
      is not null
  ),
  true,
  'Admin can create a restaurant table via RPC'
);

-- TEST 10
select lives_ok(
  $$
    select public.admin_save_restaurant_table(
      'b2700000-0000-4000-8000-000000000001', 'FR27-T1', 8, true
    )
  $$,
  'Admin can update a restaurant table via RPC'
);

-- TEST 11
select lives_ok(
  $$
    select public.admin_save_business_hours(2, false, '10:00', '20:00')
  $$,
  'Admin can set business hours for a new day via RPC'
);

-- TEST 12
select lives_ok(
  $$
    select public.admin_save_business_hours(3, true, null, null)
  $$,
  'Admin can mark a day closed via RPC'
);

-- TEST 13
select lives_ok(
  $$
    select public.admin_save_restaurant_settings(
      'Velvet Grill FR27', 'Bandung', '+62 22 1111', 'Asia/Jakarta'
    )
  $$,
  'Admin can update restaurant settings via RPC'
);

-- TEST 14
select lives_ok(
  $$
    select public.admin_save_restaurant_table(
      'b2700000-0000-4000-8000-000000000001', 'FR27-T1', 8, false
    )
  $$,
  'Admin can deactivate a restaurant table via RPC'
);

-- ============================================================
-- D. IN-RPC VALIDATION + BOUNDS (all rejected)
-- ============================================================

-- TEST 15
select throws_ok(
  $$ select public.admin_save_restaurant_table(null, 'FR27-BAD', 0, true) $$,
  '22023', null,
  'RPC rejects a zero capacity'
);

-- TEST 16
select throws_ok(
  $$ select public.admin_save_restaurant_table(null, 'FR27-BAD', null, true) $$,
  '22023', null,
  'RPC rejects a null capacity'
);

-- TEST 17
select throws_ok(
  $$ select public.admin_save_restaurant_table(null, '   ', 2, true) $$,
  '22023', null,
  'RPC rejects a blank table number'
);

-- TEST 18
select throws_ok(
  $$
    select public.admin_save_restaurant_table(
      null, repeat('a', 121), 2, true
    )
  $$,
  '22023', null,
  'RPC rejects an over-long table number'
);

-- TEST 19
select throws_ok(
  $$
    select public.admin_save_business_hours(7, false, '11:00', '22:00')
  $$,
  '22023', null,
  'RPC rejects an out-of-range day of week'
);

-- TEST 20
select throws_ok(
  $$
    select public.admin_save_business_hours(4, true, '11:00', null)
  $$,
  '22023', null,
  'RPC rejects closed hours that still supply a time'
);

-- TEST 21
select throws_ok(
  $$
    select public.admin_save_business_hours(4, false, null, '22:00')
  $$,
  '22023', null,
  'RPC rejects open hours with a missing time'
);

-- TEST 22
select throws_ok(
  $$
    select public.admin_save_business_hours(4, false, '25:00', '22:00')
  $$,
  '22023', null,
  'RPC rejects a malformed opening time'
);

-- TEST 23
select throws_ok(
  $$
    select public.admin_save_restaurant_settings('   ', null, null, 'Asia/Jakarta')
  $$,
  '22023', null,
  'RPC rejects a blank restaurant name'
);

-- ============================================================
-- E. TARGET / CONSTRAINT BACKSTOP
-- ============================================================

-- TEST 24
select throws_ok(
  $$
    select public.admin_save_restaurant_table(
      '00000000-0000-4000-8000-0000000000ff', 'FR27-GHOST', 2, true
    )
  $$,
  'P0002', null,
  'RPC rejects an update to an unknown table'
);

-- TEST 25
select throws_ok(
  $$ select public.admin_save_restaurant_table(null, 'FR27-T1', 2, true) $$,
  '23505', null,
  'DB unique constraint rejects a duplicate table number'
);

-- ============================================================
-- F. REJECTED / DENIED WRITES WRITE NO AUDIT
-- ============================================================

reset role;

-- TEST 26
select is(
  (
    select count(*) from public.admin_audit_logs
    where action = 'RESTAURANT_TABLES_INSERT'
      and actor_user_id = 'f2700000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Only the successful table create was audited; rejects wrote nothing'
);

-- TEST 27
select is(
  (
    select count(*) from public.admin_audit_logs
    where actor_user_id = 'f2700000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'Denied non-admin write wrote no audit row'
);

-- ============================================================
-- G. SUCCESSFUL WRITES AUDITED EXACTLY ONCE
-- ============================================================

-- TEST 28
select is(
  (
    select
      count(*)::text
      || '|' || count(*) filter (where action = 'RESTAURANT_TABLES_INSERT')::text
      || '|' || count(*) filter (where action = 'RESTAURANT_TABLES_UPDATE')::text
      || '|' || count(*) filter (where action = 'BUSINESS_HOURS_INSERT')::text
      || '|' || count(*) filter (where action = 'BUSINESS_HOURS_UPDATE')::text
      || '|' || count(*) filter (where action = 'RESTAURANT_SETTINGS_UPDATE')::text
      || '|' || count(*) filter (
        where action = 'RESTAURANT_SETTINGS_UPDATE' and entity_id is null
      )::text
    from public.admin_audit_logs
    where actor_user_id = 'f2700000-0000-4000-8000-000000000001'
  ),
  '6|1|2|1|1|1|1',
  'Each successful admin RPC write is audited exactly once; rejected writes none'
);

-- TEST 29
select is(
  (
    select
      count(*)::text
      || '|' || coalesce(max(before_data ->> 'capacity'), '')
      || '|' || coalesce(max(after_data ->> 'capacity'), '')
    from public.admin_audit_logs
    where action = 'RESTAURANT_TABLES_UPDATE'
      and entity_id = 'b2700000-0000-4000-8000-000000000001'
      and actor_user_id = 'f2700000-0000-4000-8000-000000000001'
      and before_data ->> 'capacity' = '4'
  ),
  '1|4|8',
  'Table update audited once with real actor and before/after capacity'
);

-- TEST 30
select is(
  (
    select
      count(*)::text
      || '|' || coalesce(max(before_data ->> 'is_closed'), '')
      || '|' || coalesce(max(after_data ->> 'is_closed'), '')
    from public.admin_audit_logs
    where action = 'BUSINESS_HOURS_UPDATE'
      and entity_id = (
        select id from public.business_hours where day_of_week = 3
      )
      and actor_user_id = 'f2700000-0000-4000-8000-000000000001'
  ),
  '1|false|true',
  'Business hours update audited once with entity id and before/after closed state'
);

-- ============================================================
-- H. CUSTOMER COMPATIBILITY + HISTORICAL INTEGRITY
-- ============================================================

reset role;
set local role anon;

-- TEST 31
select is(
  (
    select count(*) from public.restaurant_tables
    where table_number = 'FR27-T2'
  ),
  1::bigint,
  'Public reader still sees an active table created via RPC'
);

-- TEST 32
select is(
  (
    select count(*) from public.restaurant_tables
    where table_number = 'FR27-T1'
  ),
  0::bigint,
  'Deactivated table is hidden from the public read policy'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'f2700000-0000-4000-8000-000000000001';

-- TEST 33
select is(
  (
    select count(*) from public.restaurant_tables
    where table_number = 'FR27-T1'
  ),
  1::bigint,
  'Admin still reads the deactivated table for management'
);

reset role;
set local role anon;

-- TEST 34
select is(
  (
    select count(*) from public.business_hours
    where day_of_week in (2, 3)
  ),
  2::bigint,
  'Public reader still sees business hours'
);

-- TEST 35
select is(
  (
    select count(*) from public.restaurant_settings where id = 1
  ),
  1::bigint,
  'Public reader still sees restaurant settings'
);

reset role;

-- TEST 36
select is(
  (
    select count(*) from public.orders
    where id = 'd2700000-0000-4000-8000-000000000001'
      and restaurant_table_id = 'b2700000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Historical order still references the deactivated table'
);

-- TEST 37
select is(
  (
    select table_number_snapshot from public.orders
    where id = 'd2700000-0000-4000-8000-000000000001'
  ),
  'FR27-T1',
  'Historical table number snapshot is unchanged'
);

select * from finish();

rollback;
