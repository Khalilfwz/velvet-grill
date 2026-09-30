begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

-- ============================================================
-- FR-12: protect cart writes by ownership and authorization.
--
-- Fills the remaining coverage gap: cart_item_options ownership
-- paths (cross-user read/delete, client immutability) and a
-- grant-level check that `anon` has no cart-table privileges.
--
-- Cross-user cart and cart_items behavior is already covered by
-- commerce_rls_test.sql; cart_item_options insert membership and
-- cascade by cart_item_options_test.sql. Fixtures are inserted as
-- the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'fr12-customer-a@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'fr12-customer-b@test.local'
  );

insert into public.categories (
  id,
  name,
  slug,
  is_active
)
values (
  'c1111111-1111-1111-1111-111111111111',
  'FR-12 Category',
  'fr12-category',
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
  'd1111111-1111-1111-1111-111111111111',
  'c1111111-1111-1111-1111-111111111111',
  'FR-12 Product',
  'fr12-product',
  100000,
  10,
  true
);

insert into public.product_option_groups (
  id,
  product_id,
  name,
  selection_type,
  min_selections,
  max_selections,
  is_required,
  sort_order,
  is_active
)
values (
  'e1111111-1111-1111-1111-111111111111',
  'd1111111-1111-1111-1111-111111111111',
  'FR-12 Group',
  'SINGLE',
  0,
  1,
  false,
  0,
  true
);

insert into public.product_options (
  id,
  group_id,
  name,
  price_delta,
  is_available,
  sort_order
)
values (
  'f1111111-1111-1111-1111-111111111111',
  'e1111111-1111-1111-1111-111111111111',
  'FR-12 Option',
  0,
  true,
  0
);

insert into public.carts (id, user_id)
values
  (
    'a1111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111111'
  ),
  (
    'a2222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
  );

insert into public.cart_items (id, cart_id, product_id, quantity)
values
  (
    'b1111111-1111-1111-1111-111111111111',
    'a1111111-1111-1111-1111-111111111111',
    'd1111111-1111-1111-1111-111111111111',
    1
  ),
  (
    'b2222222-2222-2222-2222-222222222222',
    'a2222222-2222-2222-2222-222222222222',
    'd1111111-1111-1111-1111-111111111111',
    1
  );

-- One option row per customer, inserted as the owner.
insert into public.cart_item_options (id, cart_item_id, product_option_id)
values
  (
    'aa111111-1111-1111-1111-111111111111',
    'b1111111-1111-1111-1111-111111111111',
    'f1111111-1111-1111-1111-111111111111'
  ),
  (
    'aa222222-2222-2222-2222-222222222222',
    'b2222222-2222-2222-2222-222222222222',
    'f1111111-1111-1111-1111-111111111111'
  );

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 1
select is(
  (
    select count(*)
    from public.cart_item_options
    where cart_item_id = 'b2222222-2222-2222-2222-222222222222'
  ),
  0::bigint,
  'Customer cannot read another customer cart item options'
);

-- TEST 2
-- Unauthorized delete performed as Customer A; then prove B's row survives
-- by switching identity to Customer B, and switch back to A afterwards.
delete from public.cart_item_options
where id = 'aa222222-2222-2222-2222-222222222222';

set local request.jwt.claim.sub =
  '33333333-3333-3333-3333-333333333333';

select is(
  (
    select count(*)
    from public.cart_item_options
    where cart_item_id = 'b2222222-2222-2222-2222-222222222222'
  ),
  1::bigint,
  'Customer cannot delete another customer cart item options'
);

set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 3
select throws_ok(
  $$
    update public.cart_item_options
    set product_option_id = 'f1111111-1111-1111-1111-111111111111'
    where id = 'aa111111-1111-1111-1111-111111111111'
  $$,
  '42501',
  null,
  'Customer cannot update cart item options (no UPDATE privilege)'
);

-- TEST 4
delete from public.cart_item_options
where id = 'aa111111-1111-1111-1111-111111111111';

select is(
  (
    select count(*)
    from public.cart_item_options
    where cart_item_id = 'b1111111-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'Customer can delete their own cart item options'
);

-- TEST 5
-- Grant-level check from the test-owner context. `anon` must hold no privilege
-- at all, including UPDATE on cart_item_options, which authenticated also
-- intentionally lacks.
reset role;

select is(
  (
    select count(*)
    from (
      values
        ('carts', 'SELECT'),
        ('carts', 'INSERT'),
        ('carts', 'UPDATE'),
        ('carts', 'DELETE'),
        ('cart_items', 'SELECT'),
        ('cart_items', 'INSERT'),
        ('cart_items', 'UPDATE'),
        ('cart_items', 'DELETE'),
        ('cart_item_options', 'SELECT'),
        ('cart_item_options', 'INSERT'),
        ('cart_item_options', 'UPDATE'),
        ('cart_item_options', 'DELETE')
    ) as expected(tbl, priv)
    where has_table_privilege(
      'anon',
      'public.' || expected.tbl,
      expected.priv
    )
  ),
  0::bigint,
  'anon has no privileges on any cart table'
);

select * from finish();

rollback;
