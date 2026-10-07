-- ============================================================
-- Velvet Grill
-- FR-31: payment expiry & full refund lifecycle.
--
-- Two system-authored / admin-authored writers are added; the
-- existing RPCs, transition graph, RLS policies, grants, audit
-- triggers and notification patterns stay untouched.
--
-- 1. private.expire_stale_digital_payments():
--    A scheduled SECURITY DEFINER janitor that auto-expires
--    dummy digital payments (DUMMY_QRIS / DUMMY_BANK_TRANSFER)
--    that are still PENDING while the order sits in
--    PENDING_PAYMENT, 15 minutes after the payment row was
--    created. CASH is structurally excluded (method filter) and
--    PAID is excluded (status filter), so cash and confirmed
--    payments can never expire this way.
--
--    Per expired order, atomically in the same transaction:
--      payments.status        -> EXPIRED
--      orders.payment_status  -> EXPIRED
--      orders.order_status    -> CANCELLED
--      + order_status_history (system-authored, changed_by null)
--      + customer ORDER notification
--      + coupon_usages released for the order
--      + product stock restored (mirror of the FR-21 reservation)
--
--    Canonical lock order everywhere is ORDER -> PAYMENT (the
--    lock order confirm_order_payment uses). The scan locks
--    eligible ORDER rows with FOR UPDATE ... SKIP LOCKED and
--    re-verifies every predicate under the held order lock and
--    the payment row lock before mutating. Repeated runs are
--    idempotent no-ops, and a confirmation that wins the race
--    simply makes the next run skip the order.
--
-- 2. public.admin_refund_order_payment():
--    Admin-only FULL refund, modeled on confirm_order_payment.
--    Legal source: payments.status = orders.payment_status =
--    'PAID' and order_status IN ('CANCELLED', 'COMPLETED'). The
--    order_status is NOT changed by a refund: a refunded order
--    keeps its CANCELLED / COMPLETED fulfillment story. Coupon
--    usage stays consumed (the promotion was redeemed by a paid
--    transaction) and stock is not touched (no refills exist on
--    any path; fulfillment already happened). Already-REFUNDED
--    replays return REFUNDED and write nothing.
--
--    Audit evidence is automatic: the FR-25/GAP-05 admin audit
--    triggers record ORDERS_UPDATE + PAYMENTS_UPDATE rows with
--    before/after JSON and the admin actor. No order_status_
--    history row is written (no order_status transition occurs).
--
-- 3. pg_cron schedules function 1 every 30 seconds.
--
-- No expires_at / refunded_at columns are required: the deadline
-- derives from payments.created_at (immutable), and the refund
-- evidence lives in the audit logs + payments.updated_at.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Scheduled auto-expiry for stale PENDING digital payments.
--    Lives in the private schema (already closed to all client
--    roles) and has NO EXECUTE grants: only the owner (postgres)
--    and the cron scheduler can run it.
-- ------------------------------------------------------------

create function private.expire_stale_digital_payments()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order_user_id uuid;
  v_order_number text;
  v_order_payment_status public.payment_status;
  v_order_status public.order_status;
  v_payment_rows integer;
  v_payment_id uuid;
  v_payment_method public.payment_method;
  v_payment_status public.payment_status;
  v_payment_created_at timestamptz;
  v_product_ids uuid[];
  v_expired_count integer := 0;
