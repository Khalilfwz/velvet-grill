-- ============================================================
-- Velvet Grill
-- Initial Core Schema
-- ============================================================

-- ------------------------------------------------------------
-- Extensions
-- ------------------------------------------------------------

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Enum Types
-- ------------------------------------------------------------

create type public.user_role as enum (
  'CUSTOMER',
  'ADMIN'
);

create type public.option_selection_type as enum (
  'SINGLE',
  'MULTIPLE'
);

-- ------------------------------------------------------------
-- Utility Function: updated_at
-- ------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- Profiles
-- ------------------------------------------------------------

create table public.profiles (
  id uuid primary key
    references auth.users(id)
    on delete cascade,

  full_name text,
  phone text,
  avatar_path text,

  role public.user_role not null default 'CUSTOMER',

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'Application profile linked 1:1 with Supabase Auth users.';

comment on column public.profiles.role is
  'Privileged role. Must not be editable by the client.';

-- ------------------------------------------------------------
-- Categories
-- ------------------------------------------------------------

create table public.categories (
  id uuid primary key default gen_random_uuid(),

  name text not null,
  slug text not null unique,
  description text,

  image_path text,

  sort_order integer not null default 0
    check (sort_order >= 0),

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Products
-- ------------------------------------------------------------

create table public.products (
  id uuid primary key default gen_random_uuid(),

  category_id uuid not null
    references public.categories(id)
    on delete restrict,

  name text not null,
  slug text not null unique,
  description text,

  base_price numeric(12, 2) not null
    check (base_price >= 0),

  stock integer not null default 0
    check (stock >= 0),

  is_available boolean not null default true,
  is_featured boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index products_category_id_idx
  on public.products(category_id);

-- ------------------------------------------------------------
-- Product Images
-- ------------------------------------------------------------

create table public.product_images (
  id uuid primary key default gen_random_uuid(),

  product_id uuid not null
    references public.products(id)
    on delete cascade,

  storage_path text not null,
  alt_text text,

  sort_order integer not null default 0
    check (sort_order >= 0),

  is_primary boolean not null default false,

  created_at timestamptz not null default now()
);

create index product_images_product_id_idx
  on public.product_images(product_id);

-- ------------------------------------------------------------
-- Product Option Groups
-- ------------------------------------------------------------

create table public.product_option_groups (
  id uuid primary key default gen_random_uuid(),

  product_id uuid not null
    references public.products(id)
    on delete cascade,

  name text not null,

  selection_type public.option_selection_type
    not null default 'SINGLE',

  min_selections integer not null default 0
    check (min_selections >= 0),

  max_selections integer
    check (max_selections is null or max_selections >= 1),

  is_required boolean not null default false,

  sort_order integer not null default 0
    check (sort_order >= 0),

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint product_option_groups_selection_range_chk
    check (
      max_selections is null
      or max_selections >= min_selections
    )
);

create index product_option_groups_product_id_idx
  on public.product_option_groups(product_id);

-- ------------------------------------------------------------
-- Product Options
-- ------------------------------------------------------------

create table public.product_options (
  id uuid primary key default gen_random_uuid(),

  group_id uuid not null
    references public.product_option_groups(id)
    on delete cascade,

  name text not null,

  price_delta numeric(12, 2) not null default 0,

  is_available boolean not null default true,

  sort_order integer not null default 0
    check (sort_order >= 0),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint product_options_group_name_unique
    unique (group_id, name)
);

create index product_options_group_id_idx
  on public.product_options(group_id);

-- ------------------------------------------------------------
-- Restaurant Tables
-- ------------------------------------------------------------

create table public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),

  table_number text not null unique,

  capacity integer not null
    check (capacity > 0),

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Business Hours
-- ------------------------------------------------------------

create table public.business_hours (
  id uuid primary key default gen_random_uuid(),

  day_of_week smallint not null
    check (day_of_week between 0 and 6),

  opens_at time,
  closes_at time,

  is_closed boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint business_hours_day_unique
    unique (day_of_week),

  constraint business_hours_closed_values_chk
    check (
      (is_closed = true and opens_at is null and closes_at is null)
      or
      (is_closed = false and opens_at is not null and closes_at is not null)
    )
);

-- ------------------------------------------------------------
-- Restaurant Settings
-- Singleton table: only id = 1 is allowed
-- ------------------------------------------------------------

create table public.restaurant_settings (
  id smallint primary key default 1
    check (id = 1),

  restaurant_name text not null default 'Velvet Grill',

  address text,
  phone text,

  currency_code text not null default 'IDR'
    check (currency_code = 'IDR'),

  timezone text not null default 'Asia/Jakarta',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- updated_at Triggers
-- ------------------------------------------------------------

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create trigger categories_set_updated_at
before update on public.categories
for each row
execute function public.set_updated_at();

create trigger products_set_updated_at
before update on public.products
for each row
execute function public.set_updated_at();

create trigger product_option_groups_set_updated_at
before update on public.product_option_groups
for each row
execute function public.set_updated_at();

create trigger product_options_set_updated_at
before update on public.product_options
for each row
execute function public.set_updated_at();

create trigger restaurant_tables_set_updated_at
before update on public.restaurant_tables
for each row
execute function public.set_updated_at();

create trigger business_hours_set_updated_at
before update on public.business_hours
for each row
execute function public.set_updated_at();

create trigger restaurant_settings_set_updated_at
before update on public.restaurant_settings
for each row
execute function public.set_updated_at();
