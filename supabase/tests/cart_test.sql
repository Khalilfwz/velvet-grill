begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- ============================================================
-- FR-10: customers create and manage one personal cart.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the
-- table owner before switching to the `authenticated` role.
--
-- Cross-user isolation and RLS-enabled remain covered by
-- commerce_rls_test.sql. FR-11 owns option-membership and
-- cart_item_options cascade assertions.
-- ============================================================

insert into auth.users (id, email)
values (
  '11111111-1111-1111-1111-111111111111',
  'fr10-customer@test.local'
);

insert into public.categories (
  id,
  name,
  slug,
  is_active
)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Steak',
  'fr10-steak',
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
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'FR-10 Steak',
  'fr10-steak-product',
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
    insert into public.carts (id, user_id)
    values (
      '10101010-1010-1010-1010-101010101010',
      '11111111-1111-1111-1111-111111111111'
    )
  $$,
  'Customer can create their own cart'
);

-- TEST 2
select is(
  (
    select count(*)
    from public.carts
  ),
  1::bigint,
  'Exactly one own cart exists'
);

-- TEST 3
select lives_ok(
  $$
    insert into public.cart_items (id, cart_id, product_id, quantity)
    values (
      '30303030-3030-3030-3030-303030303030',
      '10101010-1010-1010-1010-101010101010',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      2
    )
  $$,
  'Customer can add an item to their own cart'
);

-- TEST 4
select is(
  (
    select count(*)
    from public.cart_items
  ),
  1::bigint,
  'Exactly one own cart item exists'
);

-- TEST 5
update public.cart_items
set quantity = 3
where id = '30303030-3030-3030-3030-303030303030';

select is(
  (
    select quantity
    from public.cart_items
    where id = '30303030-3030-3030-3030-303030303030'
  ),
  3,
  'Customer can update their own cart item quantity'
);

-- TEST 6
delete from public.cart_items
where id = '30303030-3030-3030-3030-303030303030';

select is(
  (
    select count(*)
    from public.cart_items
  ),
  0::bigint,
  'Customer can remove their own cart item; 0 items remain'
);

-- ============================================================
-- ANON
-- ============================================================

set local role anon;

-- TEST 7
select throws_ok(
  $$
    select count(*)
    from public.carts
  $$,
  '42501',
  null,
  'Anonymous users cannot read carts'
);

-- TEST 8
select throws_ok(
  $$
    insert into public.carts (user_id)
    values ('11111111-1111-1111-1111-111111111111')
  $$,
  '42501',
  null,
  'Anonymous users cannot insert carts'
);

select * from finish();

rollback;
