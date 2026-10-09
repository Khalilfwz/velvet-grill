-- ============================================================
-- Velvet Grill
-- BUG-03: cart item merging
--
-- Adding the same product with an identical option selection
-- produced duplicate cart lines. Cart line identity is
-- (cart, product, exact set of cart_item_options rows), which
-- no constraint expressed and the application never checked.
--
-- This migration provides, in order:
--   1. add_cart_item(): the only authorized add path. Follows
--      the create_order pattern (SECURITY DEFINER, re-derived
--      identity, full revalidation, single transaction) and
--      merges into an existing line instead of duplicating.
--   2. assert_cart_line_unique() + repair: non-lossy merge of
--      pre-existing duplicate lines, aborting (never clamping)
--      if a group sums beyond the quantity limit, then a full
--      validation pass.
--   3. Deferred constraint triggers enforcing the invariant on
--      every committed write path, including direct writes.
--
-- Cross-transaction safety: a deferred trigger's duplicate
-- query alone is not race-safe (two commits can check against
-- snapshots that exclude each other). The check therefore locks
-- the parent carts row FOR UPDATE first; commit-time checks for
-- the same cart serialize, and the post-wait re-check runs on a
-- fresh snapshot that sees the winner's rows.
-- ============================================================

-- ------------------------------------------------------------
-- Line identity helper expressions
--
-- A line's option signature is the sorted set of its
-- cart_item_options product_option_id rows (empty set when the
-- item has no options). It is always derived at check time —
-- never stored — so it cannot become stale or forged.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Uniqueness check
-- ------------------------------------------------------------

