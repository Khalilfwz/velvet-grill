begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

-- ============================================================
-- FR-19: retry-sensitive order/payment operations.
--
-- Proves the existing create_order idempotency (per-user key,
-- replay fast paths, no duplicate side effects, failed attempts
-- do not consume the key, conflicting-input first-success-wins),
-- the existing confirm_order_payment replay safety, and the new
-- update_order_status idempotent same-status no-op, while the
-- FR-18 transition/gate/history rules remain intact.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  ('19191919-1111-1111-1111-111111111111', 'fr19-customer-a@test.local'),
  ('29292929-2222-2222-2222-222222222222', 'fr19-customer-b@test.local'),
  ('39393939-3333-3333-3333-333333333333', 'fr19-admin@test.local');

update public.profiles
set full_name = 'FR-19 Customer A'
where id = '19191919-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'FR-19 Customer B'
where id = '29292929-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'FR-19 Admin', role = 'ADMIN'
where id = '39393939-3333-3333-3333-333333333333';

insert into public.categories (id, name, slug, is_active)
values (
  'c1919191-1111-1111-1111-111111111111',
  'FR-19 Category',
  'fr19-category',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  'd1919191-1111-1111-1111-111111111111',
  'c1919191-1111-1111-1111-111111111111',
  'FR-19 Product',
  'fr19-product',
  100000,
  10,
  true
);

insert into public.product_option_groups (
  id, product_id, name, selection_type, min_selections, max_selections,
  is_required, sort_order, is_active
)
values (
  'e1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  'FR-19 Choice',
  'SINGLE',
  0,
  1,
  false,
  0,
  true
);

insert into public.product_options (
  id, group_id, name, price_delta, is_available, sort_order
)
values (
  'f1919191-1111-1111-1111-111111111111',
  'e1919191-1111-1111-1111-111111111111',
  'FR-19 Option A',
  5000,
  true,
  0
);

insert into public.carts (id, user_id)
values
  ('a1919191-1111-1111-1111-111111111111', '19191919-1111-1111-1111-111111111111'),
  ('a1919192-2222-2222-2222-222222222222', '29292929-2222-2222-2222-222222222222');

insert into public.coupons (
  id, code, description, discount_type, discount_value, max_discount_amount,
  min_order_subtotal, starts_at, ends_at, usage_limit, per_customer_limit,
  is_active
)
values (
  'c1919192-2222-2222-2222-222222222222',
  'FR19',
  'FR-19 coupon',
  'FIXED_AMOUNT',
  10000,
  null,
  0,
  now() - interval '1 hour',
  now() + interval '1 hour',
  null,
  null,
  true
);

-- Customer B's independent cart line for its own fr19-a order.
insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919194-4444-4444-4444-444444444444',
  'a1919192-2222-2222-2222-222222222222',
  'd1919191-1111-1111-1111-111111111111',
  1
);

-- ============================================================
-- S0 - FAILED CREATE DOES NOT CONSUME THE IDEMPOTENCY KEY
-- (A's cart exists but is empty)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

-- T1
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-failed', 'CASH'
    )
  $$,
  '22023',
  'Your cart is empty',
  'Failed create_order raises the real domain error'
);

-- T2
select is(
  (
    select count(*)
    from public.orders
    where user_id = '19191919-1111-1111-1111-111111111111'
      and idempotency_key = 'fr19-failed'
  ),
  0::bigint,
  'No order is committed for the failed idempotency key'
);

-- Fix the condition and reuse the SAME key.
reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919191-1111-1111-1111-111111111111',
  'a1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  1
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1919191-1111-1111-1111-111111111111',
  'f1919191-1111-1111-1111-111111111111'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

select set_config(
  'fr19.order_f',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-failed', 'CASH'
    )::text
  ),
  true
);

-- T3
select is(
  (
    select id::text
    from public.orders
    where user_id = '19191919-1111-1111-1111-111111111111'
      and idempotency_key = 'fr19-failed'
  ),
  current_setting('fr19.order_f'),
  'The same failed key succeeds once the condition is fixed'
);

-- T4
select is(
  (
    select count(*)
    from public.orders
    where user_id = '19191919-1111-1111-1111-111111111111'
      and idempotency_key = 'fr19-failed'
  ),
  1::bigint,
  'Exactly one order exists for the reused key'
);

-- ============================================================
-- S1 - CREATE_ORDER REPLAY / CONFLICT / PER-USER SCOPE
-- ============================================================

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919192-2222-2222-2222-222222222222',
  'a1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1919192-2222-2222-2222-222222222222',
  'f1919191-1111-1111-1111-111111111111'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

