-- ============================================================
-- Velvet Grill
-- GAP-03: persistent, in-app customer notifications for locked
-- order/payment events.
--
-- The notifications table and its RLS already exist
-- (20260922013928 / 20260922014836); this migration adds only
-- the authoritative producers. No schema, enum, RLS, or grant
-- change.
--
-- Producers are added to the existing authoritative RPCs so a
-- notification is written in the SAME transaction as the
-- business event it describes:
--   - public.update_order_status  -> ORDER notifications for
--     CONFIRMED / READY / COMPLETED / CANCELLED (genuine
--     transitions only; PREPARING is not a notification event).
--   - public.confirm_order_payment -> PAYMENT notification when
--     a payment genuinely becomes PAID.
--
-- The recipient is derived from orders.user_id, never from the
-- caller or the browser. orders.user_id is nullable, so an
-- orphaned order produces no notification.
--
-- Idempotency is preserved: both functions keep their existing
-- replay guards (update_order_status step 4b; confirm_order_payment
-- step f) which return BEFORE the new INSERTs, so retries and
-- same-status replays create no duplicate.
--
-- update_order_status is copied from its latest effective body
-- (20261006000001_bug02_completed_requires_paid.sql) and
-- confirm_order_payment from its fr17 body
-- (20261001000000_fr17_payments.sql). Every existing rule is
-- unchanged: SECURITY DEFINER, SET search_path = '', authorization,
-- the transition graph, the digital CONFIRMED -> PREPARING gate,
-- the BUG-02 READY -> COMPLETED "COMPLETED => PAID" gate, the
-- atomic status + history write, and payment semantics.
-- CREATE OR REPLACE preserves ownership and ACL, so no
-- grant/revoke statements are added.
-- ============================================================

-- ------------------------------------------------------------
-- 1. update_order_status: add ORDER notifications after the
--    atomic status + history write.
-- ------------------------------------------------------------

