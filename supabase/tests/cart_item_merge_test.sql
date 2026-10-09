begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

-- ============================================================
-- BUG-03: cart item merging
--
-- add_cart_item() merges same product + identical option set
-- into one line; different options/products stay separate; the
-- no-duplicate-line invariant holds for every permitted write
-- path (verified in-transaction by forcing the deferred
-- constraint triggers with SET CONSTRAINTS ALL IMMEDIATE), and
-- repair_duplicate_cart_lines() is non-lossy or aborts safely.
--
-- Cross-session commit behavior is covered separately by
-- supabase/tests/integration/cart_merge_concurrency.sh; this
-- suite is single-session and makes no concurrency claim.
--
-- Fixtures are inserted as the table owner before switching to
-- the `authenticated` role. The whole file runs in one rolled
-- back transaction, so deferred triggers never fire on their
-- own; invariant tests force them explicitly.
-- ============================================================

insert into auth.users (id, email)
values
  ('31313131-3131-3131-3131-313131313131', 'bug03-a@test.local'),
  ('32323232-3232-3232-3232-323232323232', 'bug03-b@test.local'),
  ('34343434-3434-3434-3434-343434343434', 'bug03-r1@test.local'),
  ('35353535-3535-3535-3535-353535353535', 'bug03-r2@test.local');

insert into public.categories (id, name, slug, is_active)
values ('c1111111-1111-1111-1111-111111111111', 'BUG03', 'bug03-merge', true);

insert into public.products (id, category_id, name, slug, base_price, stock, is_available)
values
  ('d1111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 'BUG03 Steak',  'bug03-steak',  100000, 100, true),
  ('d2222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111', 'BUG03 Sides',  'bug03-sides',  20000,  100, true),
  ('d3333333-3333-3333-3333-333333333333', 'c1111111-1111-1111-1111-111111111111', 'BUG03 Hidden', 'bug03-hidden', 50000,  100, false),
  ('d4444444-4444-4444-4444-444444444444', 'c1111111-1111-1111-1111-111111111111', 'BUG03 Combo Meal', 'bug03-combo-meal', 80000, 100, true);

insert into public.product_option_groups (
  id, product_id, name, selection_type, min_selections, max_selections, is_required, sort_order, is_active
)
values
  ('e1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111111', 'Doneness', 'SINGLE',   1, null, true,  0, true),
  ('e2222222-2222-2222-2222-222222222222', 'd1111111-1111-1111-1111-111111111111', 'Extras',   'MULTIPLE', 0, 1,    false, 1, true),
  ('e4444444-4444-4444-4444-444444444444', 'd4444444-4444-4444-4444-444444444444', 'Combos',   'MULTIPLE', 2, null, false, 0, true);

insert into public.product_options (id, group_id, name, price_delta, is_available, sort_order)
values
  ('f1111111-1111-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111', 'Rare',          0,     true,  0),
  ('f2222222-2222-2222-2222-222222222222', 'e1111111-1111-1111-1111-111111111111', 'Medium',        5000,  true,  1),
  ('f3333333-3333-3333-3333-333333333333', 'e2222222-2222-2222-2222-222222222222', 'Extra sauce',   2000,  true,  0),
  ('f4444444-4444-4444-4444-444444444444', 'e2222222-2222-2222-2222-222222222222', 'Extra cheese',  3000,  true,  1),
  ('f5555555-5555-5555-5555-555555555555', 'e2222222-2222-2222-2222-222222222222', 'Sold-out extra',1000,  false, 2),
  ('f8888888-8888-8888-8888-888888888888', 'e4444444-4444-4444-4444-444444444444', 'Combo A',       0,     true,  0),
  ('f9999999-9999-9999-9999-999999999999', 'e4444444-4444-4444-4444-444444444444', 'Combo B',       0,     true,  1);

-- Repair fixture carts and duplicate lines are seeded in the repair
-- section below (while owner): seeding them here would queue deferred
-- uniqueness events that fire at the first SET CONSTRAINTS force.

-- ============================================================
-- MERGE BEHAVIOR (customer A)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '31313131-3131-3131-3131-313131313131';

-- TEST 1
select lives_ok(
  $$ select public.add_cart_item('d2222222-2222-2222-2222-222222222222'::uuid, 2) $$,
  'First add creates the cart and one line'
);

-- TEST 2
select is(
  (
    select count(*)::int
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  1,
  'Same product, no options: still one line after first add'
);

-- TEST 3
select lives_ok(
  $$ select public.add_cart_item('d2222222-2222-2222-2222-222222222222'::uuid, 3) $$,
  'Second identical add merges into the existing line'
);

-- TEST 4
select is(
  (
    select ci.quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  5,
  'Merged quantity is the sum (2 + 3)'
);

-- TEST 5
select lives_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111', 'f3333333-3333-3333-3333-333333333333']::uuid[]
  ) $$,
  'Add with options succeeds'
);

-- TEST 6
select lives_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    2,
    array['f3333333-3333-3333-3333-333333333333', 'f1111111-1111-1111-1111-111111111111']::uuid[]
  ) $$,
  'Same options in a different order merge (order-insensitive identity)'
);