begin
  -- 1. Lock eligible ORDER rows first (canonical ORDER -> PAYMENT
  --    lock order; never acquire a payment before its order).
  --    SKIP LOCKED keeps the run from colliding with an in-flight
  --    confirmation: that order is revisited by the next run, and
  --    whichever side settles first decides the outcome.
  for v_order_id in
    select o.id
    from public.orders o
    join public.payments p on p.order_id = o.id
    where
      p.method in ('DUMMY_QRIS', 'DUMMY_BANK_TRANSFER')
      and p.status = 'PENDING'
      and o.payment_status = 'PENDING'
      and o.order_status = 'PENDING_PAYMENT'
      and p.created_at < now() - interval '15 minutes'
    order by o.id
    for update of o skip locked
  loop
    -- 2. Re-read the order under the held lock.
    select o.user_id, o.order_number, o.payment_status, o.order_status
    into v_order_user_id, v_order_number, v_order_payment_status, v_order_status
    from public.orders o
    where o.id = v_order_id;

    -- 3. Exactly one payment row is required; zero or multiple rows is an
    --    unrepresentable state that is left untouched (existing writers
    --    cannot produce it, and raising would starve the whole batch).
    select count(*)
    into v_payment_rows
    from public.payments p
    where p.order_id = v_order_id;

    if v_payment_rows <> 1 then
      continue;
    end if;

    -- 4. Lock the single payment row (order lock already held).
    select p.id, p.method, p.status, p.created_at
    into v_payment_id, v_payment_method, v_payment_status, v_payment_created_at
    from public.payments p
    where p.order_id = v_order_id
    for update;

    -- 5. Re-verify every predicate under both locks. In-flight
    --    confirmations and settled states (PAID / EXPIRED /
    --    CANCELLED / CONFIRMED) fail closed here and write nothing.
    if v_payment_method not in ('DUMMY_QRIS', 'DUMMY_BANK_TRANSFER')
      or v_payment_status is distinct from 'PENDING'
      or v_order_payment_status is distinct from 'PENDING'
      or v_order_status is distinct from 'PENDING_PAYMENT'
      or v_payment_created_at >= now() - interval '15 minutes'
    then
      continue;
    end if;

    -- 6. Transition both representations atomically.
    update public.payments
    set status = 'EXPIRED'
    where id = v_payment_id;

    update public.orders
    set payment_status = 'EXPIRED',
        order_status = 'CANCELLED'
    where id = v_order_id;

    -- 7. System-authored history row: changed_by is null because
    --    no human performed this transition.
    insert into public.order_status_history (
      order_id,
      from_status,
      to_status,
      changed_by,
      note
    )
    values (
      v_order_id,
      'PENDING_PAYMENT',
      'CANCELLED',
      null,
      'Automatically cancelled: the payment was not confirmed within 15 minutes.'
    );

    -- 8. Customer cancellation notification (same shape as the
    --    update_order_status CANCELLED path, with the payment-timeout
    --    cause). Orphaned orders notify no one.
    if v_order_user_id is not null then
      insert into public.notifications (user_id, type, title, message, order_id)
      values (
        v_order_user_id,
        'ORDER',
        'Order cancelled',
        'Payment for your order ' || v_order_number || ' was not completed in time. The order was cancelled.',
        v_order_id
      );
    end if;

    -- 9. Release the coupon redemption so the expired unpaid order does
    --    not consume usage_limit / per_customer_limit. Row deletes on
    --    coupon_usages only: no coupon-row lock, so no lock cycle can
    --    form with create_order's coupon lock.
    delete from public.coupon_usages cu
    where cu.order_id = v_order_id;

    -- 10. Restore the stock that create_order (FR-21) reserved for
    --     this order: the exact mirror of the cumulative decrement,
    --     aggregated per product from order_items. Products are locked
    --     in ascending id order (the same discipline FR-21 uses) so
    --     concurrent carts/orders cannot deadlock. is_available is
    --     never touched; availability remains an admin decision.
    select coalesce(
      array_agg(distinct oi.product_id),
      array[]::uuid[]
    )
    into v_product_ids
    from public.order_items oi
    where oi.order_id = v_order_id
      and oi.product_id is not null;

    perform 1
    from public.products p
    where p.id = any (v_product_ids)
    order by p.id
    for update;

    update public.products p
    set stock = p.stock + r.qty
    from (
      select oi.product_id, sum(oi.quantity)::integer as qty
      from public.order_items oi
      where oi.order_id = v_order_id
        and oi.product_id is not null
      group by oi.product_id
    ) r
    where p.id = r.product_id;

    v_expired_count := v_expired_count + 1;
  end loop;

  return v_expired_count;
end;
$$;

revoke all on function private.expire_stale_digital_payments() from public;

-- ------------------------------------------------------------
-- 2. admin_refund_order_payment: the only path that advances a
--    payment to REFUNDED.
--
--    Modeled on confirm_order_payment: the caller is an admin
--    (re-derived in-database via private.is_admin(); the browser
--    submits only the order id), the order and the single payment
--    row are locked in the canonical ORDER -> PAYMENT order, and
--    both representations must agree before anything is written.
--    Already-REFUNDED replays are idempotent. The order_status is
--    never modified (PAID+CANCELLED stays CANCELLED; PAID+
--    COMPLETED stays COMPLETED), coupon usage stays consumed and
--    no stock is restored.
-- ------------------------------------------------------------

create function public.admin_refund_order_payment(p_order_id uuid)
returns public.payment_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_is_admin boolean := (select private.is_admin());
  v_order_user_id uuid;
  v_order_payment_status public.payment_status;
  v_order_status public.order_status;
  v_order_number text;
  v_payment_id uuid;
  v_payment_method public.payment_method;
  v_payment_status public.payment_status;
  v_payment_count integer;
