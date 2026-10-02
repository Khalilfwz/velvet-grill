-- ============================================================
-- Velvet Grill
-- FR-24: keep analytics separate from transactional revenue truth.
--
-- Analytics are supplementary behavioral events. Client roles may
-- only append whitelisted behavioral events (order_id null, self
-- user_id) and may not read, update, or delete analytics rows.
-- Revenue truth (orders/payments) remains server-authoritative:
-- authenticated customers cannot directly write it.
--
-- Enforcement may come from privileges, RLS, or both; assertions
-- below check the outcome (SQLSTATE 42501), not the mechanism.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table
-- owner before switching roles.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- ============================================================
-- TEST FIXTURES
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'fr24-customer-a@test.local'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'fr24-admin@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'fr24-customer-b@test.local'
  );

update public.profiles
set full_name = 'Customer A'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Admin', role = 'ADMIN'
where id = '22222222-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'Customer B'
where id = '33333333-3333-3333-3333-333333333333';

insert into public.categories (
  id,
  name,
  slug,
  is_active
)
values (
  'aaaaaaaa-0000-4000-8000-000000000001',
  'Steak',
  'steak',
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
  'bbbbbbbb-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000001',
  'Wagyu Ribeye Steak',
  'wagyu-ribeye-fr24',
  250000,
  10,
  true
);

-- Customer A revenue truth: one completed, paid order.
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
values (
  '90909090-0000-4000-8000-000000000001',
  'VG-FR24-001',
  '11111111-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'Customer A',
  '080000000001',
  250000,
  0,
  250000,
  'PAID',
  'COMPLETED'
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
values (
  '92929292-0000-4000-8000-000000000001',
  '90909090-0000-4000-8000-000000000001',
  'bbbbbbbb-0000-4000-8000-000000000001',
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
  amount,
  paid_at
)
values (
  '93939393-0000-4000-8000-000000000001',
  '90909090-0000-4000-8000-000000000001',
  'CASH',
  'PAID',
  250000,
  now()
);

-- ============================================================
-- ANON
-- ============================================================

set local role anon;

-- TEST 1
select lives_ok(
  $$
    insert into public.analytics_events (
      session_id,
      event_name,
      event_category
    )
    values (
      'fr24-anon-session',
      'PAGE_VIEWED',
      'BEHAVIORAL'
    )
  $$,
  'Anonymous users can append whitelisted behavioral analytics'
);

-- TEST 2
select throws_ok(
  $$
    insert into public.analytics_events (
      session_id,
      event_name,
      event_category,
      order_id
    )
    values (
      'fr24-anon-session',
      'CHECKOUT_STARTED',
      'BEHAVIORAL',
      '90909090-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot link analytics to a real order'
);

-- TEST 3
select throws_ok(
  $$
    insert into public.analytics_events (
      session_id,
      event_name,
      event_category
    )
    values (
      'fr24-anon-session',
      'PAYMENT_SUCCESS',
      'TRANSACTION'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot append financial/transaction analytics'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 4
select lives_ok(
  $$
    insert into public.analytics_events (
      user_id,
      session_id,
      event_name,
      event_category
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'fr24-customer-session',
      'PRODUCT_VIEWED',
      'BEHAVIORAL'
    )
  $$,
  'Customer can append whitelisted behavioral analytics for themselves'
);

-- TEST 5
select throws_ok(
  $$
    insert into public.analytics_events (
      user_id,
      session_id,
      event_name,
      event_category
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'fr24-customer-session',
      'PAYMENT_SUCCESS',
      'TRANSACTION'
    )
  $$,
  '42501',
  null,
  'Customer cannot append financial/transaction analytics'
);

-- TEST 6
select throws_ok(
  $$
    insert into public.analytics_events (
      user_id,
      session_id,
      event_name,
      event_category,
      order_id
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'fr24-customer-session',
      'CHECKOUT_STARTED',
      'BEHAVIORAL',
      '90909090-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'Customer cannot link analytics to a real order'
);

-- TEST 7
select throws_ok(
  $$
    insert into public.analytics_events (
      user_id,
      session_id,
      event_name,
      event_category
    )
    values (
      '33333333-3333-3333-3333-333333333333',
      'fr24-customer-session',
      'PRODUCT_VIEWED',
      'BEHAVIORAL'
    )
  $$,
  '42501',
  null,
  'Customer cannot append analytics on behalf of another user'
);

-- TEST 8
select throws_ok(
  $$
    update public.analytics_events
    set event_name = 'PAGE_VIEWED'
  $$,
  '42501',
  null,
  'Customer cannot update analytics rows'
);

-- TEST 9
select throws_ok(
  $$
    delete from public.analytics_events
  $$,
  '42501',
  null,
  'Customer cannot delete analytics rows'
);

-- TEST 10
select is(
  (
    select count(*)
    from public.analytics_events
  ),
  0::bigint,
  'Customer cannot read analytics rows'
);

-- ============================================================
-- ADMIN
-- ============================================================

set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 11
select is(
  (
    select count(*)
    from public.analytics_events
  ),
  2::bigint,
  'Admin can read analytics rows'
);

-- ============================================================
-- SIDE EFFECTS ON REVENUE TRUTH
-- ============================================================

set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 12
select lives_ok(
  $$
    insert into public.analytics_events (
      user_id,
      session_id,
      event_name,
      event_category
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'fr24-side-effect-session',
      'PRODUCT_VIEWED',
      'BEHAVIORAL'
    )
  $$,
  'Customer behavioral analytics insert succeeds'
);

-- TEST 13
select is(
  (
    select final_total
    from public.orders
    where id = '90909090-0000-4000-8000-000000000001'
  ),
  250000::numeric,
  'Client analytics insert does not alter order final_total'
);

-- TEST 14
select is(
  (
    select payment_status::text
    from public.orders
    where id = '90909090-0000-4000-8000-000000000001'
  ),
  'PAID',
  'Client analytics insert does not alter order payment_status'
);

-- TEST 15
select is(
  (
    select count(*)
    from public.payments
    where order_id = '90909090-0000-4000-8000-000000000001'
      and amount = 250000
      and status = 'PAID'
  ),
  1::bigint,
  'Client analytics insert does not alter payment truth'
);

-- TEST 16
select throws_ok(
  $$
    insert into public.orders (
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
    values (
      'VG-FR24-DIRECT',
      '11111111-1111-1111-1111-111111111111',
      'PICKUP',
      now() + interval '2 hours',
      'Customer A',
      '080000000001',
      250000,
      0,
      250000,
      'PAID',
      'COMPLETED'
    )
  $$,
  '42501',
  null,
  'Authenticated customer cannot directly write order truth'
);

-- TEST 17
select throws_ok(
  $$
    insert into public.payments (
      order_id,
      method,
      status,
      amount
    )
    values (
      '90909090-0000-4000-8000-000000000001',
      'CASH',
      'PAID',
      999999
    )
  $$,
  '42501',
  null,
  'Authenticated customer cannot directly write payment truth'
);

select * from finish();

rollback;
