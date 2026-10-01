begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

-- ============================================================
-- FR-17: payment state is modeled separately from order state.
--
-- Proves: create_order records the chosen method and the
-- authoritative initial state; cash is confirmed by staff only;
-- dummy digital payments are confirmed by their owner; state
-- consistency between orders.payment_status and payments.status
-- is enforced; and neither customer nor admin can write payment
-- state directly (only the SECURITY DEFINER RPCs can).
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '17171717-1717-1717-1717-171717171717',
    'fr17-customer-a@test.local'
  ),
  (
    '27272727-2727-2727-2727-272727272727',
    'fr17-customer-b@test.local'
  ),
  (
    '37373737-3737-3737-3737-373737373737',
    'fr17-admin@test.local'
  );

update public.profiles
set full_name = 'FR-17 Customer A'
where id = '17171717-1717-1717-1717-171717171717';

update public.profiles
set full_name = 'FR-17 Customer B'
where id = '27272727-2727-2727-2727-272727272727';

update public.profiles
set full_name = 'FR-17 Admin', role = 'ADMIN'
where id = '37373737-3737-3737-3737-373737373737';

insert into public.categories (id, name, slug, is_active)
values (
  'c1717171-1111-1111-1111-111111111111',
  'FR-17 Category',
  'fr17-category',
  true
);

-- base_price 100000, quantity 2 => a 200000 order total.
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
  'd1717171-1111-1111-1111-111111111111',
  'c1717171-1111-1111-1111-111111111111',
  'FR-17 Product',
  'fr17-product',
  100000,
  10,
  true
);

insert into public.carts (id, user_id)
values (
  'a1717171-1111-1111-1111-111111111111',
  '17171717-1717-1717-1717-171717171717'
);

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1717171-1111-1111-1111-111111111111',
  'a1717171-1111-1111-1111-111111111111',
  'd1717171-1111-1111-1111-111111111111',
  2
);

-- ============================================================
-- WRITE DENIAL (privileges)
-- ============================================================

-- TEST 1
select is(
  has_function_privilege('anon', 'public.confirm_order_payment(uuid)', 'EXECUTE'),
  false,
  'anon cannot execute public.confirm_order_payment'
);

-- TEST 2
select is(
  has_function_privilege(
    'authenticated', 'public.confirm_order_payment(uuid)', 'EXECUTE'
  ),
  true,
  'authenticated can execute public.confirm_order_payment'
);

-- TEST 3
select is(
  has_column_privilege(
    'authenticated', 'public.orders', 'payment_status', 'UPDATE'
  ),
  false,
  'authenticated cannot update orders.payment_status directly'
);

-- TEST 4
select is(
  (
    select count(*)
    from (
      values
        (has_table_privilege('authenticated', 'public.payments', 'INSERT')),
        (has_table_privilege('authenticated', 'public.payments', 'UPDATE')),
        (has_table_privilege('authenticated', 'public.payments', 'DELETE'))
    ) as t(granted)
    where t.granted
  ),
  0::bigint,
  'authenticated has no INSERT/UPDATE/DELETE privilege on payments'
);

-- ============================================================
-- CUSTOMER A
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- TEST 5
select throws_ok(
  $$
    select public.create_order(
      'PICKUP', 'FR-17 Customer A', null, null,
      now() + interval '2 hours', null, 'fr17-null-method',
      null::public.payment_method
    )
  $$,
  '22023',
  'Payment method is invalid',
  'Order creation rejects a missing payment method'
);

-- ------------------------------------------------------------
-- CASH order
-- ------------------------------------------------------------

select set_config(
  'fr17.cash_order',
  (
    select public.create_order(
      'PICKUP', 'FR-17 Customer A', null, null,
      now() + interval '2 hours', null, 'fr17-cash', 'CASH'
    )::text
  ),
  true
);

-- TEST 6
select is(
  (
    select payment_status
    from public.orders
    where id = current_setting('fr17.cash_order')::uuid
  ),
  'UNPAID'::public.payment_status,
  'Cash order starts with orders.payment_status UNPAID'
);

-- TEST 7
select is(
  (
    select method
    from public.payments
    where order_id = current_setting('fr17.cash_order')::uuid
  ),
  'CASH'::public.payment_method,
  'Cash order records the CASH payment method'
);

