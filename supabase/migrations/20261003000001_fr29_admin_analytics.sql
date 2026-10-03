-- ============================================================
-- Velvet Grill
-- FR-29: admins inspect operational analytics.
--
-- One read-only, admin-gated aggregate over transactional orders.
-- analytics_events are not consulted; transactional tables remain the
-- source of truth. Gross order value excludes CANCELLED orders only
-- (a REFUNDED, non-cancelled order remains included). The RPC is
-- SECURITY DEFINER with a pinned search_path and re-checks
-- private.is_admin(); it therefore does not rely on orders RLS for its
-- authorization (RLS stays enabled and unchanged for the direct path).
-- It executes in the caller's authenticated context, so the caller JWT
-- remains available to private.is_admin(). No service-role is used and
-- no audit rows are written (reads are not audited).
-- ============================================================

create or replace function public.admin_operational_analytics(
  p_from date default null,
  p_to date default null
)
returns table(
  total_orders bigint,
  orders_pending_payment bigint,
  orders_confirmed bigint,
  orders_preparing bigint,
  orders_ready bigint,
  orders_completed bigint,
  orders_cancelled bigint,
  payments_unpaid bigint,
  payments_pending bigint,
  payments_paid bigint,
  payments_failed bigint,
  payments_expired bigint,
  payments_refunded bigint,
  fulfillment_pickup bigint,
  fulfillment_dine_in bigint,
  gross_order_value numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz   text;
  v_from date;
  v_to   date;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- The RPC owns the timezone and the authoritative timestamp boundaries.
  v_tz := coalesce(
    (select timezone from public.restaurant_settings where id = 1),
    'Asia/Jakarta'
  );

  if p_from is null and p_to is null then
    v_to   := (now() at time zone v_tz)::date;
    v_from := v_to - 6;                       -- default: last 7 calendar days
  elsif p_from is null or p_to is null then
    raise exception 'Date range is invalid' using errcode = '22023';
  else
    v_from := p_from;
    v_to   := p_to;
  end if;

  if v_from > v_to then
    raise exception 'Date range is invalid' using errcode = '22023';
  end if;

  -- Half-open window [v_from 00:00, (v_to + 1) 00:00) in restaurant TZ.
  -- Max 366 calendar days inclusive => (v_to - v_from) <= 365.
  if (v_to - v_from) > 365 then
    raise exception 'Date range is invalid' using errcode = '22023';
  end if;

  return query
  select
    count(*)::bigint,
    count(*) filter (where o.order_status = 'PENDING_PAYMENT')::bigint,
    count(*) filter (where o.order_status = 'CONFIRMED')::bigint,
    count(*) filter (where o.order_status = 'PREPARING')::bigint,
    count(*) filter (where o.order_status = 'READY')::bigint,
    count(*) filter (where o.order_status = 'COMPLETED')::bigint,
    count(*) filter (where o.order_status = 'CANCELLED')::bigint,
    count(*) filter (where o.payment_status = 'UNPAID')::bigint,
    count(*) filter (where o.payment_status = 'PENDING')::bigint,
    count(*) filter (where o.payment_status = 'PAID')::bigint,
    count(*) filter (where o.payment_status = 'FAILED')::bigint,
    count(*) filter (where o.payment_status = 'EXPIRED')::bigint,
    count(*) filter (where o.payment_status = 'REFUNDED')::bigint,
    count(*) filter (where o.fulfillment_type = 'PICKUP')::bigint,
    count(*) filter (where o.fulfillment_type = 'DINE_IN')::bigint,
    coalesce(
      sum(o.final_total) filter (where o.order_status <> 'CANCELLED'),
      0
    )
  from public.orders o
  where o.created_at >= (v_from::timestamp at time zone v_tz)
    and o.created_at <  ((v_to + 1)::timestamp at time zone v_tz);
end;
$$;

revoke all on function public.admin_operational_analytics(date, date) from public;
revoke all on function public.admin_operational_analytics(date, date) from anon;
grant execute on function public.admin_operational_analytics(date, date) to authenticated;
