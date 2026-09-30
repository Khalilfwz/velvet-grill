begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ============================================================
-- FR-08: customer-facing profile updates must not change role
-- or unauthorized account state.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures only set the attributes
-- this suite depends on, as the table owner.
-- ============================================================

insert into auth.users (id, email)
values
  (
    'a1111111-1111-1111-1111-111111111111',
    'fr08-customer@test.local'
  ),
  (
    'a2222222-2222-2222-2222-222222222222',
    'fr08-admin@test.local'
  ),
  (
    'a3333333-3333-3333-3333-333333333333',
    'fr08-other@test.local'
  ),
  (
    'a4444444-4444-4444-4444-444444444444',
    'fr08-inactive-admin@test.local'
  );

update public.profiles
set full_name = 'FR-08 Customer'
where id = 'a1111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'FR-08 Admin', role = 'ADMIN'
where id = 'a2222222-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'FR-08 Other'
where id = 'a3333333-3333-3333-3333-333333333333';

update public.profiles
set full_name = 'FR-08 Inactive Admin', role = 'ADMIN', is_active = false
where id = 'a4444444-4444-4444-4444-444444444444';

-- ============================================================
-- PRIVILEGE LAYER
--
-- Column-level UPDATE privileges restrict WHICH COLUMNS an
-- authenticated user may modify, independent of RLS.
-- ============================================================

-- TEST 1
select is(
  has_column_privilege(
    'authenticated',
    'public.profiles',
    'full_name',
    'UPDATE'
  ),
  true,
  'authenticated has UPDATE privilege on profiles.full_name'
);

-- TEST 2
select is(
  has_column_privilege(
    'authenticated',
    'public.profiles',
    'role',
    'UPDATE'
  ),
  false,
  'authenticated has no UPDATE privilege on profiles.role'
);

-- TEST 3
select is(
  has_column_privilege(
    'authenticated',
    'public.profiles',
    'is_active',
    'UPDATE'
  ),
  false,
  'authenticated has no UPDATE privilege on profiles.is_active'
);

-- ============================================================
-- CUSTOMER BEHAVIOR
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'a1111111-1111-1111-1111-111111111111';

-- TEST 4
select lives_ok(
  $$
    update public.profiles
    set
      full_name = 'FR-08 Customer Updated',
      phone = '+620000000000',
      avatar_path = 'avatars/fr08.png'
    where id = 'a1111111-1111-1111-1111-111111111111'
  $$,
  'Customer can update the allowed columns on own profile'
);

-- TEST 5
select is(
  (
    select full_name
    from public.profiles
    where id = 'a1111111-1111-1111-1111-111111111111'
  ),
  'FR-08 Customer Updated',
  'Allowed own-profile update is persisted'
);

-- TEST 6
select throws_ok(
  $$
    update public.profiles
    set role = 'ADMIN'
    where id = 'a1111111-1111-1111-1111-111111111111'
  $$,
  '42501',
  null,
  'Customer cannot change own role'
);

-- TEST 7
select throws_ok(
  $$
    update public.profiles
    set is_active = false
    where id = 'a1111111-1111-1111-1111-111111111111'
  $$,
  '42501',
  null,
  'Customer cannot change own is_active'
);

-- TEST 8
select is(
  (
    select role
    from public.profiles
    where id = 'a1111111-1111-1111-1111-111111111111'
  ),
  'CUSTOMER'::public.user_role,
  'Customer role is unchanged after the rejected escalation'
);

-- TEST 9
-- Prove row-level enforcement: a customer UPDATE targeting
-- another user's row must affect exactly 0 rows under
-- profiles_update_own. The data-modifying CTE is evaluated at
-- the top level and its affected-row count is stashed in a
-- transaction-local setting for the assertion below.
with cross_user_update as (
  update public.profiles
  set full_name = 'Hijacked by cross-user update'
  where id = 'a3333333-3333-3333-3333-333333333333'
  returning id
)
select set_config(
  'fr08.cross_user_rows',
  (select count(*)::text from cross_user_update),
  true
);

select is(
  current_setting('fr08.cross_user_rows')::bigint,
  0::bigint,
  'Customer UPDATE targeting another user profile affects 0 rows'
);

-- ============================================================
-- ADMIN GATING
-- ============================================================

set local request.jwt.claim.sub =
  'a1111111-1111-1111-1111-111111111111';

-- TEST 10
select is(
  (
    select private.is_admin()
  ),
  false,
  'Admin helper returns false for a CUSTOMER'
);

set local request.jwt.claim.sub =
  'a4444444-4444-4444-4444-444444444444';

-- TEST 11
select is(
  (
    select private.is_admin()
  ),
  false,
  'Admin helper returns false for an inactive ADMIN'
);

-- TEST 12
select is(
  (
    select count(*)
    from public.profiles
    where id = 'a3333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Inactive admin cannot read another customer profile'
);

-- ============================================================
-- ANON + ADMIN DEFENSE
-- ============================================================

set local role anon;

-- TEST 13
select throws_ok(
  $$
    update public.profiles
    set full_name = 'Anon Attack'
    where id = 'a1111111-1111-1111-1111-111111111111'
  $$,
  '42501',
  null,
  'Anonymous users cannot update profiles'
);

-- TEST 14
set local role authenticated;
set local request.jwt.claim.sub =
  'a2222222-2222-2222-2222-222222222222';

-- Scoped to this suite's own fixture profiles so unrelated local development
-- or E2E rows cannot change the result. The property under test is unchanged:
-- an active admin may read all profiles, not only their own.
select is(
  (
    select count(*)
    from public.profiles
    where id in (
      'a1111111-1111-1111-1111-111111111111',
      'a2222222-2222-2222-2222-222222222222',
      'a3333333-3333-3333-3333-333333333333',
      'a4444444-4444-4444-4444-444444444444'
    )
  ),
  4::bigint,
  'Active admin can read all fixture profiles'
);

select * from finish();

rollback;
