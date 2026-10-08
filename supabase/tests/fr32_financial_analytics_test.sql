-- ============================================================
-- Velvet Grill
-- FR-32: financial analytics correctness.
--
-- Covers the extended public.admin_operational_analytics
-- (migration 20261008000000): the 16 legacy FR-29 columns are
-- unchanged; 5 financial columns are added (settled_orders,
-- gross_settled_value, refunded_value, net_collected_value,
-- avg_settled_order_value).
--
-- Definitions asserted here:
--   gross settled value = sum(final_total) where payment_status
--                         in (PAID, REFUNDED)
--   refunded value      = ... where payment_status = REFUNDED
--   net collected value = ... where payment_status = PAID
--   settled orders      = count where payment_status in (PAID, REFUNDED)
--   average settled     = gross settled / settled orders, NULL when
--                         no settled orders
--   identity: gross settled = net collected + refunded (by
--   construction, since payment_status is single-valued).
--
-- Fixture isolation (no bulk DELETE / TRUNCATE, unlike FR-29):
--   - every fixture uses a dedicated UUID namespace (f032...) and
--     unique order numbers, so nothing collides with seed or other
--     suites;
--   - all fixtures live in the dedicated 2099-01-01..2099-01-07
--     window and every RPC call passes an explicit p_from/p_to, so
--     pre-existing local data can never change the expectations;
--   - the whole suite runs in one rolled-back transaction, so the
--     uncommitted fixture rows are invisible to the pg_cron janitor
--     session; as belt-and-braces, every PENDING digital payment
--     fixture has a fresh payments.created_at and would not be
--     expiry-eligible even if it were visible;
--   - rows 1-16 of the matrix are production-reachable
--     order_status x payment_status combinations; row 17 (FAILED)
--     is a synthetic, unreachable-in-production state pinned only to
--     define the enum's metric behavior (no code path writes FAILED).
--
-- Profiles are provisioned by the on_auth_user_created trigger;
-- fixtures are inserted as the table owner (bypasses RLS).
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(36);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('f032a000-0000-4000-8000-000000000001', 'fr32-customer@test.local'),
  ('f032a000-0000-4000-8000-000000000002', 'fr32-admin@test.local');

update public.profiles
set full_name = 'FR-32 Customer'
where id = 'f032a000-0000-4000-8000-000000000001';

update public.profiles
set full_name = 'Admin', role = 'ADMIN', is_active = true
where id = 'f032a000-0000-4000-8000-000000000002';

-- Pin the restaurant timezone the RPC resolves (rolled back).
update public.restaurant_settings
set timezone = 'Asia/Jakarta'
where id = 1;

