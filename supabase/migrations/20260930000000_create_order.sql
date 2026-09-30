-- ============================================================
-- Velvet Grill
-- FR-13: customer order placement (pickup and dine-in)
--
-- Customers have no INSERT policy on public.orders (order
-- creation is intentionally server-controlled), so the only
-- authorized creation path is this SECURITY DEFINER function.
-- It re-derives identity, revalidates all inputs and the whole
-- cart against current database state, computes every monetary
-- and snapshot value itself, and writes order + items + options
-- in a single transaction.
-- ============================================================

-- ------------------------------------------------------------
-- Order number sequence
-- ------------------------------------------------------------

create sequence if not exists private.order_number_seq;

revoke all on sequence private.order_number_seq
  from public, anon, authenticated;

-- ------------------------------------------------------------
-- Order-creation idempotency
--
-- Nullable so existing/admin order paths and fixtures are
-- unaffected. Uniqueness is scoped to the authenticated
-- customer: one order per (customer, idempotency key).
-- ------------------------------------------------------------

alter table public.orders
  add column if not exists idempotency_key text;

comment on column public.orders.idempotency_key is
  'Client-supplied idempotency key for server-created orders. Identifier only, not proof of identity or ownership.';

create unique index if not exists orders_user_idempotency_key_unique
  on public.orders (user_id, idempotency_key)
  where idempotency_key is not null;

-- ------------------------------------------------------------
-- Order creation
-- ------------------------------------------------------------

