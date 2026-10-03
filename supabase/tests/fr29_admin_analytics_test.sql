-- ============================================================
-- Velvet Grill
-- FR-29: admins inspect operational analytics.
--
-- Covers public.admin_operational_analytics
-- (migration 20261003000001): a read-only, admin-gated aggregate
-- over transactional orders. analytics_events are never consulted.
--
-- Gross order value excludes CANCELLED orders only; a REFUNDED,
-- non-cancelled order remains included. Reads write no audit rows.
--
-- Because the RPC aggregates ALL orders in a window, any pre-existing
-- orders would change the absolute expectations below. This suite runs
-- in a rolled-back transaction, so it clears public.orders first to make
-- the global counts deterministic. coupon_usages references orders
-- with ON DELETE RESTRICT, so any such rows must be absent (none exist
-- for these fixtures).
--
-- Fixture timestamps are expressed in the restaurant timezone
-- (Asia/Jakarta), matching the RPC's boundary computation.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table owner.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'fr29-customer@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'fr29-admin@test.local');

update public.profiles
set full_name = 'FR-29 Customer'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Admin', role = 'ADMIN', is_active = true
where id = '22222222-2222-2222-2222-222222222222';

insert into public.restaurant_tables (id, table_number, capacity, is_active)
values ('40000000-0000-4000-8000-000000000029', 'FR29-T1', 4, true);

-- Deterministic global counts. This runs inside the pgTAP transaction and is
-- rolled back, so pre-existing local development data is restored.
--
-- Delete dependent rows in FK order first (no CASCADE, no schema changes):
--   reviews -> order_items is ON DELETE RESTRICT
--   coupon_usages -> orders is ON DELETE RESTRICT
-- Deleting orders then cascades order_items/order_item_options/payments/
-- order_status_history and nulls analytics_events/notifications order_id.
delete from public.reviews;
delete from public.coupon_usages;
delete from public.orders;

insert into public.orders (
  id,
  order_number,
  user_id,
  fulfillment_type,
  pickup_at,
  restaurant_table_id,
  table_number_snapshot,
  customer_name_snapshot,
  customer_phone_snapshot,
  subtotal,
  discount_total,
  final_total,
  payment_status,
  order_status,
  created_at
)
values
  -- O1: today 12:00, PICKUP, COMPLETED, PAID, 100000
  (
    'd2900000-0000-4000-8000-000000000001',
    'VG-FR29-001',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    ((now() at time zone 'Asia/Jakarta')::date + time '14:00')
      at time zone 'Asia/Jakarta',
    null,
    null,
    'FR-29 Customer',
    '080000000029',
    100000,
    0,
    100000,
    'PAID',
    'COMPLETED',
    ((now() at time zone 'Asia/Jakarta')::date + time '12:00')
      at time zone 'Asia/Jakarta'
  ),
  -- O2: today 18:00, DINE_IN, CANCELLED, UNPAID, 50000
  (
    'd2900000-0000-4000-8000-000000000002',
    'VG-FR29-002',
    '11111111-1111-1111-1111-111111111111',
    'DINE_IN',
    null,
    '40000000-0000-4000-8000-000000000029',
    'FR29-T1',
    'FR-29 Customer',
    '080000000029',
    50000,
    0,
    50000,
    'UNPAID',
    'CANCELLED',
    ((now() at time zone 'Asia/Jakarta')::date + time '18:00')
      at time zone 'Asia/Jakarta'
  ),
  -- O3: today-2 09:00, PICKUP, PREPARING, PENDING, 200000
  (
    'd2900000-0000-4000-8000-000000000003',
    'VG-FR29-003',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    (((now() at time zone 'Asia/Jakarta')::date - 2) + time '11:00')
      at time zone 'Asia/Jakarta',
    null,
    null,
    'FR-29 Customer',
    '080000000029',
    200000,
    0,
    200000,
    'PENDING',
    'PREPARING',
    (((now() at time zone 'Asia/Jakarta')::date - 2) + time '09:00')
      at time zone 'Asia/Jakarta'
  ),
  -- O4: today-6 00:00, DINE_IN, CONFIRMED, REFUNDED, 300000
  (
    'd2900000-0000-4000-8000-000000000004',
    'VG-FR29-004',
    '11111111-1111-1111-1111-111111111111',
    'DINE_IN',
    null,
    '40000000-0000-4000-8000-000000000029',
    'FR29-T1',
    'FR-29 Customer',
    '080000000029',
    300000,
    0,
    300000,
    'REFUNDED',
    'CONFIRMED',
    (((now() at time zone 'Asia/Jakarta')::date - 6) + time '00:00')
      at time zone 'Asia/Jakarta'
  ),
  -- O5: today-7 00:00, PICKUP, COMPLETED, PAID, 700000 (outside default window)
  (
    'd2900000-0000-4000-8000-000000000005',
    'VG-FR29-005',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    (((now() at time zone 'Asia/Jakarta')::date - 7) + time '02:00')
      at time zone 'Asia/Jakarta',
    null,
    null,
    'FR-29 Customer',
    '080000000029',
    700000,
    0,
    700000,
    'PAID',
    'COMPLETED',
    (((now() at time zone 'Asia/Jakarta')::date - 7) + time '00:00')
      at time zone 'Asia/Jakarta'
  ),
  -- O6: today+1 00:00, PICKUP, READY, PENDING, 400000 (outside default window)
  (
    'd2900000-0000-4000-8000-000000000006',
    'VG-FR29-006',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    (((now() at time zone 'Asia/Jakarta')::date + 1) + time '02:00')
      at time zone 'Asia/Jakarta',
    null,
    null,
    'FR-29 Customer',
    '080000000029',
    400000,
    0,
    400000,
    'PENDING',
    'READY',
    (((now() at time zone 'Asia/Jakarta')::date + 1) + time '00:00')
      at time zone 'Asia/Jakarta'
  );

