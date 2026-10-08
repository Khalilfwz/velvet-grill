begin;

create extension if not exists pgtap with schema extensions;

select plan(34);

-- ============================================================
-- FR-33: order & payment lifecycle consistency.
--
-- Pins the one authoritative change of FR-33 and the corners it
-- touches:
--   - a CANCELLED order is terminal for payment confirmation:
--     confirm_order_payment raises 42501 and writes nothing for
--     (CANCELLED, digital PENDING) by the owner, (CANCELLED,
--     CASH UNPAID) by admin, and - the deliberate contract change -
--     for (CANCELLED, PAID+PAID) replays (previously a silent PAID);
--   - confirmation idempotency on NON-cancelled orders is unchanged:
--     (CONFIRMED, PAID+PAID) replay returns PAID with zero writes;
--   - legal confirmation paths still work for digital PENDING and
--     CASH UNPAID (paid_at set, exactly one PAYMENT notification);
--   - refund flows are unaffected: cancel-after-pay (CONFIRMED ->
--     CANCELLED via update_order_status) then refund -> REFUNDED
--     with order_status kept CANCELLED, coupon usage kept consumed,
--     no stock change, and an idempotent REFUNDED replay.
--
-- Zero-write assertions cover rows, paid_at, notification counts and
-- history counts. Notification counts are inspected after
-- `reset role` (as the table owner) because notifications SELECT is
-- owner-scoped under RLS - the same convention the GAP-03/FR-31
-- suites use. Direct payment-table write denial is already pinned by
-- the FR-31 suite and is not duplicated here.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

-- ============================================================
-- Fixtures
-- ============================================================

insert into auth.users (id, email)
values
  (
    'a0330000-0000-4000-8000-0000000000a1',
    'fr33-customer-a@test.local'
  ),
  (
    'c0330000-0000-4000-8000-0000000000c1',
    'fr33-admin@test.local'
  );

update public.profiles
set full_name = 'FR-33 Customer A'
where id = 'a0330000-0000-4000-8000-0000000000a1';

update public.profiles
set full_name = 'FR-33 Admin', role = 'ADMIN'
where id = 'c0330000-0000-4000-8000-0000000000c1';

-- Dedicated category/products/fixtures only (never the seed data).
insert into public.categories (
  id, name, slug, is_active
)
values (
  'd0330000-0000-4000-8000-0000000000c1',
  'FR-33 Test',
  'fr-33-test',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  'e0330000-0000-4000-8000-00000000000a',
  'd0330000-0000-4000-8000-0000000000c1',
  'FR-33 Product A',
  'fr-33-product-a',
  100000, 10, true
);

update public.products
set stock = 8
where id = 'e0330000-0000-4000-8000-00000000000a';
-- Simulates the FR-21 reservation for o04 (10 reserved - 2 = 8); the
-- refund in PHASE B must restore nothing (expiry-only rule).

insert into public.coupons (
  id,
  code,
  discount_type,
  discount_value,
  max_discount_amount,
  min_order_subtotal,
  starts_at,
  ends_at,
  usage_limit,
  per_customer_limit,
  is_active
)
values (
  'f0330000-0000-4000-8000-0000000000c2',
  'FR33TEST',
  'FIXED_AMOUNT',
  0,
  null,
  0,
  '2020-01-01T00:00:00Z',
  '2030-01-01T00:00:00Z',
  5,
  5,
  true
);