select set_config(
  'fr19.order_a',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-a', 'CASH', 'FR19'
    )::text
  ),
  true
);

-- T5
select is(
  current_setting('fr19.order_a') <> '',
  true,
  'First create_order succeeds and returns an order id'
);

select set_config(
  'fr19.order_a_replay',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-a', 'CASH', 'FR19'
    )::text
  ),
  true
);

-- T6
select is(
  current_setting('fr19.order_a_replay'),
  current_setting('fr19.order_a'),
  'Exact replay returns the same order id'
);

-- T7
select is(
  (
    select count(*)
    from public.orders
    where user_id = '19191919-1111-1111-1111-111111111111'
      and idempotency_key = 'fr19-a'
  ),
  1::bigint,
  'Exactly one order exists for the key'
);

-- T8
select is(
  (
    select count(*)
    from public.order_items
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  1::bigint,
  'Replay does not duplicate order_items'
);

-- T9
select is(
  (
    select count(*)
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr19.order_a')::uuid
  ),
  1::bigint,
  'Replay does not duplicate order_item_options'
);

-- T10
select is(
  (
    select count(*)
    from public.payments
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  1::bigint,
  'Replay does not duplicate payments'
);

-- T11
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  1::bigint,
  'Replay does not duplicate the initial order_status_history row'
);

-- T12
select is(
  (
    select count(*)
    from public.coupon_usages
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  1::bigint,
  'Replay does not duplicate coupon_usages'
);

-- T13
select is(
  (
    select count(*)
    from public.cart_items
    where cart_id = 'a1919191-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'Cart consumption is not repeated by the replay'
);

-- Conflicting input: a fresh cart line plus different call input, same key.
reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919193-3333-3333-3333-333333333333',
  'a1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

select set_config(
  'fr19.order_a_conflict',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', '+620000000001', 'different note',
      '2026-01-05T12:00', null, 'fr19-a', 'DUMMY_QRIS', null
    )::text
  ),
  true
);

-- T14
select is(
  current_setting('fr19.order_a_conflict'),
  current_setting('fr19.order_a'),
  'Conflicting-input replay returns the original order'
);

-- T15
select is(
  (
    select count(*)
    from public.cart_items
    where cart_id = 'a1919191-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'Conflicting replay does not consume the newly added cart item'
);

-- T16
select is(
  (select count(*)
     from public.order_items
     where order_id = current_setting('fr19.order_a')::uuid)::text
  || '/' ||
  (select count(*)
     from public.order_item_options oio
     join public.order_items oi on oi.id = oio.order_item_id
     where oi.order_id = current_setting('fr19.order_a')::uuid)::text
  || '/' ||
  (select count(*)
     from public.payments
     where order_id = current_setting('fr19.order_a')::uuid)::text
  || '/' ||
  (select count(*)
     from public.order_status_history
     where order_id = current_setting('fr19.order_a')::uuid)::text
  || '/' ||
  (select count(*)
     from public.coupon_usages
     where order_id = current_setting('fr19.order_a')::uuid)::text,
  '1/1/1/1/1',
  'Conflicting replay leaves the original order side effects unchanged'
);

-- A different user may reuse the same key string independently.
set local request.jwt.claim.sub =
  '29292929-2222-2222-2222-222222222222';

select set_config(
  'fr19.order_b',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer B', null, null,
      '2026-01-05T12:00', null, 'fr19-a', 'CASH'
    )::text
  ),
  true
);

-- T17
select isnt(
  current_setting('fr19.order_b'),
  current_setting('fr19.order_a'),
  'Another user reusing the same key receives a different order'
);

-- T18
select is(
  (
    select user_id
    from public.orders
    where id = current_setting('fr19.order_b')::uuid
  ),
  '29292929-2222-2222-2222-222222222222'::uuid,
  'The second order is owned by the second user'
);

-- Restore customer A as the subject so RLS permits reading A's order below.
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

-- T19
select is(
  (
    select count(*)
    from public.orders
    where user_id = '19191919-1111-1111-1111-111111111111'
      and idempotency_key = 'fr19-a'
  ),
  1::bigint,
  'The first user still has exactly one order for the shared key string'
);

-- ============================================================
-- S2 - CONFIRM_ORDER_PAYMENT
-- ============================================================

-- Digital order D.
reset role;

delete from public.cart_items
where cart_id = 'a1919191-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919195-5555-5555-5555-555555555555',
  'a1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

select set_config(
  'fr19.order_d',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-digital', 'DUMMY_QRIS'
    )::text
  ),
  true
);

