begin;

create extension if not exists pgtap with schema extensions;

select plan(50);

-- ============================================================
-- FR-31: automatic digital payment expiry + admin full refund.
--
-- Expiry (private.expire_stale_digital_payments):
--   - expires stale PENDING digital payments only (DUMMY_QRIS /
--     DUMMY_BANK_TRANSFER, order PENDING_PAYMENT, deadline =
--     payments.created_at + 15 minutes);
--   - CASH and PAID orders are structurally excluded;
--   - one transaction writes payment EXPIRED, orders EXPIRED +
--     CANCELLED, a system-authored history row (changed_by null),
--     a customer cancellation notification, releases the order's
--     coupon_usages, and restores the stock reserved by create_order;
--   - replays are no-ops (no double-restock, no duplicates);
--   - system expiry writes NO admin audit rows (not an admin action).
--
-- Refund (public.admin_refund_order_payment):
--   - admin only, order UUID only, browser never chooses state;
--   - requires PAID in both representations AND order_status IN
--     (CANCELLED, COMPLETED); order_status is never changed by the
--     refund; coupon usage stays consumed; stock is untouched;
--   - idempotent replay; audited by the FR-25/GAP-05 triggers
--     (PAYMENTS_UPDATE + ORDERS_UPDATE with the admin actor);
--   - clients cannot write payment state directly.
--
-- Fixtures are inserted as the table owner; the suite rolls back.
-- ============================================================

-- ============================================================
-- Fixtures
-- ============================================================

insert into auth.users (id, email)
values
  (
    'a0310000-0000-4000-8000-0000000000a1',
    'fr31-customer-a@test.local'
  ),
  (
    'b0310000-0000-4000-8000-0000000000b1',
    'fr31-customer-b@test.local'
  ),
  (
    'c0310000-0000-4000-8000-0000000000c1',
    'fr31-admin@test.local'
  );

update public.profiles
set full_name = 'FR-31 Customer A'
where id = 'a0310000-0000-4000-8000-0000000000a1';

update public.profiles
set full_name = 'FR-31 Customer B'
where id = 'b0310000-0000-4000-8000-0000000000b1';

update public.profiles
set full_name = 'FR-31 Admin', role = 'ADMIN'
where id = 'c0310000-0000-4000-8000-0000000000c1';

-- Dedicated category/products/fixtures only (never the seed data).
insert into public.categories (
  id, name, slug, is_active
)
values (
  'd0310000-0000-4000-8000-0000000000c1',
  'FR-31 Test',
  'fr31-test',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values
  (
    'e0310000-0000-4000-8000-00000000000a',
    'd0310000-0000-4000-8000-0000000000c1',
    'FR-31 Product A',
    'fr31-product-a',
    100000, 10, true
  ),
  (
    'e0310000-0000-4000-8000-00000000000b',
    'd0310000-0000-4000-8000-0000000000c1',
    'FR-31 Product B',
    'fr31-product-b',
    200000, 5, true
  );

-- Coupon used by the release/keep checks.
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
  'f0310000-0000-4000-8000-0000000000c2',
  'FR31TEST',
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

-- Orders (all owned by customer A; customer B is for the
-- unauthorized refund attempt). Payment deadline comes from
-- payments.created_at, so only the payments rows are backdated.
--
-- o01 fresh digital pending (must NOT expire)
-- o02 stale digital pending, 3 items (5 units of A + null product)
-- o03 stale CASH unpaid (must NOT expire)
-- o04 stale digital already PAID (must NOT expire)
-- o05 stale digital pending but order CONFIRMED (must NOT expire)
-- o06 stale digital pending but order CANCELLED (must NOT expire)
-- o07 order with zero payment rows (never a candidate)
-- o08 stale digital pending, zero items (expires, zero restock)
-- o09 PAID + COMPLETED (refund subject)
-- o10 CASH PAID + CANCELLED (cash refund subject)
-- o11 PAID + CONFIRMED (refund rejected)
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
    'f0310000-0000-4000-8000-000000000001',
    'VG-FR31-001',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PENDING',
    'PENDING_PAYMENT'
  ),
  (
    'f0310000-0000-4000-8000-000000000002',
    'VG-FR31-002',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PENDING',
    'PENDING_PAYMENT'
  ),
  (
    'f0310000-0000-4000-8000-000000000003',
    'VG-FR31-003',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'PENDING_PAYMENT'
  ),
  (
    'f0310000-0000-4000-8000-000000000004',
    'VG-FR31-004',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PAID',
    'PENDING_PAYMENT'
  ),
  (
    'f0310000-0000-4000-8000-000000000005',
    'VG-FR31-005',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PENDING',
    'CONFIRMED'
  ),
  (
    'f0310000-0000-4000-8000-000000000006',
    'VG-FR31-006',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PENDING',
    'CANCELLED'
  ),
  (
    'f0310000-0000-4000-8000-000000000007',
    'VG-FR31-007',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'UNPAID',
    'PENDING_PAYMENT'
  ),
  (
    'f0310000-0000-4000-8000-000000000008',
    'VG-FR31-008',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PENDING',
    'PENDING_PAYMENT'
  ),
  (
    'f0310000-0000-4000-8000-000000000009',
    'VG-FR31-009',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PAID',
    'COMPLETED'
  ),
  (
    'f0310000-0000-4000-8000-000000000010',
    'VG-FR31-010',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PAID',
    'CANCELLED'
  ),
  (
    'f0310000-0000-4000-8000-000000000011',
    'VG-FR31-011',
    'a0310000-0000-4000-8000-0000000000a1',
    'PICKUP',
    '2026-01-05T12:00:00Z',
    'FR-31 Customer A',
    100000, 0, 100000,
    'PAID',
    'CONFIRMED'
  );

