begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ============================================================
-- FR-20: dine-in table validation.
--
-- Verification-only. Proves the existing authoritative
-- public.create_order behavior: PICKUP/DINE_IN table rules,
-- server-resolved table context, the unified (no-oracle) error
-- for nonexistent vs inactive tables, no partial side effects on
-- failed validation, the orders_fulfillment_chk backstop, and
-- that a table-validation rejection does not consume the
-- idempotency key.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

-- ------------------------------------------------------------
-- FIXTURES (owner context)
-- ------------------------------------------------------------

insert into auth.users (id, email)
values (
  '20202020-1111-1111-1111-111111111111',
  'fr20-customer-a@test.local'
);

update public.profiles
set full_name = 'FR-20 Customer A'
where id = '20202020-1111-1111-1111-111111111111';

insert into public.categories (id, name, slug, is_active)
values (
  'c2020202-1111-1111-1111-111111111111',
  'FR-20 Category',
  'fr20-category',
  true
);

-- No option groups: create_order tolerates a product with zero
-- active groups, so the cart line needs no option selection.
insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  'd2020202-1111-1111-1111-111111111111',
  'c2020202-1111-1111-1111-111111111111',
  'FR-20 Product',
  'fr20-product',
  100000,
  10,
  true
);

insert into public.carts (id, user_id)
values (
  'a2020202-1111-1111-1111-111111111111',
  '20202020-1111-1111-1111-111111111111'
);

insert into public.restaurant_tables (
  id, table_number, capacity, is_active
)
values
  ('e2020201-1111-1111-1111-111111111111', 'FR20-ACTIVE', 4, true),
  ('e2020202-2222-2222-2222-222222222222', 'FR20-INACTIVE', 4, false);

-- ============================================================
-- A. restaurant_tables client read visibility
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '20202020-1111-1111-1111-111111111111';

-- T1
select is(
  (
    select count(*)
    from public.restaurant_tables
    where id = 'e2020201-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'Authenticated customer can read the active table'
);

-- T2
select is(
  (
    select count(*)
    from public.restaurant_tables
    where id = 'e2020202-2222-2222-2222-222222222222'
  ),
  0::bigint,
  'Inactive table is not exposed to the customer'
);

-- T3
select is(
  (
    select count(*)
    from public.restaurant_tables
    where id = '00000000-0000-0000-0000-000000000000'
  ),
  0::bigint,
  'Nonexistent table is unreadable like the inactive one (no read oracle)'
);

-- ------------------------------------------------------------
-- Cart line X exists for the rejected attempt below (owner).
-- ------------------------------------------------------------

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b2020201-1111-1111-1111-111111111111',
  'a2020202-1111-1111-1111-111111111111',
  'd2020202-1111-1111-1111-111111111111',
  1
);

-- ============================================================
-- D. Invalid/tampered fulfillment-table combinations
-- (uses the same key 'fr20-retry' as the later valid DINE_IN)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '20202020-1111-1111-1111-111111111111';

-- T4
select throws_ok(
  $$
    select public.create_order(
      'DINE_IN', 'FR-20 Customer A', null, null, null,
      'e2020202-2222-2222-2222-222222222222', 'fr20-retry', 'CASH'
    )
  $$,
  '22023',
  'The selected table is not available',
  'DINE_IN with an inactive table is rejected'
);

-- T5
select is(
  (
    select count(*)
    from public.cart_items
    where cart_id = 'a2020202-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'The rejected attempt leaves the cart unconsumed and usable'
);

-- T6
select throws_ok(
  $$
    select public.create_order(
      'DINE_IN', 'FR-20 Customer A', null, null, null,
      '00000000-0000-0000-0000-000000000000', 'fr20-nonexistent', 'CASH'
    )
  $$,
  '22023',
  'The selected table is not available',
  'DINE_IN with a nonexistent table gives the identical error (no oracle)'
);

-- T7
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-20 Customer A', null, null,
      now() + interval '2 hours',
      'e2020201-1111-1111-1111-111111111111', 'fr20-pickup-table', 'CASH'
    )
  $$,
  '22023',
  'Pickup details are invalid',
  'PICKUP with a non-null table is rejected'
);

-- T8
select throws_ok(
  $$
    select public.create_order(
      'DINE_IN', 'FR-20 Customer A', null, null, null,
      null, 'fr20-dinein-null', 'CASH'
    )
  $$,
  '22023',
  'Dine-in details are invalid',
  'DINE_IN with a null table is rejected'
);

-- ============================================================
-- B. Valid PICKUP (reuses the surviving cart line X)
-- ============================================================

select set_config(
  'fr20.pickup_order',
  (
    select public.create_order(
      'PICKUP', 'FR-20 Customer A', null, null,
      now() + interval '2 hours', null, 'fr20-pickup', 'CASH'
    )::text
  ),
  true
);

-- T9
select is(
  (
    select count(*)
    from public.orders
    where id = current_setting('fr20.pickup_order')::uuid
  ),
  1::bigint,
  'A valid PICKUP order succeeds'
);

-- T10
select is(
  (
    select fulfillment_type::text || '/' || (pickup_at is not null)::text
    from public.orders
    where id = current_setting('fr20.pickup_order')::uuid
  ),
  'PICKUP/true',
  'PICKUP fulfillment_type and pickup_at are persisted correctly'
);

-- T11
select is(
  (
    select (restaurant_table_id is null)::text || '/' ||
      (table_number_snapshot is null)::text
    from public.orders
    where id = current_setting('fr20.pickup_order')::uuid
  ),
  'true/true',
  'PICKUP stores no table reference and no table snapshot'
);