create or replace function public.assert_cart_line_unique(
  p_cart_item_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart_id uuid;
  v_product_id uuid;
  v_line_sig uuid[];
begin
  select
    ci.cart_id,
    ci.product_id,
    coalesce((
      select array_agg(cio.product_option_id order by cio.product_option_id)
      from public.cart_item_options cio
      where cio.cart_item_id = ci.id
    ), '{}') as sig
  into v_cart_id, v_product_id, v_line_sig
  from public.cart_items ci
  where ci.id = p_cart_item_id;

  -- The line vanished inside this transaction (e.g. cascade
  -- delete in progress): it cannot be part of a duplicate.
  if v_cart_id is null then
    return;
  end if;

  -- Serialize all commit-time checks for this cart. The lock is
  -- held until this committing transaction completes, so a
  -- concurrent writer's check waits here and then re-reads on a
  -- fresh snapshot that includes the committed winner.
  perform 1
  from public.carts c
  where c.id = v_cart_id
  for update;

  -- The cart itself vanished (cascade in progress).
  if not found then
    return;
  end if;

  if exists (
    select 1
    from public.cart_items other
    where other.cart_id = v_cart_id
      and other.product_id = v_product_id
      and other.id <> p_cart_item_id
      and coalesce((
        select array_agg(cio.product_option_id order by cio.product_option_id)
        from public.cart_item_options cio
        where cio.cart_item_id = other.id
      ), '{}') = v_line_sig
  ) then
    raise exception 'Duplicate cart line for product % in cart %', v_product_id, v_cart_id
      using errcode = '23505';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- Trigger wrappers
-- ------------------------------------------------------------

create or replace function public.cart_items_unique_line_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.assert_cart_line_unique(new.id);
  return null;
end;
$$;

create or replace function public.cart_item_options_unique_line_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.assert_cart_line_unique(
    case when tg_op = 'DELETE' then old.cart_item_id else new.cart_item_id end
  );
  return null;
end;
$$;

-- ------------------------------------------------------------
-- Non-lossy repair of pre-existing duplicate lines
--
-- Groups committed lines by identity. Per duplicate group the
-- earliest line survives with the SUM of the group's quantities;
-- the others are deleted (option rows cascade). A group summing
-- beyond the application limit stops the migration with a
-- reported conflict — quantities are never clamped or discarded.
-- Non-group rows are never touched. Ends with a full validation
-- pass: deferred triggers only fire for rows modified in this
-- transaction, so untouched duplicates need an explicit check.
-- ------------------------------------------------------------

create or replace function public.repair_duplicate_cart_lines()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group record;
  v_survivor_id uuid;
begin
  for v_group in
    with line_sigs as (
      select
        ci.id,
        ci.cart_id,
        ci.product_id,
        ci.quantity,
        coalesce((
          select array_agg(cio.product_option_id order by cio.product_option_id)
          from public.cart_item_options cio
          where cio.cart_item_id = ci.id
        ), '{}') as sig
      from public.cart_items ci
    )
    select
      cart_id,
      product_id,
      sig,
      count(*) as line_count,
      sum(quantity) as total_quantity
    from line_sigs
    group by cart_id, product_id, sig
    having count(*) > 1
    order by cart_id, product_id, sig
  loop
    if v_group.total_quantity > 99 then
      raise exception
        'Cart repair stopped: duplicate lines for product % in cart % sum to % across % lines, exceeding the quantity limit of 99',
        v_group.product_id, v_group.cart_id, v_group.total_quantity, v_group.line_count
        using errcode = 'P0001';
    end if;

    select ci.id
    into v_survivor_id
    from public.cart_items ci
    where ci.cart_id = v_group.cart_id
      and ci.product_id = v_group.product_id
      and coalesce((
        select array_agg(cio.product_option_id order by cio.product_option_id)
        from public.cart_item_options cio
        where cio.cart_item_id = ci.id
      ), '{}') = v_group.sig
    order by ci.created_at, ci.id
    limit 1;

    update public.cart_items
    set quantity = v_group.total_quantity
    where id = v_survivor_id;

    delete from public.cart_items
    where cart_id = v_group.cart_id
      and product_id = v_group.product_id
      and id <> v_survivor_id
      and coalesce((
        select array_agg(cio.product_option_id order by cio.product_option_id)
        from public.cart_item_options cio
        where cio.cart_item_id = cart_items.id
      ), '{}') = v_group.sig;
  end loop;

  if exists (
    with line_sigs as (
      select
        ci.cart_id,
        ci.product_id,
        coalesce((
          select array_agg(cio.product_option_id order by cio.product_option_id)
          from public.cart_item_options cio
          where cio.cart_item_id = ci.id
        ), '{}') as sig
      from public.cart_items ci
    )
    select 1
    from line_sigs
    group by cart_id, product_id, sig
    having count(*) > 1
  ) then
    raise exception 'Cart repair validation failed: duplicate cart lines remain'
      using errcode = 'P0001';
  end if;
end;
$$;

-- Repair runs before the triggers exist; the whole migration is
-- one transaction, so a conflict aborts everything atomically.
select public.repair_duplicate_cart_lines();

-- ------------------------------------------------------------
-- add_cart_item: authorized merge-aware add path
--
-- Clients can call RPCs directly, so the function re-derives
-- identity and revalidates every input against current database
-- state. The item, its cart, and all option rows are written in
-- a single transaction.
-- ------------------------------------------------------------

create or replace function public.add_cart_item(
  p_product_id uuid,
  p_quantity integer,
  p_option_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_cart_id uuid;
  v_option_ids uuid[];
  v_existing_item_id uuid;
  v_current_quantity integer;
  v_item_id uuid;
  v_group record;
  v_selected integer;
begin
  -- 1. Identity is authoritative.
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  -- 2. Independent input validation.
  if p_quantity is null or p_quantity < 1 or p_quantity > 99 then
    raise exception 'Cart quantity is invalid' using errcode = '22023';
  end if;

  -- Deduplicate submitted option ids: identity is a set.
  v_option_ids := coalesce((
    select array_agg(distinct o order by o)
    from unnest(coalesce(p_option_ids, '{}')) as o
  ), '{}');

  -- 3. The product must exist and be available.
  if not exists (
    select 1
    from public.products p
    where p.id = p_product_id
      and p.is_available = true
  ) then
    raise exception 'Cart product is unavailable' using errcode = '22023';
  end if;

  -- 4. Membership and availability: every submitted option must
  --    be a currently available option of an active group of this
  --    product (the database backstop the RLS insert policy
  --    provides for non-definer writes).
  if exists (
    select 1
    from unnest(v_option_ids) as u(oid)
    where not exists (
      select 1
      from public.product_options po
      join public.product_option_groups pog on pog.id = po.group_id
      where po.id = u.oid
        and pog.product_id = p_product_id
        and po.is_available = true
        and pog.is_active = true
    )
  ) then
    raise exception 'Cart options are invalid' using errcode = '22023';
  end if;

  -- 5. Cardinality per active group, mirroring the application
  --    rule isGroupSatisfied: effectiveMin = max(min_selections,
  --    required ? 1 : 0); effectiveMax = SINGLE ? 1 : max_selections.
  for v_group in
    select
      g.id,
      g.selection_type,
      g.min_selections,
      g.max_selections,
      g.is_required
    from public.product_option_groups g
    where g.product_id = p_product_id
      and g.is_active = true
  loop
    select count(*)::integer
    into v_selected
    from unnest(v_option_ids) as u(oid)
    join public.product_options po on po.id = u.oid
    where po.group_id = v_group.id;

    if v_selected < greatest(v_group.min_selections, case when v_group.is_required then 1 else 0 end)
      or (
        case when v_group.selection_type = 'SINGLE' then 1 else v_group.max_selections end is not null
        and v_selected > case when v_group.selection_type = 'SINGLE' then 1 else v_group.max_selections end
      ) then
      raise exception 'Cart options are invalid' using errcode = '22023';
    end if;
  end loop;

  -- 6. One cart per customer (carts_user_unique); the loser of a
  --    creation race re-reads the winning row.
  select id
  into v_cart_id
  from public.carts
  where user_id = v_user_id;

  if v_cart_id is null then
    begin
      insert into public.carts (user_id)
      values (v_user_id)
      returning id into v_cart_id;
    exception when unique_violation then
      select id
      into v_cart_id
      from public.carts
      where user_id = v_user_id;
    end;
  end if;

  if v_cart_id is null then
    raise exception 'Cart could not be created' using errcode = '55000';
  end if;

  -- 7. Serialize cooperating adds per (cart, product) so two
  --    concurrent identical adds merge instead of racing to
  --    insert. The commit-time uniqueness triggers remain the
  --    backstop for writes that bypass this lock.
  perform pg_advisory_xact_lock(
    hashtextextended(v_cart_id::text || ':' || p_product_id::text, 0)
  );

  -- 8. Find a mergeable line: same product, same option set.
  select ci.id
  into v_existing_item_id
  from public.cart_items ci
  where ci.cart_id = v_cart_id
    and ci.product_id = p_product_id
    and coalesce((
      select array_agg(cio.product_option_id order by cio.product_option_id)
      from public.cart_item_options cio
      where cio.cart_item_id = ci.id
    ), '{}')
      = coalesce((
        select array_agg(o order by o)
        from unnest(v_option_ids) as o
      ), '{}')
  limit 1;

  if v_existing_item_id is not null then
    -- 9a. Merge: lock the line, then add quantities.
    select ci.quantity
    into v_current_quantity
    from public.cart_items ci
    where ci.id = v_existing_item_id
    for update;

    if v_current_quantity is not null then
      if v_current_quantity + p_quantity > 99 then
        raise exception 'Cart quantity limit exceeded' using errcode = '22023';
      end if;

      update public.cart_items
      set quantity = v_current_quantity + p_quantity
      where id = v_existing_item_id;

      return v_existing_item_id;
    end if;

    -- The line vanished between match and lock (a concurrent
    -- direct delete): fall through and insert a fresh line.
  end if;

  -- 9b. New line plus its option rows, atomically.
  insert into public.cart_items (cart_id, product_id, quantity)
  values (v_cart_id, p_product_id, p_quantity)
  returning id into v_item_id;

  if coalesce(array_length(v_option_ids, 1), 0) > 0 then
    insert into public.cart_item_options (cart_item_id, product_option_id)
    select v_item_id, o
    from unnest(v_option_ids) as o;
  end if;

  return v_item_id;
end;
$$;

-- ------------------------------------------------------------
-- Enforcement (created last, after repair)
--
-- Deferred so the invariant is enforced on committed state and
-- multi-write sequences (item then options) never trip on
-- transient intermediate states.
-- ------------------------------------------------------------

create constraint trigger cart_items_no_duplicate_line
after insert or update on public.cart_items
deferrable initially deferred
for each row
execute function public.cart_items_unique_line_trigger();

create constraint trigger cart_item_options_no_duplicate_line
after insert or delete on public.cart_item_options
deferrable initially deferred
for each row
execute function public.cart_item_options_unique_line_trigger();

-- ------------------------------------------------------------
-- Privileges
-- ------------------------------------------------------------

revoke all on function public.add_cart_item(uuid, integer, uuid[])
  from public, anon;
grant execute on function public.add_cart_item(uuid, integer, uuid[])
  to authenticated;

revoke all on function public.assert_cart_line_unique(uuid)
  from public, anon, authenticated;
revoke all on function public.cart_items_unique_line_trigger()
  from public, anon, authenticated;
revoke all on function public.cart_item_options_unique_line_trigger()
  from public, anon, authenticated;
revoke all on function public.repair_duplicate_cart_lines()
  from public, anon, authenticated;
