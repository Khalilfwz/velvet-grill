begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

-- ============================================================
-- TEST FIXTURES
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'customer-a@test.local'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'supporting-admin@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'customer-b@test.local'
  );

-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000_provision_profile_on_signup). This suite only
-- needs to set the fixture attributes it depends on.
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
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
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
values
  (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Wagyu Ribeye Steak',
    'wagyu-ribeye',
    250000,
    10,
    true
  ),
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Grilled Salmon',
    'grilled-salmon',
    180000,
    10,
    true
  );

-- ------------------------------------------------------------
-- Customer A completed order
-- ------------------------------------------------------------

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
  '90909090-9090-9090-9090-909090909090',
  'VG-SUP-001',
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
  '92929292-9292-9292-9292-929292929292',
  '90909090-9090-9090-9090-909090909090',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'Wagyu Ribeye Steak',
  250000,
  250000,
  1,
  250000
);

-- ------------------------------------------------------------
-- Customer B completed order
-- Two different products/items are used for review tests.
-- ------------------------------------------------------------

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
  '91919191-9191-9191-9191-919191919191',
  'VG-SUP-002',
  '33333333-3333-3333-3333-333333333333',
  'PICKUP',
  now() + interval '3 hours',
  'Customer B',
  '080000000002',
  430000,
  0,
  430000,
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
values
  (
    '93939393-9393-9393-9393-939393939393',
    '91919191-9191-9191-9191-919191919191',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'Wagyu Ribeye Steak',
    250000,
    250000,
    1,
    250000
  ),
  (
    '94949494-9494-9494-9494-949494949494',
    '91919191-9191-9191-9191-919191919191',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'Grilled Salmon',
    180000,
    180000,
    1,
    180000
  );

-- ------------------------------------------------------------
-- Reviews
-- One published review and one hidden review owned by B.
-- ------------------------------------------------------------

insert into public.reviews (
  id,
  user_id,
  product_id,
  order_item_id,
  rating,
  title,
  content,
  status
)
values
  (
    'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    '33333333-3333-3333-3333-333333333333',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '93939393-9393-9393-9393-939393939393',
    5,
    'Excellent',
    'Very good.',
    'PUBLISHED'
  ),
  (
    'bbbbbbbb-cccc-dddd-eeee-ffffffffffff',
    '33333333-3333-3333-3333-333333333333',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '94949494-9494-9494-9494-949494949494',
    2,
    'Private Review',
    'Needs improvement.',
    'HIDDEN'
  );

-- ------------------------------------------------------------
-- Notifications
-- ------------------------------------------------------------

insert into public.notifications (
  id,
  user_id,
  type,
  title,
  message,
  is_read
)
values
  (
    '10101010-1010-1010-1010-101010101010',
    '11111111-1111-1111-1111-111111111111',
    'ORDER',
    'Order completed',
    'Your order has been completed.',
    false
  ),
  (
    '20202020-2020-2020-2020-202020202020',
    '33333333-3333-3333-3333-333333333333',
    'ORDER',
    'Order completed',
    'Customer B order completed.',
    false
  );

-- ------------------------------------------------------------
-- Admin audit log fixture
-- ------------------------------------------------------------

insert into public.admin_audit_logs (
  id,
  actor_user_id,
  action,
  entity_type,
  entity_id,
  before_data,
  after_data
)
values (
  '30303030-3030-3030-3030-303030303030',
  '22222222-2222-2222-2222-222222222222',
  'UPDATE_PRODUCT',
  'products',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '{"base_price":250000}',
  '{"base_price":275000}'
);

-- ============================================================
-- TEST 1
-- All supporting tables have RLS enabled
-- ============================================================

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in (
        'reviews',
        'notifications',
        'analytics_events',
        'admin_audit_logs'
      )
      and c.relrowsecurity = true
  ),
  4::bigint,
  'All supporting tables have RLS enabled'
);

-- ============================================================
-- ANON
-- ============================================================

set local role anon;

-- TEST 2
select is(
  (
    select coalesce(string_agg(id::text, ',' order by id), '')
    from public.reviews
    where id in (
      'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
    )
  ),
  'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  'Anonymous users see only the published fixture review'
);

-- TEST 3
select lives_ok(
  $$
    insert into public.analytics_events (
      event_name,
      event_category,
      session_id
    )
    values (
      'PAGE_VIEWED',
      'BEHAVIORAL',
      'anon-session-001'
    )
  $$,
  'Anonymous users can submit allowed behavioral analytics'
);

