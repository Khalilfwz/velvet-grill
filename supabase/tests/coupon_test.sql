begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- ============================================================
-- FR-16: coupon validation and discount calculation are
-- authoritative inside public.create_order.
--
-- Every coupon failure raises the SAME unified error, so the
-- function never reveals whether a code exists, is inactive, is
-- outside its window, or has exhausted a limit. Each scenario
-- below isolates exactly one failing condition, so a rejection
-- with that unified error proves the condition is enforced.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values (
  '11111111-1111-1111-1111-111111111111',
  'fr16-customer@test.local'
);

update public.profiles
set full_name = 'FR-16 Customer'
where id = '11111111-1111-1111-1111-111111111111';

insert into public.categories (id, name, slug, is_active)
values (
  'c1616161-1111-1111-1111-111111111111',
  'FR-16 Category',
  'fr16-category',
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
values (
  'd1616161-1111-1111-1111-111111111111',
  'c1616161-1111-1111-1111-111111111111',
  'FR-16 Product',
  'fr16-product',
  100000,
  10,
  true
);

-- Option delta is 0 so the subtotal math stays exact:
-- 100000 * 2 = 200000.
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
values (
  'e1616161-1111-1111-1111-111111111111',
  'd1616161-1111-1111-1111-111111111111',
  'FR-16 Group',
  'SINGLE',
  0,
  1,
  false,
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
values (
  'f1616161-1111-1111-1111-111111111111',
  'e1616161-1111-1111-1111-111111111111',
  'FR-16 Option',
  0,
  true,
  0
);

insert into public.carts (id, user_id)
values (
  'a1616161-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111'
);

-- Initial cart contents (re-seeded before every scenario that needs a cart).
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1616161-1111-1111-1111-111111111111',
  'a1616161-1111-1111-1111-111111111111',
  'd1616161-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1616161-1111-1111-1111-111111111111',
  'f1616161-1111-1111-1111-111111111111'
);

-- Coupons.
insert into public.coupons (
  id,
  code,
  discount_type,
  discount_value,
  max_discount_amount,
  min_order_subtotal,
  starts_at,
  ends_at,
  usage_limit,
  per_customer_limit,
  is_active
)
values
  (
    'aa161616-1111-1111-1111-111111111111',
    'FR16-PCT10',
    'PERCENTAGE',
    10,
    null,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    null,
    true
  ),
  (
    'aa161616-2222-2222-2222-222222222222',
    'FR16-CAP',
    'PERCENTAGE',
    50,
    30000,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    null,
    true
  ),
  (
    'aa161616-3333-3333-3333-333333333333',
    'FR16-FIXED',
    'FIXED_AMOUNT',
    25000,
    null,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    null,
    true
  ),
  (
    'aa161616-4444-4444-4444-444444444444',
    'FR16-CLAMP',
    'FIXED_AMOUNT',
    999000,
    null,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    null,
    true
  ),
  (
    'aa161616-5555-5555-5555-555555555555',
    'FR16-INACTIVE',
    'PERCENTAGE',
    10,
    null,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    null,
    false
  ),
  (
    'aa161616-6666-6666-6666-666666666666',
    'FR16-FUTURE',
    'PERCENTAGE',
    10,
    null,
    0,
    now() + interval '1 day',
    now() + interval '2 days',
    null,
    null,
    true
  ),
  (
    'aa161616-7777-7777-7777-777777777777',
    'FR16-EXPIRED',
    'PERCENTAGE',
    10,
    null,
    0,
    now() - interval '2 days',
    now() - interval '1 day',
    null,
    null,
    true
  ),
  (
    'aa161616-8888-8888-8888-888888888888',
    'FR16-MIN',
    'PERCENTAGE',
    10,
    null,
    500000,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    null,
    true
  ),
  (
    'aa161616-9999-9999-9999-999999999999',
    'FR16-USAGELIMIT',
    'PERCENTAGE',
    10,
    null,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    1,
    null,
    true
  ),
  (
    'aa161616-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'FR16-PERCUST',
    'PERCENTAGE',
    10,
    null,
    0,
    now() - interval '1 day',
    now() + interval '30 days',
    null,
    1,
    true
  );

-- A prior order owned by A, used only to anchor the pre-existing coupon
-- usages that exhaust the two limit coupons.
insert into public.orders (
  id,
  order_number,
  user_id,
  fulfillment_type,
  pickup_at,
  customer_name_snapshot,
  subtotal,
  discount_total,
  final_total
)
values (
  'dd161616-1111-1111-1111-111111111111',
  'VG-FR16-HIST-0001',
  '11111111-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'FR-16 Customer',
  100000,
  0,
  100000
);

insert into public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
values
  (
    'aa161616-9999-9999-9999-999999999999',
    'dd161616-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111111',
    0
  ),
  (
    'aa161616-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'dd161616-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111111',
    0
  );

-- ============================================================
-- SCENARIO 1: percentage coupon (10% of 200000)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

select set_config(
  'fr16.pct_order',
  (
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-pct', 'DUMMY_QRIS', 'FR16-PCT10'
    )::text
  ),
  true
);

-- TEST 1
select is(
  (
    select (discount_total, final_total)::text
    from public.orders
    where id = current_setting('fr16.pct_order')::uuid
  ),
  '(20000.00,180000.00)'::text,
  'Percentage coupon applies the discount and reduces the final total'
);

-- ============================================================
-- SCENARIO 2: percentage coupon capped by max_discount_amount
-- 50% of 200000 = 100000, capped to 30000
-- ============================================================

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1616161-2222-2222-2222-222222222222',
  'a1616161-1111-1111-1111-111111111111',
  'd1616161-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1616161-2222-2222-2222-222222222222',
  'f1616161-1111-1111-1111-111111111111'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

