-- ============================================================
-- Velvet Grill
-- FR-34: admin top products analytics.
--
-- Covers public.admin_top_products (migration 20261009010002):
-- the five products with the highest fulfilled unit quantity in the
-- selected range. "Units fulfilled" is an operational metric:
--   - only order_status = 'COMPLETED' contributes (SUM of
--     order_items.quantity across order lines, never line counts);
--   - completed orders later marked REFUNDED remain included;
--   - pending / confirmed / preparing / ready / cancelled orders are
--     excluded;
--   - attribution follows orders.created_at in the restaurant
--     timezone (same inclusive calendar-date window and 366-day
--     maximum as FR-32), never order_items.created_at;
--   - identity: aggregate by order_items.product_id when present;
--     when the product was deleted (ON DELETE SET NULL), preserve the
--     rows under the namespaced key 'deleted:' || product_name_snapshot.
--     Known limitation (pinned by design, not fixed here): distinct
--     deleted products that shared an identical historical snapshot
--     name cannot be distinguished once product_id is lost.
--
-- Fixture isolation (same conventions as fr32_financial_analytics_
-- test.sql, no bulk DELETE / TRUNCATE):
--   - dedicated UUID namespace (f034...) and unique order numbers,
--     so nothing collides with seed or other suites;
--   - the dedicated 2098-05-01..2098-05-07 window with explicit
--     p_from/p_to on every call, so pre-existing local data can never
--     change the expectations;
--   - the whole suite runs in one rolled-back transaction; no fixture
--     carries a PENDING digital payment, so nothing is expiry-eligible
--     even if the uncommitted rows were visible to the janitor.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('f034a000-0000-4000-8000-000000000001', 'fr34-admin@test.local'),
  ('f034a000-0000-4000-8000-000000000002', 'fr34-admin-inactive@test.local'),
  ('f034a000-0000-4000-8000-000000000003', 'fr34-customer@test.local');

update public.profiles
set full_name = 'Admin', role = 'ADMIN', is_active = true
where id = 'f034a000-0000-4000-8000-000000000001';

update public.profiles
set full_name = 'Admin Inactive', role = 'ADMIN', is_active = false
where id = 'f034a000-0000-4000-8000-000000000002';

update public.profiles
set full_name = 'FR-34 Customer'
where id = 'f034a000-0000-4000-8000-000000000003';

-- Pin the restaurant timezone the RPC resolves (rolled back).
update public.restaurant_settings
set timezone = 'Asia/Jakarta'
where id = 1;

insert into public.categories (id, name, slug)
values
  ('f034d000-0000-4000-8000-000000000001', 'FR-34 Fixtures', 'fr-34-fixtures');

insert into public.products (id, category_id, name, slug, base_price, stock)
values
  ('f034c000-0000-4000-8000-000000000001', 'f034d000-0000-4000-8000-000000000001', 'Char Burger',            'fr34-a', 25000, 100),
  ('f034c000-0000-4000-8000-000000000002', 'f034d000-0000-4000-8000-000000000001', 'Excluded Burger',        'fr34-b', 25000, 100),
  ('f034c000-0000-4000-8000-000000000003', 'f034d000-0000-4000-8000-000000000001', 'Iced Tea',               'fr34-c', 10000, 100),
  ('f034c000-0000-4000-8000-000000000004', 'f034d000-0000-4000-8000-000000000001', 'Old Name',               'fr34-d', 15000, 100),
  ('f034c000-0000-4000-8000-000000000005', 'f034d000-0000-4000-8000-000000000001', 'Beta Roast',             'fr34-e', 30000, 100),
  ('f034c000-0000-4000-8000-000000000006', 'f034d000-0000-4000-8000-000000000001', 'Alpha Roast',            'fr34-f', 30000, 100),
  ('f034c000-0000-4000-8000-000000000007', 'f034d000-0000-4000-8000-000000000001', 'Low Seller',             'fr34-g', 20000, 100),
  ('f034c000-0000-4000-8000-000000000008', 'f034d000-0000-4000-8000-000000000001', 'Midnight Snack',         'fr34-h', 12000, 100);

