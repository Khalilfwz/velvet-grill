begin;

create extension if not exists pgtap with schema extensions;

select plan(31);

-- ============================================================
-- FR-21: prevent overselling when stock is enabled.
--
-- Stock is always-on and authoritative. This suite proves:
--   * the guarded mutation primitive (is_available AND stock >= qty);
--   * successful checkout decrements stock exactly once;
--   * boundary behavior (exact remaining, zero, insufficient);
--   * a failed stock attempt rolls back with no side effects and no
--     stock consumption;
--   * the normal unavailable-product regression path;
--   * idempotent replay never decrements stock twice;
--   * multi-product atomicity and summed duplicate cart lines;
--   * a non-admin cannot mutate stock directly (RLS).
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- No seed/manual data is required.
-- ============================================================

insert into auth.users (id, email)
values (
  'a2121212-1111-1111-1111-111111111111',
  'fr21-customer@test.local'
);

insert into public.categories (id, name, slug, is_active)
values (
  'c2121212-1111-1111-1111-111111111111',
  'FR-21 Category',
  'fr21-category',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values
  (
    'd2100001-0000-0000-0000-000000000001',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Primitive Low', 'fr21-prim-low', 100000, 1, true
  ),
  (
    'd2100002-0000-0000-0000-000000000002',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Primitive Ok', 'fr21-prim-ok', 100000, 10, true
  ),
  (
    'd2100003-0000-0000-0000-000000000003',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Primitive Unavailable', 'fr21-prim-unavail', 100000, 10, false
  ),
  (
    'd2100011-0000-0000-0000-000000000011',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Success', 'fr21-success-p', 100000, 10, true
  ),
  (
    'd2100012-0000-0000-0000-000000000012',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Exact', 'fr21-exact-p', 100000, 5, true
  ),
  (
    'd2100013-0000-0000-0000-000000000013',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Insufficient', 'fr21-insuff-p', 100000, 3, true
  ),
  (
    'd2100014-0000-0000-0000-000000000014',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Replay', 'fr21-replay-p', 100000, 10, true
  ),
  (
    'd2100015-0000-0000-0000-000000000015',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Multi A', 'fr21-multi-a', 100000, 10, true
  ),
  (
    'd2100016-0000-0000-0000-000000000016',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Multi B', 'fr21-multi-b', 100000, 10, true
  ),
  (
    'd2100017-0000-0000-0000-000000000017',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Independent', 'fr21-independent', 100000, 10, true
  ),
  (
    'd2100018-0000-0000-0000-000000000018',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Multi Insuf A', 'fr21-mi-a', 100000, 10, true
  ),
  (
    'd2100019-0000-0000-0000-000000000019',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Multi Insuf B', 'fr21-mi-b', 100000, 1, true
  ),
  (
    'd2100020-0000-0000-0000-000000000020',
    'c2121212-1111-1111-1111-111111111111',
    'FR-21 Duplicate', 'fr21-dup-p', 100000, 10, true
  );

insert into public.product_option_groups (
  id, product_id, name, selection_type, min_selections, max_selections,
  is_required, sort_order, is_active
)
values (
  'f2100001-0000-0000-0000-000000000001',
  'd2100013-0000-0000-0000-000000000013',
  'FR-21 Choice', 'SINGLE', 0, 1, false, 0, true
);

insert into public.product_options (
  id, group_id, name, price_delta, is_available, sort_order
)
values (
  'f2100002-0000-0000-0000-000000000002',
  'f2100001-0000-0000-0000-000000000001',
  'FR-21 Option', 0, true, 0
);

insert into public.carts (id, user_id)
values (
  'e2121212-1111-1111-1111-111111111111',
  'a2121212-1111-1111-1111-111111111111'
);

insert into public.coupons (
  id, code, discount_type, discount_value, max_discount_amount,
  min_order_subtotal, starts_at, ends_at, usage_limit, per_customer_limit,
  is_active
)
values (
  'ab212121-1111-1111-1111-111111111111',
  'FR21', 'FIXED_AMOUNT', 10000, null, 0,
  now() - interval '1 day', now() + interval '30 days', null, null, true
);

-- ============================================================
-- A. Guarded-mutation primitive
-- ============================================================

-- T1
with u as (
  update public.products
  set stock = stock - 2
  where id = 'd2100001-0000-0000-0000-000000000001'
    and is_available = true
    and stock >= 2
  returning 1
)
select is(
  (select count(*) from u)::text || '/' ||
    (select stock::text from public.products
     where id = 'd2100001-0000-0000-0000-000000000001'),
  '0/1',
  'T1 guarded UPDATE with insufficient stock affects 0 rows and leaves stock unchanged'
);

-- T2
with u as (
  update public.products
  set stock = stock - 2
  where id = 'd2100003-0000-0000-0000-000000000003'
    and is_available = true
    and stock >= 2
  returning 1
)
select is(
  (select count(*) from u)::text || '/' ||
    (select stock::text from public.products
     where id = 'd2100003-0000-0000-0000-000000000003'),
  '0/10',
  'T2 guarded UPDATE on an unavailable product affects 0 rows and leaves stock unchanged'
);

-- T3
with u as (
  update public.products
  set stock = stock - 2
  where id = 'd2100002-0000-0000-0000-000000000002'
    and is_available = true
    and stock >= 2
  returning stock
)
select is(
  (select count(*) from u)::text || '/' || (select stock::text from u),
  '1/8',
  'T3 guarded UPDATE on available sufficient stock affects 1 row and decrements correctly'
);

-- ============================================================
-- B. Success path
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100301-0000-0000-0000-000000000301',
  'e2121212-1111-1111-1111-111111111111',
  'd2100011-0000-0000-0000-000000000011',
  2
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

-- T4
select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-success', 'CASH'
    )
  $$,
  'T4 sufficient-stock create_order succeeds'
);

