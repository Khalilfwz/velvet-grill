-- ============================================================
-- Velvet Grill
-- FR-26: admin catalog management through authoritative RPCs.
--
-- Direct catalog writes are removed from authenticated. Admin
-- mutations flow through six SECURITY DEFINER RPCs, each of which
-- re-checks private.is_admin(), enforces value validation and
-- parent scoping explicitly, and relies on the existing table
-- constraints/FKs as the final integrity backstop.
--
-- Because a SECURITY DEFINER function writes as its owner, RLS is
-- not the RPC write-path backstop; it stays enabled and unchanged
-- as defense-in-depth for the revoked direct path. Writes execute
-- in the authenticated admin context, so auth.uid() is preserved
-- for the FR-25 audit triggers. No service-role is used.
-- ============================================================

-- ------------------------------------------------------------
-- Remove direct catalog write grants (keep select)
-- ------------------------------------------------------------

revoke insert, update on table public.categories from authenticated;
revoke insert, update on table public.products from authenticated;
revoke insert, update on table public.product_option_groups from authenticated;
revoke insert, update on table public.product_options from authenticated;
revoke insert, update, delete on table public.product_images from authenticated;

-- ------------------------------------------------------------
-- Private path-safety helper
-- ------------------------------------------------------------

create or replace function private.is_safe_relative_path(p_path text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select
    p_path is not null
    and p_path <> ''
    and length(p_path) <= 255
    and p_path !~ '^/'
    and p_path !~ '/$'
    and p_path not like '%//%'
    and p_path !~ '(^|/)\.\.(/|$)'
    and p_path not like '%://%'
    and p_path ~ '^[A-Za-z0-9._/-]+$';
$$;

revoke all on function private.is_safe_relative_path(text) from public;

-- ------------------------------------------------------------
-- Categories
-- ------------------------------------------------------------

create or replace function public.admin_save_category(
  p_id uuid,
  p_name text,
  p_slug text,
  p_description text,
  p_image_path text,
  p_sort_order integer,
  p_is_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text;
  v_slug text;
  v_description text;
  v_image_path text;
  v_sort_order integer;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  v_name := btrim(coalesce(p_name, ''));
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Invalid name' using errcode = '22023';
  end if;

  v_slug := btrim(coalesce(p_slug, ''));
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_slug) > 80 then
    raise exception 'Invalid slug' using errcode = '22023';
  end if;

  if p_description is not null and length(p_description) > 1000 then
    raise exception 'Invalid description' using errcode = '22023';
  end if;
  v_description := nullif(btrim(coalesce(p_description, '')), '');

  v_image_path := nullif(btrim(coalesce(p_image_path, '')), '');
  if v_image_path is not null and not private.is_safe_relative_path(v_image_path) then
    raise exception 'Invalid image path' using errcode = '22023';
  end if;

  v_sort_order := coalesce(p_sort_order, 0);
  if v_sort_order < 0 then
    raise exception 'Invalid sort order' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.categories (
      name, slug, description, image_path, sort_order, is_active
    )
    values (
      v_name, v_slug, v_description, v_image_path, v_sort_order,
      coalesce(p_is_active, true)
    )
    returning id into v_id;
  else
    update public.categories
    set name = v_name,
        slug = v_slug,
        description = v_description,
        image_path = v_image_path,
        sort_order = v_sort_order,
        is_active = coalesce(p_is_active, true)
    where id = p_id;

    if not found then
      raise exception 'Category not found' using errcode = 'P0002';
    end if;

    v_id := p_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_save_category(uuid, text, text, text, text, integer, boolean) from public;
grant execute on function public.admin_save_category(uuid, text, text, text, text, integer, boolean) to authenticated;

-- ------------------------------------------------------------
-- Products
-- ------------------------------------------------------------

create or replace function public.admin_save_product(
  p_id uuid,
  p_category_id uuid,
  p_name text,
  p_slug text,
  p_description text,
  p_base_price numeric,
  p_stock integer,
  p_is_available boolean,
  p_is_featured boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text;
  v_slug text;
  v_description text;
  v_stock integer;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_category_id is null
     or not exists (
       select 1 from public.categories c where c.id = p_category_id
     ) then
    raise exception 'Invalid category' using errcode = '23503';
  end if;

  v_name := btrim(coalesce(p_name, ''));
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Invalid name' using errcode = '22023';
  end if;

  v_slug := btrim(coalesce(p_slug, ''));
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_slug) > 80 then
    raise exception 'Invalid slug' using errcode = '22023';
  end if;

  if p_description is not null and length(p_description) > 1000 then
    raise exception 'Invalid description' using errcode = '22023';
  end if;
  v_description := nullif(btrim(coalesce(p_description, '')), '');

  if p_base_price is null
     or p_base_price < 0
     or p_base_price > 9999999999.99 then
    raise exception 'Invalid base price' using errcode = '22023';
  end if;

  v_stock := coalesce(p_stock, 0);
  if v_stock < 0 or v_stock > 1000000 then
    raise exception 'Invalid stock' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.products (
      category_id, name, slug, description, base_price, stock,
      is_available, is_featured
    )
    values (
      p_category_id, v_name, v_slug, v_description, p_base_price, v_stock,
      coalesce(p_is_available, true), coalesce(p_is_featured, false)
    )
    returning id into v_id;
  else
    update public.products
    set category_id = p_category_id,
        name = v_name,
        slug = v_slug,
        description = v_description,
        base_price = p_base_price,
        stock = v_stock,
        is_available = coalesce(p_is_available, true),
        is_featured = coalesce(p_is_featured, false)
    where id = p_id;

    if not found then
      raise exception 'Product not found' using errcode = 'P0002';
    end if;

    v_id := p_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_save_product(uuid, uuid, text, text, text, numeric, integer, boolean, boolean) from public;
grant execute on function public.admin_save_product(uuid, uuid, text, text, text, numeric, integer, boolean, boolean) to authenticated;

-- ------------------------------------------------------------
-- Product images
-- ------------------------------------------------------------

create or replace function public.admin_save_product_image(
  p_id uuid,
  p_product_id uuid,
  p_storage_path text,
  p_alt_text text,
  p_sort_order integer,
  p_is_primary boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_storage_path text;
  v_alt_text text;
  v_sort_order integer;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_product_id is null
     or not exists (
       select 1 from public.products p where p.id = p_product_id
     ) then
    raise exception 'Invalid product' using errcode = '23503';
  end if;

  v_storage_path := btrim(coalesce(p_storage_path, ''));
  if not private.is_safe_relative_path(v_storage_path) then
    raise exception 'Invalid storage path' using errcode = '22023';
  end if;

  if p_alt_text is not null and length(p_alt_text) > 200 then
    raise exception 'Invalid alt text' using errcode = '22023';
  end if;
  v_alt_text := nullif(btrim(coalesce(p_alt_text, '')), '');

  v_sort_order := coalesce(p_sort_order, 0);
  if v_sort_order < 0 then
    raise exception 'Invalid sort order' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.product_images (
      product_id, storage_path, alt_text, sort_order, is_primary
    )
    values (
      p_product_id, v_storage_path, v_alt_text, v_sort_order,
      coalesce(p_is_primary, false)
    )
    returning id into v_id;
  else
    -- product_id is not writable; the scope guard rejects cross-product edits.
    update public.product_images
    set storage_path = v_storage_path,
        alt_text = v_alt_text,
        sort_order = v_sort_order,
        is_primary = coalesce(p_is_primary, false)
    where id = p_id and product_id = p_product_id;

    if not found then
      raise exception 'Image not found' using errcode = 'P0002';
    end if;

    v_id := p_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_save_product_image(uuid, uuid, text, text, integer, boolean) from public;
grant execute on function public.admin_save_product_image(uuid, uuid, text, text, integer, boolean) to authenticated;

create or replace function public.admin_delete_product_image(
  p_id uuid,
  p_product_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_id is null or p_product_id is null then
    raise exception 'Image not found' using errcode = 'P0002';
  end if;

  delete from public.product_images
  where id = p_id and product_id = p_product_id;

  if not found then
    raise exception 'Image not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.admin_delete_product_image(uuid, uuid) from public;
grant execute on function public.admin_delete_product_image(uuid, uuid) to authenticated;

-- ------------------------------------------------------------
-- Product option groups
-- ------------------------------------------------------------

create or replace function public.admin_save_option_group(
  p_id uuid,
  p_product_id uuid,
  p_name text,
  p_selection_type public.option_selection_type,
  p_min_selections integer,
  p_max_selections integer,
  p_is_required boolean,
  p_sort_order integer,
  p_is_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text;
  v_min_selections integer;
  v_max_selections integer;
  v_sort_order integer;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_product_id is null
     or not exists (
       select 1 from public.products p where p.id = p_product_id
     ) then
    raise exception 'Invalid product' using errcode = '23503';
  end if;

  v_name := btrim(coalesce(p_name, ''));
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Invalid name' using errcode = '22023';
  end if;

  if p_selection_type is null then
    raise exception 'Invalid selection type' using errcode = '22023';
  end if;

  v_min_selections := coalesce(p_min_selections, 0);
  if v_min_selections < 0 then
    raise exception 'Invalid minimum selections' using errcode = '22023';
  end if;

  if p_selection_type = 'SINGLE' then
    if v_min_selections > 1 then
      raise exception 'Invalid minimum selections' using errcode = '22023';
    end if;
    v_max_selections := 1;
  else
    v_max_selections := p_max_selections;
    if v_max_selections is not null
       and (v_max_selections < 1 or v_max_selections < v_min_selections) then
      raise exception 'Invalid maximum selections' using errcode = '22023';
    end if;
  end if;

  v_sort_order := coalesce(p_sort_order, 0);
  if v_sort_order < 0 then
    raise exception 'Invalid sort order' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.product_option_groups (
      product_id, name, selection_type, min_selections, max_selections,
      is_required, sort_order, is_active
    )
    values (
      p_product_id, v_name, p_selection_type, v_min_selections, v_max_selections,
      coalesce(p_is_required, false), v_sort_order, coalesce(p_is_active, true)
    )
    returning id into v_id;
  else
    update public.product_option_groups
    set name = v_name,
        selection_type = p_selection_type,
        min_selections = v_min_selections,
        max_selections = v_max_selections,
        is_required = coalesce(p_is_required, false),
        sort_order = v_sort_order,
        is_active = coalesce(p_is_active, true)
    where id = p_id and product_id = p_product_id;

    if not found then
      raise exception 'Option group not found' using errcode = 'P0002';
    end if;

    v_id := p_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_save_option_group(uuid, uuid, text, public.option_selection_type, integer, integer, boolean, integer, boolean) from public;
grant execute on function public.admin_save_option_group(uuid, uuid, text, public.option_selection_type, integer, integer, boolean, integer, boolean) to authenticated;

-- ------------------------------------------------------------
-- Product options
-- ------------------------------------------------------------

create or replace function public.admin_save_option(
  p_id uuid,
  p_group_id uuid,
  p_product_id uuid,
  p_name text,
  p_price_delta numeric,
  p_is_available boolean,
  p_sort_order integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text;
  v_price_delta numeric;
  v_sort_order integer;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  -- The group must exist and belong to the product in scope.
  if p_group_id is null
     or p_product_id is null
     or not exists (
       select 1
       from public.product_option_groups g
       where g.id = p_group_id
         and g.product_id = p_product_id
     ) then
    raise exception 'Invalid option group' using errcode = '23503';
  end if;

  v_name := btrim(coalesce(p_name, ''));
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Invalid name' using errcode = '22023';
  end if;

  v_price_delta := coalesce(p_price_delta, 0);
  if v_price_delta < -9999999999.99 or v_price_delta > 9999999999.99 then
    raise exception 'Invalid price delta' using errcode = '22023';
  end if;

  v_sort_order := coalesce(p_sort_order, 0);
  if v_sort_order < 0 then
    raise exception 'Invalid sort order' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.product_options (
      group_id, name, price_delta, is_available, sort_order
    )
    values (
      p_group_id, v_name, v_price_delta, coalesce(p_is_available, true), v_sort_order
    )
    returning id into v_id;
  else
    update public.product_options
    set name = v_name,
        price_delta = v_price_delta,
        is_available = coalesce(p_is_available, true),
        sort_order = v_sort_order
    where id = p_id and group_id = p_group_id;

    if not found then
      raise exception 'Option not found' using errcode = 'P0002';
    end if;

    v_id := p_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_save_option(uuid, uuid, uuid, text, numeric, boolean, integer) from public;
grant execute on function public.admin_save_option(uuid, uuid, uuid, text, numeric, boolean, integer) to authenticated;