begin
  -- 1. Identity is authoritative.
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- 2. Admin only: refunding paid money is a staff bookkeeping
  --    action. A non-admin caller is indistinguishable from a
  --    missing order on purpose.
  if not v_is_admin then
    raise exception 'Refund is not available for this order'
      using errcode = '42501';
  end if;

  -- 3. Lock the order.
  select o.user_id, o.payment_status, o.order_status, o.order_number
  into v_order_user_id, v_order_payment_status, v_order_status, v_order_number
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Refund is not available for this order'
      using errcode = '42501';
  end if;

  -- 4. Exactly one payment row is required; zero or multiple rows is
  --    not a refundable state.
  select count(*)
  into v_payment_count
  from public.payments p
  where p.order_id = p_order_id;

  if v_payment_count <> 1 then
    raise exception 'Refund is not available for this order'
      using errcode = '42501';
  end if;

  select p.id, p.method, p.status
  into v_payment_id, v_payment_method, v_payment_status
  from public.payments p
  where p.order_id = p_order_id
  for update;

  -- 5. Order and payment state must agree. A mismatch (either
  --    direction) is a safe failure; it is never silently repaired.
  if v_order_payment_status is distinct from v_payment_status then
    raise exception 'Refund is not available for this order'
      using errcode = '42501';
  end if;

  -- 6. Idempotent replay: already REFUNDED in both representations.
  if v_payment_status = 'REFUNDED' then
    return 'REFUNDED'::public.payment_status;
  end if;

  -- 7. Authoritative PAID state only: both representations must be
  --    PAID. EXPIRED / PENDING / UNPAID / FAILED are not refundable.
  if v_order_payment_status <> 'PAID' or v_payment_status <> 'PAID' then
    raise exception 'Refund is not available for this order'
      using errcode = '22023';
  end if;

  -- 8. Refund targets only closed orders. A PAID order still in flight
  --    must reach CANCELLED through the existing status graph first; a
  --    refund must not silently change an unrelated order status.
  if v_order_status not in ('CANCELLED', 'COMPLETED') then
    raise exception 'Refund is not available for this order'
      using errcode = '22023';
  end if;

  -- 9. Apply the refund to both representations atomically. CASH is
  --    permitted (payments_cash_status_chk already allows CASH +
  --    REFUNDED); this is a full refund, never partial.
  update public.payments
  set status = 'REFUNDED'
  where id = v_payment_id;

  update public.orders
  set payment_status = 'REFUNDED'
  where id = p_order_id;

  -- 10. Notify the order owner. The step-6 replay returns earlier, so
  --     a retry creates no duplicate. An orphaned order notifies no one.
  if v_order_user_id is not null then
    insert into public.notifications (user_id, type, title, message, order_id)
    values (
      v_order_user_id,
      'PAYMENT',
      'Payment refunded',
      'Payment for your order ' || v_order_number || ' has been refunded.',
      p_order_id
    );
  end if;

  -- Audit evidence is produced automatically by the FR-25/GAP-05
  -- admin audit triggers: this caller is an admin, so PAYMENTS_UPDATE
  -- and ORDERS_UPDATE rows with before/after JSON are recorded.

  return 'REFUNDED'::public.payment_status;
end;
$$;

revoke all on function public.admin_refund_order_payment(uuid) from public, anon;

grant execute on function public.admin_refund_order_payment(uuid) to authenticated;

-- ------------------------------------------------------------
-- 3. Schedule the expiry janitor with pg_cron. The 15-minute
--    deadline is fixed business policy, the job is looked up by
--    name so the migration stays re-runnable, and the command
--    string runs the private function (no client-role EXECUTE).
-- ------------------------------------------------------------

do $do$
begin
  create extension if not exists pg_cron;

  if not exists (
    select 1
    from cron.job
    where jobname = 'fr31_expire_digital_payments'
  ) then
    perform cron.schedule(
      'fr31_expire_digital_payments',
      '30 seconds',
      $command$
        select private.expire_stale_digital_payments();
      $command$
    );
  end if;
end
$do$;

-- ------------------------------------------------------------
-- 4. Document the invariants on the functions themselves.
-- ------------------------------------------------------------

comment on function private.expire_stale_digital_payments() is $$FR-31:
auto-expires DUMMY_QRIS / DUMMY_BANK_TRANSFER payments that are still
PENDING while the order is PENDING_PAYMENT 15 minutes after
payments.created_at. Atomically sets payments.status = EXPIRED,
orders.payment_status = EXPIRED and orders.order_status = CANCELLED,
writes a system-authored order_status_history row (changed_by null),
notifies the customer, releases the order''s coupon_usages and
restores the stock reserved by create_order. Locks order rows first
(SKIP LOCKED), then the single payment row, and re-verifies every
predicate before mutating; CASH and PAID payments are structurally
excluded and repeated runs are idempotent no-ops. Not executable by
client roles (private schema, no EXECUTE grants).$$;

comment on function public.admin_refund_order_payment(uuid) is $$FR-31:
admin-only FULL refund. Requires payments.status = orders.payment_status
= PAID and order_status IN (CANCELLED, COMPLETED); refunds an otherwise
in-flight PAID order only after it is CANCELLED via the order status
flow. Sets both representations to REFUNDED atomically without changing
order_status, keeps coupon usage consumed, restores no stock, and
notifies the customer. Idempotent on already-REFUNDED replay and
audited by the FR-25/GAP-05 admin audit triggers. Granted EXECUTE to
authenticated only; admin authority is enforced inside via
private.is_admin().$$;