insert into public.payments (
  id, order_id, method, status, amount, created_at
)
values
  (
    'bf031000-0000-4000-8000-000000000001',
    'f0310000-0000-4000-8000-000000000001',
    'DUMMY_QRIS', 'PENDING', 100000,
    now()
  ),
  (
    'bf031000-0000-4000-8000-000000000002',
    'f0310000-0000-4000-8000-000000000002',
    'DUMMY_QRIS', 'PENDING', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000003',
    'f0310000-0000-4000-8000-000000000003',
    'CASH', 'UNPAID', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000004',
    'f0310000-0000-4000-8000-000000000004',
    'DUMMY_QRIS', 'PAID', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000005',
    'f0310000-0000-4000-8000-000000000005',
    'DUMMY_QRIS', 'PENDING', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000006',
    'f0310000-0000-4000-8000-000000000006',
    'DUMMY_QRIS', 'PENDING', 100000,
    now() - interval '1 hour'
  ),
  -- order 007 intentionally has no payment row
  (
    'bf031000-0000-4000-8000-000000000008',
    'f0310000-0000-4000-8000-000000000008',
    'DUMMY_BANK_TRANSFER', 'PENDING', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000009',
    'f0310000-0000-4000-8000-000000000009',
    'DUMMY_QRIS', 'PAID', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000010',
    'f0310000-0000-4000-8000-000000000010',
    'CASH', 'PAID', 100000,
    now() - interval '1 hour'
  ),
  (
    'bf031000-0000-4000-8000-000000000011',
    'f0310000-0000-4000-8000-000000000011',
    'DUMMY_QRIS', 'PAID', 100000,
    now() - interval '1 hour'
  );

-- Order 2 line items: product A qty 2 + qty 3 on separate rows plus
-- a row with a null product_id (never restocked).
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
    'a0310000-0000-4000-8000-000000000001',
    'f0310000-0000-4000-8000-000000000002',
    'e0310000-0000-4000-8000-00000000000a',
    'FR-31 Product A',
    100000, 100000, 2, 200000
  ),
  (
    'a0310000-0000-4000-8000-000000000002',
    'f0310000-0000-4000-8000-000000000002',
    'e0310000-0000-4000-8000-00000000000a',
    'FR-31 Product A',
    100000, 100000, 3, 300000
  ),
  (
    'a0310000-0000-4000-8000-000000000003',
    'f0310000-0000-4000-8000-000000000002',
    null,
    'Legacy product',
    100000, 100000, 1, 100000
  );

-- Simulate the FR-21 reservation for order 2: stock 10 -> 5.
update public.products
set stock = 5
where id = 'e0310000-0000-4000-8000-00000000000a';

-- Coupon usages: released by expiry (order 2), kept by refund (order 10).
insert into public.coupon_usages (
  coupon_id, order_id, user_id, discount_amount
)
values
  (
    'f0310000-0000-4000-8000-0000000000c2',
    'f0310000-0000-4000-8000-000000000002',
    'a0310000-0000-4000-8000-0000000000a1',
    0
  ),
  (
    'f0310000-0000-4000-8000-0000000000c2',
    'f0310000-0000-4000-8000-000000000010',
    'a0310000-0000-4000-8000-0000000000a1',
    0
  );