-- All PICKUP so no restaurant-table fixture is needed. Completed orders
-- are PAID or REFUNDED; no fixture carries a PENDING digital payment.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total,
  payment_status, order_status, created_at
)
values
  -- o01: two lines for product A (2 + 3), summed across order lines.
  ('f0340000-0000-4000-8000-000000000001', 'VG-FR34-001',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-02 12:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   125000, 0, 125000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-02 10:00' at time zone 'Asia/Jakarta')),
  -- o02: completed then refunded — still counts (operational metric).
  ('f0340000-0000-4000-8000-000000000002', 'VG-FR34-002',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-03 13:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   25000, 0, 25000, 'REFUNDED', 'COMPLETED',
   (timestamp '2098-05-03 11:00' at time zone 'Asia/Jakarta')),
  -- o03: cancelled — its 100 units must never appear.
  ('f0340000-0000-4000-8000-000000000003', 'VG-FR34-003',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-04 11:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   2500000, 0, 2500000, 'PAID', 'CANCELLED',
   (timestamp '2098-05-04 09:00' at time zone 'Asia/Jakarta')),
  -- o04: preparing — also excluded (only COMPLETED contributes).
  ('f0340000-0000-4000-8000-000000000004', 'VG-FR34-004',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-04 14:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   500000, 0, 500000, 'PAID', 'PREPARING',
   (timestamp '2098-05-04 12:00' at time zone 'Asia/Jakarta')),
  -- o05: A again (4 units, cross-order sum) plus C (2 units).
  ('f0340000-0000-4000-8000-000000000005', 'VG-FR34-005',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-05 15:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   120000, 0, 120000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-05 13:00' at time zone 'Asia/Jakarta')),
  -- o06: product D under its historical snapshot name.
  ('f0340000-0000-4000-8000-000000000006', 'VG-FR34-006',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-06 12:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   30000, 0, 30000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-06 10:00' at time zone 'Asia/Jakarta')),
  -- o07: product D again, renamed in the snapshot; same product_id
  -- aggregates with o06 and shows the latest snapshot name.
  ('f0340000-0000-4000-8000-000000000007', 'VG-FR34-007',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-06 17:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   45000, 0, 45000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-06 15:00' at time zone 'Asia/Jakarta')),
  -- o08: first boundary day; product was deleted, so product_id is
  -- NULL and only the snapshot name survives.
  ('f0340000-0000-4000-8000-000000000008', 'VG-FR34-008',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-01 02:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   70000, 0, 70000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-01 00:30' at time zone 'Asia/Jakarta')),
  -- o09/o10: the 6-vs-6 tie — name asc must order Alpha before Beta.
  ('f0340000-0000-4000-8000-000000000009', 'VG-FR34-009',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-05 11:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   180000, 0, 180000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-05 09:00' at time zone 'Asia/Jakarta')),
  ('f0340000-0000-4000-8000-000000000010', 'VG-FR34-010',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-06 20:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   180000, 0, 180000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-06 18:00' at time zone 'Asia/Jakarta')),
  -- o11: below the Top-5 cutoff.
  ('f0340000-0000-4000-8000-000000000011', 'VG-FR34-011',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-06 21:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   20000, 0, 20000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-06 19:00' at time zone 'Asia/Jakarta')),
  -- o12: created 2098-05-07 20:00 UTC = 2098-05-08 03:00 restaurant
  -- time — OUTSIDE the window only because of the restaurant TZ.
  ('f0340000-0000-4000-8000-000000000012', 'VG-FR34-012',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-08 05:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   5000000, 0, 5000000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-07 20:00' at time zone 'UTC')),
  -- o13: last boundary day, near midnight restaurant time — inside.
  ('f0340000-0000-4000-8000-000000000013', 'VG-FR34-013',
   'f034a000-0000-4000-8000-000000000003', 'PICKUP',
   (timestamp '2098-05-08 01:00' at time zone 'Asia/Jakarta'),
   'FR-34 Customer', '080000000034',
   12000, 0, 12000, 'PAID', 'COMPLETED',
   (timestamp '2098-05-07 23:30' at time zone 'Asia/Jakarta'));

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal, created_at
)
values
  ('f034b000-0000-4000-8000-000000000001',
   'f0340000-0000-4000-8000-000000000001',
   'f034c000-0000-4000-8000-000000000001', 'Char Burger',
   25000, 25000, 2, 50000,
   (timestamp '2098-05-02 10:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000002',
   'f0340000-0000-4000-8000-000000000001',
   'f034c000-0000-4000-8000-000000000001', 'Char Burger',
   25000, 25000, 3, 75000,
   (timestamp '2098-05-02 10:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000003',
   'f0340000-0000-4000-8000-000000000002',
   'f034c000-0000-4000-8000-000000000001', 'Char Burger',
   25000, 25000, 1, 25000,
   (timestamp '2098-05-03 11:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000004',
   'f0340000-0000-4000-8000-000000000003',
   'f034c000-0000-4000-8000-000000000002', 'Excluded Burger',
   25000, 25000, 100, 2500000,
   (timestamp '2098-05-04 09:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000005',
   'f0340000-0000-4000-8000-000000000004',
   'f034c000-0000-4000-8000-000000000003', 'Iced Tea',
   10000, 10000, 50, 500000,
   (timestamp '2098-05-04 12:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000006',
   'f0340000-0000-4000-8000-000000000005',
   'f034c000-0000-4000-8000-000000000001', 'Char Burger',
   25000, 25000, 4, 100000,
   (timestamp '2098-05-05 13:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000007',
   'f0340000-0000-4000-8000-000000000005',
   'f034c000-0000-4000-8000-000000000003', 'Iced Tea',
   10000, 10000, 2, 20000,
   (timestamp '2098-05-05 13:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000008',
   'f0340000-0000-4000-8000-000000000006',
   'f034c000-0000-4000-8000-000000000004', 'Old Name',
   15000, 15000, 2, 30000,
   (timestamp '2098-05-06 10:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000009',
   'f0340000-0000-4000-8000-000000000007',
   'f034c000-0000-4000-8000-000000000004', 'Signature Fries Deluxe',
   15000, 15000, 3, 45000,
   (timestamp '2098-05-06 15:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000010',
   'f0340000-0000-4000-8000-000000000008',
   null, 'Legacy Burger',
   10000, 10000, 7, 70000,
   (timestamp '2098-05-01 00:30' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000011',
   'f0340000-0000-4000-8000-000000000009',
   'f034c000-0000-4000-8000-000000000005', 'Beta Roast',
   30000, 30000, 6, 180000,
   (timestamp '2098-05-05 09:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000012',
   'f0340000-0000-4000-8000-000000000010',
   'f034c000-0000-4000-8000-000000000006', 'Alpha Roast',
   30000, 30000, 6, 180000,
   (timestamp '2098-05-06 18:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000013',
   'f0340000-0000-4000-8000-000000000011',
   'f034c000-0000-4000-8000-000000000007', 'Low Seller',
   20000, 20000, 1, 20000,
   (timestamp '2098-05-06 19:00' at time zone 'Asia/Jakarta')),
  ('f034b000-0000-4000-8000-000000000014',
   'f0340000-0000-4000-8000-000000000012',
   'f034c000-0000-4000-8000-000000000002', 'Excluded Burger',
   25000, 25000, 200, 5000000,
   (timestamp '2098-05-07 20:00' at time zone 'UTC')),
  ('f034b000-0000-4000-8000-000000000015',
   'f0340000-0000-4000-8000-000000000013',
   'f034c000-0000-4000-8000-000000000008', 'Midnight Snack',
   12000, 12000, 1, 12000,
   (timestamp '2098-05-07 23:30' at time zone 'Asia/Jakarta'));

-- Baseline for the no-mutation assertion (property 15): counts are
-- taken after all fixtures exist and before any RPC call.
create temp table fr34_baseline as
select
  (select count(*) from public.orders
    where order_number like 'VG-FR34-%') as orders_n,
  (select count(*) from public.payments p
    where p.order_id in (select id from public.orders
      where order_number like 'VG-FR34-%')) as payments_n,
  (select count(*) from public.order_items oi
    where oi.order_id in (select id from public.orders
      where order_number like 'VG-FR34-%')) as order_items_n,
  (select count(*) from public.admin_audit_logs) as audit_n;

-- ============================================================
-- A. AUTHORIZATION
-- ============================================================

set local role anon;
set local request.jwt.claim.sub = '';

-- A1
select throws_ok(
  $$
    select * from public.admin_top_products(
      date '2098-05-01', date '2098-05-07'
    )
  $$,
  '42501',
  null,
  'Anon cannot execute the top products RPC'
);

set local role authenticated;
set local request.jwt.claim.sub = 'f034a000-0000-4000-8000-000000000003';

-- A2
select throws_ok(
  $$
    select * from public.admin_top_products(
      date '2098-05-01', date '2098-05-07'
    )
  $$,
  '42501',
  null,
  'Active customer cannot access protected analytics'
);

set local request.jwt.claim.sub = 'f034a000-0000-4000-8000-000000000002';

-- A3
select throws_ok(
  $$
    select * from public.admin_top_products(
      date '2098-05-01', date '2098-05-07'
    )
  $$,
  '42501',
  null,
  'Inactive admin is denied'
);

set local request.jwt.claim.sub = 'f034a000-0000-4000-8000-000000000001';

-- A4: admin succeeds; exactly five rows is also the Top-5 limit.
select is(
  (
    select count(*)::bigint
    from public.admin_top_products(
      date '2098-05-01', date '2098-05-07'
    )
  ),
  5::bigint,
  'Admin can call the RPC and receives at most five ranked rows'
);

reset role;

-- A5
select is(
  (select has_function_privilege(
    'anon',
    'public.admin_top_products(date, date)',
    'execute'
  )),
  false,
  'anon has no EXECUTE privilege on the RPC'
);

-- A6
select is(
  (select has_function_privilege(
    'authenticated',
    'public.admin_top_products(date, date)',
    'execute'
  )),
  true,
  'authenticated has EXECUTE privilege (subject to the internal admin check)'
);

-- ============================================================
-- B. RANKING, IDENTITY, WINDOW
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = 'f034a000-0000-4000-8000-000000000001';

-- B1: the full deterministic ranking for 2098-05-01..2098-05-07.
-- Covers: only COMPLETED contributes (o03/o04 excluded); quantities
-- summed across lines and orders (A = 2+3+1+4 = 10); the refunded
-- completed order o02 still contributes; the name tie orders Alpha
-- before Beta; the renamed product aggregates by id under its latest
-- snapshot name; the deleted-product row survives under the
-- namespaced key. Ranking: A 10, Legacy 7, Alpha 6, Beta 6, D 5;
-- Iced Tea (2), Low Seller (1), Midnight Snack (1) miss the cutoff.
select results_eq(
  $$
    select product_key, product_name, units_fulfilled
    from public.admin_top_products(
      date '2098-05-01', date '2098-05-07'
    )
  $$,
  $$
    values
      ('f034c000-0000-4000-8000-000000000001'::uuid::text,
       'Char Burger', 10::bigint),
      ('deleted:Legacy Burger', 'Legacy Burger', 7::bigint),
      ('f034c000-0000-4000-8000-000000000006'::uuid::text,
       'Alpha Roast', 6::bigint),
      ('f034c000-0000-4000-8000-000000000005'::uuid::text,
       'Beta Roast', 6::bigint),
      ('f034c000-0000-4000-8000-000000000004'::uuid::text,
       'Signature Fries Deluxe', 5::bigint)
  $$,
  'Ranking, summing, refunded inclusion, and exclusion are all correct'
);

-- B2: empty range yields zero rows, not fabricated zeros.
select is(
  (
    select count(*)::bigint
    from public.admin_top_products(
      date '2098-05-20', date '2098-05-21'
    )
  ),
  0::bigint,
  'A range without completed order items yields zero rows'
);

-- B3: date boundaries follow the restaurant timezone and order
-- creation date. o13 (2098-05-07 23:30 Asia/Jakarta) is inside the
-- last day; o12 (created 2098-05-07 20:00 UTC = 2098-05-08 03:00
-- restaurant time) is outside only because of the timezone.
select is(
  (
    select (
      count(*) = 1
      and bool_and(units_fulfilled = 1)
      and bool_and(product_name = 'Midnight Snack')
    )
    from public.admin_top_products(
      date '2098-05-07', date '2098-05-07'
    )
  ),
  true,
  'Single-day window uses order creation date in the restaurant timezone'
);

-- ============================================================
-- C. INVALID RANGES
-- ============================================================

-- C1
select throws_ok(
  $$
    select * from public.admin_top_products(
      date '2098-05-07', date '2098-05-01'
    )
  $$,
  '22023',
  null,
  'Reversed date range is rejected'
);

-- C2
select throws_ok(
  $$
    select * from public.admin_top_products(
      date '2098-05-01', null::date
    )
  $$,
  '22023',
  null,
  'A one-sided null range is rejected'
);

-- C3: (v_to - v_from) = 366 > 365, i.e. 367 inclusive days.
select throws_ok(
  $$
    select * from public.admin_top_products(
      date '2098-01-01', date '2099-01-02'
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
                           where order_number like 'VG-FR34-%')
       and b.payments_n = (select count(*) from public.payments p
                             where p.order_id in (select id from public.orders
                               where order_number like 'VG-FR34-%'))
       and b.order_items_n = (select count(*) from public.order_items oi
                                where oi.order_id in (select id from public.orders
                                  where order_number like 'VG-FR34-%'))
       and b.audit_n = (select count(*) from public.admin_audit_logs)
    from fr34_baseline b
  ),
  true,
  'Calling the analytics RPC mutates no transaction records and writes no admin audit logs'
);

select * from finish();

rollback;
