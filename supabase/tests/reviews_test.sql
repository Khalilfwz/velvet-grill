-- ============================================================
-- Velvet Grill
-- FR-22: reviews are allowed only for eligible completed purchases.
--
-- The eligibility rule is enforced by RLS and table constraints
-- (public.reviews, migration 20260922013928 / 20260922014836,
-- corrected by 20260922015420). This suite proves the rule,
-- including the previously untested "not completed" negatives,
-- duplicate prevention, ownership boundaries, visibility, and
-- dynamic eligibility once an order reaches COMPLETED.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table
-- owner before switching to the `authenticated` role.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

-- ============================================================
-- TEST FIXTURES
-- ============================================================

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'fr22-customer-a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'fr22-admin@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'fr22-customer-b@test.local');

update public.profiles
set full_name = 'Customer A'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Admin', role = 'ADMIN'
where id = '22222222-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'Customer B'
where id = '33333333-3333-3333-3333-333333333333';

insert into public.categories (id, name, slug, is_active)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Steak', 'fr22-steak', true);

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
    'FR-22 Wagyu',
    'fr22-wagyu',
    250000,
    10,
    true
  ),
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'FR-22 Salmon',
    'fr22-salmon',
    180000,
    10,
    true
  );

-- Orders owned by Customer A in several states, plus one owned by B.
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
    'd0000000-0000-4000-8000-000000000001',
    'VG-FR22-001',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    now() + interval '2 hours',
    'Customer A',
    '080000000001',
    430000,
    0,
    430000,
    'PAID',
    'COMPLETED'
  ),
  (
    'd0000000-0000-4000-8000-000000000002',
    'VG-FR22-002',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    now() + interval '3 hours',
    'Customer A',
    '080000000001',
    250000,
    0,
    250000,
    'PAID',
    'CONFIRMED'
  ),
  (
    'd0000000-0000-4000-8000-000000000003',
    'VG-FR22-003',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    now() + interval '4 hours',
    'Customer A',
    '080000000001',
    250000,
    0,
    250000,
    'UNPAID',
    'PENDING_PAYMENT'
  ),
  (
    'd0000000-0000-4000-8000-000000000004',
    'VG-FR22-004',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    now() + interval '5 hours',
    'Customer A',
    '080000000001',
    250000,
    0,
    250000,
    'UNPAID',
    'CANCELLED'
  ),
  (
    'd0000000-0000-4000-8000-000000000005',
    'VG-FR22-005',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    now() + interval '6 hours',
    'Customer A',
    '080000000001',
    250000,
    0,
    250000,
    'PAID',
    'READY'
  ),
  (
    'd0000000-0000-4000-8000-000000000006',
    'VG-FR22-006',
    '33333333-3333-3333-3333-333333333333',
    'PICKUP',
    now() + interval '7 hours',
    'Customer B',
    '080000000002',
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
values
  (
    'e0000000-0000-4000-8000-000000000001',
    'd0000000-0000-4000-8000-000000000001',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'FR-22 Wagyu',
    250000,
    250000,
    1,
    250000
  ),
  (
    'e0000000-0000-4000-8000-000000000002',
    'd0000000-0000-4000-8000-000000000001',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'FR-22 Salmon',
    180000,
    180000,
    1,
    180000
  ),
  (
    'e0000000-0000-4000-8000-000000000003',
    'd0000000-0000-4000-8000-000000000002',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'FR-22 Wagyu',
    250000,
    250000,
    1,
    250000
  ),
  (
    'e0000000-0000-4000-8000-000000000004',
    'd0000000-0000-4000-8000-000000000003',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'FR-22 Wagyu',
    250000,
    250000,
    1,
    250000
  ),
  (
    'e0000000-0000-4000-8000-000000000005',
    'd0000000-0000-4000-8000-000000000004',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'FR-22 Wagyu',
    250000,
    250000,
    1,
    250000
  ),
  (
    'e0000000-0000-4000-8000-000000000006',
    'd0000000-0000-4000-8000-000000000005',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'FR-22 Wagyu',
    250000,
    250000,
    1,
    250000
  ),
  (
    'e0000000-0000-4000-8000-000000000007',
    'd0000000-0000-4000-8000-000000000006',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'FR-22 Wagyu',
    250000,
    250000,
    1,
    250000
  );

-- Customer B's published review, used for cross-user update/delete
-- and public visibility assertions.
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
values (
  'f0000000-0000-4000-8000-000000000001',
  '33333333-3333-3333-3333-333333333333',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'e0000000-0000-4000-8000-000000000007',
  4,
  'Original B',
  'B original content.',
  'PUBLISHED'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T1
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
      'e0000000-0000-4000-8000-000000000001',
      5,
      'Great',
      'Excellent steak.'
    )
  $$,
  'Customer can review their own completed purchase'
);

-- T2
select is(
  (
    select status::text
    from public.reviews
    where order_item_id = 'e0000000-0000-4000-8000-000000000001'
  ),
  'PUBLISHED',
  'New review defaults to PUBLISHED status'
);