reset role;

-- T5
select is(
  (
    select stock from public.products
    where id = 'd2100011-0000-0000-0000-000000000011'
  ),
  8,
  'T5 stock is decremented by exactly the ordered quantity'
);

-- T6
select is(
  (
    select count(*) from public.orders
    where user_id = 'a2121212-1111-1111-1111-111111111111'
      and idempotency_key = 'fr21-success'
  ),
  1::bigint,
  'T6 exactly one order is created'
);

-- T7
select is(
  (
    select count(*)
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-success'
  ),
  1::bigint,
  'T7 exactly one payment is recorded'
);

-- T8
select is(
  (
    select count(*)
    from public.order_status_history h
    join public.orders o on o.id = h.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-success'
  ),
  1::bigint,
  'T8 exactly one initial status-history row is recorded'
);

-- T9
select is(
  (
    select count(*) from public.cart_items
    where cart_id = 'e2121212-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'T9 the ordered cart items are consumed'
);

-- ============================================================
-- C. Boundaries: exact remaining, zero, insufficient
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100302-0000-0000-0000-000000000302',
  'e2121212-1111-1111-1111-111111111111',
  'd2100012-0000-0000-0000-000000000012',
  5
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

-- T10
select lives_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-exact', 'CASH'
    )
  $$,
  'T10 an order for the exact remaining stock succeeds'
);

reset role;

-- T11
select is(
  (
    select stock from public.products
    where id = 'd2100012-0000-0000-0000-000000000012'
  ),
  0,
  'T11 the exact remaining order reaches exactly zero'
);

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100303-0000-0000-0000-000000000303',
  'e2121212-1111-1111-1111-111111111111',
  'd2100012-0000-0000-0000-000000000012',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

-- T12
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-zero', 'CASH'
    )
  $$,
  '22023',
  'Some items are no longer available',
  'T12 a product at stock zero is rejected'
);

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100304-0000-0000-0000-000000000304',
  'e2121212-1111-1111-1111-111111111111',
  'd2100013-0000-0000-0000-000000000013',
  4
);

insert into public.cart_item_options (cart_item_id, product_option_id)
values (
  'e2100304-0000-0000-0000-000000000304',
  'f2100002-0000-0000-0000-000000000002'
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

-- T13
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-fail', 'CASH', 'FR21'
    )
  $$,
  '22023',
  'Some items are no longer available',
  'T13 insufficient stock is rejected with the generic error'
);

reset role;

-- T14
select is(
  (
    select stock from public.products
    where id = 'd2100013-0000-0000-0000-000000000013'
  ),
  3,
  'T14 a failed stock attempt leaves stock unchanged'
);