create or replace function public.update_order_status(
  p_order_id uuid,
  p_to_status public.order_status,
  p_note text default null
)
returns public.order_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_is_admin boolean := (select private.is_admin());
  v_from public.order_status;
  v_payment_status public.payment_status;
  v_payment_rows integer;
  v_payment_method public.payment_method;
  v_payment_row_status public.payment_status;
  v_order_number text;
  v_order_user_id uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- 1. Identity is authoritative.
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- 2. Admin-only: this is the sole order-status transition authority.
  if not v_is_admin then
    raise exception 'Order status cannot be changed' using errcode = '42501';
  end if;

  -- 3. Bounded note (matches the order-level note bound).
  if v_note is not null and length(v_note) > 500 then
    raise exception 'Order status note is invalid' using errcode = '22023';
  end if;

  -- 4. Lock the order. A missing order and an unauthorized caller are
  --    indistinguishable on purpose. The lock serializes concurrent
  --    transitions for the same order.
  select o.order_status, o.payment_status, o.order_number, o.user_id
  into v_from, v_payment_status, v_order_number, v_order_user_id
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Order status cannot be changed' using errcode = '42501';
  end if;

  -- 4b. FR-19 idempotent replay. An exact successful replay (the requested
  --     status equals the order's current status) is a harmless no-op: return
  --     the current status and write nothing. This runs after the identity,
  --     admin authorization and locked lookup above, so it cannot bypass
  --     authorization or act as an existence oracle.
  if p_to_status is not null and p_to_status = v_from then
    return v_from;
  end if;

  -- 5. Structural transition must be one of the documented allowed edges.
  --    Self-transitions and everything else are rejected.
  if p_to_status is null
    or p_to_status = v_from
    or not (
      (v_from = 'PENDING_PAYMENT' and p_to_status in ('CONFIRMED', 'CANCELLED'))
      or (v_from = 'CONFIRMED' and p_to_status in ('PREPARING', 'CANCELLED'))
      or (v_from = 'PREPARING' and p_to_status = 'READY')
      or (v_from = 'READY' and p_to_status = 'COMPLETED')
    )
  then
    raise exception 'Order status transition is not allowed'
      using errcode = '22023';
  end if;

  -- 6. Payment gate for CONFIRMED -> PREPARING only.
  --    - 0 payment rows: legacy pre-FR17 order, no method to gate.
  --    - 1 CASH row: allowed while payment remains UNPAID.
  --    - 1 digital row: both order and payment must be PAID.
  --    - >1 rows: ambiguous/corrupt, fail closed (never pick a row).
  if v_from = 'CONFIRMED' and p_to_status = 'PREPARING' then
    select count(*)
    into v_payment_rows
    from public.payments p
    where p.order_id = p_order_id;

    if v_payment_rows > 1 then
      raise exception 'Order is not eligible to enter preparation'
        using errcode = '22023';
    elsif v_payment_rows = 1 then
      select p.method, p.status
      into v_payment_method, v_payment_row_status
      from public.payments p
      where p.order_id = p_order_id;

      if v_payment_method in ('DUMMY_QRIS', 'DUMMY_BANK_TRANSFER') then
        -- Digital payments must be PAID in BOTH representations; the order and
        -- its payment row must agree.
        if v_payment_status <> 'PAID' or v_payment_row_status <> 'PAID' then
          raise exception 'Order is not eligible to enter preparation'
            using errcode = '22023';
        end if;
      end if;
      -- CASH: allowed while payment remains UNPAID.
    end if;
  end if;

  -- 6b. Completion gate (universal): an order may enter COMPLETED only when its
  --     authoritative payment_status is PAID. Payment confirmation remains a
  --     separate admin action (public.confirm_order_payment); completion never
  --     confirms payment and never mutates payment state.
  if v_from = 'READY' and p_to_status = 'COMPLETED'
    and v_payment_status is distinct from 'PAID'
  then
    raise exception 'Order is not eligible for completion' using errcode = '22023';
  end if;

  -- 7. Apply the status change and its history row atomically. Both succeed
  --    or neither is written (any failure above has already raised).
  update public.orders
  set order_status = p_to_status
  where id = p_order_id;

  insert into public.order_status_history (
    order_id,
    from_status,
    to_status,
    changed_by,
    note
  )
  values (
    p_order_id,
    v_from,
    p_to_status,
    v_user_id,
    v_note
  );

  -- 7b. GAP-03: notify the order owner on locked ORDER events. This runs only
  --     on a genuine transition (the 4b replay returns earlier) and inside the
  --     same transaction as the status + history write. The recipient is the
  --     order owner, never the caller or the browser. PREPARING is not a
  --     notification event. An orphaned order (user_id is null) notifies no one.
  if v_order_user_id is not null
    and p_to_status in ('CONFIRMED', 'READY', 'COMPLETED', 'CANCELLED')
  then
    insert into public.notifications (user_id, type, title, message, order_id)
    values (
      v_order_user_id,
      'ORDER',
      case p_to_status
        when 'CONFIRMED' then 'Order confirmed'
        when 'READY' then 'Order ready'
        when 'COMPLETED' then 'Order completed'
        when 'CANCELLED' then 'Order cancelled'
      end,
      case p_to_status
        when 'CONFIRMED' then 'Your order ' || v_order_number || ' has been confirmed.'
        when 'READY' then 'Your order ' || v_order_number || ' is ready.'
        when 'COMPLETED' then 'Your order ' || v_order_number || ' has been completed.'
        when 'CANCELLED' then 'Your order ' || v_order_number || ' has been cancelled.'
      end,
      p_order_id
    );
  end if;

  return p_to_status;
end;
$$;

-- ------------------------------------------------------------
-- 2. confirm_order_payment: add a PAYMENT notification after the
--    atomic payment transition.
-- ------------------------------------------------------------

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
  select o.user_id, o.payment_status, o.order_number
  into v_order_user_id, v_order_payment_status, v_order_number
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
