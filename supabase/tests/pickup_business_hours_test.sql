begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

-- ============================================================
-- BUG-01: pickup business-hours enforcement inside create_order.
--
-- create_order is the sole scheduling authority. Pickup input is a
-- restaurant-local wall-clock text value; Postgres resolves it with the
-- authoritative restaurant_settings.timezone and enforces business_hours.
--
-- The suite is deterministic: every pickup literal is a fixed wall-clock in a
-- known weekday slot. Each SUCCESSFUL call consumes the cart, so every success
-- inserts its own fresh cart_item and uses a unique idempotency key.
--
-- Configuration tables are admin-managed, so their mutations run in the owner
-- context (`reset role` ... `set local role authenticated`) while create_order
-- is exercised as an authenticated customer.
-- The whole file rolls back.
-- ============================================================

-- ------------------------------------------------------------
-- Fixtures (inserted as owner, before the authenticated role)
-- ------------------------------------------------------------

insert into auth.users (id, email)
values (
  'a0010101-0000-0000-0000-000000000001',
  'bug01-customer@test.local'
);

insert into public.categories (id, name, slug, is_active)
values (
  'c0010101-0000-0000-0000-000000000001',
  'BUG-01 Category',
  'bug01-category',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  'd0010101-0000-0000-0000-000000000001',
  'c0010101-0000-0000-0000-000000000001',
  'BUG-01 Product',
  'bug01-product',
  100000,
  1000,
  true
);

insert into public.carts (id, user_id)
values (
  'b0010101-0000-0000-0000-000000000001',
  'a0010101-0000-0000-0000-000000000001'
);

insert into public.restaurant_tables (id, table_number, capacity, is_active)
values (
  'e0010101-0000-0000-0000-000000000001',
  'BUG01-T1',
  4,
  true
);

-- Authoritative configuration: deterministic defaults (seed-independent).
insert into public.restaurant_settings (id, restaurant_name, timezone)
values (1, 'Velvet Grill', 'Asia/Jakarta')
on conflict (id) do update set timezone = excluded.timezone;

insert into public.business_hours (day_of_week, opens_at, closes_at, is_closed)
values
  (0, '11:00', '22:00', false),
  (1, '11:00', '22:00', false),
  (2, '11:00', '22:00', false),
  (3, '11:00', '22:00', false),
  (4, '11:00', '22:00', false),
  (5, '11:00', '23:00', false),
  (6, '11:00', '23:00', false)
on conflict (day_of_week) do update
  set opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      is_closed = excluded.is_closed;

set local role authenticated;
set local request.jwt.claim.sub = 'a0010101-0000-0000-0000-000000000001';

-- ============================================================
-- Normal interval. 2026-01-05 is a Monday (dow = 1), 11:00-22:00.
-- ============================================================

-- T1: valid pickup during opening hours.
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000001',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T12:00', null, 'bug01-ok-1', 'CASH'
    )
  $$,
  'In-hours pickup is accepted'
);

-- T2: before opening is rejected.
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T10:59', null, 'bug01-before', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'Before opening is rejected'
);

-- T3: exact opening boundary is accepted (inclusive).
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000002',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T11:00', null, 'bug01-open', 'CASH'
    )
  $$,
  'Exact opening time is accepted'
);

-- T4: exact closing boundary is rejected (exclusive).
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T22:00', null, 'bug01-close', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'Exact closing time is rejected'
);

-- ============================================================
-- Closed day and missing row. 2026-01-07 is Wednesday (dow = 3);
-- 2026-01-08 is Thursday (dow = 4).
-- ============================================================

-- T5: closed day is rejected.
reset role;
update public.business_hours
set is_closed = true, opens_at = null, closes_at = null
where day_of_week = 3;
set local role authenticated;

select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-07T12:00', null, 'bug01-closed', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'A closed day is rejected'
);

reset role;
update public.business_hours
set is_closed = false, opens_at = '11:00', closes_at = '22:00'
where day_of_week = 3;
set local role authenticated;

-- T6: a missing business_hours row is treated as closed and rejected.
reset role;
delete from public.business_hours where day_of_week = 4;
set local role authenticated;

select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-08T12:00', null, 'bug01-missing', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'A missing business_hours row is rejected'
);

reset role;
insert into public.business_hours (day_of_week, opens_at, closes_at, is_closed)
values (4, '11:00', '22:00', false);
set local role authenticated;

-- ============================================================
-- Overnight interval. Monday (dow = 1) becomes 18:00-02:00;
-- 2026-01-06 is Tuesday (dow = 2), 11:00-22:00.
-- ============================================================

reset role;
update public.business_hours
set opens_at = '18:00', closes_at = '02:00', is_closed = false
where day_of_week = 1;
set local role authenticated;

-- T7: evening portion (before midnight), same day.
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000003',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T23:00', null, 'bug01-ovn-eve', 'CASH'
    )
  $$,
  'Overnight opening before midnight is accepted'
);