-- TEST 8
select is(
  (
    select status
    from public.payments
    where order_id = current_setting('fr17.cash_order')::uuid
  ),
  'UNPAID'::public.payment_status,
  'Cash payment row starts UNPAID'
);

-- ------------------------------------------------------------
-- DUMMY_QRIS order
-- ------------------------------------------------------------

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1717172-2222-2222-2222-222222222222',
  'a1717171-1111-1111-1111-111111111111',
  'd1717171-1111-1111-1111-111111111111',
  2
);

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

select set_config(
  'fr17.qris_order',
  (
    select public.create_order(
      'PICKUP', 'FR-17 Customer A', null, null,
      now() + interval '2 hours', null, 'fr17-qris', 'DUMMY_QRIS'
    )::text
  ),
  true
);

-- TEST 9
select is(
  (
    select payment_status
    from public.orders
    where id = current_setting('fr17.qris_order')::uuid
  ),
  'PENDING'::public.payment_status,
  'Digital order starts with orders.payment_status PENDING'
);

-- TEST 10
select is(
  (
    select method
    from public.payments
    where order_id = current_setting('fr17.qris_order')::uuid
  ),
  'DUMMY_QRIS'::public.payment_method,
  'QRIS order records the DUMMY_QRIS payment method'
);

-- TEST 11
select is(
  (
    select status
    from public.payments
    where order_id = current_setting('fr17.qris_order')::uuid
  ),
  'PENDING'::public.payment_status,
  'QRIS payment row starts PENDING'
);

-- ------------------------------------------------------------
-- DUMMY_BANK_TRANSFER order
-- ------------------------------------------------------------

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1717173-3333-3333-3333-333333333333',
  'a1717171-1111-1111-1111-111111111111',
  'd1717171-1111-1111-1111-111111111111',
  2
);

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

select set_config(
  'fr17.bank_order',
  (
    select public.create_order(
      'PICKUP', 'FR-17 Customer A', null, null,
      now() + interval '2 hours', null, 'fr17-bank', 'DUMMY_BANK_TRANSFER'
    )::text
  ),
  true
);

-- TEST 12
select is(
  (
    select method
    from public.payments
    where order_id = current_setting('fr17.bank_order')::uuid
  ),
  'DUMMY_BANK_TRANSFER'::public.payment_method,
  'Bank-transfer order records the DUMMY_BANK_TRANSFER method'
);

-- TEST 13
select is(
  (
    select status
    from public.payments
    where order_id = current_setting('fr17.bank_order')::uuid
  ),
  'PENDING'::public.payment_status,
  'Bank-transfer payment row starts PENDING'
);

-- TEST 14
select is(
  (
    select count(*)
    from public.payments
    where order_id = current_setting('fr17.qris_order')::uuid
  ),
  1::bigint,
  'An order has exactly one payment row'
);

-- TEST 15
select is(
  (
    select amount
    from public.payments
    where order_id = current_setting('fr17.qris_order')::uuid
  ),
  (
    select final_total
    from public.orders
    where id = current_setting('fr17.qris_order')::uuid
  ),
  'Payment amount equals the authoritative order total'
);

-- ============================================================
-- create_order IDEMPOTENCY WITH PAYMENTS
-- ============================================================

select set_config(
  'fr17.qris_replay',
  (
    select public.create_order(
      'PICKUP', 'FR-17 Customer A', null, null,
      now() + interval '2 hours', null, 'fr17-qris', 'DUMMY_QRIS'
    )::text
  ),
  true
);

-- TEST 16
select is(
  current_setting('fr17.qris_replay'),
  current_setting('fr17.qris_order'),
  'Replaying the same idempotency key returns the same order'
);

-- TEST 17
select is(
  (
    select count(*)
    from public.payments
    where order_id = current_setting('fr17.qris_order')::uuid
  ),
  1::bigint,
  'Replay does not create a second payment attempt'
);

-- ============================================================
-- DIRECT PAYMENT-STATE WRITES ARE DENIED FOR THE ADMIN BROWSER
-- ============================================================

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- TEST 18
select throws_ok(
  $$
    update public.orders
    set payment_status = 'PAID'
    where idempotency_key = 'fr17-qris'
  $$,
  '42501',
  null,
  'Admin cannot change orders.payment_status directly'
);

