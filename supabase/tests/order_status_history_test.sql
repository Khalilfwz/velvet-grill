begin;

create extension if not exists pgtap with schema extensions;

select plan(44);

-- ============================================================
-- FR-18: order status history.
--
-- Proves: create_order records one initial NULL -> PENDING_PAYMENT
-- event atomically; update_order_status is admin-only, enforces
-- the documented structural transitions and the payment gate for
-- CONFIRMED -> PREPARING, and writes the status change and its
-- history row atomically; history is immutable to clients; and
-- legacy pre-FR18 orders stay safe (no backfill, first transition
-- records their real previous status).
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '17171717-1717-1717-1717-171717171717',
    'fr18-customer-a@test.local'
  ),
  (
    '27272727-2727-2727-2727-272727272727',
    'fr18-customer-b@test.local'
  ),
  (
    '37373737-3737-3737-3737-373737373737',
    'fr18-admin@test.local'
  );

update public.profiles
set full_name = 'FR-18 Customer A'
where id = '17171717-1717-1717-1717-171717171717';

update public.profiles
set full_name = 'FR-18 Customer B'
where id = '27272727-2727-2727-2727-272727272727';

update public.profiles
set full_name = 'FR-18 Admin', role = 'ADMIN'
where id = '37373737-3737-3737-3737-373737373737';

insert into public.categories (id, name, slug, is_active)
values (
  'c1818181-1111-1111-1111-111111111111',
  'FR-18 Category',
  'fr18-category',
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
  'd1818181-1111-1111-1111-111111111111',
  'c1818181-1111-1111-1111-111111111111',
  'FR-18 Product',
  'fr18-product',
  100000,
  10,
  true
);

insert into public.carts (id, user_id)
values (
  'a1818181-1111-1111-1111-111111111111',
  '17171717-1717-1717-1717-171717171717'
);

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1818181-1111-1111-1111-111111111111',
  'a1818181-1111-1111-1111-111111111111',
  'd1818181-1111-1111-1111-111111111111',
  2
);

-- ============================================================
-- PRIVILEGE / WRITE-DENIAL
-- ============================================================

-- T1
select is(
  has_function_privilege(
    'anon',
    'public.update_order_status(uuid,public.order_status,text)',
    'EXECUTE'
  ),
  false,
  'anon cannot execute public.update_order_status'
);

-- T2
select is(
  has_function_privilege(
    'authenticated',
    'public.update_order_status(uuid,public.order_status,text)',
    'EXECUTE'
  ),
  true,
  'authenticated can execute public.update_order_status'
);

-- T3
select is(
  has_table_privilege(
    'authenticated', 'public.order_status_history', 'INSERT'
  ),
  false,
  'authenticated cannot insert into order_status_history'
);

-- T4
select is(
  (
    select count(*)
    from (
      values
        (has_table_privilege(
          'authenticated', 'public.order_status_history', 'UPDATE'
        )),
        (has_table_privilege(
          'authenticated', 'public.order_status_history', 'DELETE'
        ))
    ) as t(granted)
    where t.granted
  ),
  0::bigint,
  'authenticated has no UPDATE/DELETE privilege on order_status_history'
);

-- T5
select is(
  has_column_privilege(
    'authenticated', 'public.orders', 'order_status', 'UPDATE'
  ),
  false,
  'authenticated cannot update orders.order_status directly'
);

-- ============================================================
-- CUSTOMER A creates a CASH order and a digital order.
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

select set_config(
  'fr18.oa',
  (
    select public.create_order(
      'PICKUP', 'FR-18 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr18-oa', 'CASH'
    )::text
  ),
  true
);

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1818182-2222-2222-2222-222222222222',
  'a1818181-1111-1111-1111-111111111111',
  'd1818181-1111-1111-1111-111111111111',
  2
);

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

select set_config(
  'fr18.od',
  (
    select public.create_order(
      'PICKUP', 'FR-18 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr18-od', 'DUMMY_QRIS'
    )::text
  ),
  true
);

-- ============================================================
-- INITIAL HISTORY
-- ============================================================

-- T6
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  1::bigint,
  'create_order writes exactly one initial history row'
);

