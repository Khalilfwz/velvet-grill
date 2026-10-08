-- ============================================================
-- Velvet Grill
-- FR-32: financial analytics correctness.
--
-- Extends the FR-29 operational analytics RPC with clearly defined
-- financial metrics. The existing payment/refund/expiry behavior
-- (FR-17/GAP-05/FR-31) is untouched: this is a read-only reporting
-- change over public.orders.
--
-- The return shape gains columns, which PostgreSQL cannot apply via
-- CREATE OR REPLACE (a changed RETURNS TABLE is a changed return
-- type), so the function is dropped and recreated. The DROP is
-- deliberately bare (no CASCADE): any untracked dependency must fail
-- this migration instead of being silently destroyed. All 16 legacy
-- columns keep their names, order, types, and semantics; the 5 new
-- columns are appended. Grants and security attributes are restored.
--
-- Metric definitions (all over the same created_at window and
-- restaurant timezone as FR-29; order-cohort semantics: every metric
-- is attributed to the day the order was created, and re-querying an
-- older range reflects the order's current payment state — these are
-- point-in-time states of a created-at cohort, not an immutable
-- daily ledger):
--   Booked order value      = legacy gross_order_value, unchanged:
--                             sum(final_total) where order_status
--                             <> CANCELLED (includes REFUNDED
--                             non-cancelled orders).
--   Gross settled value     = sum(final_total) where payment_status
--                             in (PAID, REFUNDED): all money ever
--                             captured, regardless of later refund
--                             or order lifecycle.
--   Refunded value          = sum(final_total) where payment_status
--                             = REFUNDED.
--   Net collected value     = sum(final_total) where payment_status
--                             = PAID.
--   Settled orders          = count where payment_status in
--                             (PAID, REFUNDED).
--   Average settled order   = gross settled value / settled orders,
--                             NULL when no settled orders exist.
--   By construction (payment_status is single-valued): gross settled
--   = net collected + refunded. Aggregation reads orders.final_total
--   only and never joins payments, so duplicate payment rows cannot
--   double-count. Booked (order lifecycle) and settled (payment
--   lifecycle) are separate dimensions and must not be summed.
--
-- The RPC stays SECURITY DEFINER with a pinned search_path and
-- re-checks private.is_admin(); authorization is unchanged.
-- ============================================================

drop function public.admin_operational_analytics(date, date);

create function public.admin_operational_analytics(
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
  gross_order_value numeric,
  settled_orders bigint,
  gross_settled_value numeric,
  refunded_value numeric,
  net_collected_value numeric,
  avg_settled_order_value numeric
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
    ),
    count(*) filter (where o.payment_status in ('PAID', 'REFUNDED'))::bigint,
    coalesce(
      sum(o.final_total) filter (where o.payment_status in ('PAID', 'REFUNDED')),
      0
    ),
    coalesce(
      sum(o.final_total) filter (where o.payment_status = 'REFUNDED'),
      0
    ),
    coalesce(
      sum(o.final_total) filter (where o.payment_status = 'PAID'),
      0
    ),
    coalesce(
      sum(o.final_total) filter (where o.payment_status in ('PAID', 'REFUNDED')),
      0
    ) / nullif(
      count(*) filter (where o.payment_status in ('PAID', 'REFUNDED')),
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

comment on function public.admin_operational_analytics(date, date) is
'Admin-only operational and financial analytics (FR-29/FR-32). Read-only single-row '
'aggregate over public.orders; SECURITY DEFINER, re-checks private.is_admin(). '
'Metrics are attributed to the day the order was created (restaurant timezone) — '
'order-cohort semantics: re-querying an older range reflects the current payment '
'state of that cohort, not a historical ledger. Definitions: '
'booked order value (gross_order_value) = sum(final_total) where order_status <> CANCELLED '
'(legacy FR-29 semantics; includes REFUNDED non-cancelled orders); '
'gross settled value = sum(final_total) where payment_status in (PAID, REFUNDED); '
'refunded value = sum(final_total) where payment_status = REFUNDED; '
'net collected value = sum(final_total) where payment_status = PAID; '
'settled orders = count where payment_status in (PAID, REFUNDED); '
'average settled order value = gross settled value / settled orders, '
'NULL when no settled orders. Identity: gross settled = net collected + refunded. '
'Booked (order lifecycle) and settled (payment lifecycle) are separate dimensions.';