-- T15
select is(
  (
    select count(*) from public.orders
    where user_id = 'a2121212-1111-1111-1111-111111111111'
      and idempotency_key = 'fr21-fail'
  ),
  0::bigint,
  'T15 a failed stock attempt leaves no order'
);

-- T16
select is(
  (
    select count(*)
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-fail'
  ),
  0::bigint,
  'T16 a failed stock attempt leaves no order_items'
);

-- T17
select is(
  (
    select count(*)
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-fail'
  ),
  0::bigint,
  'T17 a failed stock attempt leaves no payment'
);

-- T18
select is(
  (
    select count(*)
    from public.order_status_history h
    join public.orders o on o.id = h.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-fail'
  ),
  0::bigint,
  'T18 a failed stock attempt leaves no status history'
);

-- T19
select is(
  (
    select count(*) from public.coupon_usages
    where user_id = 'a2121212-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'T19 a failed stock attempt leaves no coupon_usage'
);

-- T20
select is(
  (
    select count(*) from public.cart_items
    where cart_id = 'e2121212-1111-1111-1111-111111111111'
  )::text
  || '/' ||
  (
    select count(*)
    from public.cart_item_options cio
    join public.cart_items ci on ci.id = cio.cart_item_id
    where ci.cart_id = 'e2121212-1111-1111-1111-111111111111'
  )::text,
  '1/1',
  'T20 a failed stock attempt leaves cart_items and cart_item_options intact'
);

-- ============================================================
-- D. Unavailable-product regression path
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100305-0000-0000-0000-000000000305',
  'e2121212-1111-1111-1111-111111111111',
  'd2100003-0000-0000-0000-000000000003',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

-- T21
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-unavail', 'CASH'
    )
  $$,
  '22023',
  'Some items are no longer available',
  'T21 create_order rejects an unavailable product (regression path)'
);

reset role;

-- T22
select is(
  (
    select stock from public.products
    where id = 'd2100003-0000-0000-0000-000000000003'
  ),
  10,
  'T22 an unavailable product attempt leaves stock unchanged'
);

-- T23
select is(
  (
    select count(*) from public.orders
    where user_id = 'a2121212-1111-1111-1111-111111111111'
      and idempotency_key = 'fr21-unavail'
  )::text
  || '/' ||
  (
    select count(*)
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-unavail'
  )::text
  || '/' ||
  (
    select count(*)
    from public.order_status_history h
    join public.orders o on o.id = h.order_id
    where o.user_id = 'a2121212-1111-1111-1111-111111111111'
      and o.idempotency_key = 'fr21-unavail'
  )::text,
  '0/0/0',
  'T23 an unavailable product attempt leaves no order state'
);

-- ============================================================
-- E. Idempotency: replay never decrements twice
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100306-0000-0000-0000-000000000306',
  'e2121212-1111-1111-1111-111111111111',
  'd2100014-0000-0000-0000-000000000014',
  2
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

select set_config(
  'fr21.rep1',
  (
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-replay', 'CASH'
    )::text
  ),
  true
);

select set_config(
  'fr21.rep2',
  (
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-replay', 'CASH'
    )::text
  ),
  true
);

reset role;

-- T24
select is(
  current_setting('fr21.rep1'),
  current_setting('fr21.rep2'),
  'T24 an exact replay returns the same order id'
);

-- T25
select is(
  (
    select stock from public.products
    where id = 'd2100014-0000-0000-0000-000000000014'
  ),
  8,
  'T25 an exact replay does not decrement stock again'
);

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'e2100307-0000-0000-0000-000000000307',
  'e2121212-1111-1111-1111-111111111111',
  'd2100014-0000-0000-0000-000000000014',
  1
);

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

select set_config(
  'fr21.rep3',
  (
    select public.create_order(
      'PICKUP', 'FR-21 Customer', '+620000000009', 'different note',
      '2026-01-05T12:00', null, 'fr21-replay', 'DUMMY_QRIS'
    )::text
  ),
  true
);

reset role;

-- T26
select is(
  current_setting('fr21.rep3') || '/' ||
    (
      select stock::text from public.products
      where id = 'd2100014-0000-0000-0000-000000000014'
    ),
  current_setting('fr21.rep1') || '/8',
  'T26 a conflicting-input replay returns the original and does not mutate stock'
);