-- Audit baseline captured before any admin RPC call.
create temp table fr29_audit_baseline as
select count(*)::bigint as audit_count
from public.admin_audit_logs;

-- ============================================================
-- A. AUTHORIZATION
-- ============================================================

set local role anon;
set local request.jwt.claim.sub = '';

-- A1
select throws_ok(
  $$
    select * from public.admin_operational_analytics()
  $$,
  '42501',
  null,
  'Anon cannot execute the operational analytics RPC'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- A2
select throws_ok(
  $$
    select * from public.admin_operational_analytics()
  $$,
  '42501',
  null,
  'Customer cannot execute the operational analytics RPC'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- A3
select is(
  (
    select count(*)::bigint
    from public.admin_operational_analytics()
  ),
  1::bigint,
  'Admin call returns exactly one metrics row'
);

-- ============================================================
-- B. CORRECTNESS — DEFAULT WINDOW (last 7 calendar days)
-- ============================================================

-- B1
select is(
  (select total_orders from public.admin_operational_analytics()),
  4::bigint,
  'Total orders counts only the default-window orders'
);

-- B2
select is(
  (select orders_completed from public.admin_operational_analytics()),
  1::bigint,
  'Completed order count is correct'
);

-- B3
select is(
  (select orders_cancelled from public.admin_operational_analytics()),
  1::bigint,
  'Cancelled order count is correct'
);

-- B4
select is(
  (select orders_preparing from public.admin_operational_analytics()),
  1::bigint,
  'Preparing order count is correct'
);

-- B5
select is(
  (select orders_confirmed from public.admin_operational_analytics()),
  1::bigint,
  'Confirmed order count is correct'
);

-- B6
select is(
  (select orders_ready from public.admin_operational_analytics()),
  0::bigint,
  'Ready order count is zero in the default window'
);

-- B7
select is(
  (select orders_pending_payment from public.admin_operational_analytics()),
  0::bigint,
  'Pending-payment order count is zero in the default window'
);

-- B8
select is(
  (select payments_paid from public.admin_operational_analytics()),
  1::bigint,
  'Paid order count is correct'
);

-- B9
select is(
  (select payments_unpaid from public.admin_operational_analytics()),
  1::bigint,
  'Unpaid order count is correct'
);

-- B10
select is(
  (select payments_pending from public.admin_operational_analytics()),
  1::bigint,
  'Pending payment count is correct'
);

-- B11
select is(
  (select payments_refunded from public.admin_operational_analytics()),
  1::bigint,
  'Refunded payment count is correct'
);

-- B12
select is(
  (select payments_failed from public.admin_operational_analytics()),
  0::bigint,
  'Failed payment count is zero'
);

-- B13
select is(
  (select payments_expired from public.admin_operational_analytics()),
  0::bigint,
  'Expired payment count is zero'
);

-- B14
select is(
  (select fulfillment_pickup from public.admin_operational_analytics()),
  2::bigint,
  'Pickup order count is correct'
);

-- B15
select is(
  (select fulfillment_dine_in from public.admin_operational_analytics()),
  2::bigint,
  'Dine-in order count is correct'
);

-- B16
select is(
  (select gross_order_value from public.admin_operational_analytics()),
  600000::numeric,
  'Gross order value excludes cancelled but includes refunded'
);

-- ============================================================
-- C. RANGE / VALIDATION
-- ============================================================

-- C1
select is(
  (
    select (total_orders = 0 and gross_order_value = 0)
    from public.admin_operational_analytics(
      date '2000-01-01',
      date '2000-01-02'
    )
  ),
  true,
  'Empty range yields zero totals and zero gross value'
);

-- C2
select is(
  (
    select total_orders
    from public.admin_operational_analytics(
      (now() at time zone 'Asia/Jakarta')::date,
      (now() at time zone 'Asia/Jakarta')::date
    )
  ),
  2::bigint,
  'Single-day range counts only today orders'
);

-- C3
select is(
  (
    select total_orders
    from public.admin_operational_analytics(
      (now() at time zone 'Asia/Jakarta')::date - 7,
      (now() at time zone 'Asia/Jakarta')::date
    )
  ),
  5::bigint,
  'Inclusive start boundary includes the today-7 order'
);

-- C4
select is(
  (
    select total_orders
    from public.admin_operational_analytics(
      (now() at time zone 'Asia/Jakarta')::date + 1,
      (now() at time zone 'Asia/Jakarta')::date + 1
    )
  ),
  1::bigint,
  'Future single-day range selects only the future order'
);

-- C5
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2026-02-01',
      date '2026-01-01'
    )
  $$,
  '22023',
  null,
  'Reversed date range is rejected'
);

