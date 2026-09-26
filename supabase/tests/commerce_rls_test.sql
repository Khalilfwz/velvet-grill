begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- ============================================================
-- TEST FIXTURES
-- ============================================================

-- Test users
insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'customer-a@test.local'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'admin@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'customer-b@test.local'
  );

-- Profiles
insert into public.profiles (
  id,
  full_name,
  role
)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'Customer A',
    'CUSTOMER'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'Admin',
    'ADMIN'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'Customer B',
    'CUSTOMER'
  );

-- Category
insert into public.categories (
  id,
  name,
  slug,
  is_active
)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Steak',
  'steak',
  true
);

-- Product
insert into public.products (
  id,
  category_id,
  name,
  slug,
  base_price,
  stock,
  is_available
)
values (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Wagyu Ribeye Steak',
  'wagyu-ribeye',
  250000,
  10,
  true
);

-- Restaurant table
insert into public.restaurant_tables (
  id,
  table_number,
  capacity,
  is_active
)
values (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'test-T01',
  4,
  true
);

-- Coupon
insert into public.coupons (
  id,
  code,
  description,
  discount_type,
  discount_value,
  starts_at,
  ends_at,
  is_active
)
values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'TEST20',
  'Test coupon',
  'PERCENTAGE',
  20,
  now() - interval '1 day',
  now() + interval '30 days',
  true
);

-- ============================================================
-- CART FIXTURES
-- ============================================================

insert into public.carts (
  id,
  user_id
)
values
  (
    '10101010-1010-1010-1010-101010101010',
    '11111111-1111-1111-1111-111111111111'
  ),
  (
    '20202020-2020-2020-2020-202020202020',
    '33333333-3333-3333-3333-333333333333'
  );

insert into public.cart_items (
  id,
  cart_id,
  product_id,
  quantity
)
values
  (
    '30303030-3030-3030-3030-303030303030',
    '10101010-1010-1010-1010-101010101010',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    2
  ),
  (
    '40404040-4040-4040-4040-404040404040',
    '20202020-2020-2020-2020-202020202020',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    1
  );

-- ============================================================
-- WISHLIST FIXTURES
-- ============================================================

insert into public.wishlists (
  id,
  user_id
)
values
  (
    '50505050-5050-5050-5050-505050505050',
    '11111111-1111-1111-1111-111111111111'
  ),
  (
    '60606060-6060-6060-6060-606060606060',
    '33333333-3333-3333-3333-333333333333'
  );

insert into public.wishlist_items (
  id,
  wishlist_id,
  product_id
)
values
  (
    '70707070-7070-7070-7070-707070707070',
    '50505050-5050-5050-5050-505050505050',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  ),
  (
    '80808080-8080-8080-8080-808080808080',
    '60606060-6060-6060-6060-606060606060',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  );

-- ============================================================
-- ORDER FIXTURES
-- ============================================================

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
  order_status
)
values
  (
    '90909090-9090-9090-9090-909090909090',
    'VG-TEST-001',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    now() + interval '2 hours',
    'Customer A',
    '080000000001',
    250000,
    0,
    250000,
    'PENDING',
    'CONFIRMED'
  ),
  (
    '91919191-9191-9191-9191-919191919191',
    'VG-TEST-002',
    '33333333-3333-3333-3333-333333333333',
    'PICKUP',
    now() + interval '3 hours',
    'Customer B',
    '080000000002',
    250000,
    0,
    250000,
    'UNPAID',
    'CONFIRMED'
  );

insert into public.order_items (
  id,
  order_id,
  product_id,
  product_name_snapshot,
  base_price_snapshot,
  final_unit_price,
  quantity,
  subtotal
)
values
  (
    '92929292-9292-9292-9292-929292929292',
    '90909090-9090-9090-9090-909090909090',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Wagyu Ribeye Steak',
    250000,
    250000,
    1,
    250000
  ),
  (
    '93939393-9393-9393-9393-939393939393',
    '91919191-9191-9191-9191-919191919191',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Wagyu Ribeye Steak',
    250000,
    250000,
    1,
    250000
  );

insert into public.payments (
  id,
  order_id,
  method,
  status,
  amount
)
values
  (
    '94949494-9494-9494-9494-949494949494',
    '90909090-9090-9090-9090-909090909090',
    'DUMMY_QRIS',
    'PENDING',
    250000
  ),
  (
    '95959595-9595-9595-9595-959595959595',
    '91919191-9191-9191-9191-919191919191',
    'CASH',
    'UNPAID',
    250000
  );

insert into public.order_status_history (
  id,
  order_id,
  from_status,
  to_status,
  changed_by,
  note
)
values
  (
    '96969696-9696-9696-9696-969696969696',
    '90909090-9090-9090-9090-909090909090',
    'PENDING_PAYMENT',
    'CONFIRMED',
    '22222222-2222-2222-2222-222222222222',
    'Test admin confirmation'
  ),
  (
    '97979797-9797-9797-9797-979797979797',
    '91919191-9191-9191-9191-919191919191',
    'PENDING_PAYMENT',
    'CONFIRMED',
    '22222222-2222-2222-2222-222222222222',
    'Test admin confirmation'
  );