-- T7
select is(
  (
    select from_status
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  null::public.order_status,
  'Initial history row has from_status NULL'
);

-- T8
select is(
  (
    select to_status
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  'PENDING_PAYMENT'::public.order_status,
  'Initial history row has to_status PENDING_PAYMENT'
);

-- T9
select is(
  (
    select changed_by
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  '17171717-1717-1717-1717-171717171717'::uuid,
  'Initial history row records the creating customer'
);

-- ============================================================
-- create_order IDEMPOTENCY DOES NOT DUPLICATE THE INITIAL ROW
-- ============================================================

select set_config(
  'fr18.oa_replay',
  (
    select public.create_order(
      'PICKUP', 'FR-18 Customer A', null, null,
      '2026-01-05T12:00', null, 'fr18-oa', 'CASH'
    )::text
  ),
  true
);

-- T10
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  1::bigint,
  'Replaying create_order adds no second initial history row'
);

-- ============================================================
-- LEGACY / MISMATCH FIXTURES (inserted as the owner)
-- ============================================================

reset role;

-- OH: historical pre-FR18 order, no payment row.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values (
  '18181818-1111-1111-1111-111111111111',
  'VG-FR18-HIST',
  '17171717-1717-1717-1717-171717171717',
  'PICKUP',
  now() + interval '2 hours',
  'FR-18 Customer A',
  100000, 0, 100000,
  'UNPAID',
  'PENDING_PAYMENT'
);

-- OC1: CONFIRMED, one digital row, orders=PENDING but payments=PAID.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values (
  '1c1c1c1c-1111-1111-1111-111111111111',
  'VG-FR18-OC1',
  '17171717-1717-1717-1717-171717171717',
  'PICKUP',
  now() + interval '2 hours',
  'FR-18 Customer A',
  100000, 0, 100000,
  'PENDING',
  'CONFIRMED'
);

insert into public.payments (id, order_id, method, status, amount, paid_at)
values (
  '1d1d1d1d-1111-1111-1111-111111111111',
  '1c1c1c1c-1111-1111-1111-111111111111',
  'DUMMY_QRIS', 'PAID', 100000, now()
);

-- OC2: CONFIRMED, one digital row, orders=PAID but payments=PENDING.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values (
  '1c2c2c2c-2222-2222-2222-222222222222',
  'VG-FR18-OC2',
  '17171717-1717-1717-1717-171717171717',
  'PICKUP',
  now() + interval '2 hours',
  'FR-18 Customer A',
  100000, 0, 100000,
  'PAID',
  'CONFIRMED'
);

insert into public.payments (id, order_id, method, status, amount)
values (
  '1d2d2d2d-2222-2222-2222-222222222222',
  '1c2c2c2c-2222-2222-2222-222222222222',
  'DUMMY_QRIS', 'PENDING', 100000
);

-- OM: CONFIRMED, two digital payment rows.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, subtotal, discount_total, final_total,
  payment_status, order_status
)
values (
  '1a1a1a1a-1111-1111-1111-111111111111',
  'VG-FR18-OM',
  '17171717-1717-1717-1717-171717171717',
  'PICKUP',
  now() + interval '2 hours',
  'FR-18 Customer A',
  100000, 0, 100000,
  'PENDING',
  'CONFIRMED'
);

insert into public.payments (id, order_id, method, status, amount)
values
  (
    '1d3d3d3d-3333-3333-3333-333333333333',
    '1a1a1a1a-1111-1111-1111-111111111111',
    'DUMMY_QRIS', 'PENDING', 100000
  ),
  (
    '1d4d4d4d-4444-4444-4444-444444444444',
    '1a1a1a1a-1111-1111-1111-111111111111',
    'DUMMY_QRIS', 'PENDING', 100000
  );

-- ============================================================
-- ADMIN: CASH ALLOWED PATH (incl. cash PREPARING while UNPAID)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- T11
select is(
  (
    select public.update_order_status(
      current_setting('fr18.oa')::uuid, 'CONFIRMED'
    )::text
  ),
  'CONFIRMED',
  'Admin confirms a PENDING_PAYMENT cash order'
);

-- T12
select is(
  (
    select order_status
    from public.orders
    where id = current_setting('fr18.oa')::uuid
  ),
  'CONFIRMED'::public.order_status,
  'Order status is CONFIRMED after the transition'
);

-- T13
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  2::bigint,
  'Allowed transition adds exactly one history entry'
);

-- T14
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
      and from_status = 'PENDING_PAYMENT'
      and to_status = 'CONFIRMED'
  ),
  1::bigint,
  'History entry records from PENDING_PAYMENT to CONFIRMED'
);

