-- ============================================================
-- Velvet Grill
-- FR-35: admin daily analytics trend.
--
-- Covers public.admin_daily_analytics (migration 20261009020000):
-- one zero-filled row per calendar day in the range, with
--   orders_created      = all orders created that day (incl. CANCELLED)
--   net_collected_value = sum(final_total) for current payment_status
--                         = 'PAID' (REFUNDED/UNPAID/PENDING/FAILED/
--                         EXPIRED contribute zero)
-- attributed to the restaurant-local orders.created_at day, using the
-- same inclusive calendar-date window as FR-32, ordered by day asc.
--
-- Fixture isolation (same conventions as fr32/fr34, no bulk DELETE /
-- TRUNCATE): dedicated UUID namespace (f035...) and unique order
-- numbers, the dedicated 2097-03-01..2097-03-07 window with explicit
-- p_from/p_to on every call, and a single rolled-back transaction so
-- nothing touches pre-existing data or the janitor's view.
--
-- `reset role` is issued before reading the owner-created temp
-- baseline and the privileged audit count (the FR-34 lesson), so a
-- fixture-role permission failure is never mistaken for an RPC one.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('f035a000-0000-4000-8000-000000000001', 'fr35-admin@test.local'),
  ('f035a000-0000-4000-8000-000000000002', 'fr35-admin-inactive@test.local'),
  ('f035a000-0000-4000-8000-000000000003', 'fr35-customer@test.local');

update public.profiles
set full_name = 'Admin', role = 'ADMIN', is_active = true
where id = 'f035a000-0000-4000-8000-000000000001';

update public.profiles
set full_name = 'Admin Inactive', role = 'ADMIN', is_active = false
where id = 'f035a000-0000-4000-8000-000000000002';

update public.profiles
set full_name = 'FR-35 Customer'
where id = 'f035a000-0000-4000-8000-000000000003';

-- Pin the restaurant timezone the RPC resolves (rolled back).
update public.restaurant_settings
set timezone = 'Asia/Jakarta'
where id = 1;

-- All PICKUP so no restaurant-table fixture is needed. Statuses span
-- the whole enum to prove orders_created counts every order status and
-- net_collected_value only counts PAID.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total,
  payment_status, order_status, created_at
)
values
  -- d1 = 2097-03-01: one PAID, one UNPAID.
  ('f0350000-0000-4000-8000-000000000001', 'VG-FR35-001',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-01 10:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   50000, 0, 50000, 'PAID', 'COMPLETED',
   (timestamp '2097-03-01 10:00' at time zone 'Asia/Jakarta')),
  ('f0350000-0000-4000-8000-000000000002', 'VG-FR35-002',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-01 12:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   30000, 0, 30000, 'UNPAID', 'PENDING_PAYMENT',
   (timestamp '2097-03-01 12:00' at time zone 'Asia/Jakarta')),
  -- d2 = 2097-03-02: REFUNDED (counts as created, zero net) and a
  -- CANCELLED order that is still PAID (counts toward net).
  ('f0350000-0000-4000-8000-000000000003', 'VG-FR35-003',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-02 09:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   40000, 0, 40000, 'REFUNDED', 'COMPLETED',
   (timestamp '2097-03-02 09:00' at time zone 'Asia/Jakarta')),
  ('f0350000-0000-4000-8000-000000000004', 'VG-FR35-004',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-02 15:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   25000, 0, 25000, 'PAID', 'CANCELLED',
   (timestamp '2097-03-02 15:00' at time zone 'Asia/Jakarta')),
  -- d4 = 2097-03-04: an EXPIRED/CANCELLED order (zero net).
  ('f0350000-0000-4000-8000-000000000005', 'VG-FR35-005',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-04 08:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   99000, 0, 99000, 'EXPIRED', 'CANCELLED',
   (timestamp '2097-03-04 08:00' at time zone 'Asia/Jakarta')),
  -- Belongs to d5, not d4: created 2097-03-04 20:00 UTC =
  -- 2097-03-05 03:00 restaurant time. PENDING (zero net).
  ('f0350000-0000-4000-8000-000000000006', 'VG-FR35-006',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-05 05:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   20000, 0, 20000, 'PENDING', 'PENDING_PAYMENT',
   (timestamp '2097-03-04 20:00' at time zone 'UTC')),
  -- d5 = 2097-03-05: synthetic FAILED (unreachable in production,
  -- pinned only for the enum) and a PAID near-midnight boundary order.
  ('f0350000-0000-4000-8000-000000000007', 'VG-FR35-007',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-05 12:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   15000, 0, 15000, 'FAILED', 'PENDING_PAYMENT',
   (timestamp '2097-03-05 10:00' at time zone 'Asia/Jakarta')),
  ('f0350000-0000-4000-8000-000000000008', 'VG-FR35-008',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-06 00:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   60000, 0, 60000, 'PAID', 'PREPARING',
   (timestamp '2097-03-05 23:30' at time zone 'Asia/Jakarta')),
  -- d7 = 2097-03-07.
  ('f0350000-0000-4000-8000-000000000009', 'VG-FR35-009',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-07 09:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   80000, 0, 80000, 'PAID', 'COMPLETED',
   (timestamp '2097-03-07 09:00' at time zone 'Asia/Jakarta')),
  ('f0350000-0000-4000-8000-000000000010', 'VG-FR35-010',
   'f035a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2097-03-07 11:00' at time zone 'Asia/Jakarta'),
   'FR-35 Customer', '080000000035',
   10000, 0, 10000, 'UNPAID', 'CONFIRMED',
   (timestamp '2097-03-07 11:00' at time zone 'Asia/Jakarta'));

