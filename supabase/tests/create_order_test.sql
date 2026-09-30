begin;

create extension if not exists pgtap with schema extensions;

select plan(44);

-- ============================================================
-- FR-13: pickup and dine-in order placement via create_order.
--
-- Covers input safety, identity derivation, fulfilment fields,
-- snapshots, DB-derived totals, cart consumption, per-customer
-- idempotency, and authoritative order-time cart revalidation.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'fr13-customer-a@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'fr13-customer-b@test.local'
  );

insert into public.categories (id, name, slug, is_active)
values (
  'c1313131-1111-1111-1111-111111111111',
  'FR-13 Category',
  'fr13-category',
  true
);

insert into public.products (
  id,
  category_id,
  name,
  slug,
  base_price,
  stock,
  is_available
)
values
  (
    'd1313131-1111-1111-1111-111111111111',
    'c1313131-1111-1111-1111-111111111111',
    'FR-13 Product One',
    'fr13-product-one',
    100000,
    10,
    true
  ),
  (
    'd1313132-2222-2222-2222-222222222222',
    'c1313131-1111-1111-1111-111111111111',
    'FR-13 Product Two',
    'fr13-product-two',
    120000,
    10,
    true
  );

insert into public.product_option_groups (
  id,
  product_id,
  name,
  selection_type,
  min_selections,
  max_selections,
  is_required,
  sort_order,
  is_active
)
values
  (
    'e1313131-1111-1111-1111-111111111111',
    'd1313131-1111-1111-1111-111111111111',
    'FR-13 Choice',
    'SINGLE',
    0,
    1,
    false,
    0,
    true
  ),
  (
    'e1313132-2222-2222-2222-222222222222',
    'd1313132-2222-2222-2222-222222222222',
    'FR-13 Required',
    'SINGLE',
    1,
    1,
    true,
    0,
    true
  );

insert into public.product_options (
  id,
  group_id,
  name,
  price_delta,
  is_available,
  sort_order
)
values
  (
    'f1313131-1111-1111-1111-111111111111',
    'e1313131-1111-1111-1111-111111111111',
    'FR-13 Option A',
    5000,
    true,
    0
  ),
  (
    'f1313132-2222-2222-2222-222222222222',
    'e1313131-1111-1111-1111-111111111111',
    'FR-13 Option B',
    7000,
    true,
    1
  ),
  (
    'f1313133-3333-3333-3333-333333333333',
    'e1313132-2222-2222-2222-222222222222',
    'FR-13 Option C',
    0,
    true,
    0
  );

insert into public.restaurant_tables (id, table_number, capacity, is_active)
values
  ('71313131-1111-1111-1111-111111111111', 'T13A', 4, true),
  ('71313132-2222-2222-2222-222222222222', 'T13B', 4, false);

insert into public.carts (id, user_id)
values (
  'a1313131-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1313131-1111-1111-1111-111111111111',
  'a1313131-1111-1111-1111-111111111111',
  'd1313131-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1313131-1111-1111-1111-111111111111',
  'f1313131-1111-1111-1111-111111111111'
);

-- ============================================================
-- PRIVILEGES
-- ============================================================

-- TEST 1
select is(
  has_function_privilege(
    'anon',
    'public.create_order(public.order_fulfillment_type,text,text,text,timestamptz,uuid,text)',
    'EXECUTE'
  ),
  false,
  'anon cannot execute public.create_order'
);

-- TEST 2
select is(
  has_function_privilege(
    'authenticated',
    'public.create_order(public.order_fulfillment_type,text,text,text,timestamptz,uuid,text)',
    'EXECUTE'
  ),
  true,
  'authenticated can execute public.create_order'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 3
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours', null, ''
    )
  $$,
  '22023',
  null,
  'Order creation rejects a blank idempotency key'
);

-- TEST 4
select throws_ok(
  $$
    select public.create_order(
      'DINE_IN', 'Ada Lovelace', null, null,
      null, null, 'fr13-key-dinein-no-table'
    )
  $$,
  '22023',
  null,
  'Order creation rejects dine-in without a table'
);

-- TEST 5
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours',
      '71313131-1111-1111-1111-111111111111',
      'fr13-key-pickup-with-table'
    )
  $$,
  '22023',
  null,
  'Order creation rejects pickup with a table'
);

-- TEST 6
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', repeat('x', 130), null, null,
      now() + interval '2 hours', null, 'fr13-key-long-name'
    )
  $$,
  '22023',
  null,
  'Order creation rejects an over-length customer name'
);

-- TEST 7
select is(
  (
    select count(*)
    from public.orders
  ),
  0::bigint,
  'No order was created by the rejected input attempts'
);

-- TEST 8
select is(
  (
    select count(*)
    from public.cart_items
  ),
  1::bigint,
  'Cart items are unchanged after the rejected input attempts'
);

-- TEST 9
select is(
  (
    select count(*)
    from public.cart_item_options
  ),
  1::bigint,
  'Cart item options are unchanged after the rejected input attempts'
);

-- ============================================================
-- CUSTOMER B (no cart)
-- ============================================================

set local request.jwt.claim.sub =
  '33333333-3333-3333-3333-333333333333';