-- T15
select is(
  (
    select changed_by
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
      and to_status = 'CONFIRMED'
  ),
  '37373737-3737-3737-3737-373737373737'::uuid,
  'History entry records the acting admin'
);

-- T16
select is(
  (
    select public.update_order_status(
      current_setting('fr18.oa')::uuid, 'PREPARING'
    )::text
  ),
  'PREPARING',
  'A CASH order may enter PREPARING while payment is UNPAID'
);

-- T17
select is(
  (
    select o.order_status::text || '/' ||
      (select count(*)
       from public.order_status_history h
       where h.order_id = o.id)::text
    from public.orders o
    where o.id = current_setting('fr18.oa')::uuid
  ),
  'PREPARING/3',
  'Cash order is PREPARING with three history rows'
);

-- ============================================================
-- ILLEGAL STRUCTURAL TRANSITION
-- ============================================================

-- T18
select throws_ok(
  $$
    select public.update_order_status(
      current_setting('fr18.oa')::uuid, 'COMPLETED'
    )
  $$,
  '22023',
  'Order status transition is not allowed',
  'PREPARING -> COMPLETED is rejected'
);

-- T19
select is(
  (
    select o.order_status::text || '/' ||
      (select count(*)
       from public.order_status_history h
       where h.order_id = o.id)::text
    from public.orders o
    where o.id = current_setting('fr18.oa')::uuid
  ),
  'PREPARING/3',
  'Rejected illegal transition changed neither status nor history'
);

-- ============================================================
-- DIGITAL GATE: ALLOWED PATH
-- ============================================================

-- T20
select is(
  (
    select public.update_order_status(
      current_setting('fr18.od')::uuid, 'CONFIRMED'
    )::text
  ),
  'CONFIRMED',
  'Digital order can be confirmed while payment is PENDING'
);

-- T21
select is(
  (
    select o.order_status::text || '/' || o.payment_status::text
    from public.orders o
    where o.id = current_setting('fr18.od')::uuid
  ),
  'CONFIRMED/PENDING',
  'Digital order is CONFIRMED with payment still PENDING'
);

-- T22
select throws_ok(
  $$
    select public.update_order_status(
      current_setting('fr18.od')::uuid, 'PREPARING'
    )
  $$,
  '22023',
  'Order is not eligible to enter preparation',
  'Unpaid digital order cannot enter PREPARING'
);

-- T23
select is(
  (
    select o.order_status::text || '/' ||
      (select count(*)
       from public.order_status_history h
       where h.order_id = o.id)::text
    from public.orders o
    where o.id = current_setting('fr18.od')::uuid
  ),
  'CONFIRMED/2',
  'Rejected digital PREPARING changed neither status nor history'
);

-- Owner confirms the digital payment, then the transition is allowed.
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

select set_config(
  'fr18.od_pay',
  (
    select public.confirm_order_payment(
      current_setting('fr18.od')::uuid
    )::text
  ),
  true
);

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- T24
select is(
  (
    select o.payment_status::text || '/' || p.status::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.id = current_setting('fr18.od')::uuid
  ),
  'PAID/PAID',
  'After confirmation both order and payment states are PAID'
);

-- T25
select is(
  (
    select public.update_order_status(
      current_setting('fr18.od')::uuid, 'PREPARING'
    )::text
  ),
  'PREPARING',
  'Paid digital order can enter PREPARING'
);

-- T26
select is(
  (
    select o.order_status::text || '/' ||
      (select count(*)
       from public.order_status_history h
       where h.order_id = o.id)::text
    from public.orders o
    where o.id = current_setting('fr18.od')::uuid
  ),
  'PREPARING/3',
  'Paid digital order is PREPARING with three history rows'
);

-- ============================================================
-- DIGITAL GATE: MISMATCH AND FAIL-CLOSED
-- ============================================================

-- T27
select throws_ok(
  $$
    select public.update_order_status(
      '1c1c1c1c-1111-1111-1111-111111111111', 'PREPARING'
    )
  $$,
  '22023',
  'Order is not eligible to enter preparation',
  'Mismatched digital order (orders PENDING / payments PAID) is rejected'
);

-- T28
select is(
  (
    select o.order_status::text || '/' ||
      (select count(*)
       from public.order_status_history h
       where h.order_id = o.id)::text
    from public.orders o
    where o.id = '1c1c1c1c-1111-1111-1111-111111111111'
  ),
  'CONFIRMED/0',
  'Rejected mismatched transition changed neither status nor history'
);