-- ============================================================
-- PHASE A: expiry function (owner/postgres; no claims needed)
-- ============================================================

-- A1: only o02 and o08 are stale eligible candidates.
select is(
  (select private.expire_stale_digital_payments()),
  2::integer,
  'exactly the two stale eligible orders (o02, o08) are expired'
);

-- A2
select is(
  (select p.status::text
   from public.payments p
   where p.order_id = 'f0310000-0000-4000-8000-000000000002'),
  'EXPIRED',
  'o02 payment row is EXPIRED'
);

-- A3
select is(
  (select o.payment_status::text || '/' || o.order_status::text
   from public.orders o
   where o.id = 'f0310000-0000-4000-8000-000000000002'),
  'EXPIRED/CANCELLED',
  'o02 order representations are EXPIRED + CANCELLED together'
);

-- A4
select is(
  (select count(*) from public.order_status_history
   where order_id = 'f0310000-0000-4000-8000-000000000002'
     and from_status = 'PENDING_PAYMENT'
     and to_status = 'CANCELLED'),
  1::bigint,
  'o02 history records exactly one PENDING_PAYMENT -> CANCELLED row'
);

-- A5
select is(
  (select count(*) from public.order_status_history
   where order_id = 'f0310000-0000-4000-8000-000000000002'
     and from_status = 'PENDING_PAYMENT'
     and to_status = 'CANCELLED'
     and changed_by is null),
  1::bigint,
  'o02 expiry history row is system-authored (changed_by null)'
);

-- A6
select is(
  (select note from public.order_status_history
   where order_id = 'f0310000-0000-4000-8000-000000000002'
     and from_status = 'PENDING_PAYMENT'
     and to_status = 'CANCELLED'),
  'Automatically cancelled: the payment was not confirmed within 15 minutes.',
  'o02 history note states the auto-expiry cause'
);

-- A7
select is(
  (select n.user_id::text || '/' || n.type::text || '/' || n.title
   from public.notifications n
   where n.order_id = 'f0310000-0000-4000-8000-000000000002'),
  'a0310000-0000-4000-8000-0000000000a1/ORDER/Order cancelled',
  'o02 cancellation notification goes to the order owner'
);

-- A8
select is(
  (select message from public.notifications
   where order_id = 'f0310000-0000-4000-8000-000000000002'),
  'Payment for your order VG-FR31-002 was not completed in time. The order was cancelled.',
  'o02 notification message states the payment-timeout cause'
);

-- A9
select is(
  (select count(*) from public.coupon_usages
   where order_id = 'f0310000-0000-4000-8000-000000000002'),
  0::bigint,
  'o02 coupon usage is released by expiry'
);

-- A10
select is(
  (select stock from public.products
   where id = 'e0310000-0000-4000-8000-00000000000a'),
  10::integer,
  'o02 stock restored exactly once (5 reserved + 5 restored = 10)'
);

-- A11
select is(
  (select is_available::text from public.products
   where id = 'e0310000-0000-4000-8000-00000000000a'),
  'true',
  'is_available is never changed by expiry'
);

-- A12
select is(
  (select stock from public.products
   where id = 'e0310000-0000-4000-8000-00000000000b'),
  5::integer,
  'unrelated product B stock untouched'
);

-- A13
select is(
  (select p.status::text
   from public.payments p
   where p.order_id = 'f0310000-0000-4000-8000-000000000008'),
  'EXPIRED',
  'o08 payment row is EXPIRED (DUMMY_BANK_TRANSFER too)'
);

-- A14
select is(
  (select o.payment_status::text || '/' || o.order_status::text
   from public.orders o
   where o.id = 'f0310000-0000-4000-8000-000000000008'),
  'EXPIRED/CANCELLED',
  'o08 order representations are EXPIRED + CANCELLED together'
);

-- A15
select is(
  (select count(*) from public.order_status_history
   where order_id = 'f0310000-0000-4000-8000-000000000008'
     and from_status = 'PENDING_PAYMENT'
     and to_status = 'CANCELLED'
     and changed_by is null),
  1::bigint,
  'o08 has its own system-authored expiry history row'
);

-- A16
select is(
  (select n.user_id::text || '/' || n.type::text || '/' || n.title
   from public.notifications n
   where n.order_id = 'f0310000-0000-4000-8000-000000000008'),
  'a0310000-0000-4000-8000-0000000000a1/ORDER/Order cancelled',
  'o08 owner is notified once about the auto-cancellation'
);