-- TEST 7
select is(
  (
    select count(*)::int
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
      and (
        select count(*) from public.cart_item_options x
        where x.cart_item_id = ci.id
      ) = 2
  ),
  1,
  'Reordered identical options: one line'
);

-- TEST 8
select is(
  (
    select ci.quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
      and (
        select count(*) from public.cart_item_options x
        where x.cart_item_id = ci.id
      ) = 2
  ),
  3,
  'Reordered merge quantity is the sum (1 + 2)'
);

-- TEST 9
select lives_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111']::uuid[]
  ) $$,
  'Same product with a different option set is a separate line'
);

-- TEST 10
select is(
  (
    select count(*)::int
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
  ),
  2,
  'Same product, different options: two lines'
);

-- TEST 11
select lives_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111', 'f3333333-3333-3333-3333-333333333333', 'f3333333-3333-3333-3333-333333333333']::uuid[]
  ) $$,
  'Duplicate option ids in one payload are deduplicated and merge'
);

-- TEST 12
select is(
  (
    select ci.quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
      and (
        select count(*) from public.cart_item_options x
        where x.cart_item_id = ci.id
      ) = 2
  ),
  4,
  'Deduplicated payload merged into the existing two-option line (3 + 1)'
);

-- TEST 13
select is(
  (
    select count(*)::int
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
  ),
  2,
  'Deduplicated merge created no new line'
);

-- Different products already live in separate lines (steak vs sides above).

-- Push the no-option line near the limit to exercise the merge cap.
update public.cart_items
set quantity = 97
where id = (
  select ci.id
  from public.cart_items ci
  join public.carts c on c.id = ci.cart_id
  where c.user_id = '31313131-3131-3131-3131-313131313131'
    and ci.product_id = 'd2222222-2222-2222-2222-222222222222'
);

-- TEST 14
select throws_ok(
  $$ select public.add_cart_item('d2222222-2222-2222-2222-222222222222'::uuid, 3) $$,
  '22023',
  'Cart quantity limit exceeded',
  'Merge beyond the quantity limit is rejected'
);

-- TEST 15
select is(
  (
    select ci.quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  97,
  'Rejected merge leaves the quantity unchanged'
);

-- TEST 16
select throws_ok(
  $$ select public.add_cart_item('d3333333-3333-3333-3333-333333333333'::uuid, 1) $$,
  '22023',
  'Cart product is unavailable',
  'Unavailable product is rejected'
);

-- TEST 17
select throws_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111', 'f5555555-5555-5555-5555-555555555555']::uuid[]
  ) $$,
  '22023',
  'Cart options are invalid',
  'Unavailable option is rejected'
);

