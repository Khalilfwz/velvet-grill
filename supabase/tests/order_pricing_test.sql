begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

-- ============================================================
-- FR-14: authoritative pricing is calculated server-side.
--
-- Proves that order pricing is derived from the *current*
-- database catalog at order time (not from cart-time data and
-- never from the client), that the derived monetary columns are
-- consistent, and that create_order exposes no monetary
-- argument through which a client could supply a price.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values (
  '11111111-1111-1111-1111-111111111111',
  'fr14-customer@test.local'
);

insert into public.categories (id, name, slug, is_active)
values (
  'c1414141-1111-1111-1111-111111111111',
  'FR-14 Category',
  'fr14-category',
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
  'd1414141-1111-1111-1111-111111111111',
  'c1414141-1111-1111-1111-111111111111',
  'FR-14 Product',
  'fr14-product',
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
  'e1414141-1111-1111-1111-111111111111',
  'd1414141-1111-1111-1111-111111111111',
  'FR-14 Choice',
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
  'f1414141-1111-1111-1111-111111111111',
  'e1414141-1111-1111-1111-111111111111',
  'FR-14 Option',
  5000,
  true,
  0
);

insert into public.carts (id, user_id)
values (
  'a1414141-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1414141-1111-1111-1111-111111111111',
  'a1414141-1111-1111-1111-111111111111',
  'd1414141-1111-1111-1111-111111111111',
  2
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1414141-1111-1111-1111-111111111111',
  'f1414141-1111-1111-1111-111111111111'
);

-- The cart now holds its contents. Change the catalog *after* the cart was
-- populated: authoritative pricing must use these current values, never the
-- values that applied when the item was added.
update public.products
set base_price = 111000
where id = 'd1414141-1111-1111-1111-111111111111';

update public.product_options
set price_delta = 7000
where id = 'f1414141-1111-1111-1111-111111111111';

-- ============================================================
-- SETUP: customer A places a pickup order.
--
-- Not an assertion. If creation raised, this statement fails and the suite
-- aborts loudly, so the count stays at plan(8).
--
-- Expected, from current database state:
--   unit price    = 111000 + 7000 = 118000
--   line subtotal = 118000 * 2    = 236000
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

select set_config(
  'fr14.order',
  (
    select public.create_order(
      'PICKUP', 'Ada Lovelace', null, null,
      '2026-01-05T12:00', null, 'fr14-pricing-key', 'CASH'
    )::text
  ),
  true
);

-- TEST 1
select is(
  (
    select base_price_snapshot
    from public.order_items
    where order_id = current_setting('fr14.order')::uuid
  ),
  111000::numeric,
  'Order uses the current product base price, not the cart-time price'
);

-- TEST 2
select is(
  (
    select oio.price_delta_snapshot
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr14.order')::uuid
  ),
  7000::numeric,
  'Order uses the current option price delta'
);

-- TEST 3
select is(
  (
    select final_unit_price
    from public.order_items
    where order_id = current_setting('fr14.order')::uuid
  ),
  118000::numeric,
  'Final unit price is base price plus option deltas'
);

-- TEST 4
select is(
  (
    select subtotal
    from public.order_items
    where order_id = current_setting('fr14.order')::uuid
  ),
  236000::numeric,
  'Order item subtotal is final unit price multiplied by quantity'
);

-- TEST 5
select is(
  (
    select subtotal
    from public.orders
    where id = current_setting('fr14.order')::uuid
  ),
  236000::numeric,
  'Order subtotal is derived from the current database catalog'
);

-- TEST 6
select is(
  (
    select final_total
    from public.orders
    where id = current_setting('fr14.order')::uuid
  ),
  236000::numeric,
  'Order final total is derived from the current database catalog'
);

-- TEST 7
select is(
  (
    select discount_total
    from public.orders
    where id = current_setting('fr14.order')::uuid
  ),
  0::numeric,
  'No discount is applied (coupons belong to FR-16)'
);

-- TEST 8
-- Catalog metadata, not the formatted argument string: read the argument
-- names of the exact public.create_order signature and assert that none of
-- them opens a monetary client channel.
reset role;

select is(
  (
    select count(*)
    from pg_proc p
    cross join lateral unnest(p.proargnames) as arg_name
    where p.oid =
      'public.create_order(public.order_fulfillment_type,text,text,text,text,uuid,text,public.payment_method,text)'::regprocedure
      and arg_name ilike any (
        array['%price%', '%subtotal%', '%total%', '%discount%', '%amount%']
      )
  ),
  0::bigint,
  'create_order exposes no monetary argument name (catalog metadata)'
);

select * from finish();

rollback;