insert into public.coupon_usages (
  id,
  coupon_id,
  order_id,
  user_id,
  discount_amount
)
values
  (
    '98989898-9898-9898-9898-989898989898',
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    '90909090-9090-9090-9090-909090909090',
    '11111111-1111-1111-1111-111111111111',
    50000
  ),
  (
    '99999999-9999-9999-9999-999999999999',
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    '91919191-9191-9191-9191-919191919191',
    '33333333-3333-3333-3333-333333333333',
    50000
  );

-- ============================================================
-- TEST 1
-- All commerce tables have RLS enabled
-- ============================================================

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in (
        'carts',
        'cart_items',
        'cart_item_options',
        'wishlists',
        'wishlist_items',
        'orders',
        'order_items',
        'order_item_options',
        'payments',
        'order_status_history',
        'coupons',
        'coupon_usages'
      )
      and c.relrowsecurity = true
  ),
  12::bigint,
  'All 12 commerce tables have RLS enabled'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- 2
select is(
  (
    select count(*)
    from public.carts
  ),
  1::bigint,
  'Customer A sees only their own cart'
);

-- 3
select is(
  (
    select count(*)
    from public.carts
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer A cannot see Customer B cart'
);

-- 4
select is(
  (
    select count(*)
    from public.cart_items
  ),
  1::bigint,
  'Customer A sees only their own cart items'
);

-- 5
select is(
  (
    select count(*)
    from public.wishlists
  ),
  1::bigint,
  'Customer A sees only their own wishlist'
);

-- 6
select is(
  (
    select count(*)
    from public.wishlists
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer A cannot see Customer B wishlist'
);

-- 7
select is(
  (
    select count(*)
    from public.orders
  ),
  1::bigint,
  'Customer A sees only their own orders'
);

-- 8
select is(
  (
    select count(*)
    from public.orders
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer A cannot see Customer B orders'
);

-- 9
select is(
  (
    select count(*)
    from public.payments
  ),
  1::bigint,
  'Customer A sees only their own payments'
);

-- 10
select is(
  (
    select count(*)
    from public.coupon_usages
  ),
  1::bigint,
  'Customer A sees only their own coupon usage'
);

-- 11
select is(
  (
    select count(*)
    from public.coupon_usages
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer A cannot see Customer B coupon usage'
);

-- 12
select throws_ok(
  $$
    insert into public.orders (
      order_number,
      user_id,
      fulfillment_type,
      pickup_at,
      customer_name_snapshot,
      subtotal,
      final_total
    )
    values (
      'VG-ATTACK-001',
      '11111111-1111-1111-1111-111111111111',
      'PICKUP',
      now() + interval '2 hours',
      'Customer A',
      1,
      1
    )
  $$,
  '42501',
  null,
  'Customer cannot create orders directly'
);

-- 13
select throws_ok(
  $$
    insert into public.payments (
      order_id,
      method,
      status,
      amount
    )
    values (
      '90909090-9090-9090-9090-909090909090',
      'DUMMY_QRIS',
      'PENDING',
      1
    )
  $$,
  '42501',
  null,
  'Customer cannot create payments directly'
);

-- 14
update public.payments
set status = 'PAID'
where id = '94949494-9494-9494-9494-949494949494';

select is(
  (
    select status
    from public.payments
    where id = '94949494-9494-9494-9494-949494949494'
  ),
  'PENDING'::public.payment_status,
  'Customer cannot change payment status'
);

-- 15
select is(
  (
    select count(*)
    from public.coupons
  ),
  0::bigint,
  'Customer cannot read coupon administration data'
);

-- ============================================================
-- CUSTOMER A cannot create cart for Customer B
-- ============================================================

-- 16
select throws_ok(
  $$
    insert into public.carts (
      id,
      user_id
    )
    values (
      '12121212-1212-1212-1212-121212121212',
      '33333333-3333-3333-3333-333333333333'
    )
  $$,
  '42501',
  null,
  'Customer cannot create a cart for another user'
);

-- 17
update public.orders
set order_status = 'PREPARING'
where id = '90909090-9090-9090-9090-909090909090';

select is(
  (
    select order_status
    from public.orders
    where id = '90909090-9090-9090-9090-909090909090'
  ),
  'CONFIRMED'::public.order_status,
  'Customer cannot change order status'
);

-- 18
select throws_ok(
  $$
    insert into public.order_status_history (
      id,
      order_id,
      from_status,
      to_status,
      changed_by,
      note
    )
    values (
      '98989898-9898-9898-9898-989898989898',
      '90909090-9090-9090-9090-909090909090',
      'CONFIRMED',
      'PREPARING',
      '11111111-1111-1111-1111-111111111111',
      'Fake customer status transition'
    )
  $$,
  '42501',
  null,
  'Customer cannot create order status history'
);

-- ============================================================
-- ADMIN
-- ============================================================

set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- 19
select ok(
  (
    select private.is_admin()
  ),
  'Admin helper identifies the ADMIN user'
);

-- 20
select is(
  (
    select count(*)
    from public.orders
  ),
  2::bigint,
  'Admin can read all orders'
);

-- 21
select is(
  (
    select count(*)
    from public.payments
  ),
  2::bigint,
  'Admin can read all payments'
);

-- 22
select is(
  (
    select count(*)
    from public.coupons
  ),
  1::bigint,
  'Admin can read coupon data'
);

-- 23
select lives_ok(
  $$
    update public.orders
    set customer_note = 'Updated by admin test'
    where id = '91919191-9191-9191-9191-919191919191'
  $$,
  'Admin can update an order'
);

select * from finish();

rollback;
