-- ============================================================
-- Velvet Grill
-- Commerce Schema
-- ============================================================

-- ------------------------------------------------------------
-- Enum Types
-- ------------------------------------------------------------

create type public.order_fulfillment_type as enum (
  'PICKUP',
  'DINE_IN'
);

create type public.order_status as enum (
  'PENDING_PAYMENT',
  'CONFIRMED',
  'PREPARING',
  'READY',
  'COMPLETED',
  'CANCELLED'
);

create type public.payment_method as enum (
  'DUMMY_QRIS',
  'DUMMY_BANK_TRANSFER',
  'CASH'
);

create type public.payment_status as enum (
  'PENDING',
  'SUCCEEDED',
  'FAILED',
  'EXPIRED',
  'CANCELLED'
);

create type public.coupon_discount_type as enum (
  'PERCENTAGE',
  'FIXED_AMOUNT'
);

-- ------------------------------------------------------------
-- Carts
-- One active cart per customer
-- ------------------------------------------------------------

create table public.carts (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint carts_user_unique
    unique (user_id)
);

-- ------------------------------------------------------------
-- Cart Items
-- ------------------------------------------------------------

create table public.cart_items (
  id uuid primary key default gen_random_uuid(),

  cart_id uuid not null
    references public.carts(id)
    on delete cascade,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  quantity integer not null
    check (quantity > 0),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index cart_items_cart_id_idx
  on public.cart_items(cart_id);

create index cart_items_product_id_idx
  on public.cart_items(product_id);

-- ------------------------------------------------------------
-- Cart Item Options
-- ------------------------------------------------------------

create table public.cart_item_options (
  id uuid primary key default gen_random_uuid(),

  cart_item_id uuid not null
    references public.cart_items(id)
    on delete cascade,

  product_option_id uuid not null
    references public.product_options(id)
    on delete restrict,

  created_at timestamptz not null default now(),

  constraint cart_item_options_unique
    unique (cart_item_id, product_option_id)
);

create index cart_item_options_cart_item_id_idx
  on public.cart_item_options(cart_item_id);

-- ------------------------------------------------------------
-- Wishlists
-- ------------------------------------------------------------

create table public.wishlists (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint wishlists_user_unique
    unique (user_id)
);

-- ------------------------------------------------------------
-- Wishlist Items
-- ------------------------------------------------------------

create table public.wishlist_items (
  id uuid primary key default gen_random_uuid(),

  wishlist_id uuid not null
    references public.wishlists(id)
    on delete cascade,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  created_at timestamptz not null default now(),

  constraint wishlist_items_unique
    unique (wishlist_id, product_id)
);

create index wishlist_items_wishlist_id_idx
  on public.wishlist_items(wishlist_id);

-- ------------------------------------------------------------
-- Orders
-- ------------------------------------------------------------

create table public.orders (
  id uuid primary key default gen_random_uuid(),

  order_number text not null unique,

  user_id uuid
    references public.profiles(id)
    on delete set null,

  fulfillment_type public.order_fulfillment_type not null,

  pickup_at timestamptz,

  restaurant_table_id uuid
    references public.restaurant_tables(id)
    on delete set null,

  table_number_snapshot text,

  customer_name_snapshot text not null,
  customer_phone_snapshot text,

  subtotal numeric(12, 2) not null
    check (subtotal >= 0),

  discount_total numeric(12, 2) not null default 0
    check (discount_total >= 0),

  final_total numeric(12, 2) not null
    check (final_total >= 0),

  coupon_id uuid,

  coupon_code_snapshot text,

  payment_status public.payment_status
    not null default 'PENDING',

  order_status public.order_status
    not null default 'PENDING_PAYMENT',

  customer_note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint orders_fulfillment_chk
    check (
      (
        fulfillment_type = 'PICKUP'
        and pickup_at is not null
        and restaurant_table_id is null
        and table_number_snapshot is null
      )
      or
      (
        fulfillment_type = 'DINE_IN'
        and pickup_at is null
        and restaurant_table_id is not null
        and table_number_snapshot is not null
      )
    )
);

create index orders_user_id_idx
  on public.orders(user_id);

create index orders_order_status_idx
  on public.orders(order_status);

create index orders_payment_status_idx
  on public.orders(payment_status);

create index orders_created_at_idx
  on public.orders(created_at);

-- ------------------------------------------------------------
-- Order Items
-- Historical product snapshot
-- ------------------------------------------------------------

create table public.order_items (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null
    references public.orders(id)
    on delete cascade,

  product_id uuid
    references public.products(id)
    on delete set null,

  product_name_snapshot text not null,

  base_price_snapshot numeric(12, 2) not null
    check (base_price_snapshot >= 0),

  final_unit_price numeric(12, 2) not null
    check (final_unit_price >= 0),

  quantity integer not null
    check (quantity > 0),

  subtotal numeric(12, 2) not null
    check (subtotal >= 0),

  created_at timestamptz not null default now()
);

create index order_items_order_id_idx
  on public.order_items(order_id);

create index order_items_product_id_idx
  on public.order_items(product_id);

-- ------------------------------------------------------------
-- Order Item Options
-- Historical option snapshot
-- ------------------------------------------------------------

create table public.order_item_options (
  id uuid primary key default gen_random_uuid(),

  order_item_id uuid not null
    references public.order_items(id)
    on delete cascade,

  product_option_id uuid
    references public.product_options(id)
    on delete set null,

  option_group_name_snapshot text not null,
  option_name_snapshot text not null,

  price_delta_snapshot numeric(12, 2) not null default 0,

  created_at timestamptz not null default now()
);

create index order_item_options_order_item_id_idx
  on public.order_item_options(order_item_id);

-- ------------------------------------------------------------
-- Payments
-- One order may have multiple payment attempts
-- ------------------------------------------------------------

create table public.payments (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null
    references public.orders(id)
    on delete cascade,

  method public.payment_method not null,

  status public.payment_status not null default 'PENDING',

  amount numeric(12, 2) not null
    check (amount >= 0),

  provider_reference text unique,

  paid_at timestamptz,

  failure_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index payments_order_id_idx
  on public.payments(order_id);

create index payments_status_idx
  on public.payments(status);

-- ------------------------------------------------------------
-- Order Status History
-- ------------------------------------------------------------

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null
    references public.orders(id)
    on delete cascade,

  from_status public.order_status,

  to_status public.order_status not null,

  changed_by uuid
    references public.profiles(id)
    on delete set null,

  note text,

  created_at timestamptz not null default now()
);

create index order_status_history_order_id_idx
  on public.order_status_history(order_id);

create index order_status_history_created_at_idx
  on public.order_status_history(created_at);

-- ------------------------------------------------------------
-- Coupons
-- ------------------------------------------------------------

create table public.coupons (
  id uuid primary key default gen_random_uuid(),

  code text not null unique,

  description text,

  discount_type public.coupon_discount_type not null,

  discount_value numeric(12, 2) not null
    check (discount_value >= 0),

  max_discount_amount numeric(12, 2)
    check (
      max_discount_amount is null
      or max_discount_amount >= 0
    ),

  min_order_subtotal numeric(12, 2) not null default 0
    check (min_order_subtotal >= 0),

  starts_at timestamptz not null,
  ends_at timestamptz not null,

  usage_limit integer
    check (
      usage_limit is null
      or usage_limit > 0
    ),

  per_customer_limit integer
    check (
      per_customer_limit is null
      or per_customer_limit > 0
    ),

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint coupons_date_range_chk
    check (ends_at > starts_at),

  constraint coupons_percentage_chk
    check (
      discount_type <> 'PERCENTAGE'
      or discount_value <= 100
    )
);

alter table public.orders
  add constraint orders_coupon_id_fkey
  foreign key (coupon_id)
  references public.coupons(id)
  on delete set null;

-- ------------------------------------------------------------
-- Coupon Usages
-- ------------------------------------------------------------

create table public.coupon_usages (
  id uuid primary key default gen_random_uuid(),

  coupon_id uuid not null
    references public.coupons(id)
    on delete restrict,

  order_id uuid not null
    references public.orders(id)
    on delete restrict,

  user_id uuid
    references public.profiles(id)
    on delete set null,

  discount_amount numeric(12, 2) not null
    check (discount_amount >= 0),

  used_at timestamptz not null default now(),

  constraint coupon_usages_order_unique
    unique (coupon_id, order_id)
);

create index coupon_usages_coupon_id_idx
  on public.coupon_usages(coupon_id);

create index coupon_usages_user_id_idx
  on public.coupon_usages(user_id);

-- ------------------------------------------------------------
-- updated_at Triggers
-- ------------------------------------------------------------

create trigger carts_set_updated_at
before update on public.carts
for each row
execute function public.set_updated_at();

create trigger cart_items_set_updated_at
before update on public.cart_items
for each row
execute function public.set_updated_at();

create trigger wishlists_set_updated_at
before update on public.wishlists
for each row
execute function public.set_updated_at();

create trigger orders_set_updated_at
before update on public.orders
for each row
execute function public.set_updated_at();

create trigger payments_set_updated_at
before update on public.payments
for each row
execute function public.set_updated_at();

create trigger coupons_set_updated_at
before update on public.coupons
for each row
execute function public.set_updated_at();