-- o01 fresh digital PENDING / PENDING_PAYMENT (owner confirms -> PAID)
-- o02 digital PENDING / CONFIRMED (owner confirms -> PAID)
-- o03 digital PENDING / CANCELLED  (owner confirm rejected: terminal)
-- o04 digital PAID / CONFIRMED     (owner replay -> PAID, zero writes;
--                                   later cancelled + refunded by admin)
-- o05 digital PAID / CANCELLED     (owner replay rejected: contract change)
-- o06 CASH PAID / CANCELLED        (admin replay rejected)
-- o07 CASH UNPAID / CANCELLED      (admin confirm rejected)
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
    'f0330000-0000-4000-8000-000000000001',
    'VG-FR33-001',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    100000, 0, 100000,
    'PENDING',
    'PENDING_PAYMENT'
  ),
  (
    'f0330000-0000-4000-8000-000000000002',
    'VG-FR33-002',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    100000, 0, 100000,
    'PENDING',
    'CONFIRMED'
  ),
  (
    'f0330000-0000-4000-8000-000000000003',
    'VG-FR33-003',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    100000, 0, 100000,
    'PENDING',
    'CANCELLED'
  ),
  (
    'f0330000-0000-4000-8000-000000000004',
    'VG-FR33-004',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    200000, 0, 200000,
    'PAID',
    'CONFIRMED'
  ),
  (
    'f0330000-0000-4000-8000-000000000005',
    'VG-FR33-005',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    100000, 0, 100000,
    'PAID',
    'CANCELLED'
  ),
  (
    'f0330000-0000-4000-8000-000000000006',
    'VG-FR33-006',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    100000, 0, 100000,
    'PAID',
    'CANCELLED'
  ),
  (
    'f0330000-0000-4000-8000-000000000007',
    'VG-FR33-007',
    'a0330000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-33 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'CANCELLED'
  );

insert into public.payments (
  id, order_id, method, status, amount, created_at, paid_at
)
values
  (
    'bf033000-0000-4000-8000-000000000001',
    'f0330000-0000-4000-8000-000000000001',
    'DUMMY_QRIS', 'PENDING', 100000,
    now(), null
  ),
  (
    'bf033000-0000-4000-8000-000000000002',
    'f0330000-0000-4000-8000-000000000002',
    'DUMMY_BANK_TRANSFER', 'PENDING', 100000,
    now(), null
  ),
  (
    'bf033000-0000-4000-8000-000000000003',
    'f0330000-0000-4000-8000-000000000003',
    'DUMMY_QRIS', 'PENDING', 100000,
    now(), null
  ),
  (
    'bf033000-0000-4000-8000-000000000004',
    'f0330000-0000-4000-8000-000000000004',
    'DUMMY_QRIS', 'PAID', 200000,
    now() - interval '1 hour',
    '2026-01-05T10:00:00Z'
  ),
  (
    'bf033000-0000-4000-8000-000000000005',
    'f0330000-0000-4000-8000-000000000005',
    'DUMMY_QRIS', 'PAID', 100000,
    now() - interval '1 hour',
    '2026-01-05T10:00:00Z'
  ),
  (
    'bf033000-0000-4000-8000-000000000006',
    'f0330000-0000-4000-8000-000000000006',
    'CASH', 'PAID', 100000,
    now() - interval '1 hour',
    '2026-01-05T10:00:00Z'
  ),
  (
    'bf033000-0000-4000-8000-000000000007',
    'f0330000-0000-4000-8000-000000000007',
    'CASH', 'UNPAID', 100000,
    now(), null
  );

-- o04 line item: product A qty 2 (matches the simulated reservation).
insert into public.order_items (
  id,
  order_id,
  product_id,
  product_name_snapshot,
  base_price_snapshot,
  final_unit_price,
  quantity,
  subtotal
)
values
  (
    'a0330000-0000-4000-8000-000000000101',
    'f0330000-0000-4000-8000-000000000004',
    'e0330000-0000-4000-8000-00000000000a',
    'FR-33 Product A',
    100000, 100000, 2, 200000
  );

-- Coupon usage for o04: kept consumed by the refund.
insert into public.coupon_usages (
  coupon_id, order_id, user_id, discount_amount
)
values
  (
    'f0330000-0000-4000-8000-0000000000c2',
    'f0330000-0000-4000-8000-000000000004',
    'a0330000-0000-4000-8000-0000000000a1',
    0
  );

-- ============================================================
-- PHASE A: owner confirmations (customer A emulated)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'a0330000-0000-4000-8000-0000000000a1';

-- A1: legal path 1 - digital PENDING on PENDING_PAYMENT order.
select is(
  (select public.confirm_order_payment(
    'f0330000-0000-4000-8000-000000000001')::text),
  'PAID',
  'owner confirms digital PENDING on a PENDING_PAYMENT order'
);

