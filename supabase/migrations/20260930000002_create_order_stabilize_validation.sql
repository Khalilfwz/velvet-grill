-- ============================================================
-- Velvet Grill
-- FR-13 correction: stabilize cart and catalog state before
-- public.create_order validates and materializes.
--
-- In 20260930000001 the non-empty check and all validation ran
-- BEFORE the cart-item lock, and the selected option rows were
-- never locked:
--   * items could be deleted between the non-empty check and the
--     item lock, allowing a zero-item order;
--   * option rows could be deleted between validation and
--     materialization;
--   * locking only the parent cart_items blocks option INSERTs
--     (FK FOR KEY SHARE conflicts with FOR UPDATE) but does NOT
--     block child DELETEs, which lock the child row itself.
--
-- Corrected order of operations:
--   1 identity -> 2 input validation -> 3 idempotency fast path
--   -> 4 lock carts row -> 5 post-lock idempotency replay
--   -> 6 lock + capture existing cart_items (frozen id set)
--   -> 7 lock existing cart_item_options for those items
--   -> 8 non-empty check against the locked set
--   -> 9 validate AND materialize from ONE statement/snapshot
--   -> 10 insert parent -> 11 insert children from that snapshot
--   -> 12 delete only the consumed items -> 13 return
--
-- Catalog rows are never locked: validation and materialization
-- read them in a single statement, so one coherent snapshot is
-- used for both and they cannot disagree.
--
-- Signature, grants and error messages are unchanged.
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
  v_cart_item_id uuid;
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
  v_invalid_availability boolean := false;
  v_invalid_option boolean := false;
  v_invalid_selection boolean := false;
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

  -- 6. Lock AND capture the existing cart items in one pass, so the frozen id
  --    set is exactly the locked set. Items inserted concurrently are not
  --    blocked (nothing can lock a row that does not exist yet) but are not
  --    captured here, so they are never ordered or deleted by this call.
  for v_cart_item_id in
    select ci.id
    from public.cart_items ci
    where ci.cart_id = v_cart_id
    for update
  loop
    v_item_ids := v_item_ids || v_cart_item_id;
  end loop;

  -- 7. Stabilize the option rows themselves. Locking the parent cart_items
  --    already blocks option INSERTs (the FK check takes FOR KEY SHARE, which
  --    conflicts with FOR UPDATE), but a child DELETE locks only the child row,
  --    so the existing option rows are locked explicitly here.
  perform 1
  from public.cart_item_options cio
  where cio.cart_item_id = any (v_item_ids)
  for update;

  -- 8. Non-empty check against the locked/current item set, never earlier.
  if coalesce(array_length(v_item_ids, 1), 0) = 0 then
    raise exception 'Your cart is empty' using errcode = '22023';
  end if;

  -- 9 & 10. Validate and materialize from ONE statement, restricted to the
  --         stabilized item set. Because it is a single statement, the
  --         product/category/option/group rows are read from one coherent
  --         snapshot, so validation cannot disagree with the snapshot.
  with line_items as (
    select
      ci.id as cart_item_id,
      ci.product_id,
      ci.quantity,
      ci.created_at,
      p.name as product_name,
      p.base_price,
      p.is_available as product_available,
      c.is_active as category_active
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    join public.categories c on c.id = p.category_id
    where ci.id = any (v_item_ids)
  ),
  selected_options as (
    select
      cio.cart_item_id,
      po.id as option_id,
      po.name as option_name,
      po.price_delta,
      po.is_available as option_available,
      pog.id as group_id,
      pog.name as group_name,
      pog.is_active as group_active,
      pog.product_id as group_product_id
    from public.cart_item_options cio
    join public.product_options po on po.id = cio.product_option_id
    join public.product_option_groups pog on pog.id = po.group_id
    where cio.cart_item_id = any (v_item_ids)
  ),
  line_options as (
    select
      so.cart_item_id,
      sum(so.price_delta) as option_delta,
      jsonb_agg(
        jsonb_build_object(
          'product_option_id', so.option_id,
          'group_name', so.group_name,
          'option_name', so.option_name,
          'price_delta', so.price_delta
        )
        order by so.group_name, so.option_name, so.option_id
      ) as options
    from selected_options so
    group by so.cart_item_id
  ),
  materialized as (
    select
      li.cart_item_id,
      li.product_id,
      li.quantity,
      li.created_at,
      li.product_name,
      li.base_price,
      li.base_price + coalesce(lo.option_delta, 0) as unit_price,
      coalesce(lo.options, '[]'::jsonb) as options
    from line_items li
    left join line_options lo on lo.cart_item_id = li.cart_item_id
  ),
  flags as (
    select
      exists (
        select 1
        from line_items li
        where li.product_available = false or li.category_active = false
      ) as invalid_availability,
      exists (
        select 1
        from line_items li
        join selected_options so on so.cart_item_id = li.cart_item_id
        where so.group_product_id <> li.product_id
           or so.option_available = false
           or so.group_active = false
      ) as invalid_option,
      exists (
        select 1
        from line_items li
        join public.product_option_groups g
          on g.product_id = li.product_id
         and g.is_active = true
        left join (
          select so.cart_item_id, so.group_id, count(*) as selected_count
          from selected_options so
          group by so.cart_item_id, so.group_id
        ) cnt
          on cnt.cart_item_id = li.cart_item_id
         and cnt.group_id = g.id
        where
          coalesce(cnt.selected_count, 0)
            < greatest(g.min_selections, case when g.is_required then 1 else 0 end)
          or coalesce(cnt.selected_count, 0)
            > coalesce(
                case
                  when g.selection_type = 'SINGLE' then 1
                  else g.max_selections
                end,
                2147483647
              )
      ) as invalid_selection
  )
  select
    coalesce(
      (select sum(m.quantity * m.unit_price) from materialized m),
      0
    ),
    coalesce(
      (select jsonb_agg(m order by m.created_at, m.cart_item_id)
       from materialized m),
      '[]'::jsonb
    ),
    f.invalid_availability,
    f.invalid_option,
    f.invalid_selection
  into
    v_subtotal,
    v_lines,
    v_invalid_availability,
    v_invalid_option,
    v_invalid_selection
  from flags f;

  if v_invalid_availability then
    raise exception 'Some items are no longer available' using errcode = '22023';
  end if;

  if v_invalid_option then
    raise exception 'Some selected options are no longer available'
      using errcode = '22023';
  end if;

  if v_invalid_selection then
    raise exception 'Your selection is no longer valid for this product'
      using errcode = '22023';
  end if;

  -- 11. Insert the parent order first.
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

  -- 12. Child rows, written from the same materialized snapshot.
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

  -- 13. Clear only the items this order actually consumed.
  delete from public.cart_items
  where id = any (v_item_ids);

  -- 14.
  return v_order_id;
end;
$$;

revoke all on function public.create_order(
  public.order_fulfillment_type, text, text, text, timestamptz, uuid, text
) from public, anon;

grant execute on function public.create_order(
  public.order_fulfillment_type, text, text, text, timestamptz, uuid, text
) to authenticated;