-- C6
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2026-01-01',
      null::date
    )
  $$,
  '22023',
  null,
  'A one-sided null range is rejected'
);

-- C7
select lives_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2000-01-01',
      date '2000-12-31'
    )
  $$,
  'A 366-inclusive-day range (365-day span) is accepted'
);

-- C8
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2000-01-01',
      date '2001-01-01'
    )
  $$,
  '22023',
  null,
  'A 367-inclusive-day range (366-day span) is rejected'
);

-- ============================================================
-- D. ISOLATION / REGRESSION
-- ============================================================

-- Behavioral analytics insert must not influence metrics.
set local role anon;
set local request.jwt.claim.sub = '';

insert into public.analytics_events (session_id, event_name, event_category)
values ('fr29-anon-session', 'PAGE_VIEWED', 'BEHAVIORAL');

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- D1
select is(
  (select total_orders from public.admin_operational_analytics()),
  4::bigint,
  'Behavioral analytics insert does not change operational metrics'
);

reset role;

-- D2
select is(
  (
    select count(*)::bigint
    from public.admin_audit_logs
  ),
  (select audit_count from fr29_audit_baseline),
  'The analytics RPC writes no audit rows'
);

-- D3
select is(
  (
    select sum(final_total)
    from public.orders
    where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  1750000::numeric,
  'The analytics RPC does not modify order rows'
);

select * from finish();

rollback;