-- ============================================================
-- F. Multi-product atomicity
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values
  (
    'e2100308-0000-0000-0000-000000000308',
    'e2121212-1111-1111-1111-111111111111',
    'd2100015-0000-0000-0000-000000000015',
    2
  ),
  (
    'e2100309-0000-0000-0000-000000000309',
    'e2121212-1111-1111-1111-111111111111',
    'd2100016-0000-0000-0000-000000000016',
    3
  );

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

select set_config(
  'fr21.multi',
  (
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-multi', 'CASH'
    )::text
  ),
  true
);

reset role;

-- T27
select is(
  (
    select stock::text from public.products
    where id = 'd2100015-0000-0000-0000-000000000015'
  ) || '/' ||
  (
    select stock::text from public.products
    where id = 'd2100016-0000-0000-0000-000000000016'
  ),
  '8/7',
  'T27 multi-product success decrements all products correctly'
);

-- T28
select is(
  (
    select stock from public.products
    where id = 'd2100017-0000-0000-0000-000000000017'
  ),
  10,
  'T28 an independent product is untouched'
);

-- ============================================================
-- G. Duplicate cart lines for one product
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values
  (
    'e2100310-0000-0000-0000-000000000310',
    'e2121212-1111-1111-1111-111111111111',
    'd2100020-0000-0000-0000-000000000020',
    1
  ),
  (
    'e2100311-0000-0000-0000-000000000311',
    'e2121212-1111-1111-1111-111111111111',
    'd2100020-0000-0000-0000-000000000020',
    2
  );

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

select set_config(
  'fr21.dup',
  (
    select public.create_order(
      'PICKUP', 'FR-21 Customer', null, null,
      '2026-01-05T12:00', null, 'fr21-dup', 'CASH'
    )::text
  ),
  true
);

reset role;

-- T29
select is(
  (
    select stock from public.products
    where id = 'd2100020-0000-0000-0000-000000000020'
  ),
  7,
  'T29 duplicate cart lines for one product decrement the summed quantity'
);

-- ============================================================
-- H. One insufficient product fails the whole multi-product order
-- ============================================================

reset role;

delete from public.cart_items
where cart_id = 'e2121212-1111-1111-1111-111111111111';

insert into public.cart_items (id, cart_id, product_id, quantity)
values
  (
    'e2100312-0000-0000-0000-000000000312',
    'e2121212-1111-1111-1111-111111111111',
    'd2100018-0000-0000-0000-000000000018',
    1
  ),
  (
    'e2100313-0000-0000-0000-000000000313',
    'e2121212-1111-1111-1111-111111111111',
    'd2100019-0000-0000-0000-000000000019',
    2
  );

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

select set_config('fr21.multifail_raised', 'f', true);

do $$
begin
  perform public.create_order(
    'PICKUP', 'FR-21 Customer', null, null,
    '2026-01-05T12:00', null, 'fr21-multifail', 'CASH'
  );
exception
  when others then
    perform set_config('fr21.multifail_raised', 't', true);
end;
$$;

reset role;

-- T30
select is(
  current_setting('fr21.multifail_raised') || '/' ||
    (
      select stock::text from public.products
      where id = 'd2100018-0000-0000-0000-000000000018'
    ) || '/' ||
    (
      select stock::text from public.products
      where id = 'd2100019-0000-0000-0000-000000000019'
    ) || '/' ||
    (
      select count(*) from public.orders
      where user_id = 'a2121212-1111-1111-1111-111111111111'
        and idempotency_key = 'fr21-multifail'
    )::text,
  't/10/1/0',
  'T30 one insufficient product fails the entire multi-product order; neither product is decremented and no order exists'
);

-- ============================================================
-- I. Server authority: non-admin cannot mutate stock directly
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'a2121212-1111-1111-1111-111111111111';

-- T31
select throws_ok(
  $$
    update public.products
    set stock = stock - 1
    where id = 'd2100011-0000-0000-0000-000000000011'
  $$,
  '42501',
  null,
  'T31 a non-admin direct product stock UPDATE is denied'
);

select * from finish();

rollback;