-- Reachable state matrix, rows 1-16, plus synthetic row 17 and the
-- outside-window row 18. All PICKUP so no table fixture is needed.
insert into public.orders (
  id,
  order_number,
  user_id,
  fulfillment_type,
  pickup_at,
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
  -- o01: row 1 — CASH at creation (reachable)
  ('f0320000-0000-4000-8000-000000000001', 'VG-FR32-001',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-01 10:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   100000, 0, 100000, 'UNPAID', 'PENDING_PAYMENT',
   (timestamp '2099-01-01 08:00' at time zone 'Asia/Jakarta')),
  -- o02: row 2 — digital awaiting payment (reachable; payment row below is fresh)
  ('f0320000-0000-4000-8000-000000000002', 'VG-FR32-002',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-01 14:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   101000, 0, 101000, 'PENDING', 'PENDING_PAYMENT',
   (timestamp '2099-01-01 12:00' at time zone 'Asia/Jakarta')),
  -- o03: row 3 — digital paid, awaiting staff confirmation (reachable)
  ('f0320000-0000-4000-8000-000000000003', 'VG-FR32-003',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-02 11:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   102000, 0, 102000, 'PAID', 'PENDING_PAYMENT',
   (timestamp '2099-01-02 09:00' at time zone 'Asia/Jakarta')),
  -- o04: row 4 — CASH confirmed, not yet paid (reachable)
  ('f0320000-0000-4000-8000-000000000004', 'VG-FR32-004',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-02 17:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   103000, 0, 103000, 'UNPAID', 'CONFIRMED',
   (timestamp '2099-01-02 15:00' at time zone 'Asia/Jakarta')),
  -- o05: row 5 — digital confirmed and paid (reachable)
  ('f0320000-0000-4000-8000-000000000005', 'VG-FR32-005',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-03 12:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   104000, 0, 104000, 'PAID', 'CONFIRMED',
   (timestamp '2099-01-03 10:00' at time zone 'Asia/Jakarta')),
  -- o06: row 6 — paid and preparing (reachable)
  ('f0320000-0000-4000-8000-000000000006', 'VG-FR32-006',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-03 18:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   105000, 0, 105000, 'PAID', 'PREPARING',
   (timestamp '2099-01-03 16:00' at time zone 'Asia/Jakarta')),
  -- o07: row 7 — CASH preparing, not yet paid (reachable)
  ('f0320000-0000-4000-8000-000000000007', 'VG-FR32-007',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-04 10:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   106000, 0, 106000, 'UNPAID', 'PREPARING',
   (timestamp '2099-01-04 08:00' at time zone 'Asia/Jakarta')),
  -- o08: row 8 — paid and ready (reachable)
  ('f0320000-0000-4000-8000-000000000008', 'VG-FR32-008',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-04 16:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   107000, 0, 107000, 'PAID', 'READY',
   (timestamp '2099-01-04 14:00' at time zone 'Asia/Jakarta')),
  -- o09: row 9 — CASH ready, not yet paid (reachable)
  ('f0320000-0000-4000-8000-000000000009', 'VG-FR32-009',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-05 11:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   108000, 0, 108000, 'UNPAID', 'READY',
   (timestamp '2099-01-05 09:00' at time zone 'Asia/Jakarta')),
  -- o10: row 10 — completed and paid (reachable; refund target in D)
  ('f0320000-0000-4000-8000-000000000010', 'VG-FR32-010',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-05 20:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   109000, 0, 109000, 'PAID', 'COMPLETED',
   (timestamp '2099-01-05 18:00' at time zone 'Asia/Jakarta')),
  -- o11: row 11 — cancelled before settlement (reachable)
  ('f0320000-0000-4000-8000-000000000011', 'VG-FR32-011',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-06 10:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   110000, 0, 110000, 'UNPAID', 'CANCELLED',
   (timestamp '2099-01-06 08:00' at time zone 'Asia/Jakarta')),
  -- o12: row 12 — cancelled while digital payment pending (reachable;
  -- janitor skips CANCELLED orders, payment row below is fresh)
  ('f0320000-0000-4000-8000-000000000012', 'VG-FR32-012',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-06 14:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   111000, 0, 111000, 'PENDING', 'CANCELLED',
   (timestamp '2099-01-06 12:00' at time zone 'Asia/Jakarta')),
  -- o13: row 13 — paid order cancelled by staff (reachable)
  ('f0320000-0000-4000-8000-000000000013', 'VG-FR32-013',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-06 19:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   112000, 0, 112000, 'PAID', 'CANCELLED',
   (timestamp '2099-01-06 17:00' at time zone 'Asia/Jakarta')),
  -- o14: row 14 — expired by the FR-31 janitor (reachable)
  ('f0320000-0000-4000-8000-000000000014', 'VG-FR32-014',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-07 10:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   113000, 0, 113000, 'EXPIRED', 'CANCELLED',
   (timestamp '2099-01-07 08:00' at time zone 'Asia/Jakarta')),
  -- o15: row 15 — CASH order refunded after cancellation (reachable)
  ('f0320000-0000-4000-8000-000000000015', 'VG-FR32-015',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-07 12:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   114000, 0, 114000, 'REFUNDED', 'CANCELLED',
   (timestamp '2099-01-07 10:00' at time zone 'Asia/Jakarta')),
  -- o16: row 16 — completed order refunded (reachable)
  ('f0320000-0000-4000-8000-000000000016', 'VG-FR32-016',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-07 14:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   115000, 0, 115000, 'REFUNDED', 'COMPLETED',
   (timestamp '2099-01-07 12:00' at time zone 'Asia/Jakarta')),
  -- o17: row 17 — SYNTHETIC: FAILED is never written by any code path;
  -- pinned only to define the enum's metric behavior.
  ('f0320000-0000-4000-8000-000000000017', 'VG-FR32-017',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-07 17:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   116000, 0, 116000, 'FAILED', 'PENDING_PAYMENT',
   (timestamp '2099-01-07 15:00' at time zone 'Asia/Jakarta')),
  -- o18: reachable, deliberately OUTSIDE the dedicated window.
  ('f0320000-0000-4000-8000-000000000018', 'VG-FR32-018',
   'f032a000-0000-4000-8000-000000000001', 'PICKUP',
   (timestamp '2099-01-08 11:00' at time zone 'Asia/Jakarta'),
   'FR-32 Customer', '080000000032',
   117000, 0, 117000, 'PAID', 'COMPLETED',
   (timestamp '2099-01-08 09:00' at time zone 'Asia/Jakarta'));

-- Payment rows only where the assertions need them. PENDING rows use a
-- fresh created_at (never stale) so they can never be expiry-eligible.
insert into public.payments (id, order_id, method, status, amount, created_at, paid_at)
values
  ('f032b000-0000-4000-8000-000000000001',
   'f0320000-0000-4000-8000-000000000002',
   'DUMMY_QRIS', 'PENDING', 101000, now(), null),
  ('f032b000-0000-4000-8000-000000000002',
   'f0320000-0000-4000-8000-000000000012',
   'DUMMY_BANK_TRANSFER', 'PENDING', 111000, now(), null),
  ('f032b000-0000-4000-8000-000000000003',
   'f0320000-0000-4000-8000-000000000010',
   'DUMMY_QRIS', 'PAID', 109000,
   (timestamp '2099-01-05 18:10' at time zone 'Asia/Jakarta'),
   (timestamp '2099-01-05 18:10' at time zone 'Asia/Jakarta'));

-- ============================================================
-- A. AUTHORIZATION
-- ============================================================

set local role anon;
set local request.jwt.claim.sub = '';

-- A1
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  $$,
  '42501',
  null,
  'Anon cannot execute the financial analytics RPC'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f032a000-0000-4000-8000-000000000001';

-- A2
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  $$,
  '42501',
  null,
  'Customer cannot execute the financial analytics RPC'
);

