-- ============================================================
-- Velvet Grill
-- BUG-03 follow-up: deadlock-safe commit-time check lock
--
-- The concurrency verification reproduced a deadlock between
-- two transactions committing cart mutations for the same cart:
-- each held FOR KEY SHARE on the parent carts row (taken by
-- cart_items FK validation) while the commit-time check in
-- assert_cart_line_unique requested FOR UPDATE, which conflicts
-- with FOR KEY SHARE.
--
-- Fix: acquire FOR NO KEY UPDATE instead. It still conflicts
-- with concurrent commit-time checks of the same mode, so the
-- per-cart serialization and the no-duplicate-line invariant
-- are unchanged, but it does not conflict with the FK's
-- FOR KEY SHARE, removing the deadlock cycle.
--
-- CREATE OR REPLACE keeps the function's signature, ownership,
-- and existing ACLs (revoke from public, anon, authenticated
-- from 20261009010000 remain in force); no permission or
-- validation logic changes.
-- ============================================================

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
  -- fresh snapshot that includes the committed winner. The lock
  -- strength is FOR NO KEY UPDATE: it conflicts with other
  -- commit-time checks (preserving serialization) while not
  -- conflicting with the FOR KEY SHARE locks that concurrent
  -- cart_items inserts hold via FK validation, which avoids the
  -- deadlock reported by the concurrency verification.
  perform 1
  from public.carts c
  where c.id = v_cart_id
  for no key update;

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
