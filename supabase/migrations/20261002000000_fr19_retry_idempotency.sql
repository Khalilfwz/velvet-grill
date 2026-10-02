-- ============================================================
-- Velvet Grill
-- FR-19: retry-sensitive order/payment operations.
--
-- create_order is already idempotent (FR-13, reinforced by
-- FR-16/17/18) and confirm_order_payment is already idempotent
-- by state (FR-17). Neither is changed here.
--
-- The remaining retry gap is update_order_status: an exact
-- successful replay (the requested status equals the order's
-- current status) used to raise "Order status transition is not
-- allowed" (22023) instead of returning the same logical result.
--
-- This migration replaces ONLY the body logic of
-- public.update_order_status(...) so that an exact same-status
-- replay becomes a harmless idempotent no-op: it returns the
-- current status and writes nothing (no orders UPDATE, no
-- order_status_history INSERT).
--
-- The replay branch runs AFTER authentication, admin
-- authorization and the locked order lookup, so it cannot bypass
-- authorization, reveal whether a nonexistent or another user's
-- order exists, or mutate state. Every other FR-18 rule is
-- preserved unchanged: illegal non-replay edges still fail, the
-- CONFIRMED -> PREPARING payment gate still applies, multiple
-- payment rows still fail closed, and the transition + history
-- write remains atomic.
--
-- The declaration and function attributes are copied verbatim
-- from FR-18 (LANGUAGE plpgsql, SECURITY DEFINER,
-- SET search_path = '', RETURNS public.order_status, and the
-- p_note default). CREATE OR REPLACE preserves ownership and
-- ACL, so no grant/revoke statements are added.
-- ============================================================

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
  select o.order_status, o.payment_status
  into v_from, v_payment_status
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

  return p_to_status;
end;
$$;