-- ------------------------------------------------------------
-- Cart line Y exists for the valid DINE_IN below (owner).
-- ------------------------------------------------------------

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b2020202-2222-2222-2222-222222222222',
  'a2020202-1111-1111-1111-111111111111',
  'd2020202-1111-1111-1111-111111111111',
  1
);

-- ============================================================
-- C. Valid DINE_IN (same key 'fr20-retry' as the rejected T4)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '20202020-1111-1111-1111-111111111111';

select set_config(
  'fr20.dinein_order',
  (
    select public.create_order(
      'DINE_IN', 'FR-20 Customer A', null, null, null,
      'e2020201-1111-1111-1111-111111111111', 'fr20-retry', 'CASH'
    )::text
  ),
  true
);

-- T12
select is(
  (
    select count(*)
    from public.orders
    where id = current_setting('fr20.dinein_order')::uuid
  ),
  1::bigint,
  'A valid DINE_IN order with the active table succeeds'
);

-- T13
select is(
  (
    select o.restaurant_table_id::text || '/' || o.table_number_snapshot
    from public.orders o
    where o.id = current_setting('fr20.dinein_order')::uuid
  ),
  (
    select rt.id::text || '/' || rt.table_number
    from public.restaurant_tables rt
    where rt.id = 'e2020201-1111-1111-1111-111111111111'
  ),
  'Persisted table id and snapshot match the server restaurant_tables row'
);

-- T14
select is(
  (
    select pickup_at is null
    from public.orders
    where id = current_setting('fr20.dinein_order')::uuid
  ),
  true,
  'DINE_IN stores no pickup time'
);

-- ============================================================
-- E. Atomic failure / no partial side effects
-- ============================================================

-- T15
select is(
  (
    select count(*)
    from public.orders
    where user_id = '20202020-1111-1111-1111-111111111111'
  ),
  2::bigint,
  'Rejected attempts created no order (only the two successes exist)'
);

-- T16
select is(
  (select count(*)
     from public.order_items oi
     join public.orders o on o.id = oi.order_id
     where o.user_id = '20202020-1111-1111-1111-111111111111')::text
  || '/' ||
  (select count(*)
     from public.payments p
     join public.orders o on o.id = p.order_id
     where o.user_id = '20202020-1111-1111-1111-111111111111')::text
  || '/' ||
  (select count(*)
     from public.order_status_history h
     join public.orders o on o.id = h.order_id
     where o.user_id = '20202020-1111-1111-1111-111111111111')::text
  || '/' ||
  (select count(*)
     from public.coupon_usages cu
     join public.orders o on o.id = cu.order_id
     where o.user_id = '20202020-1111-1111-1111-111111111111')::text,
  '2/2/2/0',
  'No partial order_items/payments/history/coupon side effects exist'
);

-- ============================================================
-- F. Database integrity backstop (orders_fulfillment_chk)
-- ============================================================

reset role;

-- T17
select throws_ok(
  $$
    insert into public.orders (
      id, order_number, user_id, fulfillment_type, pickup_at,
      restaurant_table_id, table_number_snapshot,
      customer_name_snapshot, subtotal, discount_total, final_total
    )
    values (
      '17171717-2020-2020-2020-202020202020',
      'VG-FR20-BAD-DINEIN',
      '20202020-1111-1111-1111-111111111111',
      'DINE_IN',
      null,
      'e2020201-1111-1111-1111-111111111111',
      null,
      'FR-20 Customer A',
      100000, 0, 100000
    )
  $$,
  '23514',
  null,
  'DINE_IN without a table_number_snapshot violates orders_fulfillment_chk'
);

-- T18
select throws_ok(
  $$
    insert into public.orders (
      id, order_number, user_id, fulfillment_type, pickup_at,
      restaurant_table_id, table_number_snapshot,
      customer_name_snapshot, subtotal, discount_total, final_total
    )
    values (
      '18171717-2020-2020-2020-202020202020',
      'VG-FR20-BAD-PICKUP',
      '20202020-1111-1111-1111-111111111111',
      'PICKUP',
      now() + interval '2 hours',
      'e2020201-1111-1111-1111-111111111111',
      'FR20-ACTIVE',
      'FR-20 Customer A',
      100000, 0, 100000
    )
  $$,
  '23514',
  null,
  'PICKUP with a table reference violates orders_fulfillment_chk'
);

-- T19
select lives_ok(
  $$
    insert into public.orders (
      id, order_number, user_id, fulfillment_type, pickup_at,
      restaurant_table_id, table_number_snapshot,
      customer_name_snapshot, subtotal, discount_total, final_total
    )
    values (
      '19171717-2020-2020-2020-202020202020',
      'VG-FR20-HIST',
      '20202020-1111-1111-1111-111111111111',
      'DINE_IN',
      null,
      'e2020201-1111-1111-1111-111111111111',
      'FR20-ACTIVE',
      'FR-20 Customer A',
      100000, 0, 100000
    )
  $$,
  'A valid historical-shaped DINE_IN row is still accepted'
);

-- ============================================================
-- Idempotency rollback proof
-- ============================================================

-- T20
select is(
  (select count(*)
     from public.orders
     where user_id = '20202020-1111-1111-1111-111111111111'
       and idempotency_key = 'fr20-retry')::text
  || '/' ||
  (select o.fulfillment_type::text
     from public.orders o
     where o.user_id = '20202020-1111-1111-1111-111111111111'
       and o.idempotency_key = 'fr20-retry')
  || '/' ||
  (select o.restaurant_table_id::text
     from public.orders o
     where o.user_id = '20202020-1111-1111-1111-111111111111'
       and o.idempotency_key = 'fr20-retry'),
  '1/DINE_IN/e2020201-1111-1111-1111-111111111111',
  'The rejected key is reusable and yields exactly the corrected DINE_IN order'
);

select * from finish();

rollback;