-- A2
select is(
  (select p.status::text || '/' || o.payment_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0330000-0000-4000-8000-000000000001'),
  'PAID/PAID',
  'o01 confirmation keeps both representations consistent'
);

-- A3
select is(
  (select (p.paid_at is not null)::text
   from public.payments p
   where p.order_id = 'f0330000-0000-4000-8000-000000000001'),
  'true',
  'o01 confirmation sets paid_at'
);

-- A4
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000001'
     and type = 'PAYMENT' and title = 'Payment received'),
  1::bigint,
  'o01 confirmation writes exactly one PAYMENT notification'
);

-- A5: legal path 2 - digital PENDING on a CONFIRMED order (bank transfer).
select is(
  (select public.confirm_order_payment(
    'f0330000-0000-4000-8000-000000000002')::text),
  'PAID',
  'owner confirms digital PENDING on a CONFIRMED order'
);

-- A6
select is(
  (select p.status::text || '/' || o.payment_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0330000-0000-4000-8000-000000000002'),
  'PAID/PAID',
  'o02 confirmation keeps both representations consistent'
);

-- A7
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000002'
     and type = 'PAYMENT' and title = 'Payment received'),
  1::bigint,
  'o02 confirmation writes exactly one PAYMENT notification'
);

-- A8: FR-33 guard - cancelled order + still-PENDING digital payment.
select throws_ok(
  $$
    select public.confirm_order_payment(
      'f0330000-0000-4000-8000-000000000003'
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'confirming a still-PENDING payment on a CANCELLED order is rejected'
);

-- A9: the rejected attempt wrote nothing.
select is(
  (select p.status::text || '/' || (p.paid_at is null)::text
   from public.payments p
   where p.order_id = 'f0330000-0000-4000-8000-000000000003'),
  'PENDING/true',
  'rejected o03 confirm leaves the payment PENDING with paid_at null'
);

-- A10
select is(
  (select o.payment_status::text || '/' || o.order_status::text
   from public.orders o
   where o.id = 'f0330000-0000-4000-8000-000000000003'),
  'PENDING/CANCELLED',
  'rejected o03 confirm leaves the order untouched'
);

-- A11
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000003'),
  0::bigint,
  'rejected o03 confirm writes no notification'
);

-- A12
select is(
  (select count(*) from public.order_status_history
   where order_id = 'f0330000-0000-4000-8000-000000000003'),
  0::bigint,
  'rejected o03 confirm writes no history row'
);

-- A13: replay idempotency intact on NON-cancelled orders.
select is(
  (select public.confirm_order_payment(
    'f0330000-0000-4000-8000-000000000004')::text),
  'PAID',
  'PAID replay on a CONFIRMED order still returns PAID'
);

-- A14: the replay wrote nothing (paid_at untouched).
select is(
  (select (p.paid_at = '2026-01-05T10:00:00Z'::timestamptz)::text
   from public.payments p
   where p.order_id = 'f0330000-0000-4000-8000-000000000004'),
  'true',
  'o04 replay leaves paid_at exactly as before'
);

-- A15
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000004'),
  0::bigint,
  'o04 replay writes no duplicate notification'
);

reset role;

-- ============================================================
-- PHASE B: admin confirmations, cancellation and refund
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'c0330000-0000-4000-8000-0000000000c1';

-- B1: FR-33 guard - cancelled CASH order, admin confirm attempt.
select throws_ok(
  $$
    select public.confirm_order_payment(
      'f0330000-0000-4000-8000-000000000007'
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'admin confirming an UNPAID cash payment on a CANCELLED order is rejected'
);

-- B2
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0330000-0000-4000-8000-000000000007'),
  'UNPAID/UNPAID/CANCELLED',
  'rejected o07 admin confirm leaves everything untouched'
);

-- B4: the deliberate contract change - PAID replay on a CANCELLED order.
select throws_ok(
  $$
    select public.confirm_order_payment(
      'f0330000-0000-4000-8000-000000000006'
    )
  $$,
  '42501',
  'Payment cannot be confirmed',
  'PAID replay on a CANCELLED cash order now rejects (was silent PAID)'
);