-- TEST 19
select throws_ok(
  $$
    update public.payments
    set status = 'PAID'
    where order_id = (
      select id from public.orders where idempotency_key = 'fr17-qris'
    )
  $$,
  '42501',
  null,
  'Admin cannot change payment status directly'
);

-- ============================================================
-- CUSTOMER CASH CONFIRMATION IS DENIED (BEFORE PAID)
-- ============================================================

set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- TEST 20
select throws_ok(
  $$
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-cash')
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'Customer cannot confirm a cash payment'
);

-- TEST 21
select is(
  (
    select payment_status
    from public.orders
    where idempotency_key = 'fr17-cash'
  ),
  'UNPAID'::public.payment_status,
  'Rejected cash confirmation leaves orders.payment_status UNPAID'
);

-- TEST 22
select is(
  (
    select p.status
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.idempotency_key = 'fr17-cash'
  ),
  'UNPAID'::public.payment_status,
  'Rejected cash confirmation leaves the payment row UNPAID'
);

-- ============================================================
-- ADMIN CONFIRMS CASH
-- ============================================================

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- TEST 23
select is(
  (
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-cash')
    )::text
  ),
  'PAID',
  'Admin confirms the cash payment'
);

-- TEST 24
select is(
  (
    select p.status
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.idempotency_key = 'fr17-cash'
  ),
  'PAID'::public.payment_status,
  'Admin cash confirmation sets the payment row PAID'
);

-- TEST 25
select is(
  (
    select p.paid_at is not null
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.idempotency_key = 'fr17-cash'
  ),
  true,
  'Admin cash confirmation records paid_at'
);

-- TEST 26
select is(
  (
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-cash')
    )::text
  ),
  'PAID',
  'Admin re-confirming a paid cash payment is a no-op'
);

-- ============================================================
-- CUSTOMER CASH CONFIRMATION IS DENIED (AFTER PAID)
-- ============================================================

set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- TEST 27
select throws_ok(
  $$
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-cash')
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'Customer cannot confirm a cash payment even after it is paid'
);

-- ============================================================
-- OWNER CONFIRMS A DIGITAL PAYMENT (QRIS)
-- ============================================================

-- TEST 28
select is(
  (
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-qris')
    )::text
  ),
  'PAID',
  'Owner confirms their QRIS payment'
);

-- TEST 29
select is(
  (
    select p.status
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.idempotency_key = 'fr17-qris'
  ),
  'PAID'::public.payment_status,
  'Owner QRIS confirmation sets the payment row PAID'
);

-- TEST 30
select is(
  (
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-qris')
    )::text
  ),
  'PAID',
  'Owner re-confirming a paid digital payment is a no-op'
);

-- ============================================================
-- OWNER CONFIRMS A DIGITAL PAYMENT (BANK TRANSFER)
-- ============================================================

-- TEST 31
select is(
  (
    select public.confirm_order_payment(
      (select id from public.orders where idempotency_key = 'fr17-bank')
    )::text
  ),
  'PAID',
  'Owner confirms their bank-transfer payment'
);

-- TEST 32
select is(
  (
    select p.status
    from public.payments p
    join public.orders o on o.id = p.order_id
    where o.idempotency_key = 'fr17-bank'
  ),
  'PAID'::public.payment_status,
  'Owner bank-transfer confirmation sets the payment row PAID'
);

-- ============================================================
-- CROSS-USER CONFIRMATION IS DENIED
-- ============================================================

reset role;

insert into public.cart_items (id, cart_id, product_id, quantity)
values (
  'b1717174-4444-4444-4444-444444444444',
  'a1717171-1111-1111-1111-111111111111',
  'd1717171-1111-1111-1111-111111111111',
  2
);

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

select set_config(
  'fr17.cross_order',
  (
    select public.create_order(
      'PICKUP', 'FR-17 Customer A', null, null,
      now() + interval '2 hours', null, 'fr17-cross', 'DUMMY_QRIS'
    )::text
  ),
  true
);

set local request.jwt.claim.sub =
  '27272727-2727-2727-2727-272727272727';

