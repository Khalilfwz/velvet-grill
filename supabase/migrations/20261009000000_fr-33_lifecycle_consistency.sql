-- ============================================================
-- Velvet Grill
-- FR-33: order & payment lifecycle consistency.
--
-- The FR-33 audit (verification-first) found exactly one real gap in
-- an otherwise intended lifecycle: a CANCELLED order whose digital
-- payment is still PENDING could still be driven to PAID through
-- confirm_order_payment, because
--   * the RPC checks no order_status, and
--   * the storefront confirm gate omitted order_status.
-- Admin cancellation deliberately leaves the payment row untouched
-- (frozen FR-31 policy) and the expiry janitor deliberately skips
-- non-PENDING_PAYMENT orders, so (PENDING, CANCELLED) is reachable.
--
-- This migration makes CANCELLED terminal for payment confirmation.
-- Any confirm_order_payment call on a CANCELLED order raises 42501
-- and writes nothing - including a replay of an already-PAID pair
-- (which previously returned PAID silently). Intentional contract
-- change, approved over the FR-31-frozen body at plan time:
--   * already-PAID replay idempotency on NON-cancelled orders is
--     unchanged (the PAID replay guard still returns PAID);
--   * refund flows are unaffected: admin_refund_order_payment is a
--     separate RPC and already accepts (PAID, PAID, CANCELLED), so
--     cancel-after-pay money stays recoverable.
--
-- Concurrency: the CANCELLED decision reads order_status while the
-- order row lock (FOR UPDATE, step b) is already held; the canonical
-- ORDER -> PAYMENT lock order is unchanged, no new locks are taken,
-- and no new race harness is required (confirm-vs-expiry and
-- confirm-vs-cancel interleaveings are covered by the locked read +
-- re-verification and the fr31 race script).
--
-- Everything else is preserved verbatim from
-- 20261006000002_gap03_notifications.sql (the latest effective body):
-- SECURITY DEFINER, SET search_path = '', authorization, exactly-one
-- payment row, agreement check, the PAID replay guard, payment
-- semantics and the PAYMENT notification. CREATE OR REPLACE keeps
-- function ownership and ACLs, so no grant/revoke statements are
-- added.
-- ============================================================

create or replace function public.confirm_order_payment(p_order_id uuid)
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
  -- a. Identity is authoritative.
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- b. Lock the order and require owner-or-admin. A missing order and an
  --    unauthorized caller are indistinguishable on purpose.
  select o.user_id, o.payment_status, o.order_status, o.order_number
  into v_order_user_id, v_order_payment_status, v_order_status, v_order_number
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Payment cannot be confirmed' using errcode = '42501';
  end if;

  if v_order_user_id is distinct from v_user_id and not v_is_admin then
    raise exception 'Payment cannot be confirmed' using errcode = '42501';
  end if;

  -- c. Exactly one payment row is required. Zero or multiple rows is not a
  --    confirmable state.
  select count(*)
  into v_payment_count
  from public.payments p
  where p.order_id = p_order_id;

  if v_payment_count <> 1 then
    raise exception 'Payment cannot be confirmed' using errcode = '42501';
  end if;

  select p.id, p.method, p.status
  into v_payment_id, v_payment_method, v_payment_status
  from public.payments p
  where p.order_id = p_order_id
  for update;

  -- d. Method authorization. Cash is confirmed by staff only, even when the
  --    payment is already PAID, so a customer confirming cash is always
  --    rejected.
  if v_payment_method = 'CASH' and not v_is_admin then
    raise exception 'Payment cannot be confirmed' using errcode = '42501';
  end if;

  -- e. Order and payment state must agree. A mismatch (either direction) is a
  --    safe failure; it is never silently repaired.
  if v_order_payment_status is distinct from v_payment_status then
    raise exception 'Payment cannot be confirmed' using errcode = '42501';
  end if;

  -- e2. FR-33: a CANCELLED order is terminal for payment confirmation.
  --     Any confirm call on a cancelled order - including a replay of an
  --     already-PAID pair - is rejected with no writes. Money taken on a
  --     cancelled order is recovered through public.admin_refund_order_
  --     payment; the refund RPC is a separate path and remains unchanged.
  if v_order_status = 'CANCELLED' then
    raise exception 'Payment cannot be confirmed' using errcode = '42501';
  end if;

  -- f. Idempotent replay: both states are PAID and the caller is authorized.
  if v_payment_status = 'PAID' then
    return 'PAID'::public.payment_status;
  end if;

  -- g. Source state for the only supported transitions.
  if v_payment_method = 'CASH' then
    if v_payment_status <> 'UNPAID' then
      raise exception 'Payment cannot be confirmed' using errcode = '42501';
    end if;
  else
    if v_payment_status <> 'PENDING' then
      raise exception 'Payment cannot be confirmed' using errcode = '42501';
    end if;
  end if;

  -- h. Apply the transition to both representations atomically.
  update public.payments
  set status = 'PAID',
      paid_at = now()
  where id = v_payment_id;

  update public.orders
  set payment_status = 'PAID'
  where id = p_order_id;

  -- h2. GAP-03: notify the order owner that payment was received. The step-f
  --     replay returns earlier, so a retry creates no duplicate. An orphaned
  --     order (user_id is null) notifies no one.
  if v_order_user_id is not null then
    insert into public.notifications (user_id, type, title, message, order_id)
    values (
      v_order_user_id,
      'PAYMENT',
      'Payment received',
      'Payment for your order ' || v_order_number || ' has been received.',
      p_order_id
    );
  end if;

  return 'PAID'::public.payment_status;
end;
$$;

-- ------------------------------------------------------------
-- Document the invariants on the function itself.
-- ------------------------------------------------------------

comment on function public.confirm_order_payment(uuid) is $$Confirms a
payment and atomically transitions both representations:
payments.status + orders.payment_status -> PAID (paid_at set), plus a
PAYMENT notification in the same transaction. Confirmable sources:
CASH UNPAID (admin/staff only) and digital PENDING (order owner or
admin); the single payments row must agree with orders.payment_status
and is locked in the canonical ORDER -> PAYMENT lock order after the
order row. FR-33: a CANCELLED order is terminal for payment
confirmation - any call with order_status = CANCELLED raises 42501 and
writes nothing, including a replay of an already-PAID pair (deliberate
contract change; money taken on a cancelled order is recovered through
admin_refund_order_payment instead). Already-PAID replay idempotency
on non-cancelled orders is unchanged. SECURITY DEFINER with
search_path = ''; ownership and ACLs are preserved by CREATE OR
REPLACE, so no grant/revoke statements are emitted by the FR-33
migration.$$;