-- B5
select is(
  (select (p.paid_at = '2026-01-05T10:00:00Z'::timestamptz)::text
   from public.payments p
   where p.order_id = 'f0330000-0000-4000-8000-000000000006'),
  'true',
  'rejected o06 replay leaves paid_at untouched'
);

-- B6
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0330000-0000-4000-8000-000000000006'),
  'PAID/PAID/CANCELLED',
  'rejected o06 replay leaves the consistent PAID pair untouched'
);

-- B8: a failed confirm is not an audited admin action (no rows exist).
select is(
  (select count(*) from public.admin_audit_logs
   where entity_id in (
     'f0330000-0000-4000-8000-000000000006',
     'bf033000-0000-4000-8000-000000000006'
   )),
  0::bigint,
  'rejected admin confirm produces no audit rows'
);

-- B9: cancel-after-pay through the legal graph edge.
select is(
  (select public.update_order_status(
    'f0330000-0000-4000-8000-000000000004', 'CANCELLED')::text),
  'CANCELLED',
  'CONFIRMED -> CANCELLED on a PAID digital order succeeds'
);

-- B10
select is(
  (select count(*) from public.order_status_history
   where order_id = 'f0330000-0000-4000-8000-000000000004'
     and from_status = 'CONFIRMED' and to_status = 'CANCELLED'),
  1::bigint,
  'o04 cancellation records exactly one history row'
);

-- B12: refund flows are unaffected by the FR-33 confirm guard.
select is(
  (select public.admin_refund_order_payment(
    'f0330000-0000-4000-8000-000000000004')::text),
  'REFUNDED',
  'cancel-after-pay digital order refunds successfully'
);

-- B13
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0330000-0000-4000-8000-000000000004'),
  'REFUNDED/REFUNDED/CANCELLED',
  'o04 refund keeps order_status CANCELLED'
);

-- B15
select is(
  (select count(*) from public.coupon_usages
   where order_id = 'f0330000-0000-4000-8000-000000000004'),
  1::bigint,
  'refunded paid order keeps its coupon usage consumed'
);

-- B16
select is(
  (select stock from public.products
   where id = 'e0330000-0000-4000-8000-00000000000a'),
  8::integer,
  'refund restores no stock (expiry-only rule)'
);

-- B17
select is(
  (select (p.paid_at = '2026-01-05T10:00:00Z'::timestamptz)::text
   from public.payments p
   where p.order_id = 'f0330000-0000-4000-8000-000000000004'),
  'true',
  'refund does not alter paid_at'
);

-- B18: refund replay idempotency (REFUNDED pairs replay via the refund RPC).
select is(
  (select public.admin_refund_order_payment(
    'f0330000-0000-4000-8000-000000000004')::text),
  'REFUNDED',
  'refund replay returns REFUNDED'
);

reset role;

-- ============================================================
-- PHASE C: notification counts (as table owner; notifications SELECT
-- is owner-scoped under RLS, so the admin emulation cannot see them)
-- ============================================================

-- C1: the rejected admin confirms wrote no notification at all.
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000007'),
  0::bigint,
  'rejected o07 admin confirm wrote no notification'
);

-- C2
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000006'),
  0::bigint,
  'rejected o06 replay wrote no notification'
);

-- C3: the genuine cancellation notified once.
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000004'
     and type = 'ORDER' and title = 'Order cancelled'),
  1::bigint,
  'o04 cancellation notified the owner exactly once'
);

-- C4: the refund notified once, and the refund replay added no duplicate.
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000004'
     and type = 'PAYMENT' and title = 'Payment refunded'),
  1::bigint,
  'o04 refund notified the owner exactly once (replay added none)'
);

-- C5: the o04 PAID replay (A13) added no PAYMENT notification either.
select is(
  (select count(*) from public.notifications
   where order_id = 'f0330000-0000-4000-8000-000000000004'
     and type = 'PAYMENT' and title = 'Payment received'),
  0::bigint,
  'o04 PAID replay wrote no PAYMENT notification'
);

select * from finish();

rollback;
