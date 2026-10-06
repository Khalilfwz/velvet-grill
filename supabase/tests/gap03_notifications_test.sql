begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- ============================================================
-- GAP-03: persistent in-app notifications for locked events.
--
-- Proves the producers added in migration 20261006000002:
--   - update_order_status writes ONE ORDER notification on genuine
--     CONFIRMED / READY / COMPLETED / CANCELLED transitions;
--   - PREPARING is not a notification event;
--   - confirm_order_payment writes ONE PAYMENT notification on a
--     genuine PAID transition;
--   - retries / same-status replays create no duplicate;
--   - the BUG-02 READY + UNPAID -> COMPLETED gate is preserved
--     (22023) and writes neither a notification nor history;
--   - the recipient is derived from orders.user_id (null -> none);
--   - produced rows stay owner-scoped under RLS.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'gap03-customer-a@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'gap03-customer-b@test.local'
  ),
  (
    '37373737-3737-3737-3737-373737373737',
    'gap03-admin@test.local'
  );

update public.profiles
set full_name = 'GAP-03 Customer A'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'GAP-03 Customer B'
where id = '33333333-3333-3333-3333-333333333333';

update public.profiles
set full_name = 'GAP-03 Admin', role = 'ADMIN'
where id = '37373737-3737-3737-3737-373737373737';

-- o1 CONFIRMED path        PENDING_PAYMENT/UNPAID CASH (customer A)
-- o2 PREPARING (no notify)  CONFIRMED/UNPAID       CASH
-- o3 READY path             PREPARING/UNPAID       CASH
-- o4 reject + pay + complete READY/UNPAID          CASH
-- o5 CANCELLED path         PENDING_PAYMENT/UNPAID CASH
-- o6 same-status replay     COMPLETED/PAID         DUMMY_QRIS
-- o7 digital PAYMENT        CONFIRMED/PENDING      DUMMY_QRIS
-- o8 orphan (user_id null)  PENDING_PAYMENT/UNPAID CASH
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
    'b0300000-0000-4000-8000-000000000001',
    'VG-GAP03-001',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'PENDING_PAYMENT'
  ),
  (
    'b0300000-0000-4000-8000-000000000002',
    'VG-GAP03-002',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'CONFIRMED'
  ),
  (
    'b0300000-0000-4000-8000-000000000003',
    'VG-GAP03-003',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'PREPARING'
  ),
  (
    'b0300000-0000-4000-8000-000000000004',
    'VG-GAP03-004',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'READY'
  ),
  (
    'b0300000-0000-4000-8000-000000000005',
    'VG-GAP03-005',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'PENDING_PAYMENT'
  ),
  (
    'b0300000-0000-4000-8000-000000000006',
    'VG-GAP03-006',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'PAID',
    'COMPLETED'
  ),
  (
    'b0300000-0000-4000-8000-000000000007',
    'VG-GAP03-007',
    '11111111-1111-1111-1111-111111111111',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'GAP-03 Customer A',
    100000, 0, 100000,
    'PENDING',
    'CONFIRMED'
  ),
  (
    'b0300000-0000-4000-8000-000000000008',
    'VG-GAP03-008',
    null,
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'Orphaned Order',
    100000, 0, 100000,
    'UNPAID',
    'PENDING_PAYMENT'
  );

insert into public.payments (id, order_id, method, status, amount)
values
  ('c0300000-0000-4000-8000-000000000001', 'b0300000-0000-4000-8000-000000000001', 'CASH', 'UNPAID', 100000),
  ('c0300000-0000-4000-8000-000000000002', 'b0300000-0000-4000-8000-000000000002', 'CASH', 'UNPAID', 100000),
  ('c0300000-0000-4000-8000-000000000003', 'b0300000-0000-4000-8000-000000000003', 'CASH', 'UNPAID', 100000),
  ('c0300000-0000-4000-8000-000000000004', 'b0300000-0000-4000-8000-000000000004', 'CASH', 'UNPAID', 100000),
  ('c0300000-0000-4000-8000-000000000005', 'b0300000-0000-4000-8000-000000000005', 'CASH', 'UNPAID', 100000),
  ('c0300000-0000-4000-8000-000000000006', 'b0300000-0000-4000-8000-000000000006', 'DUMMY_QRIS', 'PAID', 100000),
  ('c0300000-0000-4000-8000-000000000007', 'b0300000-0000-4000-8000-000000000007', 'DUMMY_QRIS', 'PENDING', 100000),
  ('c0300000-0000-4000-8000-000000000008', 'b0300000-0000-4000-8000-000000000008', 'CASH', 'UNPAID', 100000);

-- ============================================================
-- PHASE A: authoritative RPC calls (as admin)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '37373737-3737-3737-3737-373737373737';

-- A1
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000001', 'CONFIRMED')::text),
  'CONFIRMED',
  'PENDING_PAYMENT -> CONFIRMED succeeds'
);

-- A2
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000002', 'PREPARING')::text),
  'PREPARING',
  'CONFIRMED -> PREPARING succeeds (cash, unpaid)'
);