create or replace function public.create_order(
  p_fulfillment_type public.order_fulfillment_type,
  p_customer_name text,
  p_customer_phone text,
  p_customer_note text,
  p_pickup_at timestamptz,
  p_restaurant_table_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_cart_id uuid;
  v_order_id uuid;
  v_existing_order_id uuid;
  v_order_item_id uuid;
  v_table_number text;
  v_order_number text;
  v_name text := btrim(coalesce(p_customer_name, ''));
  v_phone text := nullif(btrim(coalesce(p_customer_phone, '')), '');
  v_note text := nullif(btrim(coalesce(p_customer_note, '')), '');
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_subtotal numeric(12, 2) := 0;
  v_delta numeric(12, 2);
  v_line record;
begin
  -- 1. Identity is authoritative; the idempotency key is not identity.
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- 2. Independent input validation (clients can call this directly).
  if v_key is null or length(v_key) > 100 then
    raise exception 'Order key is invalid' using errcode = '22023';
  end if;

  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Customer name is invalid' using errcode = '22023';
  end if;

  if v_phone is not null and length(v_phone) > 32 then
    raise exception 'Customer phone is invalid' using errcode = '22023';
  end if;

  if v_note is not null and length(v_note) > 500 then
    raise exception 'Customer note is invalid' using errcode = '22023';
  end if;

  if p_fulfillment_type = 'PICKUP' then
    if p_pickup_at is null or p_restaurant_table_id is not null then
      raise exception 'Pickup details are invalid' using errcode = '22023';
    end if;
  elsif p_fulfillment_type = 'DINE_IN' then
    if p_restaurant_table_id is null or p_pickup_at is not null then
      raise exception 'Dine-in details are invalid' using errcode = '22023';
    end if;

    select rt.table_number
    into v_table_number
    from public.restaurant_tables rt
    where rt.id = p_restaurant_table_id
      and rt.is_active = true;

    if v_table_number is null then
      raise exception 'The selected table is not available'
        using errcode = '22023';
    end if;
  else
    raise exception 'Fulfillment type is invalid' using errcode = '22023';
  end if;

  -- 3. Idempotent replay, fast path (before any cart/empty check).
  select o.id
  into v_existing_order_id
  from public.orders o
  where o.user_id = v_user_id
    and o.idempotency_key = v_key;

  if v_existing_order_id is not null then
    return v_existing_order_id;
  end if;

  -- 4. Lock the caller's cart row to serialize concurrent requests.
  select c.id
  into v_cart_id
  from public.carts c
  where c.user_id = v_user_id
  for update;

  if v_cart_id is null then
    raise exception 'Your cart is empty' using errcode = '22023';
  end if;

  -- 5. Authoritative idempotent replay, now serialized by the row lock.
  select o.id
  into v_existing_order_id
  from public.orders o
  where o.user_id = v_user_id
    and o.idempotency_key = v_key;

  if v_existing_order_id is not null then
    return v_existing_order_id;
  end if;

  -- 6. Cart must not be empty.
  if not exists (
    select 1 from public.cart_items ci where ci.cart_id = v_cart_id
  ) then
    raise exception 'Your cart is empty' using errcode = '22023';
  end if;

  -- 7a. Products and categories must still be available.
  if exists (
    select 1
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    join public.categories c on c.id = p.category_id
    where ci.cart_id = v_cart_id
      and (p.is_available = false or c.is_active = false)
  ) then
    raise exception 'Some items are no longer available' using errcode = '22023';
  end if;

  -- 7b. Selected options must still belong to the product, be available,
  --     and live in an active group.
  if exists (
    select 1
    from public.cart_items ci
    join public.cart_item_options cio on cio.cart_item_id = ci.id
    join public.product_options po on po.id = cio.product_option_id
    join public.product_option_groups pog on pog.id = po.group_id
    where ci.cart_id = v_cart_id
      and (
        pog.product_id <> ci.product_id
        or po.is_available = false
        or pog.is_active = false
      )
  ) then
    raise exception 'Some selected options are no longer available'
      using errcode = '22023';
  end if;

  -- 7c. Current required-group / SINGLE-MULTIPLE / min-max cardinality.
  if exists (
    select 1
    from public.cart_items ci
    join public.product_option_groups g
      on g.product_id = ci.product_id
     and g.is_active = true
    left join (
      select cio.cart_item_id, po.group_id, count(*) as selected_count
      from public.cart_item_options cio
      join public.product_options po on po.id = cio.product_option_id
      group by cio.cart_item_id, po.group_id
    ) sel
      on sel.cart_item_id = ci.id
     and sel.group_id = g.id
    where ci.cart_id = v_cart_id
      and (
        coalesce(sel.selected_count, 0)
          < greatest(g.min_selections, case when g.is_required then 1 else 0 end)
        or coalesce(sel.selected_count, 0)
          > coalesce(
              case
                when g.selection_type = 'SINGLE' then 1
                else g.max_selections
              end,
              2147483647
            )
      )
  ) then
    raise exception 'Your selection is no longer valid for this product'
      using errcode = '22023';
  end if;

  -- 8. Compute totals from current database rows (no child writes yet).
  select coalesce(
           sum(ci.quantity * (p.base_price + coalesce(opt.delta, 0))),
           0
         )
  into v_subtotal
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  left join lateral (
    select sum(po.price_delta) as delta
    from public.cart_item_options cio
    join public.product_options po on po.id = cio.product_option_id
    where cio.cart_item_id = ci.id
  ) opt on true
  where ci.cart_id = v_cart_id;

  -- 9. Insert the parent order first.
  v_order_number :=
    'VG-' || to_char(now(), 'YYYYMMDD') || '-' ||
    lpad(nextval('private.order_number_seq')::text, 6, '0');

  begin
    insert into public.orders (
      order_number,
      user_id,
      fulfillment_type,
      pickup_at,
      restaurant_table_id,
      table_number_snapshot,
      customer_name_snapshot,
      customer_phone_snapshot,
      subtotal,
      discount_total,
      final_total,
      customer_note,
      idempotency_key
    )
    values (
      v_order_number,
      v_user_id,
      p_fulfillment_type,
      p_pickup_at,
      p_restaurant_table_id,
      v_table_number,
      v_name,
      v_phone,
      v_subtotal,
      0,
      v_subtotal,
      v_note,
      v_key
    )
    returning id into v_order_id;
  exception
    when unique_violation then
      -- Narrowly scoped: only a conflict on this customer's existing
      -- idempotency key is treated as a replay. Any other unique violation
      -- (e.g. order_number) is re-raised and never misclassified.
      select o.id
      into v_order_id
      from public.orders o
      where o.user_id = v_user_id
        and o.idempotency_key = v_key;

      if v_order_id is null then
        raise;
      end if;

      return v_order_id;
  end;

  -- 10 & 11. Child rows: order items, then their option snapshots.
  for v_line in
    select ci.id as cart_item_id, ci.product_id, ci.quantity, p.name, p.base_price
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart_id
    order by ci.created_at, ci.id
  loop
    select coalesce(sum(po.price_delta), 0)
    into v_delta
    from public.cart_item_options cio
    join public.product_options po on po.id = cio.product_option_id
    where cio.cart_item_id = v_line.cart_item_id;

    insert into public.order_items (
      order_id,
      product_id,
      product_name_snapshot,
      base_price_snapshot,
      final_unit_price,
      quantity,
      subtotal
    )
    values (
      v_order_id,
      v_line.product_id,
      v_line.name,
      v_line.base_price,
      v_line.base_price + v_delta,
      v_line.quantity,
      v_line.quantity * (v_line.base_price + v_delta)
    )
    returning id into v_order_item_id;

    insert into public.order_item_options (
      order_item_id,
      product_option_id,
      option_group_name_snapshot,
      option_name_snapshot,
      price_delta_snapshot
    )
    select
      v_order_item_id,
      po.id,
      pog.name,
      po.name,
      po.price_delta
    from public.cart_item_options cio
    join public.product_options po on po.id = cio.product_option_id
    join public.product_option_groups pog on pog.id = po.group_id
    where cio.cart_item_id = v_line.cart_item_id;
  end loop;

  -- 12. Clear the cart only after every order row was created.
  delete from public.cart_items where cart_id = v_cart_id;

  -- 13.
  return v_order_id;
end;
$$;

revoke all on function public.create_order(
  public.order_fulfillment_type, text, text, text, timestamptz, uuid, text
) from public, anon;

grant execute on function public.create_order(
  public.order_fulfillment_type, text, text, text, timestamptz, uuid, text
) to authenticated;