-- TEST 18
select throws_ok(
  $$ select public.add_cart_item(
    'd2222222-2222-2222-2222-222222222222'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111']::uuid[]
  ) $$,
  '22023',
  'Cart options are invalid',
  'Option of another product is rejected'
);

-- TEST 19
select throws_ok(
  $$ select public.add_cart_item('d1111111-1111-1111-1111-111111111111'::uuid, 1) $$,
  '22023',
  'Cart options are invalid',
  'Empty selection for a required group is rejected'
);

-- TEST 20
select throws_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111', 'f2222222-2222-2222-2222-222222222222']::uuid[]
  ) $$,
  '22023',
  'Cart options are invalid',
  'Two selections in a SINGLE group are rejected'
);

-- TEST 21
select throws_ok(
  $$ select public.add_cart_item(
    'd4444444-4444-4444-4444-444444444444'::uuid,
    1,
    array['f8888888-8888-8888-8888-888888888888']::uuid[]
  ) $$,
  '22023',
  'Cart options are invalid',
  'Selection below min_selections is rejected'
);

-- TEST 22
select throws_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111', 'f3333333-3333-3333-3333-333333333333', 'f4444444-4444-4444-4444-444444444444']::uuid[]
  ) $$,
  '22023',
  'Cart options are invalid',
  'Selection above max_selections is rejected'
);

-- TEST 23
select throws_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    0,
    array['f1111111-1111-1111-1111-111111111111']::uuid[]
  ) $$,
  '22023',
  'Cart quantity is invalid',
  'Quantity below 1 is rejected'
);

-- TEST 24
set local request.jwt.claim.sub = '';
select throws_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    1,
    array['f1111111-1111-1111-1111-111111111111']::uuid[]
  ) $$,
  '28000',
  'Not authenticated',
  'Unauthenticated call is rejected'
);
set local request.jwt.claim.sub = '31313131-3131-3131-3131-313131313131';

-- ============================================================
-- OWNERSHIP ISOLATION (customer B)
-- ============================================================

set local request.jwt.claim.sub = '32323232-3232-3232-3232-323232323232';

-- TEST 25
select lives_ok(
  $$ select public.add_cart_item(
    'd1111111-1111-1111-1111-111111111111'::uuid,
    5,
    array['f1111111-1111-1111-1111-111111111111']::uuid[]
  ) $$,
  'Customer B adds the same product + options to their own cart'
);

-- TEST 26
select is(
  (
    select count(*)::int from public.carts
    where user_id = '32323232-3232-3232-3232-323232323232'
  ),
  1,
  'Customer B has exactly one cart'
);

-- TEST 27
select is(
  (
    select ci.quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '32323232-3232-3232-3232-323232323232'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
  ),
  5,
  'Customer B has their own line with their quantity'
);

