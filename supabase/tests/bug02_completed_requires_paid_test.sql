begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- ============================================================
-- BUG-02: an order may not become COMPLETED unless it is PAID.
--
-- Proves the READY -> COMPLETED gate added to
-- public.update_order_status (migration 20261006000001):
--   - CASH READY + UNPAID is rejected (22023) and writes no history;
--   - CASH READY + PAID succeeds, with PAID reached through the real
--     public.confirm_order_payment flow;
--   - DIGITAL READY + PAID still succeeds;
--   - the CONFIRMED -> PREPARING digital payment gate is unchanged;
--   - the same-status COMPLETED replay stays idempotent;
--   - authorization is unchanged;
--   - confirm_order_payment keeps orders.payment_status and
--     payments.status consistent and is idempotent.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'bug02-customer@test.local'
  ),
  (
    '37373737-3737-3737-3737-373737373737',
    'bug02-admin@test.local'
  );

update public.profiles
set full_name = 'BUG-02 Customer'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'BUG-02 Admin', role = 'ADMIN'
where id = '37373737-3737-3737-3737-373737373737';

-- Orders:
--   1 CASH    READY     UNPAID
--   2 CASH    READY     UNPAID   (advanced via confirm_order_payment)
--   3 DIGITAL READY     PAID
--   4 DIGITAL CONFIRMED PENDING  (digital PREPARING gate)
--   5 DIGITAL COMPLETED PAID     (replay)
--   6 CASH    READY     UNPAID   (legacy: no payments row)
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
  payment_status,
  order_status
)
values
  (
    'b0200000-0000-4000-8000-000000000001',
    'VG-BUG02-001',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'BUG-02 Customer',
    100000,
    0,
    100000,
    'UNPAID',
    'READY'
  ),
  (
    'b0200000-0000-4000-8000-000000000002',
    'VG-BUG02-002',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'BUG-02 Customer',
    100000,
    0,
    100000,
    'UNPAID',
    'READY'
  ),
  (
    'b0200000-0000-4000-8000-000000000003',
    'VG-BUG02-003',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'BUG-02 Customer',
    100000,
    0,
    100000,
    'PAID',
    'READY'
  ),
  (
    'b0200000-0000-4000-8000-000000000004',
    'VG-BUG02-004',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'BUG-02 Customer',
    100000,
    0,
    100000,
    'PENDING',
    'CONFIRMED'
  ),
  (
    'b0200000-0000-4000-8000-000000000005',
    'VG-BUG02-005',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'BUG-02 Customer',
    100000,
    0,
    100000,
    'PAID',
    'COMPLETED'
  ),
  (
    'b0200000-0000-4000-8000-000000000006',
    'VG-BUG02-006',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'BUG-02 Customer',
    100000,
    0,
    100000,
    'UNPAID',
    'READY'
  );

insert into public.payments (id, order_id, method, status, amount)
values
  (
    'c0200000-0000-4000-8000-000000000001',
    'b0200000-0000-4000-8000-000000000001',
    'CASH',
    'UNPAID',
    100000
  ),
  (
    'c0200000-0000-4000-8000-000000000002',
    'b0200000-0000-4000-8000-000000000002',
    'CASH',
    'UNPAID',
    100000
  ),
  (
    'c0200000-0000-4000-8000-000000000003',
    'b0200000-0000-4000-8000-000000000003',
    'DUMMY_QRIS',
    'PAID',
    100000
  ),
  (
    'c0200000-0000-4000-8000-000000000004',
    'b0200000-0000-4000-8000-000000000004',
    'DUMMY_QRIS',
    'PENDING',
    100000
  ),
  (
    'c0200000-0000-4000-8000-000000000005',
    'b0200000-0000-4000-8000-000000000005',
    'DUMMY_QRIS',
    'PAID',
    100000
  );

-- ============================================================
-- ADMIN CONTEXT
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- ============================================================
-- CASH READY + UNPAID -> COMPLETED is rejected, no history
-- ============================================================

-- T1
select throws_ok(
  $$
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000001', 'COMPLETED'
    )
  $$,
  '22023',
  'Order is not eligible for completion',
  'CASH READY + UNPAID cannot become COMPLETED'
);

-- T2
select is(
  (
    select order_status
    from public.orders
    where id = 'b0200000-0000-4000-8000-000000000001'
  ),
  'READY'::public.order_status,
  'Rejected completion leaves the order READY'
);

-- T3
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = 'b0200000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'Rejected completion writes no history row'
);

-- ============================================================
-- CASH READY + PAID -> COMPLETED succeeds (real confirm flow)
-- ============================================================

-- T4
select is(
  (
    select payment_status
    from public.orders
    where id = 'b0200000-0000-4000-8000-000000000002'
  ),
  'UNPAID'::public.payment_status,
  'CASH order starts UNPAID'
);