-- T3
select is(
  (
    select count(*)
    from public.reviews
    where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'Customer has exactly one review after the eligible insert'
);

-- T4
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000003',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot review an order that is not completed (CONFIRMED)'
);

-- T5
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000004',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot review an order that is not completed (PENDING_PAYMENT)'
);

-- T6
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000005',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot review a cancelled order'
);

-- T7
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000007',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot review another customer completed purchase'
);

-- T8
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '33333333-3333-3333-3333-333333333333',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'e0000000-0000-4000-8000-000000000002',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot spoof the review author'
);

-- T9
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000002',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot attach a review to the wrong product'
);

-- T10
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000001',
      5
    )
  $$,
  '23505',
  null,
  'Customer cannot create a second review for the same order item'
);

-- T11
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'e0000000-0000-4000-8000-000000000002',
      6
    )
  $$,
  '23514',
  null,
  'Review rating must stay within 1 and 5'
);

-- T12
select lives_ok(
  $$
    update public.reviews
    set rating = 4,
        title = 'Updated',
        content = 'Revised content.'
    where order_item_id = 'e0000000-0000-4000-8000-000000000001'
  $$,
  'Customer can update their own review content'
);

-- T13
select is(
  (
    select title
    from public.reviews
    where order_item_id = 'e0000000-0000-4000-8000-000000000001'
  ),
  'Updated',
  'Updated review content is persisted'
);

-- T14
select throws_ok(
  $$
    update public.reviews
    set status = 'HIDDEN'
    where order_item_id = 'e0000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'Customer cannot change review moderation status'
);

-- T15 setup: A attempts to modify B's review (RLS affects zero rows).
update public.reviews
set title = 'Hacked'
where id = 'f0000000-0000-4000-8000-000000000001';

-- T15
select is(
  (
    select title
    from public.reviews
    where id = 'f0000000-0000-4000-8000-000000000001'
  ),
  'Original B',
  'Customer cannot modify another customer review'
);

-- A hidden review owned by A, created by trusted moderation context.
reset role;

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
values (
  'f0000000-0000-4000-8000-000000000002',
  '11111111-1111-1111-1111-111111111111',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'e0000000-0000-4000-8000-000000000002',
  3,
  'Hidden',
  'Hidden from the public.',
  'HIDDEN'
);

-- ============================================================
-- ANONYMOUS
-- ============================================================

reset role;
set local role anon;
set local request.jwt.claim.sub = '';

-- T16
select is(
  (
    select count(*)
    from public.reviews
    where (
      id in (
        'f0000000-0000-4000-8000-000000000001',
        'f0000000-0000-4000-8000-000000000002'
      )
      or order_item_id in (
        'e0000000-0000-4000-8000-000000000001',
        'e0000000-0000-4000-8000-000000000002',
        'e0000000-0000-4000-8000-000000000007'
      )
    )
  ),
  2::bigint,
  'Anonymous users see only the published fixture reviews'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T17
select is(
  (
    select count(*)
    from public.reviews
    where status = 'HIDDEN'
  ),
  1::bigint,
  'Customer can read their own hidden review'
);

-- ============================================================
-- CUSTOMER B
-- ============================================================

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

-- T18
select is(
  (
    select count(*)
    from public.reviews
    where user_id = '11111111-1111-1111-1111-111111111111'
      and status = 'HIDDEN'
  ),
  0::bigint,
  'Customer cannot read another customer hidden review'
);

-- ============================================================
-- ADMIN
-- ============================================================

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- T19
select is(
  (
    select count(*)
    from public.reviews
    where status = 'HIDDEN'
  ),
  1::bigint,
  'Admin can read hidden reviews for moderation'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T20 setup: A attempts to delete B's review (RLS affects zero rows).
delete from public.reviews
where id = 'f0000000-0000-4000-8000-000000000001';

-- T20
select is(
  (
    select count(*)
    from public.reviews
    where id = 'f0000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'Customer cannot delete another customer review'
);

-- T21
select lives_ok(
  $$
    delete from public.reviews
    where order_item_id = 'e0000000-0000-4000-8000-000000000001'
  $$,
  'Customer can delete their own review'
);

-- T22
select throws_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000006',
      5
    )
  $$,
  '42501',
  null,
  'Customer cannot review an order item that is not yet completed'
);

-- ============================================================
-- ADMIN advances the order to COMPLETED (FR-18 authority)
-- ============================================================

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- T23
select lives_ok(
  $$
    select public.update_order_status(
      'd0000000-0000-4000-8000-000000000005',
      'COMPLETED'
    )
  $$,
  'Admin can advance a ready order to completed'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T24
select lives_ok(
  $$
    insert into public.reviews (user_id, product_id, order_item_id, rating)
    values (
      '11111111-1111-1111-1111-111111111111',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'e0000000-0000-4000-8000-000000000006',
      5
    )
  $$,
  'Customer can review the order item once the order is completed'
);

select * from finish();

rollback;
