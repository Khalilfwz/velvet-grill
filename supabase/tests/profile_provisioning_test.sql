begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

-- ============================================================
-- FIXTURES
--
-- The profile row is created by the on_auth_user_created trigger
-- (migration 20260929000000); it is not inserted by hand here.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '44444444-4444-4444-4444-444444444444',
    'provisioned@test.local'
  );

-- ============================================================
-- PROVISIONING
-- ============================================================

-- TEST 1
select is(
  (
    select count(*)
    from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'
  ),
  1::bigint,
  'Inserting an auth user creates exactly one profile'
);

-- TEST 2
select is(
  (
    select role
    from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'
  ),
  'CUSTOMER'::public.user_role,
  'Provisioned profile defaults to the CUSTOMER role'
);

-- TEST 3
select is(
  (
    select is_active
    from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'
  ),
  true,
  'Provisioned profile is active'
);

-- TEST 4
select is(
  (
    select full_name
    from public.profiles
    where id = '44444444-4444-4444-4444-444444444444'
  ),
  null,
  'Provisioned profile does not copy metadata into full_name'
);

-- ============================================================
-- PRIVILEGES
-- ============================================================

-- TEST 5
select is(
  has_function_privilege(
    'authenticated',
    'private.handle_new_user()',
    'EXECUTE'
  ),
  false,
  'authenticated cannot execute private.handle_new_user()'
);

-- TEST 6
set local role anon;

select throws_ok(
  $$
    insert into public.profiles (id)
    values ('55555555-5555-5555-5555-555555555555')
  $$,
  '42501',
  null,
  'anon cannot insert profiles directly'
);

-- TEST 7
set local role authenticated;
set local request.jwt.claim.sub =
  '44444444-4444-4444-4444-444444444444';

select throws_ok(
  $$
    insert into public.profiles (id)
    values ('66666666-6666-6666-6666-666666666666')
  $$,
  '42501',
  null,
  'authenticated cannot insert profiles directly'
);

select * from finish();

rollback;
