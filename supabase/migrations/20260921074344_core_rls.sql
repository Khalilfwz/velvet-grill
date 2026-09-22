-- ============================================================
-- Velvet Grill
-- Core Row Level Security, Grants, and Admin Helper
-- ============================================================

-- ------------------------------------------------------------
-- Private schema for security-definer helpers
-- ------------------------------------------------------------

create schema if not exists private;

revoke all on schema private from public;

grant usage on schema private to authenticated;

-- ------------------------------------------------------------
-- Admin helper
-- ------------------------------------------------------------

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'ADMIN'::public.user_role
      and is_active = true
  );
$$;

revoke all on function private.is_admin() from public;

grant execute on function private.is_admin() to authenticated;

-- ------------------------------------------------------------
-- Future default privileges
-- Keep newly created public objects closed by default.
-- Future migrations must grant only required access.
-- ------------------------------------------------------------

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;

-- ------------------------------------------------------------
-- Enable RLS
-- ------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.product_option_groups enable row level security;
alter table public.product_options enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.business_hours enable row level security;
alter table public.restaurant_settings enable row level security;

-- ------------------------------------------------------------
-- Remove existing table privileges
-- ------------------------------------------------------------

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.categories from anon, authenticated;
revoke all on table public.products from anon, authenticated;
revoke all on table public.product_images from anon, authenticated;
revoke all on table public.product_option_groups from anon, authenticated;
revoke all on table public.product_options from anon, authenticated;
revoke all on table public.restaurant_tables from anon, authenticated;
revoke all on table public.business_hours from anon, authenticated;
revoke all on table public.restaurant_settings from anon, authenticated;

-- ------------------------------------------------------------
-- Grants: profiles
-- ------------------------------------------------------------

grant select on table public.profiles
  to authenticated;

grant update (full_name, phone, avatar_path)
  on table public.profiles
  to authenticated;

-- ------------------------------------------------------------
-- Grants: public catalog
-- ------------------------------------------------------------

grant select on table public.categories
  to anon, authenticated;

grant insert, update on table public.categories
  to authenticated;

grant select on table public.products
  to anon, authenticated;

grant insert, update on table public.products
  to authenticated;

grant select on table public.product_images
  to anon, authenticated;

grant insert, update, delete on table public.product_images
  to authenticated;

grant select on table public.product_option_groups
  to anon, authenticated;

grant insert, update on table public.product_option_groups
  to authenticated;

grant select on table public.product_options
  to anon, authenticated;

grant insert, update on table public.product_options
  to authenticated;

-- ------------------------------------------------------------
-- Grants: restaurant information
-- ------------------------------------------------------------

grant select on table public.restaurant_tables
  to anon, authenticated;

grant insert, update on table public.restaurant_tables
  to authenticated;

grant select on table public.business_hours
  to anon, authenticated;

grant insert, update on table public.business_hours
  to authenticated;

grant select on table public.restaurant_settings
  to anon, authenticated;

grant update on table public.restaurant_settings
  to authenticated;

-- ------------------------------------------------------------
-- Profiles policies
-- ------------------------------------------------------------

create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (
  (select auth.uid()) = id
);

create policy "profiles_admin_select"
on public.profiles
for select
to authenticated
using (
  (select private.is_admin())
);

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (
  (select auth.uid()) = id
)
with check (
  (select auth.uid()) = id
);

-- ------------------------------------------------------------
-- Categories policies
-- ------------------------------------------------------------

create policy "categories_public_read"
on public.categories
for select
to anon, authenticated
using (
  is_active = true
);

create policy "categories_admin_manage"
on public.categories
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Products policies
-- ------------------------------------------------------------

create policy "products_public_read"
on public.products
for select
to anon, authenticated
using (
  is_available = true
  and exists (
    select 1
    from public.categories c
    where c.id = category_id
      and c.is_active = true
  )
);

create policy "products_admin_manage"
on public.products
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Product Images policies
-- ------------------------------------------------------------

create policy "product_images_public_read"
on public.product_images
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.products p
    join public.categories c
      on c.id = p.category_id
    where p.id = product_id
      and p.is_available = true
      and c.is_active = true
  )
);

create policy "product_images_admin_manage"
on public.product_images
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Product Option Groups policies
-- ------------------------------------------------------------

create policy "product_option_groups_public_read"
on public.product_option_groups
for select
to anon, authenticated
using (
  is_active = true
  and exists (
    select 1
    from public.products p
    join public.categories c
      on c.id = p.category_id
    where p.id = product_id
      and p.is_available = true
      and c.is_active = true
  )
);

create policy "product_option_groups_admin_manage"
on public.product_option_groups
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Product Options policies
-- ------------------------------------------------------------

create policy "product_options_public_read"
on public.product_options
for select
to anon, authenticated
using (
  is_available = true
  and exists (
    select 1
    from public.product_option_groups g
    join public.products p
      on p.id = g.product_id
    join public.categories c
      on c.id = p.category_id
    where g.id = group_id
      and g.is_active = true
      and p.is_available = true
      and c.is_active = true
  )
);

create policy "product_options_admin_manage"
on public.product_options
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Restaurant Tables policies
-- ------------------------------------------------------------

create policy "restaurant_tables_public_read"
on public.restaurant_tables
for select
to anon, authenticated
using (
  is_active = true
);

create policy "restaurant_tables_admin_manage"
on public.restaurant_tables
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Business Hours policies
-- ------------------------------------------------------------

create policy "business_hours_public_read"
on public.business_hours
for select
to anon, authenticated
using (
  true
);

create policy "business_hours_admin_manage"
on public.business_hours
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- Restaurant Settings policies
-- ------------------------------------------------------------

create policy "restaurant_settings_public_read"
on public.restaurant_settings
for select
to anon, authenticated
using (
  true
);

create policy "restaurant_settings_admin_manage"
on public.restaurant_settings
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);