-- TEST 28 (as owner: RLS correctly hides customer A's cart from B's session,
-- so the cross-user assertion must bypass RLS to inspect A's line)
reset role;
select is(
  (
    select ci.quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
      and (select count(*) from public.cart_item_options x where x.cart_item_id = ci.id) = 1
  ),
  1,
  'Customer A line is untouched by customer B add'
);

-- ============================================================
-- INVARIANT ACROSS PERMITTED WRITE PATHS (customer A)
--
-- Deferred constraint triggers only fire at commit; inside this
-- rolled-back transaction they are forced explicitly with
-- SET CONSTRAINTS ALL IMMEDIATE.
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '31313131-3131-3131-3131-313131313131';

-- TEST 29: a plain quantity update by the owner passes the check.
select lives_ok(
  $$
    update public.cart_items
    set quantity = 98
    where id = (
      select ci.id
      from public.cart_items ci
      join public.carts c on c.id = ci.cart_id
      where c.user_id = '31313131-3131-3131-3131-313131313131'
        and ci.product_id = 'd2222222-2222-2222-2222-222222222222'
    )
  $$,
  'Direct quantity update on an own line is allowed'
);

-- TEST 30
select lives_ok(
  $$ set constraints all immediate $$,
  'Clean state passes the uniqueness check'
);

set constraints all deferred;

-- TEST 31: a direct duplicate insert succeeds while deferred...
select lives_ok(
  $$
    insert into public.cart_items (cart_id, product_id, quantity)
    select c.id, 'd2222222-2222-2222-2222-222222222222'::uuid, 1
    from public.carts c
    where c.user_id = '31313131-3131-3131-3131-313131313131'
  $$,
  'Direct duplicate insert queues (no statement-time enforcement)'
);

-- TEST 32: ...but can never commit.
select throws_ok(
  $$ set constraints all immediate $$,
  '23505',
  null,
  'Direct duplicate insert is rejected at commit'
);

delete from public.cart_items
where cart_id = (
  select c.id from public.carts c
  where c.user_id = '31313131-3131-3131-3131-313131313131'
)
  and product_id = 'd2222222-2222-2222-2222-222222222222'
  and quantity = 1;

set constraints all deferred;

-- TEST 33: adding an option row that makes a line identical to a sibling...
select lives_ok(
  $$
    insert into public.cart_item_options (cart_item_id, product_option_id)
    select ci.id, 'f3333333-3333-3333-3333-333333333333'::uuid
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
      and (select count(*) from public.cart_item_options x where x.cart_item_id = ci.id) = 1
  $$,
  'Direct option insert queues while deferred'
);

-- TEST 34: ...cannot commit.
select throws_ok(
  $$ set constraints all immediate $$,
  '23505',
  null,
  'Option insert creating a duplicate line is rejected at commit'
);

-- Undo TEST 33: both P1 lines now carry {O1, O3}. Removing O3 from either
-- one restores a clean {O1, O3} + {O1} state, so drop it from one
-- deterministically.
delete from public.cart_item_options
where product_option_id = 'f3333333-3333-3333-3333-333333333333'
  and cart_item_id = (
    select ci.id
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id
    where c.user_id = '31313131-3131-3131-3131-313131313131'
      and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
      and (select count(*) from public.cart_item_options x where x.cart_item_id = ci.id) = 2
    order by ci.id
    limit 1
  );

set constraints all deferred;

-- TEST 35: deleting an option row that makes a line identical to a sibling...
select lives_ok(
  $$
    delete from public.cart_item_options
    where cart_item_id = (
      select ci.id
      from public.cart_items ci
      join public.carts c on c.id = ci.cart_id
      where c.user_id = '31313131-3131-3131-3131-313131313131'
        and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
        and (select count(*) from public.cart_item_options x where x.cart_item_id = ci.id) = 2
    )
      and product_option_id = 'f3333333-3333-3333-3333-333333333333'
  $$,
  'Direct option delete queues while deferred'
);

-- TEST 36: ...cannot commit.
select throws_ok(
  $$ set constraints all immediate $$,
  '23505',
  null,
  'Option delete creating a duplicate line is rejected at commit'
);

-- Restore: return one of the two {O1} lines to {O1, O3}. (TEST 36 left two
-- identical one-option lines, so target a single row deterministically.)
insert into public.cart_item_options (cart_item_id, product_option_id)
select ci.id, 'f3333333-3333-3333-3333-333333333333'::uuid
from public.cart_items ci
join public.carts c on c.id = ci.cart_id
where c.user_id = '31313131-3131-3131-3131-313131313131'
  and ci.product_id = 'd1111111-1111-1111-1111-111111111111'
  and (select count(*) from public.cart_item_options x where x.cart_item_id = ci.id) = 1
order by ci.id
limit 1;

set constraints all deferred;

-- ============================================================
-- DUPLICATE REPAIR (as owner)
-- ============================================================

reset role;

-- Repair fixtures (owner-owned; the repair function runs as owner).
insert into public.carts (id, user_id)
values
  ('c4444444-4444-4444-4444-444444444444', '34343434-3434-3434-3434-343434343434'),
  ('c5555555-5555-5555-5555-555555555555', '35353535-3535-3535-3535-353535353535');

insert into public.cart_items (id, cart_id, product_id, quantity)
values
  ('b4444441-1111-1111-1111-111111111111', 'c4444444-4444-4444-4444-444444444444', 'd2222222-2222-2222-2222-222222222222', 2),
  ('b4444441-2222-2222-2222-222222222222', 'c4444444-4444-4444-4444-444444444444', 'd2222222-2222-2222-2222-222222222222', 3),
  ('b4444441-3333-3333-3333-333333333333', 'c4444444-4444-4444-4444-444444444444', 'd1111111-1111-1111-1111-111111111111', 1),
  ('b5555551-1111-1111-1111-111111111111', 'c5555555-5555-5555-5555-555555555555', 'd2222222-2222-2222-2222-222222222222', 1);

-- The unrelated repair line carries one option so its identity differs.
insert into public.cart_item_options (cart_item_id, product_option_id)
values ('b4444441-3333-3333-3333-333333333333', 'f1111111-1111-1111-1111-111111111111');

-- TEST 37
select lives_ok(
  $$ select public.repair_duplicate_cart_lines() $$,
  'Repair merges pre-existing duplicate lines'
);

-- TEST 38
select is(
  (
    select count(*)::int
    from public.cart_items
    where cart_id = 'c4444444-4444-4444-4444-444444444444'
      and product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  1,
  'Duplicate pair collapses to one line'
);

-- TEST 39
select is(
  (
    select quantity
    from public.cart_items
    where cart_id = 'c4444444-4444-4444-4444-444444444444'
      and product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  5,
  'Repair preserves the summed quantity (2 + 3, no clamping)'
);

-- TEST 40
select is(
  (
    select count(*)::int
    from public.cart_items
    where cart_id = 'c4444444-4444-4444-4444-444444444444'
      and product_id = 'd1111111-1111-1111-1111-111111111111'
  ),
  1,
  'Unrelated line in the same cart is untouched'
);

-- TEST 41
select is(
  (
    select count(*)::int
    from public.cart_items
    where cart_id = 'c5555555-5555-5555-5555-555555555555'
      and product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  1,
  'Unrelated cart is untouched'
);

-- Seed a duplicate group whose sum exceeds the limit: 1 + 60 + 60 = 121.
insert into public.cart_items (id, cart_id, product_id, quantity)
values
  ('b5555551-2222-2222-2222-222222222222', 'c5555555-5555-5555-5555-555555555555', 'd2222222-2222-2222-2222-222222222222', 60),
  ('b5555551-3333-3333-3333-333333333333', 'c5555555-5555-5555-5555-555555555555', 'd2222222-2222-2222-2222-222222222222', 60);

-- TEST 42
select throws_ok(
  $$ select public.repair_duplicate_cart_lines() $$,
  'P0001',
  null,
  'Repair aborts when a duplicate group sums beyond the limit'
);

-- TEST 43
select is(
  (
    select count(*)::int
    from public.cart_items
    where cart_id = 'c5555555-5555-5555-5555-555555555555'
      and product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  3,
  'Aborted repair changes nothing (all three lines remain)'
);

-- TEST 44
select is(
  (
    select coalesce(sum(quantity), 0)::int
    from public.cart_items
    where cart_id = 'c5555555-5555-5555-5555-555555555555'
      and product_id = 'd2222222-2222-2222-2222-222222222222'
  ),
  121,
  'Aborted repair loses no quantity'
);

-- Clean the seeded conflict so the final state is invariant-clean.
delete from public.cart_items
where id in (
  'b5555551-2222-2222-2222-222222222222',
  'b5555551-3333-3333-3333-333333333333'
);

-- TEST 45
select lives_ok(
  $$ set constraints all immediate $$,
  'Final state passes the uniqueness invariant'
);

rollback;