-- A17
select is(
  (select count(*) from public.admin_audit_logs
   where entity_id in (
     'f0310000-0000-4000-8000-000000000002',
     'bf031000-0000-4000-8000-000000000002'
   )),
  0::bigint,
  'system expiry is not an admin action: no audit rows for o02'
);

-- A18
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000001'),
  'PENDING/PENDING/PENDING_PAYMENT',
  'o01 fresh digital order is untouched'
);

-- A19
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000003'),
  'UNPAID/UNPAID/PENDING_PAYMENT',
  'o03 stale CASH order is untouched'
);

-- A20
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000004'),
  'PAID/PAID/PENDING_PAYMENT',
  'o04 confirmed PAID digital order is untouched'
);

-- A21
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000005'),
  'PENDING/PENDING/CONFIRMED',
  'o05 pending payment on a CONFIRMED order is untouched'
);

-- A22
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000006'),
  'PENDING/PENDING/CANCELLED',
  'o06 pending payment on a CANCELLED order is untouched'
);

-- A23
select is(
  (select o.payment_status::text || '/' || o.order_status::text || '/' ||
          (select count(*) from public.payments p
           where p.order_id = o.id)::text
   from public.orders o
   where o.id = 'f0310000-0000-4000-8000-000000000007'),
  'UNPAID/PENDING_PAYMENT/0',
  'o07 order without a payment row is untouched'
);

-- A24: replay is a no-op.
select is(
  (select private.expire_stale_digital_payments()),
  0::integer,
  'replay run returns 0'
);

-- A25
select is(
  (select stock from public.products
   where id = 'e0310000-0000-4000-8000-00000000000a'),
  10::integer,
  'replay never double-restocks (stock still 10)'
);

-- A26
select is(
  (select count(*) from public.order_status_history
   where order_id = 'f0310000-0000-4000-8000-000000000002'),
  1::bigint,
  'replay writes no duplicate history for o02'
);

-- A27
select is(
  (select count(*) from public.notifications
   where order_id = 'f0310000-0000-4000-8000-000000000002'),
  1::bigint,
  'replay writes no duplicate notification for o02'
);

-- A28
select is(
  (select count(*) from public.coupon_usages
   where order_id = 'f0310000-0000-4000-8000-000000000002'),
  0::bigint,
  'replay keeps the released coupon usage absent'
);

-- ============================================================
-- PHASE B: refund RPC (role-emulated via JWT claim)
-- ============================================================

-- customer B is not an admin
set local role authenticated;
set local request.jwt.claim.sub =
  'b0310000-0000-4000-8000-0000000000b1';

-- B1
select throws_ok(
  $$
    select public.admin_refund_order_payment(
      'f0310000-0000-4000-8000-000000000009'
    )
  $$,
  '42501',
  'Refund is not available for this order',
  'non-admin caller is rejected'
);

reset role;

-- B2
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000009'),
  'PAID/PAID/COMPLETED',
  'rejected non-admin refund leaves o09 untouched'
);

-- admin user
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

-- B3: fresh PENDING digital payment is not REFUNDED state
select throws_ok(
  $$
    select public.admin_refund_order_payment(
      'f0310000-0000-4000-8000-000000000001'
    )
  $$,
  '22023',
  'Refund is not available for this order',
  'refund requires authoritative PAID'
);

reset role;

-- B4: PAID order still in CONFIRMED must be cancelled first
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

select throws_ok(
  $$
    select public.admin_refund_order_payment(
      'f0310000-0000-4000-8000-000000000011'
    )
  $$,
  '22023',
  'Refund is not available for this order',
  'in-flight PAID order is not refundable'
);

reset role;

-- B5
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000011'),
  'PAID/PAID/CONFIRMED',
  'rejected refund leaves o11 untouched'
);

-- B6
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

select is(
  (select public.admin_refund_order_payment(
    'f0310000-0000-4000-8000-000000000009'
  )::text),
  'REFUNDED',
  'PAID + COMPLETED order refunds successfully'
);

reset role;

-- B7
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000009'),
  'REFUNDED/REFUNDED/COMPLETED',
  'o09 refund keeps both representations consistent and does not change order_status'
);

-- B8
select is(
  (select n.user_id::text || '/' || n.type::text || '/' || n.title
   from public.notifications n
   where n.order_id = 'f0310000-0000-4000-8000-000000000009'),
  'a0310000-0000-4000-8000-0000000000a1/PAYMENT/Payment refunded',
  'customer is notified once that the payment was refunded'
);