-- T29
select throws_ok(
  $$
    select public.update_order_status(
      '1c2c2c2c-2222-2222-2222-222222222222', 'PREPARING'
    )
  $$,
  '22023',
  'Order is not eligible to enter preparation',
  'Mismatched digital order (orders PAID / payments PENDING) is rejected'
);

-- T30
select throws_ok(
  $$
    select public.update_order_status(
      '1a1a1a1a-1111-1111-1111-111111111111', 'PREPARING'
    )
  $$,
  '22023',
  'Order is not eligible to enter preparation',
  'Multiple payment rows fail closed'
);

-- ============================================================
-- UNAUTHORIZED / NOT-FOUND
-- ============================================================

set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- T31
select throws_ok(
  $$
    select public.update_order_status(
      current_setting('fr18.oa')::uuid, 'COMPLETED'
    )
  $$,
  '42501',
  'Order status cannot be changed',
  'A customer cannot change order status'
);

-- T32
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  3::bigint,
  'Unauthorized attempt added no history row'
);

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- T33
select throws_ok(
  $$
    select public.update_order_status(
      '99999999-9999-9999-9999-999999999999', 'CONFIRMED'
    )
  $$,
  '42501',
  'Order status cannot be changed',
  'Transition on a non-existent order is rejected'
);

-- ============================================================
-- READ ISOLATION
-- ============================================================

set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- T34
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  3::bigint,
  'Customer reads their own order history'
);

set local request.jwt.claim.sub =
  '27272727-2727-2727-2727-272727272727';

-- T35
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = current_setting('fr18.oa')::uuid
  ),
  0::bigint,
  'Another customer cannot read that history'
);

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- T36
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id in (
      current_setting('fr18.oa')::uuid,
      current_setting('fr18.od')::uuid,
      '18181818-1111-1111-1111-111111111111',
      '1c1c1c1c-1111-1111-1111-111111111111',
      '1c2c2c2c-2222-2222-2222-222222222222',
      '1a1a1a1a-1111-1111-1111-111111111111'
    )
  ),
  6::bigint,
  'Admin reads all fixture history'
);

-- ============================================================
-- DIRECT HISTORY MUTATION IS DENIED
-- ============================================================

set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- T37
select throws_ok(
  $$
    insert into public.order_status_history (
      order_id, from_status, to_status, changed_by
    )
    values (
      current_setting('fr18.oa')::uuid,
      'PENDING_PAYMENT', 'CONFIRMED',
      '17171717-1717-1717-1717-171717171717'
    )
  $$,
  '42501',
  null,
  'Customer cannot insert order status history directly'
);

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- T38
select throws_ok(
  $$
    insert into public.order_status_history (
      order_id, from_status, to_status, changed_by
    )
    values (
      current_setting('fr18.oa')::uuid,
      'PENDING_PAYMENT', 'CONFIRMED',
      '37373737-3737-3737-3737-373737373737'
    )
  $$,
  '42501',
  null,
  'Admin cannot insert order status history directly'
);

-- ============================================================
-- HISTORICAL ORDER: NO FABRICATED INITIAL EVENT
-- ============================================================

-- T39
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = '18181818-1111-1111-1111-111111111111'
  ),
  0::bigint,
  'Historical order starts with zero history rows'
);

-- T40
select is(
  (
    select public.update_order_status(
      '18181818-1111-1111-1111-111111111111', 'CONFIRMED'
    )::text
  ),
  'CONFIRMED',
  'Historical order first transition succeeds'
);

-- T41
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = '18181818-1111-1111-1111-111111111111'
  ),
  1::bigint,
  'Historical first transition creates exactly one history row'
);

-- T42
select is(
  (
    select from_status
    from public.order_status_history
    where order_id = '18181818-1111-1111-1111-111111111111'
  ),
  'PENDING_PAYMENT'::public.order_status,
  'Historical first transition records the real previous status'
);

-- T43
select is(
  (
    select to_status
    from public.order_status_history
    where order_id = '18181818-1111-1111-1111-111111111111'
  ),
  'CONFIRMED'::public.order_status,
  'Historical first transition records the requested new status'
);

-- T44
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = '18181818-1111-1111-1111-111111111111'
      and from_status is null
  ),
  0::bigint,
  'No fabricated NULL -> PENDING_PAYMENT row for the historical order'
);

select * from finish();

rollback;