-- A3
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000003', 'READY')::text),
  'READY',
  'PREPARING -> READY succeeds'
);

-- A4: BUG-02 gate preserved (READY + UNPAID cannot complete)
select throws_ok(
  $$
    select public.update_order_status(
      'b0300000-0000-4000-8000-000000000004', 'COMPLETED'
    )
  $$,
  '22023',
  'Order is not eligible for completion',
  'READY + UNPAID -> COMPLETED still rejected (BUG-02 gate)'
);

-- A5
select is(
  (select public.confirm_order_payment(
    'b0300000-0000-4000-8000-000000000004')::text),
  'PAID',
  'Admin confirms the cash payment'
);

-- A6: idempotent replay
select is(
  (select public.confirm_order_payment(
    'b0300000-0000-4000-8000-000000000004')::text),
  'PAID',
  'Payment confirmation replay returns PAID'
);

-- A7
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000004', 'COMPLETED')::text),
  'COMPLETED',
  'READY + PAID -> COMPLETED succeeds'
);

-- A8: same-status replay
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000004', 'COMPLETED')::text),
  'COMPLETED',
  'Same-status COMPLETED replay returns COMPLETED'
);

-- A9
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000005', 'CANCELLED')::text),
  'CANCELLED',
  'PENDING_PAYMENT -> CANCELLED succeeds'
);

-- A10: same-status replay on an already-completed order
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000006', 'COMPLETED')::text),
  'COMPLETED',
  'COMPLETED same-status replay returns COMPLETED'
);

-- A11
select is(
  (select public.confirm_order_payment(
    'b0300000-0000-4000-8000-000000000007')::text),
  'PAID',
  'Digital payment confirmation succeeds'
);

-- A12: orphaned order (user_id null) still transitions
select is(
  (select public.update_order_status(
    'b0300000-0000-4000-8000-000000000008', 'CONFIRMED')::text),
  'CONFIRMED',
  'Orphaned order (user_id null) still transitions'
);

-- ============================================================
-- PHASE B: inspect produced notifications as owner
-- ============================================================

reset role;

-- B1
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000001'),
  1::bigint,
  'CONFIRMED writes exactly one notification'
);

-- B2: recipient derived from orders.user_id, correct content
select is(
  (select n.user_id::text || '/' || n.type::text || '/' ||
          n.is_read::text || '/' || n.title
   from public.notifications n
   where n.order_id = 'b0300000-0000-4000-8000-000000000001'),
  '11111111-1111-1111-1111-111111111111/ORDER/false/Order confirmed',
  'Notification recipient is the order owner with ORDER/unread content'
);

-- B3
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000002'),
  0::bigint,
  'PREPARING writes no notification'
);

-- B4
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000003'
     and type = 'ORDER'),
  1::bigint,
  'READY writes one ORDER notification'
);

-- B5
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000004'),
  2::bigint,
  'Order 4 has exactly two notifications (payment + completion)'
);

-- B6: the rejected completion added no duplicate
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000004'
     and type = 'ORDER' and title = 'Order completed'),
  1::bigint,
  'Rejected completion produced no ORDER notification (no duplicate)'
);

-- B7
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000004'
     and type = 'PAYMENT' and title = 'Payment received'),
  1::bigint,
  'Payment confirmation wrote exactly one PAYMENT notification'
);

-- B8
select is(
  (select order_status from public.orders
   where id = 'b0300000-0000-4000-8000-000000000004'),
  'COMPLETED'::public.order_status,
  'Order 4 is COMPLETED'
);

-- B9: rejected attempt wrote no history; only the real completion did
select is(
  (select count(*) from public.order_status_history
   where order_id = 'b0300000-0000-4000-8000-000000000004'),
  1::bigint,
  'Order 4 has exactly one history row (rejected attempt wrote none)'
);

-- B10
select is(
  (select count(*) from public.order_status_history
   where order_id = 'b0300000-0000-4000-8000-000000000004'
     and from_status = 'READY' and to_status = 'COMPLETED'),
  1::bigint,
  'Order 4 history records the single READY -> COMPLETED transition'
);

-- B11
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000005'
     and title = 'Order cancelled'),
  1::bigint,
  'CANCELLED writes one cancellation notification'
);

-- B12
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000006'),
  0::bigint,
  'Same-status COMPLETED replay writes no notification'
);

-- B13
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000007'
     and type = 'PAYMENT'),
  1::bigint,
  'Digital payment confirmation wrote one PAYMENT notification'
);

-- B14
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000008'),
  0::bigint,
  'Orphaned order (user_id null) writes no notification'
);

-- ============================================================
-- PHASE C: produced rows stay owner-scoped under RLS
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '33333333-3333-3333-3333-333333333333';

-- C1
select is(
  (select count(*) from public.notifications
   where order_id = 'b0300000-0000-4000-8000-000000000001'),
  0::bigint,
  'Customer B cannot see Customer A notifications'
);

select * from finish();

rollback;