set local request.jwt.claim.sub = 'f032a000-0000-4000-8000-000000000002';

-- A3
select is(
  (
    select count(*)::bigint
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  1::bigint,
  'Admin call returns exactly one metrics row'
);

reset role;

-- A4
select is(
  (select has_function_privilege(
    'anon',
    'public.admin_operational_analytics(date, date)',
    'execute'
  )),
  false,
  'anon has no EXECUTE privilege on the RPC'
);

-- A5
select is(
  (select has_function_privilege(
    'authenticated',
    'public.admin_operational_analytics(date, date)',
    'execute'
  )),
  true,
  'authenticated has EXECUTE privilege on the RPC'
);

-- ============================================================
-- B. METRIC MATRIX — dedicated window 2099-01-01..2099-01-07
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = 'f032a000-0000-4000-8000-000000000002';

-- B1: 17 orders in the dedicated window (o18 excluded).
select is(
  (
    select total_orders
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  17::bigint,
  'Total orders counts exactly the dedicated-window fixtures'
);

-- B2: o01, o02, o03, o17.
select is(
  (
    select orders_pending_payment
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  4::bigint,
  'Pending-payment order count is correct'
);

-- B3: o04, o05.
select is(
  (
    select orders_confirmed
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  2::bigint,
  'Confirmed order count is correct'
);

-- B4: o06, o07.
select is(
  (
    select orders_preparing
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  2::bigint,
  'Preparing order count is correct'
);

-- B5: o08, o09.
select is(
  (
    select orders_ready
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  2::bigint,
  'Ready order count is correct'
);

-- B6: o10, o16.
select is(
  (
    select orders_completed
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  2::bigint,
  'Completed order count is correct'
);

-- B7: o11..o15.
select is(
  (
    select orders_cancelled
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  5::bigint,
  'Cancelled order count is correct'
);

-- B8: o01, o04, o07, o09, o11 (CASH before settlement).
select is(
  (
    select payments_unpaid
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  5::bigint,
  'Unpaid payment count is correct'
);

-- B9: o02, o12.
select is(
  (
    select payments_pending
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  2::bigint,
  'Pending payment count is correct'
);

-- B10: o03, o05, o06, o08, o10, o13.
select is(
  (
    select payments_paid
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  6::bigint,
  'Paid payment count is correct'
);

-- B11: o17 synthetic FAILED; o14 EXPIRED.
select is(
  (
    select (payments_failed = 1 and payments_expired = 1)
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  true,
  'Synthetic FAILED and EXPIRED payment counts are correct'
);

-- B12: o15, o16.
select is(
  (
    select payments_refunded
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  2::bigint,
  'Refunded payment count is correct'
);

-- B13: settled = PAID + REFUNDED orders = o03, o05, o06, o08, o10, o13, o15, o16.
select is(
  (
    select settled_orders
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  8::bigint,
  'Settled order count includes exactly the PAID and REFUNDED orders'
);

-- B14: gross settled = 102000+104000+105000+107000+109000+112000+114000+115000.
select is(
  (
    select gross_settled_value
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  868000::numeric,
  'Gross settled value sums PAID and REFUNDED orders'
);

-- B15: refunded = 114000+115000 (includes the CANCELLED+REFUNDED o15).
select is(
  (
    select refunded_value
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  229000::numeric,
  'Refunded value sums REFUNDED orders regardless of order status'
);

-- B16: net = 102000+104000+105000+107000+109000+112000 (includes CANCELLED+PAID o13).
select is(
  (
    select net_collected_value
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  639000::numeric,
  'Net collected value sums PAID orders regardless of order status'
);

-- B17: average = 868000 / 8, exact.
select is(
  (
    select avg_settled_order_value
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  108500::numeric,
  'Average settled order value is gross settled divided by settled orders'
);

-- B18: legacy booked semantics unchanged: all non-cancelled totals
-- = 100000+101000+...+109000 + 115000 + 116000 (REFUNDED o16 included,
-- CANCELLED+REFUNDED o15 excluded).
select is(
  (
    select gross_order_value
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  1276000::numeric,
  'Legacy booked value semantics are preserved'
);

-- B19: identity holds by construction on the mixed fixture.
select is(
  (
    select (gross_settled_value = net_collected_value + refunded_value)
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  true,
  'Gross settled equals net collected plus refunded'
);

-- ============================================================
-- C. WINDOW / EMPTY / COHORT
-- ============================================================

-- C1: empty period yields zero sums, zero settled count, NULL average.
select is(
  (
    select (
      total_orders = 0
      and gross_settled_value = 0
      and refunded_value = 0
      and net_collected_value = 0
      and settled_orders = 0
      and avg_settled_order_value is null
    )
    from public.admin_operational_analytics(
      date '2000-01-01', date '2000-01-02'
    )
  ),
  true,
  'Empty period yields zero sums, zero settled orders, and a NULL average'
);

-- C2: the paid order just outside the window is excluded from it, and
-- its own window carries its full settled value.
select is(
  (
    select (
      total_orders = 1
      and settled_orders = 1
      and net_collected_value = 117000
      and avg_settled_order_value = 117000
    )
    from public.admin_operational_analytics(
      date '2099-01-08', date '2099-01-09'
    )
  ),
  true,
  'A settled order outside the window is excluded from it'
);

-- C3: single-day window is inclusive at the start and half-open at the
-- end: o01 and o02 only (o03 belongs to 2099-01-02).
select is(
  (
    select total_orders
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-01'
    )
  ),
  2::bigint,
  'Single-day window includes its start day only'
);

-- C4
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2099-01-07', date '2099-01-01'
    )
  $$,
  '22023',
  null,
  'Reversed date range is rejected'
);

-- C5
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2099-01-01', null::date
    )
  $$,
  '22023',
  null,
  'A one-sided null range is rejected'
);

-- C6
select throws_ok(
  $$
    select * from public.admin_operational_analytics(
      date '2000-01-01', date '2001-01-01'
    )
  $$,
  '22023',
  null,
  'A 367-inclusive-day range is rejected'
);

-- C7: order-cohort semantics — REFUNDED is attributed to the order
-- creation day (2099-01-07), with no PAID orders that day.
select is(
  (
    select (
      refunded_value = 229000
      and net_collected_value = 0
      and avg_settled_order_value = 114500
    )
    from public.admin_operational_analytics(
      date '2099-01-07', date '2099-01-07'
    )
  ),
  true,
  'Refunded value is attributed to the order creation day'
);

-- C8: dimension divergence on the same day — CANCELLED+REFUNDED o15 is
-- settled money but not booked value; synthetic FAILED o17 is booked
-- but never settled.
select is(
  (
    select (
      gross_order_value = 115000 + 116000
      and gross_settled_value = 114000 + 115000
    )
    from public.admin_operational_analytics(
      date '2099-01-07', date '2099-01-07'
    )
  ),
  true,
  'Booked and settled dimensions diverge exactly as defined'
);

-- ============================================================
-- D. INTEGRATION — metrics move correctly under the real FR-31 refund
--    RPC (which stays untouched; this only observes it).
-- ============================================================

-- D1
select is(
  (
    select public.admin_refund_order_payment(
      'f0320000-0000-4000-8000-000000000010'
    )::text
  ),
  'REFUNDED',
  'The FR-31 refund RPC refunds the PAID+COMPLETED fixture'
);

-- D2: money moved — 109000 left net collected and joined refunded.
select is(
  (
    select (net_collected_value = 530000 and refunded_value = 338000)
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  true,
  'Refund moves the order from net collected to refunded'
);

-- D3: gross settled, settled count, average, and booked value unchanged.
select is(
  (
    select (
      gross_settled_value = 868000
      and settled_orders = 8
      and avg_settled_order_value = 108500
      and gross_order_value = 1276000
    )
    from public.admin_operational_analytics(
      date '2099-01-01', date '2099-01-07'
    )
  ),
  true,
  'Refund leaves gross settled, settled count, average, and booked value unchanged'
);

-- D4: the refund does not change the order lifecycle.
select is(
  (
    select o.order_status::text
    from public.orders o
    where o.id = 'f0320000-0000-4000-8000-000000000010'
  ),
  'COMPLETED',
  'Refunded order keeps its COMPLETED lifecycle status'
);

select * from finish();

rollback;
