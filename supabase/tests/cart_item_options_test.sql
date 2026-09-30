begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

-- ============================================================
-- FR-11: selected cart options must belong to the selected
-- product.
--
-- Proves the `cart_item_options_insert_valid` RLS backstop:
-- membership, option availability, active group state, and
-- cart-item ownership.
--
-- Fixtures are inserted as the table owner before switching to
-- the `authenticated` role; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'fr11-customer-a@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'fr11-customer-b@test.local'
  );

insert into public.categories (
  id,
  name,
  slug,
  is_active
)
values (
  'c1111111-1111-1111-1111-111111111111',
  'FR-11 Category',
  'fr11-category',
  true
);

-- Two available products so membership can be tested across them.
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
    'd1111111-1111-1111-1111-111111111111',
    'c1111111-1111-1111-1111-111111111111',
    'FR-11 Product One',
    'fr11-product-one',
    100000,
    10,
    true
  ),
  (
    'd2222222-2222-2222-2222-222222222222',
    'c1111111-1111-1111-1111-111111111111',
    'FR-11 Product Two',
    'fr11-product-two',
    120000,
    10,
    true
  );

-- Groups: G1 active on P1, G2 inactive on P1, G3 active on P2.
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
values
  (
    'e1111111-1111-1111-1111-111111111111',
    'd1111111-1111-1111-1111-111111111111',
    'FR-11 Active Group',
    'SINGLE',
    0,
    1,
    false,
    0,
    true
  ),
  (
    'e2222222-2222-2222-2222-222222222222',
    'd1111111-1111-1111-1111-111111111111',
    'FR-11 Inactive Group',
    'SINGLE',
    0,
    1,
    false,
    1,
    false
  ),
  (
    'e3333333-3333-3333-3333-333333333333',
    'd2222222-2222-2222-2222-222222222222',
    'FR-11 Other Product Group',
    'SINGLE',
    0,
    1,
    false,
    0,
    true
  );

-- Options: O1 valid (P1), O2 unavailable (P1), O3 in inactive group
-- (P1), O4 valid but on another product (P2).
insert into public.product_options (
  id,
  group_id,
  name,
  price_delta,
  is_available,
  sort_order
)
values
  (
    'f1111111-1111-1111-1111-111111111111',
    'e1111111-1111-1111-1111-111111111111',
    'FR-11 Valid Option',
    0,
    true,
    0
  ),
  (
    'f2222222-2222-2222-2222-222222222222',
    'e1111111-1111-1111-1111-111111111111',
    'FR-11 Unavailable Option',
    0,
    false,
    1
  ),
  (
    'f3333333-3333-3333-3333-333333333333',
    'e2222222-2222-2222-2222-222222222222',
    'FR-11 Inactive Group Option',
    0,
    true,
    0
  ),
  (
    'f4444444-4444-4444-4444-444444444444',
    'e3333333-3333-3333-3333-333333333333',
    'FR-11 Other Product Option',
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

-- ============================================================
-- CUSTOMER A (itemA belongs to A, itemB belongs to B)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 1
select lives_ok(
  $$
    insert into public.cart_item_options (cart_item_id, product_option_id)
    values (
      'b1111111-1111-1111-1111-111111111111',
      'f1111111-1111-1111-1111-111111111111'
    )
  $$,
  'Valid option for the cart item product succeeds'
);

-- TEST 2
select throws_ok(
  $$
    insert into public.cart_item_options (cart_item_id, product_option_id)
    values (
      'b1111111-1111-1111-1111-111111111111',
      'f4444444-4444-4444-4444-444444444444'
    )
  $$,
  '42501',
  null,
  'Option belonging to another product is rejected'
);

-- TEST 3
select throws_ok(
  $$
    insert into public.cart_item_options (cart_item_id, product_option_id)
    values (
      'b1111111-1111-1111-1111-111111111111',
      'f2222222-2222-2222-2222-222222222222'
    )
  $$,
  '42501',
  null,
  'Unavailable option is rejected'
);

-- TEST 4
select throws_ok(
  $$
    insert into public.cart_item_options (cart_item_id, product_option_id)
    values (
      'b1111111-1111-1111-1111-111111111111',
      'f3333333-3333-3333-3333-333333333333'
    )
  $$,
  '42501',
  null,
  'Option in an inactive group is rejected'
);

-- TEST 5
select throws_ok(
  $$
    insert into public.cart_item_options (cart_item_id, product_option_id)
    values (
      'b2222222-2222-2222-2222-222222222222',
      'f1111111-1111-1111-1111-111111111111'
    )
  $$,
  '42501',
  null,
  'Option for another customer cart item is rejected'
);

-- TEST 6
-- Scoped to the fixture item: only the valid insert persisted.
select is(
  (
    select count(*)
    from public.cart_item_options
    where cart_item_id = 'b1111111-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'Only the valid option row persisted for the fixture cart item'
);

-- TEST 7
-- Delete as the customer, then read as the owner so cascade is actually
-- observable (RLS would otherwise hide orphaned rows).
delete from public.cart_items
where id = 'b1111111-1111-1111-1111-111111111111';

reset role;

select is(
  (
    select count(*)
    from public.cart_item_options
    where cart_item_id = 'b1111111-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'Deleting the cart item cascades to its cart_item_options rows'
);

select * from finish();

rollback;
