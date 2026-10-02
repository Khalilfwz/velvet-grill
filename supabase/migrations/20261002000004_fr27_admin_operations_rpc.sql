-- ============================================================
-- Velvet Grill
-- FR-27: admins manage business hours, tables, and restaurant settings.
--
-- Direct writes on the three tables are removed from authenticated.
-- Admin mutations flow through three SECURITY DEFINER RPCs, each of
-- which re-checks private.is_admin(), normalizes the persisted values,
-- enforces value validation and target scoping explicitly, and relies
-- on the existing table constraints/FKs as the final integrity backstop.
--
-- Because a SECURITY DEFINER function writes as its owner, RLS is not
-- the RPC write-path backstop; it stays enabled and unchanged as
-- defense-in-depth for the revoked direct path. Writes execute in the
-- authenticated admin context, so auth.uid() is preserved for the FR-25
-- audit triggers. The RPCs write no audit rows. No service-role is used.
-- ============================================================

-- ------------------------------------------------------------
-- Remove direct write grants (keep select)
-- ------------------------------------------------------------

revoke insert, update on table public.restaurant_tables from authenticated;
revoke insert, update on table public.business_hours from authenticated;
revoke update on table public.restaurant_settings from authenticated;

-- ------------------------------------------------------------
-- Restaurant tables
-- ------------------------------------------------------------

create or replace function public.admin_save_restaurant_table(
  p_id uuid,
  p_table_number text,
  p_capacity integer,
  p_is_active boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_table_number text;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  v_table_number := btrim(coalesce(p_table_number, ''));
  if length(v_table_number) < 1 or length(v_table_number) > 120 then
    raise exception 'Invalid table number' using errcode = '22023';
  end if;

  if p_capacity is null or p_capacity < 1 or p_capacity > 2147483647 then
    raise exception 'Invalid capacity' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.restaurant_tables (table_number, capacity, is_active)
    values (v_table_number, p_capacity, coalesce(p_is_active, true))
    returning id into v_id;
  else
    update public.restaurant_tables
    set table_number = v_table_number,
        capacity = p_capacity,
        is_active = coalesce(p_is_active, true)
    where id = p_id;

    if not found then
      raise exception 'Table not found' using errcode = 'P0002';
    end if;

    v_id := p_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.admin_save_restaurant_table(uuid, text, integer, boolean) from public;
grant execute on function public.admin_save_restaurant_table(uuid, text, integer, boolean) to authenticated;

-- ------------------------------------------------------------
-- Business hours
-- ------------------------------------------------------------

create or replace function public.admin_save_business_hours(
  p_day_of_week integer,
  p_is_closed boolean,
  p_opens_at text,
  p_closes_at text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_is_closed boolean;
  v_opens_at text;
  v_closes_at text;
  v_opens time;
  v_closes time;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if p_day_of_week is null or p_day_of_week < 0 or p_day_of_week > 6 then
    raise exception 'Invalid day of week' using errcode = '22023';
  end if;

  v_is_closed := coalesce(p_is_closed, false);
  v_opens_at := btrim(coalesce(p_opens_at, ''));
  v_closes_at := btrim(coalesce(p_closes_at, ''));

  if v_is_closed then
    if v_opens_at <> '' or v_closes_at <> '' then
      raise exception 'Closed hours must not include times'
        using errcode = '22023';
    end if;

    v_opens := null;
    v_closes := null;
  else
    if v_opens_at = '' or v_closes_at = '' then
      raise exception 'Open hours require both times'
        using errcode = '22023';
    end if;

    if v_opens_at !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then
      raise exception 'Invalid opening time' using errcode = '22023';
    end if;

    if v_closes_at !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then
      raise exception 'Invalid closing time' using errcode = '22023';
    end if;

    v_opens := v_opens_at::time;
    v_closes := v_closes_at::time;
  end if;

  insert into public.business_hours (
    day_of_week, opens_at, closes_at, is_closed
  )
  values (
    p_day_of_week, v_opens, v_closes, v_is_closed
  )
  on conflict (day_of_week) do update
  set opens_at = excluded.opens_at,
      closes_at = excluded.closes_at,
      is_closed = excluded.is_closed
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_save_business_hours(integer, boolean, text, text) from public;
grant execute on function public.admin_save_business_hours(integer, boolean, text, text) to authenticated;

-- ------------------------------------------------------------
-- Restaurant settings (singleton id = 1)
-- ------------------------------------------------------------

create or replace function public.admin_save_restaurant_settings(
  p_restaurant_name text,
  p_address text,
  p_phone text,
  p_timezone text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_address text;
  v_phone text;
  v_timezone text;
begin
  if not (select private.is_admin()) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  v_name := btrim(coalesce(p_restaurant_name, ''));
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Invalid restaurant name' using errcode = '22023';
  end if;

  v_address := nullif(btrim(coalesce(p_address, '')), '');
  if v_address is not null and length(v_address) > 1000 then
    raise exception 'Invalid address' using errcode = '22023';
  end if;

  v_phone := nullif(btrim(coalesce(p_phone, '')), '');
  if v_phone is not null and length(v_phone) > 32 then
    raise exception 'Invalid phone' using errcode = '22023';
  end if;

  v_timezone := btrim(coalesce(p_timezone, ''));
  if length(v_timezone) < 1 or length(v_timezone) > 120 then
    raise exception 'Invalid timezone' using errcode = '22023';
  end if;

  insert into public.restaurant_settings (
    id, restaurant_name, address, phone, timezone
  )
  values (1, v_name, v_address, v_phone, v_timezone)
  on conflict (id) do update
  set restaurant_name = excluded.restaurant_name,
      address = excluded.address,
      phone = excluded.phone,
      timezone = excluded.timezone;
end;
$$;

revoke all on function public.admin_save_restaurant_settings(text, text, text, text) from public;
grant execute on function public.admin_save_restaurant_settings(text, text, text, text) to authenticated;