select set_config(
  'fr16.cap_order',
  (
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-cap', 'DUMMY_QRIS', 'FR16-CAP'
    )::text
  ),
  true
);

-- TEST 2
select is(
  (
    select discount_total
    from public.orders
    where id = current_setting('fr16.cap_order')::uuid
  ),
  30000::numeric,
  'max_discount_amount caps the percentage discount'
);

-- ============================================================
-- SCENARIO 3: fixed-amount coupon
-- ============================================================

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1616161-3333-3333-3333-333333333333',
  'a1616161-1111-1111-1111-111111111111',
  'd1616161-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1616161-3333-3333-3333-333333333333',
  'f1616161-1111-1111-1111-111111111111'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

select set_config(
  'fr16.fixed_order',
  (
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-fixed', 'DUMMY_QRIS', 'FR16-FIXED'
    )::text
  ),
  true
);

-- TEST 3
select is(
  (
    select discount_total
    from public.orders
    where id = current_setting('fr16.fixed_order')::uuid
  ),
  25000::numeric,
  'Fixed-amount coupon applies its configured value'
);

-- ============================================================
-- SCENARIO 4: fixed amount greater than the subtotal is clamped
-- ============================================================

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1616161-4444-4444-4444-444444444444',
  'a1616161-1111-1111-1111-111111111111',
  'd1616161-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1616161-4444-4444-4444-444444444444',
  'f1616161-1111-1111-1111-111111111111'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

select set_config(
  'fr16.clamp_order',
  (
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-clamp', 'DUMMY_QRIS', 'FR16-CLAMP'
    )::text
  ),
  true
);

-- TEST 4
select is(
  (
    select final_total
    from public.orders
    where id = current_setting('fr16.clamp_order')::uuid
  ),
  0::numeric,
  'Discount never exceeds the subtotal (final total stays non-negative)'
);

-- ============================================================
-- REJECTIONS: each isolates one failing condition and must raise
-- the SAME unified error.
--
-- Re-seed the cart once: rejections raise, so nothing is consumed.
-- ============================================================

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1616161-5555-5555-5555-555555555555',
  'a1616161-1111-1111-1111-111111111111',
  'd1616161-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1616161-5555-5555-5555-555555555555',
  'f1616161-1111-1111-1111-111111111111'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 5
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-unknown', 'DUMMY_QRIS', 'FR16-NOPE'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Unknown coupon code is rejected'
);

-- TEST 6
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-inactive', 'DUMMY_QRIS', 'FR16-INACTIVE'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Inactive coupon is rejected'
);

-- TEST 7
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-future', 'DUMMY_QRIS', 'FR16-FUTURE'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Coupon that has not started is rejected'
);

-- TEST 8
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-expired', 'DUMMY_QRIS', 'FR16-EXPIRED'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Expired coupon is rejected'
);

-- TEST 9
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-min', 'DUMMY_QRIS', 'FR16-MIN'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Coupon below its minimum order subtotal is rejected'
);

-- TEST 10
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-usage', 'DUMMY_QRIS', 'FR16-USAGELIMIT'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Coupon whose global usage limit is exhausted is rejected'
);

-- TEST 11
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-16 Customer', null, null,
      '2026-01-05T12:00', null, 'fr16-reject-percustomer', 'DUMMY_QRIS', 'FR16-PERCUST'
    )
  $$,
  '22023',
  'Coupon is invalid or unavailable',
  'Coupon whose per-customer limit is reached is rejected'
);

-- TEST 12
select is(
  (
    select count(*)
    from public.orders
    where user_id = '11111111-1111-1111-1111-111111111111'
      and idempotency_key in (
        'fr16-reject-unknown',
        'fr16-reject-inactive',
        'fr16-reject-future',
        'fr16-reject-expired',
        'fr16-reject-min',
        'fr16-reject-usage',
        'fr16-reject-percustomer'
      )
  ),
  0::bigint,
  'No order was created by any rejected coupon attempt'
);

-- ============================================================
-- RECORDING AND HISTORICAL IMMUTABILITY
-- ============================================================

-- TEST 13
select is(
  (
    select (coupon_id, coupon_code_snapshot)::text
    from public.orders
    where id = current_setting('fr16.pct_order')::uuid
  ),
  '(aa161616-1111-1111-1111-111111111111,FR16-PCT10)'::text,
  'Order stores the coupon reference and code snapshot'
);

-- TEST 14
select is(
  (
    select (cu.discount_amount, cu.user_id)::text
    from public.coupon_usages cu
    where cu.order_id = current_setting('fr16.pct_order')::uuid
  ),
  '(20000.00,11111111-1111-1111-1111-111111111111)'::text,
  'Coupon usage records the authoritative discount and the caller'
);

-- The live coupon is changed after the order was placed.
reset role;

update public.coupons
set code = 'FR16-PCT10-RENAMED', discount_value = 99
where id = 'aa161616-1111-1111-1111-111111111111';

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 15
select is(
  (
    select coupon_code_snapshot
    from public.orders
    where id = current_setting('fr16.pct_order')::uuid
  ),
  'FR16-PCT10',
  'Coupon code snapshot is unchanged after the live coupon is renamed'
);

-- TEST 16
select is(
  (
    select discount_total
    from public.orders
    where id = current_setting('fr16.pct_order')::uuid
  ),
  20000::numeric,
  'Applied discount is unchanged after the live coupon value changes'
);

select * from finish();

rollback;
