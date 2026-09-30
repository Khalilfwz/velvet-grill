-- ============================================================
-- Velvet Grill
-- FR-13 correction: internal snapshot consistency for
-- public.create_order.
--
-- Previously the parent order total was computed from one read
-- while order_items / order_item_options re-read live product
-- and option values later. Under READ COMMITTED a concurrent
-- catalog update could leave the parent total disagreeing with
-- its child snapshots.
--
-- The line/option snapshot data is now materialized exactly once
-- and used for both the parent total and the child rows, and the
-- cart's existing item rows are locked FOR UPDATE so concurrent
-- cart mutations serialize against order creation. Only the items
-- this order actually consumed are cleared, so a concurrently
-- added item is never silently destroyed.
--
-- Signature and grants are unchanged.
-- ============================================================

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
  v_lines jsonb := '[]'::jsonb;
  v_line jsonb;
  v_item_ids uuid[] := array[]::uuid[];
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

  -- 4. Lock the caller's cart row to serialize order creation per customer.
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

  -- 7d. Lock the cart's existing item rows. FOR UPDATE blocks concurrent
  --     updates/deletes of these rows and, through the foreign key's
  --     FOR KEY SHARE, concurrent option inserts for them, so the snapshot
  --     taken below cannot be mutated underneath this order.
  perform 1
  from public.cart_items ci
  where ci.cart_id = v_cart_id
  for update;

  -- 8. Materialize the authoritative line and option snapshot data exactly
  --    once. The parent total and every child row are derived from this same
  --    single read, so they can never disagree.
  select
    coalesce(sum(li.quantity * li.unit_price), 0),
    coalesce(jsonb_agg(li order by li.created_at, li.cart_item_id), '[]'::jsonb),
    coalesce(
      array_agg(li.cart_item_id order by li.created_at, li.cart_item_id),
      array[]::uuid[]
    )
  into v_subtotal, v_lines, v_item_ids
  from (
    select
      ci.id as cart_item_id,
      ci.product_id,
      ci.quantity,
      ci.created_at,
      p.name as product_name,
      p.base_price,
      p.base_price + coalesce(opts.delta, 0) as unit_price,
      coalesce(opts.options, '[]'::jsonb) as options
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join lateral (
      select
        sum(po.price_delta) as delta,
        jsonb_agg(
          jsonb_build_object(
            'product_option_id', po.id,
            'group_name', pog.name,
            'option_name', po.name,
            'price_delta', po.price_delta
          )
          order by pog.name, po.name, po.id
        ) as options
      from public.cart_item_options cio
      join public.product_options po on po.id = cio.product_option_id
      join public.product_option_groups pog on pog.id = po.group_id
      where cio.cart_item_id = ci.id
    ) opts on true
    where ci.cart_id = v_cart_id
  ) li;

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

  -- 10 & 11. Child rows, written from the materialized snapshot only.
  for v_line in
    select value from jsonb_array_elements(v_lines)
  loop
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
      (v_line ->> 'product_id')::uuid,
      v_line ->> 'product_name',
      (v_line ->> 'base_price')::numeric,
      (v_line ->> 'unit_price')::numeric,
      (v_line ->> 'quantity')::integer,
      (v_line ->> 'quantity')::integer * (v_line ->> 'unit_price')::numeric
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
      (opt ->> 'product_option_id')::uuid,
      opt ->> 'group_name',
      opt ->> 'option_name',
      (opt ->> 'price_delta')::numeric
    from jsonb_array_elements(v_line -> 'options') as opt;
  end loop;

  -- 12. Clear only the items this order actually consumed, so a concurrently
  --     added item is never silently destroyed.
  delete from public.cart_items
  where id = any (v_item_ids);

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