-- T20
select is(
  (
    select count(*)
    from public.orders
    where id = current_setting('fr19.order_d')::uuid
  ),
  1::bigint,
  'Digital order D is created'
);

select set_config(
  'fr19.d_status',
  (
    select public.confirm_order_payment(
      current_setting('fr19.order_d')::uuid
    )::text
  ),
  true
);

-- T21
select is(
  current_setting('fr19.d_status'),
  'PAID',
  'Owner confirms the digital payment'
);

-- T22
select is(
  (
    select count(*)
    from public.payments
    where order_id = current_setting('fr19.order_d')::uuid
  ),
  1::bigint,
  'Confirmation does not add a second payment row'
);

select set_config(
  'fr19.d_paid_at',
  (
    select paid_at::text
    from public.payments
    where order_id = current_setting('fr19.order_d')::uuid
  ),
  true
);

select set_config(
  'fr19.d_replay',
  (
    select public.confirm_order_payment(
      current_setting('fr19.order_d')::uuid
    )::text
  ),
  true
);

-- T23
select is(
  current_setting('fr19.d_replay'),
  'PAID',
  'Exact replay of a paid digital payment succeeds as a no-op'
);

-- T24
select is(
  (
    select paid_at::text
    from public.payments
    where order_id = current_setting('fr19.order_d')::uuid
  ),
  current_setting('fr19.d_paid_at'),
  'Replay does not rewrite paid_at'
);

-- T25
select is(
  (
    select o.payment_status::text || '/' || p.status::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.id = current_setting('fr19.order_d')::uuid
  ),
  'PAID/PAID',
  'Order and payment remain PAID after the replay'
);

set local request.jwt.claim.sub =
  '29292929-2222-2222-2222-222222222222';

-- T26
select throws_ok(
  $$
    select public.confirm_order_payment(
      current_setting('fr19.order_d')::uuid
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'Another customer cannot confirm the payment'
);

-- Restore customer A as the subject so RLS permits reading A's order below.
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

-- T27
select is(
  (
    select o.payment_status::text || '/' || p.status::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.id = current_setting('fr19.order_d')::uuid
  ),
  'PAID/PAID',
  'Rejected cross-user retry leaves payment state unchanged'
);

-- Cash order C.
reset role;

delete from public.cart_items
where cart_id = 'a1919191-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919196-6666-6666-6666-666666666666',
  'a1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

select set_config(
  'fr19.order_c',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-cash', 'CASH'
    )::text
  ),
  true
);

-- T28
select is(
  (
    select count(*)
    from public.orders
    where id = current_setting('fr19.order_c')::uuid
  ),
  1::bigint,
  'Cash order C is created'
);

set local request.jwt.claim.sub =
  '39393939-3333-3333-3333-333333333333';

select set_config(
  'fr19.c_admin',
  (
    select public.confirm_order_payment(
      current_setting('fr19.order_c')::uuid
    )::text
  ),
  true
);

-- T29
select is(
  current_setting('fr19.c_admin'),
  'PAID',
  'Admin confirms the cash payment'
);

set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

-- T30
select throws_ok(
  $$
    select public.confirm_order_payment(
      current_setting('fr19.order_c')::uuid
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'Customer cannot confirm a cash payment even after admin success'
);

-- T31
select is(
  (
    select o.payment_status::text || '/' || p.status::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.id = current_setting('fr19.order_c')::uuid
  ),
  'PAID/PAID',
  'Cash payment remains PAID after the rejected customer retry'
);

-- ============================================================
-- S3 - UPDATE_ORDER_STATUS
-- (order A is a CASH order at PENDING_PAYMENT)
-- ============================================================

set local request.jwt.claim.sub =
  '39393939-3333-3333-3333-333333333333';

select set_config(
  'fr19.a_confirmed',
  (
    select public.update_order_status(
      current_setting('fr19.order_a')::uuid, 'CONFIRMED'
    )::text
  ),
  true
);

-- T32
select is(
  current_setting('fr19.a_confirmed'),
  'CONFIRMED',
  'Admin performs the first allowed transition'
);

-- T33
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  2::bigint,
  'The allowed transition adds exactly one history row'
);

select set_config(
  'fr19.a_replay',
  (
    select public.update_order_status(
      current_setting('fr19.order_a')::uuid, 'CONFIRMED'
    )::text
  ),
  true
);

-- T34
select is(
  current_setting('fr19.a_replay'),
  'CONFIRMED',
  'Exact retry to the already-current status returns success'
);

-- T35
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  2::bigint,
  'The same-status retry adds no history row'
);

