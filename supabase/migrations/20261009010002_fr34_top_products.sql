-- ============================================================
-- Velvet Grill
-- FR-34: admin top products analytics.
--
-- Adds a separate read-only RPC for the Top Products section of the
-- admin analytics page. The FR-29/FR-32 public.admin_operational_
-- analytics RPC is NOT modified in any way.
--
-- Metric: "Units fulfilled" — an operational fulfillment metric, not
-- a revenue metric.
--   - Only orders with order_status = 'COMPLETED' contribute.
--   - The value is the sum of order_items.quantity across order lines
--     (not the number of order lines), aggregated in the database.
--   - Pending, confirmed, preparing, ready, and cancelled orders are
--     excluded. A completed order later marked REFUNDED remains
--     included: the units were fulfilled operationally regardless of
--     the payment outcome.
--   - Attribution uses orders.created_at (never order_items.created_at)
--     over the same restaurant-timezone, inclusive calendar-date
--     window as FR-32: [from 00:00, (to + 1) 00:00) in the restaurant
--     timezone, maximum 366 inclusive calendar days.
--
-- Product identity and display names:
--   - When order_items.product_id is available, lines aggregate by
--     product_id, so multiple order lines and historical name changes
--     for the same product count together.
--   - The displayed name is the latest product_name_snapshot among the
--     qualifying lines, ordered by order creation time, then order-item
--     id, for determinism. Historical names are never derived from
--     public.products.name.
--   - When product_id IS NULL (catalog product removed, ON DELETE SET
--     NULL), historical rows are preserved by grouping on the
--     product_name_snapshot under a namespaced fallback key
--     ('deleted:' || snapshot) that cannot collide with a product UUID
--     key. Known limitation: distinct deleted products that shared an
--     identical historical snapshot name can no longer be told apart
--     once product_id is lost, and are reported as one row. The
--     historical schema is not modified to solve this.
--
-- Ranking: units_fulfilled DESC, then product name ascending, then
-- product identity key ascending; maximum five rows. A range without
-- completed order items returns zero rows, never fabricated zeros.
--
-- Security: SECURITY DEFINER, STABLE, pinned empty search_path,
-- re-checks private.is_admin() and raises SQLSTATE 42501 for
-- unauthorized callers, consistent with FR-29/FR-32. Read-only: no
-- mutation of orders, payments, order items, stock, or analytics
-- events; no dynamic SQL, no new policies, no new indexes.
-- ============================================================

create function public.admin_top_products(
  p_from date default null,
  p_to date default null
)
returns table(
  product_key text,
  product_name text,
  units_fulfilled bigint
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

  -- The RPC owns the timezone and the authoritative timestamp boundaries,
  -- exactly as FR-32 does.
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
  with completed_lines as (
    select
      oi.id as item_id,
      oi.product_id,
      oi.product_name_snapshot,
      oi.quantity,
      o.created_at as order_created_at
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where o.order_status = 'COMPLETED'
      and o.created_at >= (v_from::timestamp at time zone v_tz)
      and o.created_at <  ((v_to + 1)::timestamp at time zone v_tz)
  ),
  keyed as (
    select
      coalesce(
        product_id::text,
        'deleted:' || product_name_snapshot
      ) as key_text,
      product_name_snapshot as snap_name,
      quantity,
      order_created_at,
      item_id
    from completed_lines
  ),
  units as (
    select
      key_text,
      sum(quantity)::bigint as units_total
    from keyed
    group by key_text
  ),
  latest_names as (
    select distinct on (key_text)
      key_text,
      snap_name
    from keyed
    order by key_text, order_created_at desc, item_id desc
  )
  select
    units.key_text,
    latest_names.snap_name,
    units.units_total
  from units
  join latest_names on latest_names.key_text = units.key_text
  order by
    units.units_total desc,
    latest_names.snap_name asc,
    units.key_text asc
  limit 5;
end;
$$;

revoke all on function public.admin_top_products(date, date) from public;
revoke all on function public.admin_top_products(date, date) from anon;
grant execute on function public.admin_top_products(date, date) to authenticated;

comment on function public.admin_top_products(date, date) is
'Admin-only Top Products analytics (FR-34). Read-only ranking of the five products '
'with the highest fulfilled unit quantity in the selected range; SECURITY DEFINER, '
're-checks private.is_admin(). Eligibility: order_status = COMPLETED only (includes '
'completed orders later marked REFUNDED — units fulfilled is an operational metric, '
'not net collected revenue); the value is sum(order_items.quantity) across order '
'lines, attributed to the order creation date in the restaurant timezone (same '
'inclusive calendar-date window and 366-day maximum as FR-32). Identity: lines '
'aggregate by order_items.product_id when present; when the catalog product was '
'removed (product_id lost to ON DELETE SET NULL), rows are preserved under the '
'namespaced key ''deleted:'' || product_name_snapshot. Display name is the latest '
'product_name_snapshot among qualifying lines (order creation time, then order-item '
'id). Known limitation: distinct deleted products sharing an identical historical '
'snapshot name cannot be distinguished and are reported as one row. Ranking: '
'units_fulfilled desc, product name asc, product key asc, limit 5.';