-- B9
select is(
  (select message from public.notifications
   where order_id = 'f0310000-0000-4000-8000-000000000009'
     and type = 'PAYMENT'),
  'Payment for your order VG-FR31-009 has been refunded.',
  'refund notification message names the order'
);

-- B10
select is(
  (select count(*) from public.admin_audit_logs
   where action = 'PAYMENTS_UPDATE'
     and entity_type = 'payments'
     and entity_id = 'bf031000-0000-4000-8000-000000000009'
     and actor_user_id = 'c0310000-0000-4000-8000-0000000000c1'
     and after_data ->> 'status' = 'REFUNDED'),
  1::bigint,
  'refund is audited as one PAYMENTS_UPDATE row by the admin actor'
);

-- B11
select is(
  (select count(*) from public.admin_audit_logs
   where action = 'ORDERS_UPDATE'
     and entity_type = 'orders'
     and entity_id = 'f0310000-0000-4000-8000-000000000009'
     and actor_user_id = 'c0310000-0000-4000-8000-0000000000c1'
     and after_data ->> 'payment_status' = 'REFUNDED'),
  1::bigint,
  'refund is audited as one ORDERS_UPDATE row by the admin actor'
);

-- B12: idempotent replay.
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

select is(
  (select public.admin_refund_order_payment(
    'f0310000-0000-4000-8000-000000000009'
  )::text),
  'REFUNDED',
  'refund replay returns REFUNDED'
);

reset role;

-- B13
select is(
  (select count(*) from public.admin_audit_logs
   where action = 'PAYMENTS_UPDATE'
     and entity_id = 'bf031000-0000-4000-8000-000000000009'
     and after_data ->> 'status' = 'REFUNDED'),
  1::bigint,
  'refund replay writes no duplicate audit row'
);

-- B14
select is(
  (select count(*) from public.notifications
   where order_id = 'f0310000-0000-4000-8000-000000000009'
     and type = 'PAYMENT'),
  1::bigint,
  'refund replay writes no duplicate notification'
);

-- B15
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

select is(
  (select public.admin_refund_order_payment(
    'f0310000-0000-4000-8000-000000000010'
  )::text),
  'REFUNDED',
  'CASH PAID + CANCELLED order refunds successfully'
);

reset role;

-- B16
select is(
  (select p.status::text || '/' || o.payment_status::text || '/' ||
          o.order_status::text
   from public.payments p
   join public.orders o on o.id = p.order_id
   where o.id = 'f0310000-0000-4000-8000-000000000010'),
  'REFUNDED/REFUNDED/CANCELLED',
  'o10 cash refund keeps order_status CANCELLED'
);

-- B17
select is(
  (select count(*) from public.coupon_usages
   where order_id = 'f0310000-0000-4000-8000-000000000010'),
  1::bigint,
  'refunded paid order keeps its coupon usage consumed'
);

-- B18
select is(
  (select stock from public.products
   where id = 'e0310000-0000-4000-8000-00000000000a'),
  10::integer,
  'refund restores no stock (expiry-only rule)'
);

-- B19: expired payment is not refundable.
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

select throws_ok(
  $$
    select public.admin_refund_order_payment(
      'f0310000-0000-4000-8000-000000000002'
    )
  $$,
  '22023',
  'Refund is not available for this order',
  'EXPIRED payment cannot be refunded'
);

reset role;

-- B20
select is(
  (select o.payment_status::text || '/' || o.order_status::text
   from public.orders o
   where o.id = 'f0310000-0000-4000-8000-000000000002'),
  'EXPIRED/CANCELLED',
  'rejected expired-order refund leaves o02 untouched'
);

-- ============================================================
-- PHASE C: clients can never write payment state directly
-- ============================================================

-- C1
set local role authenticated;
set local request.jwt.claim.sub =
  'c0310000-0000-4000-8000-0000000000c1';

select throws_ok(
  $$
    update public.payments
    set status = 'REFUNDED'
    where id = 'bf031000-0000-4000-8000-000000000009'
  $$,
  '42501',
  'permission denied for table payments',
  'direct writes to payment state are revoked even for admins'
);

reset role;

-- C2
set local role anon;

select throws_ok(
  $$
    update public.payments
    set status = 'REFUNDED'
    where id = 'bf031000-0000-4000-8000-000000000009'
  $$,
  '42501',
  'permission denied for table payments',
  'anonymous callers cannot write payment state either'
);

select * from finish();

rollback;
