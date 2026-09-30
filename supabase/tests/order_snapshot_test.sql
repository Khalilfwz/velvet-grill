begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- ============================================================
-- FR-15: historical product/option snapshots survive live
-- catalog changes and deletions.
--
-- The order is placed first. The owner then renames and reprices
-- the live catalog and finally deletes the option and the
-- product. The suite then returns to the authenticated customer
-- and asserts through normal RLS that the historical order is
-- still readable and unchanged.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values (
  '11111111-1111-1111-1111-111111111111',
  'fr15-customer@test.local'
);

update public.profiles
set full_name = 'FR-15 Customer'
where id = '11111111-1111-1111-1111-111111111111';

insert into public.categories (id, name, slug, is_active)
values (
  'c1515151-1111-1111-1111-111111111111',
  'FR-15 Category',
  'fr15-category',
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
  'd1515151-1111-1111-1111-111111111111',
  'c1515151-1111-1111-1111-111111111111',
  'FR-15 Product',
  'fr15-product',
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
  'e1515151-1111-1111-1111-111111111111',
  'd1515151-1111-1111-1111-111111111111',
  'FR-15 Group',
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
  'f1515151-1111-1111-1111-111111111111',
  'e1515151-1111-1111-1111-111111111111',
  'FR-15 Option',
  5000,
  true,
  0
);

insert into public.carts (id, user_id)
values (
  'a1515151-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1515151-1111-1111-1111-111111111111',
  'a1515151-1111-1111-1111-111111111111',
  'd1515151-1111-1111-1111-111111111111',
  1
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'b1515151-1111-1111-1111-111111111111',
  'f1515151-1111-1111-1111-111111111111'
);

-- ============================================================
-- SETUP: place the order (not an assertion).
--
-- If creation raised, this statement fails and the suite aborts
-- loudly, so the count stays at plan(9). create_order also clears
-- the cart, so no cart rows keep the adjacent RESTRICTs alive.
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

select set_config(
  'fr15.order',
  (
    select public.create_order(
      'PICKUP', 'FR-15 Customer', null, null,
      now() + interval '2 hours', null, 'fr15-snapshot-key'
    )::text
  ),
  true
);

-- ============================================================
-- Live catalog is renamed, repriced, then removed (as the owner).
-- ============================================================

reset role;

update public.products
set name = 'RENAMED Product', base_price = 999000
where id = 'd1515151-1111-1111-1111-111111111111';

update public.product_option_groups
set name = 'RENAMED Group'
where id = 'e1515151-1111-1111-1111-111111111111';

update public.product_options
set name = 'RENAMED Option', price_delta = 999000
where id = 'f1515151-1111-1111-1111-111111111111';

delete from public.product_options
where id = 'f1515151-1111-1111-1111-111111111111';

delete from public.products
where id = 'd1515151-1111-1111-1111-111111111111';

-- ============================================================
-- Back to the customer: the historical order must still be
-- readable through normal RLS and unchanged.
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 1
select is(
  (
    select count(*)
    from public.order_items
    where order_id = current_setting('fr15.order')::uuid
  ),
  1::bigint,
  'Historical order item is still readable after catalog deletion'
);

-- TEST 2
select is(
  (
    select product_id
    from public.order_items
    where order_id = current_setting('fr15.order')::uuid
  ),
  null::uuid,
  'Product reference is nulled by ON DELETE SET NULL'
);

-- TEST 3
select is(
  (
    select product_name_snapshot
    from public.order_items
    where order_id = current_setting('fr15.order')::uuid
  ),
  'FR-15 Product',
  'Product name snapshot is unchanged by rename and deletion'
);

-- TEST 4
select is(
  (
    select base_price_snapshot
    from public.order_items
    where order_id = current_setting('fr15.order')::uuid
  ),
  100000::numeric,
  'Base price snapshot is unchanged by reprice and deletion'
);

-- TEST 5
select is(
  (
    select count(*)
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr15.order')::uuid
  ),
  1::bigint,
  'Historical order item option is still readable after catalog deletion'
);

-- TEST 6
select is(
  (
    select oio.product_option_id
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr15.order')::uuid
  ),
  null::uuid,
  'Option reference is nulled by ON DELETE SET NULL'
);

-- TEST 7
select is(
  (
    select oio.option_group_name_snapshot
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr15.order')::uuid
  ),
  'FR-15 Group',
  'Option group name snapshot is unchanged by rename and deletion'
);

-- TEST 8
select is(
  (
    select oio.option_name_snapshot
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr15.order')::uuid
  ),
  'FR-15 Option',
  'Option name snapshot is unchanged by rename and deletion'
);

-- TEST 9
select is(
  (
    select oio.price_delta_snapshot
    from public.order_item_options oio
    join public.order_items oi on oi.id = oio.order_item_id
    where oi.order_id = current_setting('fr15.order')::uuid
  ),
  5000::numeric,
  'Option price delta snapshot is unchanged by reprice and deletion'
);

select * from finish();

rollback;
