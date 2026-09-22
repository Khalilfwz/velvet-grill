-- ============================================================
-- Velvet Grill
-- Supporting Schema
-- ============================================================

-- ------------------------------------------------------------
-- Enum Types
-- ------------------------------------------------------------

create type public.notification_type as enum (
  'ORDER',
  'PAYMENT',
  'SYSTEM'
);

create type public.review_status as enum (
  'PUBLISHED',
  'HIDDEN'
);

-- ------------------------------------------------------------
-- Reviews
-- ------------------------------------------------------------

create table public.reviews (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete restrict,

  product_id uuid not null
    references public.products(id)
    on delete restrict,

  order_item_id uuid not null
    references public.order_items(id)
    on delete restrict,

  rating smallint not null
    check (rating between 1 and 5),

  title text,
  content text,

  status public.review_status not null default 'PUBLISHED',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint reviews_user_order_item_unique
    unique (user_id, order_item_id)
);

create index reviews_product_id_idx
  on public.reviews(product_id);

create index reviews_user_id_idx
  on public.reviews(user_id);

create index reviews_order_item_id_idx
  on public.reviews(order_item_id);

-- ------------------------------------------------------------
-- Notifications
-- ------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  type public.notification_type not null,

  title text not null,
  message text not null,

  order_id uuid
    references public.orders(id)
    on delete set null,

  is_read boolean not null default false,

  created_at timestamptz not null default now()
);

create index notifications_user_id_idx
  on public.notifications(user_id);

create index notifications_user_read_idx
  on public.notifications(user_id, is_read);

create index notifications_created_at_idx
  on public.notifications(created_at);

-- ------------------------------------------------------------
-- Analytics Events
-- ------------------------------------------------------------

create table public.analytics_events (
  id uuid primary key default gen_random_uuid(),

  user_id uuid
    references public.profiles(id)
    on delete set null,

  session_id text,

  event_name text not null,
  event_category text,

  product_id uuid
    references public.products(id)
    on delete set null,

  order_id uuid
    references public.orders(id)
    on delete set null,

  properties jsonb not null default '{}'::jsonb,

  occurred_at timestamptz not null default now(),

  created_at timestamptz not null default now()
);

create index analytics_events_user_id_idx
  on public.analytics_events(user_id);

create index analytics_events_session_id_idx
  on public.analytics_events(session_id);

create index analytics_events_event_name_idx
  on public.analytics_events(event_name);

create index analytics_events_product_id_idx
  on public.analytics_events(product_id);

create index analytics_events_order_id_idx
  on public.analytics_events(order_id);

create index analytics_events_occurred_at_idx
  on public.analytics_events(occurred_at);

-- ------------------------------------------------------------
-- Admin Audit Logs
-- ------------------------------------------------------------

create table public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),

  actor_user_id uuid
    references public.profiles(id)
    on delete set null,

  action text not null,
  entity_type text not null,

  entity_id uuid,

  before_data jsonb,
  after_data jsonb,

  ip_address inet,
  user_agent text,

  created_at timestamptz not null default now()
);

create index admin_audit_logs_actor_user_id_idx
  on public.admin_audit_logs(actor_user_id);

create index admin_audit_logs_entity_idx
  on public.admin_audit_logs(entity_type, entity_id);

create index admin_audit_logs_created_at_idx
  on public.admin_audit_logs(created_at);

-- ------------------------------------------------------------
-- updated_at Trigger
-- ------------------------------------------------------------

create trigger reviews_set_updated_at
before update on public.reviews
for each row
execute function public.set_updated_at();