-- TEST 10
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Grace Hopper', null, null,
      now() + interval '2 hours', null, 'fr13-key-no-cart'
    )
  $$,
  '22023',
  null,
  'Order creation rejects a caller with no cart'
);

-- TEST 11
select is(
  (
    select count(*)
    from public.orders
  ),
  0::bigint,
  'No order was created for the caller with no cart'
);

-- ============================================================
-- PICKUP ORDER
-- ============================================================

set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 12
select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', '+620000000000', null,
      now() + interval '2 hours', null, 'fr13-pickup-key'
    )
  $$,
  'Pickup order creation succeeds'
);

select set_config(
  'fr13.pickup_order',
  (
    select id::text
    from public.orders
    where user_id = '11111111-1111-1111-1111-111111111111'
      and idempotency_key = 'fr13-pickup-key'
  ),
  true
);

-- TEST 13
select is(
  (
    select fulfillment_type
    from public.orders
    where id = current_setting('fr13.pickup_order')::uuid
  ),
  'PICKUP'::public.order_fulfillment_type,
  'Pickup order records the PICKUP fulfillment type'
);

-- TEST 14
select is(
  (
    select pickup_at is not null
    from public.orders
    where id = current_setting('fr13.pickup_order')::uuid
  ),
  true,
  'Pickup order records the requested pickup time'
);

-- TEST 15
select is(
  (
    select restaurant_table_id is null and table_number_snapshot is null
    from public.orders
    where id = current_setting('fr13.pickup_order')::uuid
  ),
  true,
  'Pickup order stores no table reference'
);

-- TEST 16
select is(
  (
    select user_id
    from public.orders
    where id = current_setting('fr13.pickup_order')::uuid
  ),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'Order ownership is derived from the authenticated caller'
);

-- TEST 17
select is(
  (
    select count(*)
    from public.order_items
    where order_id = current_setting('fr13.pickup_order')::uuid
  ),
  1::bigint,
  'Pickup order has exactly one order item'
);

-- TEST 18
select is(
  (
    select product_name_snapshot
    from public.order_items
    where order_id = current_setting('fr13.pickup_order')::uuid
  ),
  'FR-13 Product One',
  'Order item snapshots the product name'
);

-- TEST 19
select is(
  (
    select base_price_snapshot
    from public.order_items
    where order_id = current_setting('fr13.pickup_order')::uuid
  ),
  100000::numeric,
  'Order item snapshots the base price from the database'
);

-- TEST 20
select is(
  (
    select quantity
    from public.order_items
    where order_id = current_setting('fr13.pickup_order')::uuid
  ),
  2,
  'Order item snapshots the cart quantity'
);

-- TEST 21
select is(
  (
    select count(*)
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr13.pickup_order')::uuid
  ),
  1::bigint,
  'Pickup order item has exactly one option snapshot'
);

-- TEST 22
select is(
  (
    select oio.option_name_snapshot
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr13.pickup_order')::uuid
  ),
  'FR-13 Option A',
  'Option snapshot records the option name'
);

-- TEST 23
select is(
  (
    select oio.price_delta_snapshot
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr13.pickup_order')::uuid
  ),
  5000::numeric,
  'Option snapshot records the price delta'
);

-- TEST 24
select is(
  (
    select subtotal
    from public.orders
    where id = current_setting('fr13.pickup_order')::uuid
  ),
  210000::numeric,
  'Subtotal is derived from current database prices'
);

-- TEST 25
select is(
  (
    select final_total
    from public.orders
    where id = current_setting('fr13.pickup_order')::uuid
  ),
  210000::numeric,
  'Final total is derived from current database prices'
);

-- TEST 26
select is(
  (
    select count(*)
    from public.cart_items
  ),
  0::bigint,
  'Cart items are cleared after a successful order'
);

-- ============================================================
-- IDEMPOTENT REPLAY
-- ============================================================

select set_config(
  'fr13.replay_order',
  (
    select public.create_order(
      'PICKUP', 'Ada Lovelace', '+620000000000', null,
      now() + interval '2 hours', null, 'fr13-pickup-key'
    )::text
  ),
  true
);

-- TEST 27
select is(
  current_setting('fr13.replay_order'),
  current_setting('fr13.pickup_order'),
  'Retrying with the same idempotency key returns the same order'
);

-- TEST 28
select is(
  (
    select count(*)
    from public.orders
    where user_id = '11111111-1111-1111-1111-111111111111'
      and idempotency_key = 'fr13-pickup-key'
  ),
  1::bigint,
  'Exactly one order exists for the idempotency key'
);

-- TEST 29
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours', null, 'fr13-other-key'
    )
  $$,
  '22023',
  null,
  'A different key after the cart was consumed is rejected'
);

-- TEST 30
select is(
  (
    select count(*)
    from public.orders
  ),
  1::bigint,
  'Still exactly one order exists for the customer'
);

-- ============================================================
-- DINE-IN ORDER
-- ============================================================

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1313133-3333-3333-3333-333333333333',
  'a1313131-1111-1111-1111-111111111111',
  'd1313131-1111-1111-1111-111111111111',
  1
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1313133-3333-3333-3333-333333333333',
  'f1313131-1111-1111-1111-111111111111'
);