-- T8: after-midnight portion is accepted via the previous day's overnight tail.
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000004',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-06T01:00', null, 'bug01-ovn-am', 'CASH'
    )
  $$,
  'Overnight continuation after midnight is accepted via the previous day'
);

-- T9: outside the overnight interval is rejected.
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-06T03:00', null, 'bug01-ovn-out', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'Outside the overnight interval is rejected'
);

reset role;
update public.business_hours
set opens_at = '11:00', closes_at = '22:00', is_closed = false
where day_of_week = 1;
set local role authenticated;

-- ============================================================
-- Timezone configuration fails closed.
-- ============================================================

-- T10: invalid IANA timezone rejects pickup.
reset role;
update public.restaurant_settings set timezone = 'Not/AZone' where id = 1;
set local role authenticated;

select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T12:00', null, 'bug01-badtz', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'An invalid restaurant timezone rejects pickup (fail closed)'
);

-- T11: DINE_IN is unaffected by the invalid timezone.
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000005',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

select lives_ok(
  $$
    select public.create_order(
      'DINE_IN', 'BUG-01 Customer', null, null, null,
      'e0010101-0000-0000-0000-000000000001', 'bug01-dinein-badtz', 'CASH'
    )
  $$,
  'DINE_IN still succeeds while the restaurant timezone is invalid'
);

reset role;
update public.restaurant_settings set timezone = 'Asia/Jakarta' where id = 1;
set local role authenticated;

-- T12: a missing restaurant_settings row rejects pickup.
reset role;
delete from public.restaurant_settings where id = 1;
set local role authenticated;

select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T12:00', null, 'bug01-notz', 'CASH'
    )
  $$,
  '22023',
  'Pickup time is outside business hours',
  'A missing restaurant timezone rejects pickup (fail closed)'
);

reset role;
insert into public.restaurant_settings (id, restaurant_name, timezone)
values (1, 'Velvet Grill', 'Asia/Jakarta');
set local role authenticated;

-- ============================================================
-- Input shape fails closed.
-- ============================================================

-- T13: non-wall-clock text is rejected.
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      'not-a-date', null, 'bug01-garbage', 'CASH'
    )
  $$,
  '22023',
  'Pickup details are invalid',
  'A malformed pickup value is rejected'
);

-- T14: an impossible calendar date passes the shape check but fails the cast.
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-02-30T12:00', null, 'bug01-imp', 'CASH'
    )
  $$,
  '22023',
  'Pickup details are invalid',
  'An impossible calendar date is rejected (fail closed)'
);

-- ============================================================
-- DINE_IN remains unaffected.
-- ============================================================

-- T15: a normal DINE_IN order still succeeds.
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000006',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

select lives_ok(
  $$
    select public.create_order(
      'DINE_IN', 'BUG-01 Customer', null, null, null,
      'e0010101-0000-0000-0000-000000000001', 'bug01-dinein', 'CASH'
    )
  $$,
  'DINE_IN order creation is unchanged'
);

-- T16: a DINE_IN order stores no pickup time.
select is(
  (
    select pickup_at is null
    from public.orders
    where idempotency_key = 'bug01-dinein'
  ),
  true,
  'DINE_IN order stores no pickup time'
);

-- ============================================================
-- Idempotency replay is not invalidated by a later config change.
-- ============================================================

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'f0010101-0000-0000-0000-000000000007',
  'b0010101-0000-0000-0000-000000000001',
  'd0010101-0000-0000-0000-000000000001',
  1
);

-- T17a: the original order is created.
select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T12:00', null, 'bug01-replay', 'CASH'
    )
  $$,
  'Pickup order for replay is created'
);

select set_config(
  'bug01.replay_id',
  (
    select id::text
    from public.orders
    where idempotency_key = 'bug01-replay'
  ),
  true
);

-- The configuration changes after the order exists (invalid timezone).
reset role;
update public.restaurant_settings set timezone = 'Not/AZone' where id = 1;
set local role authenticated;

-- T17b: replaying the same key still returns the original order.
select is(
  (
    select public.create_order(
      'PICKUP', 'BUG-01 Customer', null, null,
      '2026-01-05T12:00', null, 'bug01-replay', 'CASH'
    )::text
  ),
  current_setting('bug01.replay_id'),
  'An idempotent replay is unaffected by a later timezone change'
);

reset role;
update public.restaurant_settings set timezone = 'Asia/Jakarta' where id = 1;
set local role authenticated;

-- ============================================================
-- Existing pricing behavior is intact.
-- ============================================================

-- T18: the order total is still derived server-side.
select is(
  (
    select final_total
    from public.orders
    where idempotency_key = 'bug01-ok-1'
  ),
  100000.00::numeric,
  'Pickup order pricing is unchanged'
);

select * from finish();

rollback;
