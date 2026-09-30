begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- ============================================================
-- FR-09: customers create and manage one personal wishlist.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the
-- table owner before switching to the `authenticated` role.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'fr09-customer@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'fr09-other@test.local'
  );

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
    'fr09-steak',
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
    'FR-09 Steak',
    'fr09-steak-product',
    100000,
    10,
    true
  );

-- ============================================================
-- CUSTOMER
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 1
select lives_ok(
  $$
    insert into public.wishlists (id, user_id)
    values (
      '70707070-7070-7070-7070-707070707070',
      '11111111-1111-1111-1111-111111111111'
    )
  $$,
  'Customer can create their own wishlist'
);

-- TEST 2
select is(
  (
    select count(*)
    from public.wishlists
  ),
  1::bigint,
  'Exactly one own wishlist exists'
);

-- TEST 3
select throws_ok(
  $$
    insert into public.wishlists (user_id)
    values ('33333333-3333-3333-3333-333333333333')
  $$,
  '42501',
  null,
  'Customer cannot create a wishlist for another user'
);

-- TEST 4
select lives_ok(
  $$
    insert into public.wishlist_items (id, wishlist_id, product_id)
    values (
      '80808080-8080-8080-8080-808080808080',
      '70707070-7070-7070-7070-707070707070',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    )
  $$,
  'Customer can add an available product to their own wishlist'
);

-- TEST 5
select is(
  (
    select count(*)
    from public.wishlist_items
  ),
  1::bigint,
  'Exactly one item exists after the add'
);

-- TEST 6
-- Mirrors the application path: INSERT ... ON CONFLICT DO NOTHING must
-- create no additional rows.
with duplicate_insert as (
  insert into public.wishlist_items (wishlist_id, product_id)
  values (
    '70707070-7070-7070-7070-707070707070',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  )
  on conflict (wishlist_id, product_id) do nothing
  returning id
)
select set_config(
  'fr09.duplicate_rows',
  (select count(*)::text from duplicate_insert),
  true
);

select is(
  current_setting('fr09.duplicate_rows')::bigint,
  0::bigint,
  'Duplicate add is idempotent and creates 0 additional rows'
);

-- TEST 7
select is(
  (
    select count(*)
    from public.wishlist_items
  ),
  1::bigint,
  'Final item count remains exactly 1 after the duplicate add'
);

-- TEST 8
-- T7 proved exactly one item existed, so removal must leave zero.
delete from public.wishlist_items
where wishlist_id = '70707070-7070-7070-7070-707070707070'
  and product_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

select is(
  (
    select count(*)
    from public.wishlist_items
  ),
  0::bigint,
  'Customer can remove their own wishlist item; 0 items remain'
);

-- ============================================================
-- ANON
-- ============================================================

set local role anon;

-- TEST 9
select throws_ok(
  $$
    select count(*)
    from public.wishlists
  $$,
  '42501',
  null,
  'Anonymous users cannot read wishlists'
);

-- TEST 10
select throws_ok(
  $$
    insert into public.wishlists (user_id)
    values ('11111111-1111-1111-1111-111111111111')
  $$,
  '42501',
  null,
  'Anonymous users cannot insert wishlists'
);

select * from finish();

rollback;