-- T5
select is(
  (
    select public.confirm_order_payment(
      'b0200000-0000-4000-8000-000000000002'
    )::text
  ),
  'PAID',
  'Admin confirms the CASH payment through confirm_order_payment'
);

-- T6
select is(
  (
    select o.payment_status::text || '/' || p.status::text
    from public.orders o
    join public.payments p on p.order_id = o.id
    where o.id = 'b0200000-0000-4000-8000-000000000002'
  ),
  'PAID/PAID',
  'confirm_order_payment sets both order and payment state to PAID'
);

-- T7
select is(
  (
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000002', 'COMPLETED'
    )::text
  ),
  'COMPLETED',
  'CASH READY + PAID can become COMPLETED'
);

-- T8
select is(
  (
    select order_status
    from public.orders
    where id = 'b0200000-0000-4000-8000-000000000002'
  ),
  'COMPLETED'::public.order_status,
  'Order is COMPLETED after the paid cash transition'
);

-- T9
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = 'b0200000-0000-4000-8000-000000000002'
      and from_status = 'READY'
      and to_status = 'COMPLETED'
  ),
  1::bigint,
  'Successful completion writes exactly one READY -> COMPLETED history row'
);

-- ============================================================
-- DIGITAL READY + PAID -> COMPLETED still succeeds
-- ============================================================

-- T10
select is(
  (
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000003', 'COMPLETED'
    )::text
  ),
  'COMPLETED',
  'DIGITAL READY + PAID can still become COMPLETED'
);

-- T11
select is(
  (
    select order_status
    from public.orders
    where id = 'b0200000-0000-4000-8000-000000000003'
  ),
  'COMPLETED'::public.order_status,
  'Paid digital order is COMPLETED'
);

-- ============================================================
-- DIGITAL CONFIRMED -> PREPARING gate is unchanged
-- ============================================================

-- T12
select throws_ok(
  $$
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000004', 'PREPARING'
    )
  $$,
  '22023',
  'Order is not eligible to enter preparation',
  'Unpaid digital order cannot enter PREPARING'
);

-- T13
select is(
  (
    select order_status
    from public.orders
    where id = 'b0200000-0000-4000-8000-000000000004'
  ),
  'CONFIRMED'::public.order_status,
  'Rejected digital PREPARING leaves the order CONFIRMED'
);

-- T14
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = 'b0200000-0000-4000-8000-000000000004'
  ),
  0::bigint,
  'Rejected digital PREPARING writes no history row'
);

-- T15
select is(
  (
    select public.confirm_order_payment(
      'b0200000-0000-4000-8000-000000000004'
    )::text
  ),
  'PAID',
  'Owner/admin confirms the digital payment'
);

-- T16
select is(
  (
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000004', 'PREPARING'
    )::text
  ),
  'PREPARING',
  'Paid digital order can still enter PREPARING'
);

-- ============================================================
-- SAME-STATUS COMPLETED REPLAY IS IDEMPOTENT
-- ============================================================

-- T17
select is(
  (
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000005', 'COMPLETED'
    )::text
  ),
  'COMPLETED',
  'Same-status COMPLETED replay returns COMPLETED'
);

-- T18
select is(
  (
    select count(*)
    from public.order_status_history
    where order_id = 'b0200000-0000-4000-8000-000000000005'
  ),
  0::bigint,
  'Same-status COMPLETED replay writes no history row'
);

-- ============================================================
-- AUTHORIZATION IS UNCHANGED
-- ============================================================

-- T19
select is(
  (
    select public.confirm_order_payment(
      'b0200000-0000-4000-8000-000000000002'
    )::text
  ),
  'PAID',
  'confirm_order_payment replay is idempotent'
);

set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- T20
select throws_ok(
  $$
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000001', 'COMPLETED'
    )
  $$,
  '42501',
  'Order status cannot be changed',
  'A customer cannot change order status'
);

set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- T21
select throws_ok(
  $$
    select public.update_order_status(
      '99999999-9999-9999-9999-999999999999', 'COMPLETED'
    )
  $$,
  '42501',
  'Order status cannot be changed',
  'A nonexistent order is rejected safely'
);

-- ============================================================
-- LEGACY ORDER WITHOUT A PAYMENT ROW CANNOT COMPLETE
-- ============================================================

-- T22
select throws_ok(
  $$
    select public.update_order_status(
      'b0200000-0000-4000-8000-000000000006', 'COMPLETED'
    )
  $$,
  '22023',
  'Order is not eligible for completion',
  'READY + UNPAID with no payment row cannot become COMPLETED'
);

-- T23
select is(
  (
    select order_status
    from public.orders
    where id = 'b0200000-0000-4000-8000-000000000006'
  ),
  'READY'::public.order_status,
  'Legacy order stays READY after rejected completion'
);

select * from finish();

rollback;