-- T36
select is(
  (
    select order_status
    from public.orders
    where id = current_setting('fr19.order_a')::uuid
  ),
  'CONFIRMED'::public.order_status,
  'Order status remains unchanged by the retry'
);

set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

-- T37
select throws_ok(
  $$
    select public.update_order_status(
      current_setting('fr19.order_a')::uuid, 'CONFIRMED'
    )
  $$,
  '42501',
  'Order status cannot be changed',
  'A customer cannot use the same-status path'
);

set local request.jwt.claim.sub =
  '39393939-3333-3333-3333-333333333333';

-- T38
select throws_ok(
  $$
    select public.update_order_status(
      '99999999-9999-9999-9999-999999999999', 'CONFIRMED'
    )
  $$,
  '42501',
  'Order status cannot be changed',
  'A nonexistent order is rejected safely'
);

-- T39
select throws_ok(
  $$
    select public.update_order_status(
      current_setting('fr19.order_a')::uuid, 'READY'
    )
  $$,
  '22023',
  'Order status transition is not allowed',
  'A different illegal edge is still rejected'
);

-- T40
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr19.order_a')::uuid
  ),
  2::bigint,
  'The failed illegal transition adds no history'
);

-- Unpaid digital gate order D2.
reset role;

delete from public.cart_items
where cart_id = 'a1919191-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1919197-7777-7777-7777-777777777777',
  'a1919191-1111-1111-1111-111111111111',
  'd1919191-1111-1111-1111-111111111111',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  '19191919-1111-1111-1111-111111111111';

select set_config(
  'fr19.order_d2',
  (
    select public.create_order(
      'PICKUP', 'FR-19 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr19-gate', 'DUMMY_QRIS'
    )::text
  ),
  true
);

-- T41
select is(
  (
    select count(*)
    from public.orders
    where id = current_setting('fr19.order_d2')::uuid
  ),
  1::bigint,
  'The unpaid digital gate order is created'
);

set local request.jwt.claim.sub =
  '39393939-3333-3333-3333-333333333333';

select set_config(
  'fr19.d2_confirmed',
  (
    select public.update_order_status(
      current_setting('fr19.order_d2')::uuid, 'CONFIRMED'
    )::text
  ),
  true
);

-- T42
select is(
  current_setting('fr19.d2_confirmed'),
  'CONFIRMED',
  'A digital order may be confirmed while payment is pending'
);

-- T43
select throws_ok(
  $$
    select public.update_order_status(
      current_setting('fr19.order_d2')::uuid, 'PREPARING'
    )
  $$,
  '22023',
  'Order is not eligible to enter preparation',
  'An unpaid digital order cannot enter PREPARING'
);

-- T44
select is(
  (
    select o.order_status::text || '/' ||
      (select count(*)
       from public.order_status_history h
       where h.order_id = o.id)::text
    from public.orders o
    where o.id = current_setting('fr19.order_d2')::uuid
  ),
  'CONFIRMED/2',
  'The gate order is unchanged after the rejected transition'
);

-- ============================================================
-- S4 - LEGACY / NO FABRICATED HISTORY
-- ============================================================

reset role;

insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values (
  '18191919-1111-1111-1111-111111111111',
  'VG-FR19-LEGACY',
  '19191919-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'FR-19 Customer A',
  100000, 0, 100000,
  'UNPAID',
  'CONFIRMED'
);

-- T45
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = '18191919-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'A legacy order starts with zero history rows'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '39393939-3333-3333-3333-333333333333';

select set_config(
  'fr19.legacy_noop',
  (
    select public.update_order_status(
      '18191919-1111-1111-1111-111111111111', 'CONFIRMED'
    )::text
  ),
  true
);

-- T46
select is(
  current_setting('fr19.legacy_noop'),
  'CONFIRMED',
  'A legacy same-status no-op returns the current status'
);

-- T47
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = '18191919-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'No fabricated history is introduced for the legacy order'
);

reset role;

insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values (
  '18191920-2222-2222-2222-222222222222',
  'VG-FR19-LEGACY-2',
  '19191919-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'FR-19 Customer A',
  100000, 0, 100000,
  'UNPAID',
  'PENDING_PAYMENT'
);

-- T48
select is(
  (
    select count(*)
    from public.orders
    where id in (
      '18191919-1111-1111-1111-111111111111',
      '18191920-2222-2222-2222-222222222222'
    )
      and idempotency_key is null
  ),
  2::bigint,
  'Two NULL idempotency-key legacy rows may coexist'
);

select * from finish();

rollback;
