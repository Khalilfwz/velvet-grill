begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ============================================================
-- Test Data
-- ============================================================

-- Test users
insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'customer@test.local'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'admin@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'other@test.local'
  );

-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000_provision_profile_on_signup). This suite only
-- needs to set the fixture attributes it depends on.
update public.profiles
set full_name = 'Test Customer'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Test Admin', role = 'ADMIN'
where id = '22222222-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'Other Customer'
where id = '33333333-3333-3333-3333-333333333333';

-- Categories
insert into public.categories (
  id,
  name,
  slug,
  is_active
)
values
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Steak',
    'steak',
    true
  );

-- Products
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
    'test-wagyu-ribeye-steak',
    250000,
    10,
    true
  ),
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Hidden Test Product',
    'hidden-test-product',
    100000,
    10,
    false
  );

-- ============================================================
-- Test 1: All nine core tables have RLS enabled
-- ============================================================

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in (
        'profiles',
        'categories',
        'products',
        'product_images',
        'product_option_groups',
        'product_options',
        'restaurant_tables',
        'business_hours',
        'restaurant_settings'
      )
      and c.relrowsecurity = true
  ),
  9::bigint,
  'All nine core tables have RLS enabled'
);

-- ============================================================
-- ANON TESTS
-- ============================================================

set local role anon;

-- Test 2: Anonymous users can see available products only
select is(
  (
    select count(*)
    from public.products
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  ),
  1::bigint,
  'Anonymous users see only available products'
);

-- Test 3: Anonymous users cannot insert products
select throws_ok(
  $$
    insert into public.products (
      category_id,
      name,
      slug,
      base_price,
      stock,
      is_available
    )
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'Anonymous Attack',
      'anonymous-attack',
      1,
      1,
      true
    )
  $$,
  '42501',
  null,
  'Anonymous users cannot insert products'
);

-- ============================================================
-- CUSTOMER TESTS
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- Test 4: Customer can see public product
select is(
  (
    select count(*)
    from public.products
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  ),
  1::bigint,
  'Customer can read available products'
);

-- Test 5: Customer can see own profile
select is(
  (
    select count(*)
    from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'Customer can read own profile'
);

-- Test 6: Customer cannot see another customer profile
select is(
  (
    select count(*)
    from public.profiles
    where id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'Customer cannot read another customer profile'
);

-- Test 7: Customer can update allowed own profile fields
select lives_ok(
  $$
    update public.profiles
    set full_name = 'Updated Customer'
    where id = '11111111-1111-1111-1111-111111111111'
  $$,
  'Customer can update allowed fields on own profile'
);

-- Test 8: Customer cannot change own role
select throws_ok(
  $$
    update public.profiles
    set role = 'ADMIN'
    where id = '11111111-1111-1111-1111-111111111111'
  $$,
  '42501',
  null,
  'Customer cannot escalate own role to ADMIN'
);

-- Test 9: Customer cannot insert a product
select throws_ok(
  $$
    insert into public.products (
      category_id,
      name,
      slug,
      base_price,
      stock,
      is_available
    )
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'Customer Attack',
      'customer-attack',
      1,
      1,
      true
    )
  $$,
  '42501',
  null,
  'Customer cannot create products'
);

-- Test 10: Customer cannot modify an existing product
update public.products
set name = 'Hacked Product'
where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

select is(
  (
    select name
    from public.products
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  ),
  'Wagyu Ribeye Steak',
  'Customer cannot modify products'
);

-- ============================================================
-- ADMIN TESTS
-- ============================================================

set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- Test 11: Admin helper identifies active ADMIN
select ok(
  (
    select private.is_admin()
  ),
  'Admin helper returns true for active ADMIN'
);

-- Test 12: Admin can modify product
select lives_ok(
  $$
    update public.products
    set name = 'Wagyu Ribeye Steak - Admin'
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  $$,
  'Admin can modify products'
);

-- Test 13: Admin can modify restaurant settings
select lives_ok(
  $$
    update public.restaurant_settings
    set restaurant_name = 'Velvet Grill Admin Test'
    where id = 1
  $$,
  'Admin can modify restaurant settings'
);

-- Test 14: Admin can read another customer profile
select is(
  (
    select count(*)
    from public.profiles
    where id = '33333333-3333-3333-3333-333333333333'
  ),
  1::bigint,
  'Admin can read customer profiles'
);

select * from finish();

rollback;