-- TEST 33
select throws_ok(
  $$
    select public.confirm_order_payment(
      current_setting('fr17.cross_order')::uuid
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'Another customer cannot confirm a payment'
);

reset role;

-- TEST 34
select is(
  (
    select payment_status
    from public.orders
    where id = current_setting('fr17.cross_order')::uuid
  ),
  'PENDING'::public.payment_status,
  'An unauthorized attempt leaves the payment unchanged'
);

-- ============================================================
-- ZERO OR MULTIPLE PAYMENT ROWS FAIL SAFELY
-- ============================================================

insert into public.orders (
  id,
  order_number,
  user_id,
  fulfillment_type,
  pickup_at,
  customer_name_snapshot,
  subtotal,
  discount_total,
  final_total,
  payment_status
)
values
  (
    'e1717171-1111-1111-1111-111111111111',
    'VG-FR17-ZERO',
    '17171717-1717-1717-1717-171717171717',
    'PICKUP',
    now() + interval '2 hours',
    'FR-17 Customer A',
    100000,
    0,
    100000,
    'UNPAID'
  ),
  (
    'e1717172-2222-2222-2222-222222222222',
    'VG-FR17-MULTI',
    '17171717-1717-1717-1717-171717171717',
    'PICKUP',
    now() + interval '2 hours',
    'FR-17 Customer A',
    100000,
    0,
    100000,
    'PENDING'
  );

insert into public.payments (id, order_id, method, status, amount)
values
  (
    'f1717172-2222-2222-2222-222222222222',
    'e1717172-2222-2222-2222-222222222222',
    'DUMMY_QRIS',
    'PENDING',
    100000
  ),
  (
    'f1717173-3333-3333-3333-333333333333',
    'e1717172-2222-2222-2222-222222222222',
    'DUMMY_QRIS',
    'PENDING',
    100000
  );

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- TEST 35
select throws_ok(
  $$
    select public.confirm_order_payment(
      'e1717171-1111-1111-1111-111111111111'
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'An order with no payment row cannot be confirmed'
);

-- TEST 36
select throws_ok(
  $$
    select public.confirm_order_payment(
      'e1717172-2222-2222-2222-222222222222'
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'An order with multiple payment rows cannot be confirmed'
);

-- ============================================================
-- INCONSISTENT ORDER/PAYMENT STATE IS REJECTED AND NOT REPAIRED
-- ============================================================

reset role;

insert into public.orders (
  id,
  order_number,
  user_id,
  fulfillment_type,
  pickup_at,
  customer_name_snapshot,
  subtotal,
  discount_total,
  final_total,
  payment_status
)
values (
  'e1717173-3333-3333-3333-333333333333',
  'VG-FR17-MISMATCH',
  '17171717-1717-1717-1717-171717171717',
  'PICKUP',
  now() + interval '2 hours',
  'FR-17 Customer A',
  100000,
  0,
  100000,
  'PENDING'
);

insert into public.payments (id, order_id, method, status, amount, paid_at)
values (
  'f1717174-4444-4444-4444-444444444444',
  'e1717173-3333-3333-3333-333333333333',
  'DUMMY_QRIS',
  'PAID',
  100000,
  now()
);

set local role authenticated;
set local request.jwt.claim.sub =
  '17171717-1717-1717-1717-171717171717';

-- TEST 37
select throws_ok(
  $$
    select public.confirm_order_payment(
      'e1717173-3333-3333-3333-333333333333'
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'Inconsistent order/payment state is rejected'
);

-- TEST 38
select is(
  (
    select o.payment_status::text || '/' || p.status::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.id = 'e1717173-3333-3333-3333-333333333333'
  ),
  'PENDING/PAID',
  'Inconsistent state is unchanged after the rejected attempt'
);

-- ============================================================
-- CASH CANNOT USE THE PENDING STATE (CHECK, OWNER CONTEXT)
-- ============================================================

reset role;

-- TEST 39
select throws_ok(
  $$
    insert into public.payments (order_id, method, status, amount)
    values (
      'e1717171-1111-1111-1111-111111111111',
      'CASH',
      'PENDING',
      1
    )
  $$,
  '23514',
  null,
  'A cash payment cannot be PENDING (constraint, not RLS)'
);

select * from finish();

rollback;