-- TEST 4
select throws_ok(
  $$
    insert into public.analytics_events (
      event_name,
      event_category
    )
    values (
      'PAYMENT_SUCCESS',
      'TRANSACTION'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot submit transaction analytics'
);

-- TEST 5
select throws_ok(
  $$
    insert into public.admin_audit_logs (
      actor_user_id,
      action,
      entity_type
    )
    values (
      null,
      'FAKE_ACTION',
      'products'
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot write audit logs'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 6
select is(
  (
    select count(*)
    from public.reviews
    where id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
      and status = 'PUBLISHED'
  ),
  1::bigint,
  'Customer can read the published fixture review'
);

-- TEST 7
select is(
  (
    select count(*)
    from public.reviews
    where status = 'HIDDEN'
  ),
  0::bigint,
  'Customer cannot read hidden reviews belonging to others'
);

-- TEST 8
select lives_ok(
  $$
    insert into public.reviews (
      user_id,
      product_id,
      order_item_id,
      rating,
      title,
      content
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      '92929292-9292-9292-9292-929292929292',
      5,
      'Great',
      'Excellent steak.'
    )
  $$,
  'Customer can review their own completed purchase'
);

-- TEST 9
select throws_ok(
  $$
    insert into public.reviews (
      user_id,
      product_id,
      order_item_id,
      rating,
      content
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      '93939393-9393-9393-9393-939393939393',
      5,
      'Unauthorized review'
    )
  $$,
  '42501',
  null,
  'Customer cannot review another customer order'
);

-- TEST 10
select throws_ok(
  $$
    insert into public.reviews (
      user_id,
      product_id,
      order_item_id,
      rating,
      content
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      '92929292-9292-9292-9292-929292929292',
      5,
      'Product mismatch attack'
    )
  $$,
  '42501',
  null,
  'Customer cannot attach a review to the wrong product'
);

-- TEST 11
select is(
  (
    select count(*)
    from public.notifications
  ),
  1::bigint,
  'Customer sees only their own notifications'
);

-- TEST 12
select is(
  (
    select count(*)
    from public.notifications
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer cannot see another customer notification'
);

-- TEST 13
select lives_ok(
  $$
    update public.notifications
    set is_read = true
    where id = '10101010-1010-1010-1010-101010101010'
  $$,
  'Customer can mark their own notification as read'
);

-- TEST 14
select throws_ok(
  $$
    insert into public.notifications (
      user_id,
      type,
      title,
      message
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'ORDER',
      'Fake notification',
      'Fake message'
    )
  $$,
  '42501',
  null,
  'Customer cannot create notifications directly'
);

-- TEST 15
select is(
  (
    select count(*)
    from public.analytics_events
  ),
  0::bigint,
  'Customer cannot read analytics events directly'
);

-- TEST 16
select throws_ok(
  $$
    insert into public.analytics_events (
      event_name,
      event_category,
      user_id,
      order_id
    )
    values (
      'CHECKOUT_STARTED',
      'BEHAVIORAL',
      '11111111-1111-1111-1111-111111111111',
      '90909090-9090-9090-9090-909090909090'
    )
  $$,
  '42501',
  null,
  'Customer cannot submit analytics containing an order reference'
);

-- TEST 17
select throws_ok(
  $$
    insert into public.analytics_events (
      event_name,
      event_category,
      user_id
    )
    values (
      'PRODUCT_VIEWED',
      'BEHAVIORAL',
      '33333333-3333-3333-3333-333333333333'
    )
  $$,
  '42501',
  null,
  'Customer cannot submit analytics on behalf of another user'
);

-- TEST 18
select throws_ok(
  $$
    insert into public.admin_audit_logs (
      actor_user_id,
      action,
      entity_type
    )
    values (
      '11111111-1111-1111-1111-111111111111',
      'FAKE_ACTION',
      'products'
    )
  $$,
  '42501',
  null,
  'Customer cannot write audit logs'
);

-- ============================================================
-- ADMIN
-- ============================================================

set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 19
select ok(
  (
    select private.is_admin()
  ),
  'Admin helper identifies the ADMIN user'
);

-- TEST 20
select is(
  (
    select count(*)
    from public.reviews
    where id = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
      and status = 'HIDDEN'
  ),
  1::bigint,
  'Admin can read the hidden fixture review for moderation'
);

-- TEST 21
select throws_ok(
  $$
    update public.reviews
    set status = 'PUBLISHED'
    where id = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
  $$,
  '42501',
  null,
  'Admin cannot change review status directly'
);

-- TEST 22
select is(
  (
    select count(*)
    from public.admin_audit_logs
    where id = '30303030-3030-3030-3030-303030303030'
  ),
  1::bigint,
  'Admin can read the fixture audit log'
);

-- TEST 23
select is(
  (
    select count(*)
    from public.analytics_events
  ),
  1::bigint,
  'Admin can read analytics events'
);

-- TEST 24
select throws_ok(
  $$
    update public.reviews
    set status = 'PUBLISHED'
    where id = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
  $$,
  '42501',
  null,
  'Customer cannot change review moderation status'
);

select * from finish();

rollback;
