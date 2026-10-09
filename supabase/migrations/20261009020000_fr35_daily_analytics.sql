-- ============================================================
-- Velvet Grill
-- FR-35: admin daily analytics trend.
--
-- Adds a separate read-only RPC for the two daily trend charts on
-- the admin analytics page: daily orders created and daily net
-- collected. The FR-29/FR-32 public.admin_operational_analytics and
-- the FR-34 public.admin_top_products RPCs are NOT modified.
--
-- Metrics (daily grain, restaurant timezone, same inclusive
-- calendar-date window as FR-32: [from 00:00, (to + 1) 00:00)):
--   orders_created      = count of ALL orders created on each day,
--                         including CANCELLED. Uses orders.created_at
--                         only, never status history or payment
--                         timestamps.
--   net_collected_value = sum(orders.final_total) where the order's
--                         CURRENT payment_status = 'PAID'. REFUNDED,
--                         UNPAID, PENDING, FAILED, and EXPIRED orders
--                         contribute zero. Order-cohort semantics are
--                         identical to FR-32: a later refund
--                         retroactively lowers the figure for the
--                         order's creation day, and refunded orders
--                         remain counted in orders_created. Reads
--                         orders.final_total only and never joins
--                         payments or order items, so duplicate rows
--                         cannot double-count.
--
-- One row is returned for EVERY calendar day in the range, including
-- days with no orders (zero-filled), ordered by day ascending. The
-- sum of daily order counts equals FR-32 total_orders and the sum of
-- daily net collected equals FR-32 net_collected_value for the same
-- window.
--
-- The calendar spine is a single bounded generate_series, LEFT JOINed
-- to one grouped daily-orders aggregate — not a correlated subquery
-- per date.
--
-- Date range: both-null defaults to the last seven calendar days; a
-- one-sided null, a reversed range, and a span greater than 365 days
-- (366 inclusive days) raise SQLSTATE 22023.
--
-- Security: SECURITY DEFINER, STABLE, pinned empty search_path,
-- re-checks private.is_admin() and raises SQLSTATE 42501 for
-- unauthorized callers, consistent with FR-29/FR-32/FR-34. Read-only:
-- no mutation of orders, payments, order items, or audit data; no
-- dynamic SQL, no new policies, no new indexes, no new dependencies.
-- ============================================================

create function public.admin_daily_analytics(
  p_from date default null,
  p_to date default null
)
returns table(
  day date,
  orders_created bigint,
  net_collected_value numeric
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

  -- The RPC owns the timezone and the authoritative timestamp
  -- boundaries, exactly as FR-32 does.
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
  with day_spine as (
    select (gs.day_ts)::date as day
    from pg_catalog.generate_series(
      v_from::timestamp,
      v_to::timestamp,
      interval '1 day'
    ) as gs(day_ts)
  ),
  daily_totals as (
    select
      ((o.created_at at time zone v_tz)::date) as day,
      count(*)::bigint as orders_n,
      coalesce(
        sum(o.final_total) filter (where o.payment_status = 'PAID'),
        0
      ) as net_value
    from public.orders o
    where o.created_at >= (v_from::timestamp at time zone v_tz)
      and o.created_at <  ((v_to + 1)::timestamp at time zone v_tz)
    group by 1
  )
  select
    s.day,
    coalesce(t.orders_n, 0::bigint),
    coalesce(t.net_value, 0::numeric)
  from day_spine s
  left join daily_totals t on t.day = s.day
  order by s.day asc;
end;
$$;

revoke all on function public.admin_daily_analytics(date, date) from public;
revoke all on function public.admin_daily_analytics(date, date) from anon;
grant execute on function public.admin_daily_analytics(date, date) to authenticated;

comment on function public.admin_daily_analytics(date, date) is
'Admin-only daily analytics trend (FR-35). Read-only one-row-per-day series over '
'public.orders in the restaurant timezone; SECURITY DEFINER, re-checks '
'private.is_admin(). Same inclusive calendar-date window and 366-day maximum as FR-32. '
'orders_created = count of all orders created each day, including CANCELLED, using '
'orders.created_at only. net_collected_value = sum(final_total) for orders whose '
'current payment_status = PAID (REFUNDED/UNPAID/PENDING/FAILED/EXPIRED contribute '
'zero); order-cohort semantics identical to FR-32, so a later refund lowers the '
'creation-day figure. Every day in the range is returned, zero-filled, ordered by day '
'ascending; the daily sums reconcile with FR-32 total_orders and net_collected_value. '
'No joins to payments or order items, so no row duplication is possible.';