-- TEST 31
select throws_ok(
  $$
    select public.create_order(
      'DINE_IN', 'Ada Lovelace', null, null,
      null, '71313132-2222-2222-2222-222222222222', 'fr13-dinein-inactive'
    )
  $$,
  '22023',
  null,
  'Dine-in order is rejected for an inactive table'
);

-- TEST 32
select is(
  (
    select count(*)
    from public.orders
  ),
  1::bigint,
  'No order was created for the rejected dine-in attempt'
);

-- TEST 33
select lives_ok(
  $$
    select public.create_order(
      'DINE_IN', 'Ada Lovelace', null, null,
      null, '71313131-1111-1111-1111-111111111111', 'fr13-dinein-key'
    )
  $$,
  'Dine-in order creation succeeds for an active table'
);

select set_config(
  'fr13.dinein_order',
  (
    select id::text
    from public.orders
    where user_id = '11111111-1111-1111-1111-111111111111'
      and idempotency_key = 'fr13-dinein-key'
  ),
  true
);

-- TEST 34
select is(
  (
    select fulfillment_type
    from public.orders
    where id = current_setting('fr13.dinein_order')::uuid
  ),
  'DINE_IN'::public.order_fulfillment_type,
  'Dine-in order records the DINE_IN fulfillment type'
);

-- TEST 35
select is(
  (
    select pickup_at is null
    from public.orders
    where id = current_setting('fr13.dinein_order')::uuid
  ),
  true,
  'Dine-in order stores no pickup time'
);

-- TEST 36
select is(
  (
    select restaurant_table_id
    from public.orders
    where id = current_setting('fr13.dinein_order')::uuid
  ),
  '71313131-1111-1111-1111-111111111111'::uuid,
  'Dine-in order stores the validated table reference'
);

-- TEST 37
select is(
  (
    select table_number_snapshot
    from public.orders
    where id = current_setting('fr13.dinein_order')::uuid
  ),
  'T13A',
  'Dine-in order snapshots the table number'
);

-- ============================================================
-- AUTHORITATIVE CART REVALIDATION
--
-- Forged/current-invalid cart states are created as the owner
-- (clients cannot produce some of them) and must be rejected.
-- ============================================================

reset role;

update public.products
set is_available = false
where id = 'd1313131-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1313141-1111-1111-1111-111111111111',
  'a1313131-1111-1111-1111-111111111111',
  'd1313131-1111-1111-1111-111111111111',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 38
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours', null, 'fr13-inv-product'
    )
  $$,
  '22023',
  null,
  'Order creation rejects a cart line whose product is unavailable'
);

reset role;

update public.products
set is_available = true
where id = 'd1313131-1111-1111-1111-111111111111';

delete from public.cart_items
where cart_id = 'a1313131-1111-1111-1111-111111111111';

update public.product_options
set is_available = false
where id = 'f1313132-2222-2222-2222-222222222222';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1313142-1111-1111-1111-111111111111',
  'a1313131-1111-1111-1111-111111111111',
  'd1313131-1111-1111-1111-111111111111',
  1
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1313142-1111-1111-1111-111111111111',
  'f1313132-2222-2222-2222-222222222222'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 39
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours', null, 'fr13-inv-option'
    )
  $$,
  '22023',
  null,
  'Order creation rejects a cart line whose selected option is unavailable'
);

reset role;

update public.product_options
set is_available = true
where id = 'f1313132-2222-2222-2222-222222222222';

delete from public.cart_items
where cart_id = 'a1313131-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1313143-1111-1111-1111-111111111111',
  'a1313131-1111-1111-1111-111111111111',
  'd1313132-2222-2222-2222-222222222222',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 40
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours', null, 'fr13-required-group'
    )
  $$,
  '22023',
  null,
  'Order creation rejects a selection that no longer satisfies a required group'
);

reset role;

delete from public.cart_items
where cart_id = 'a1313131-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1313144-1111-1111-1111-111111111111',
  'a1313131-1111-1111-1111-111111111111',
  'd1313131-1111-1111-1111-111111111111',
  1
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values
  (
    'b1313144-1111-1111-1111-111111111111',
    'f1313131-1111-1111-1111-111111111111'
  ),
  (
    'b1313144-1111-1111-1111-111111111111',
    'f1313132-2222-2222-2222-222222222222'
  );

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 41
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      now() + interval '2 hours', null, 'fr13-single-two'
    )
  $$,
  '22023',
  null,
  'Order creation rejects a SINGLE group holding more than one selected option'
);

-- TEST 42
select is(
  (
    select count(*)
    from public.orders
  ),
  2::bigint,
  'No order was created by the rejected revalidation attempts'
);

-- TEST 43
select is(
  (
    select count(*)
    from public.cart_items
  ),
  1::bigint,
  'Cart items remain intact after the rejected revalidation attempts'
);

-- TEST 44
select is(
  (
    select count(*)
    from public.cart_item_options
  ),
  2::bigint,
  'Cart item options remain intact after the rejected revalidation attempts'
);

select * from finish();

rollback;