-- Baseline for the no-mutation assertion, taken after all fixtures
-- exist and before any RPC call.
create temp table fr35_baseline as
select
  (select count(*) from public.orders
    where order_number like 'VG-FR35-%') as orders_n,
  (select count(*) from public.payments p
    where p.order_id in (select id from public.orders
      where order_number like 'VG-FR35-%')) as payments_n,
  (select count(*) from public.order_items oi
    where oi.order_id in (select id from public.orders
      where order_number like 'VG-FR35-%')) as order_items_n,
  (select count(*) from public.admin_audit_logs) as audit_n;

-- ============================================================
-- A. AUTHORIZATION
-- ============================================================

set local role anon;
set local request.jwt.claim.sub = '';

-- A1
select throws_ok(
  $$
    select * from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  $$,
  '42501',
  null,
  'Anon cannot execute the daily analytics RPC'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f035a000-0000-4000-8000-000000000003';

-- A2
select throws_ok(
  $$
    select * from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  $$,
  '42501',
  null,
  'Active customer cannot execute the daily analytics RPC'
);

set local request.jwt.claim.sub = 'f035a000-0000-4000-8000-000000000002';

-- A3
select throws_ok(
  $$
    select * from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  $$,
  '42501',
  null,
  'Inactive admin is denied'
);

set local request.jwt.claim.sub = 'f035a000-0000-4000-8000-000000000001';

-- A4: admin succeeds and the 7-day range yields exactly 7 rows.
select is(
  (
    select count(*)::bigint
    from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  ),
  7::bigint,
  'Admin can call the RPC and receives one row per day in the range'
);

reset role;

-- A5
select is(
  (select has_function_privilege(
    'anon',
    'public.admin_daily_analytics(date, date)',
    'execute'
  )),
  false,
  'anon has no EXECUTE privilege on the RPC'
);

-- A6
select is(
  (select has_function_privilege(
    'authenticated',
    'public.admin_daily_analytics(date, date)',
    'execute'
  )),
  true,
  'authenticated has EXECUTE privilege (subject to the internal admin check)'
);

-- ============================================================
-- B. SERIES, GROUPING, RECONCILIATION
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = 'f035a000-0000-4000-8000-000000000001';

-- B1: the full deterministic series for 2097-03-01..2097-03-07.
-- Covers: every day present including the zero-filled 03-03 and 03-06;
-- all order statuses counted by orders_created; only PAID counted by
-- net_collected_value (REFUNDED 40000 on 03-02 contributes zero, PAID
-- CANCELLED 25000 on 03-02 does contribute); the UTC-created order
-- lands on 03-05 by restaurant-local date; the near-midnight order
-- stays on 03-05.
select results_eq(
  $$
    select day, orders_created, net_collected_value
    from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  $$,
  $$
    values
      (date '2097-03-01',  2::bigint, 50000::numeric),
      (date '2097-03-02',  2::bigint, 25000::numeric),
      (date '2097-03-03',  0::bigint,     0::numeric),
      (date '2097-03-04',  1::bigint,     0::numeric),
      (date '2097-03-05',  3::bigint, 60000::numeric),
      (date '2097-03-06',  0::bigint,     0::numeric),
      (date '2097-03-07',  2::bigint, 80000::numeric)
  $$,
  'Every day is present, zero-filled, and grouped by restaurant-local creation date'
);

-- B2: daily order counts reconcile with FR-32 total_orders.
select is(
  (
    select sum(orders_created)::bigint
    from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  ),
  (
    select total_orders
    from public.admin_operational_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  ),
  'Sum of daily order counts equals FR-32 total_orders for the same window'
);

-- B3: daily net collected reconciles with FR-32 net_collected_value.
select is(
  (
    select sum(net_collected_value)
    from public.admin_daily_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  ),
  (
    select net_collected_value
    from public.admin_operational_analytics(
      date '2097-03-01', date '2097-03-07'
    )
  ),
  'Sum of daily net collected equals FR-32 net_collected_value for the same window'
);

-- B4: refund-dependent cohort semantics match FR-32 on the refund day
-- (03-02): the REFUNDED order is attributed to its creation day and
-- contributes only the PAID 25000.
select is(
  (
    select net_collected_value
    from public.admin_daily_analytics(
      date '2097-03-02', date '2097-03-02'
    )
  ),
  (
    select net_collected_value
    from public.admin_operational_analytics(
      date '2097-03-02', date '2097-03-02'
    )
  ),
  'Refund-dependent cohort net matches FR-32 on the order creation day'
);

-- ============================================================
-- C. SINGLE DAY AND INVALID RANGES
-- ============================================================

-- C1: a one-day range yields exactly that day.
select results_eq(
  $$
    select day, orders_created, net_collected_value
    from public.admin_daily_analytics(
      date '2097-03-05', date '2097-03-05'
    )
  $$,
  $$
    values (date '2097-03-05', 3::bigint, 60000::numeric)
  $$,
  'A one-day range returns exactly that day'
);

-- C2
select throws_ok(
  $$
    select * from public.admin_daily_analytics(
      date '2097-03-07', date '2097-03-01'
    )
  $$,
  '22023',
  null,
  'Reversed date range is rejected'
);

-- C3
select throws_ok(
  $$
    select * from public.admin_daily_analytics(
      date '2097-03-01', null::date
    )
  $$,
  '22023',
  null,
  'A one-sided null range is rejected'
);

-- C4: (v_to - v_from) = 366 > 365, i.e. 367 inclusive days.
select throws_ok(
  $$
    select * from public.admin_daily_analytics(
      date '2097-01-01', date '2098-01-02'
    )
  $$,
  '22023',
  null,
  'A range beyond the 366-day maximum is rejected'
);

-- ============================================================
-- D. READ-ONLY GUARANTEE
-- ============================================================

reset role;

-- D1: no fixture transaction record changed and no admin audit log
-- row was written by any RPC call in this suite.
select is(
  (
    select b.orders_n = (select count(*) from public.orders
                           where order_number like 'VG-FR35-%')
       and b.payments_n = (select count(*) from public.payments p
                             where p.order_id in (select id from public.orders
                               where order_number like 'VG-FR35-%'))
       and b.order_items_n = (select count(*) from public.order_items oi
                                where oi.order_id in (select id from public.orders
                                  where order_number like 'VG-FR35-%'))
       and b.audit_n = (select count(*) from public.admin_audit_logs)
    from fr35_baseline b
  ),
  true,
  'Calling the daily analytics RPC mutates no transaction records and writes no admin audit logs'
);

select * from finish();

rollback;
