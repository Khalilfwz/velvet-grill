-- ============================================================
-- Velvet Grill
-- FR-23: customers can view and manage their own notifications.
--
-- Access is enforced by RLS and grants on public.notifications
-- (migration 20260922013928 / 20260922014836): authenticated
-- customers may read their own rows and update only their own
-- is_read flag; there is no client INSERT or DELETE grant.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table
-- owner before switching to the `authenticated` role.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- ============================================================
-- TEST FIXTURES
-- ============================================================

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'fr23-customer-a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'fr23-admin@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'fr23-customer-b@test.local');

update public.profiles
set full_name = 'Customer A'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Admin', role = 'ADMIN'
where id = '22222222-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'Customer B'
where id = '33333333-3333-3333-3333-333333333333';

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
    'a0000000-0000-4000-8000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'ORDER',
    'Order completed',
    'Your order has been completed.',
    false
  ),
  (
    'a0000000-0000-4000-8000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'SYSTEM',
    'Welcome',
    'Welcome to Velvet Grill.',
    true
  ),
  (
    'a0000000-0000-4000-8000-000000000003',
    '33333333-3333-3333-3333-333333333333',
    'ORDER',
    'Order completed',
    'Customer B order completed.',
    false
  );

-- ============================================================
-- TEST 1
-- RLS is enabled on notifications
-- ============================================================

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'notifications'
      and c.relrowsecurity = true
  ),
  1::bigint,
  'Notifications table has RLS enabled'
);

-- ============================================================
-- ANONYMOUS
-- ============================================================

reset role;
set local role anon;
set local request.jwt.claim.sub = '';

-- T2
select throws_ok(
  $$
    select count(*)
    from public.notifications
  $$,
  '42501',
  null,
  'Anonymous users cannot read notifications'
);

-- T3
select throws_ok(
  $$
    update public.notifications
    set is_read = true
  $$,
  '42501',
  null,
  'Anonymous users cannot update notifications'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T4
select is(
  (
    select count(*)
    from public.notifications
  ),
  2::bigint,
  'Customer sees only their own notifications'
);

-- T5
select is(
  (
    select count(*)
    from public.notifications
    where user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer cannot see another customer notification'
);

-- T6
select lives_ok(
  $$
    update public.notifications
    set is_read = true
    where id = 'a0000000-0000-4000-8000-000000000001'
  $$,
  'Customer can mark their own notification as read'
);

-- T7
select is(
  (
    select is_read
    from public.notifications
    where id = 'a0000000-0000-4000-8000-000000000001'
  ),
  true,
  'Read state is persisted'
);

-- T8
select lives_ok(
  $$
    update public.notifications
    set is_read = false
    where id = 'a0000000-0000-4000-8000-000000000002'
  $$,
  'Customer can mark their own notification as unread'
);

-- T9
select is(
  (
    select is_read
    from public.notifications
    where id = 'a0000000-0000-4000-8000-000000000002'
  ),
  false,
  'Unread state is persisted'
);

-- T10 setup: A attempts to mark B's notification read (RLS affects zero rows).
update public.notifications
set is_read = true
where id = 'a0000000-0000-4000-8000-000000000003';

reset role;

-- T10
select is(
  (
    select is_read
    from public.notifications
    where id = 'a0000000-0000-4000-8000-000000000003'
  ),
  false,
  'Customer cannot mark another customer notification as read'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T11
select throws_ok(
  $$
    update public.notifications
    set title = 'Hacked'
    where id = 'a0000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'Customer cannot update notification columns beyond is_read'
);

-- T12
select throws_ok(
  $$
    update public.notifications
    set user_id = '33333333-3333-3333-3333-333333333333'
    where id = 'a0000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'Customer cannot transfer notification ownership'
);

-- T13
select throws_ok(
  $$
    insert into public.notifications (user_id, type, title, message)
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

-- T14
select throws_ok(
  $$
    delete from public.notifications
    where id = 'a0000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'Customer cannot delete notifications directly'
);

-- ============================================================
-- ADMIN
-- ============================================================

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- T15
select is(
  (
    select count(*)
    from public.notifications
    where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'Admin does not implicitly see another customer notifications'
);

-- T16 setup: admin attempts to mark B's notification read (RLS affects zero rows).
update public.notifications
set is_read = true
where id = 'a0000000-0000-4000-8000-000000000003';

reset role;

-- T16
select is(
  (
    select is_read
    from public.notifications
    where id = 'a0000000-0000-4000-8000-000000000003'
  ),
  false,
  'Admin does not implicitly update another customer notification'
);

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

-- ============================================================
-- CUSTOMER B
-- ============================================================

set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

-- T17
select is(
  (
    select count(*)
    from public.notifications
  ),
  1::bigint,
  'Customer B sees only their own notification'
);

select * from finish();

rollback;
