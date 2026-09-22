-- ============================================================
-- Velvet Grill
-- Supporting Row Level Security and Grants
-- ============================================================

-- ------------------------------------------------------------
-- Enable RLS
-- ------------------------------------------------------------

alter table public.reviews enable row level security;
alter table public.notifications enable row level security;
alter table public.analytics_events enable row level security;
alter table public.admin_audit_logs enable row level security;

-- ------------------------------------------------------------
-- Remove default client privileges
-- ------------------------------------------------------------

revoke all on table public.reviews from anon, authenticated;
revoke all on table public.notifications from anon, authenticated;
revoke all on table public.analytics_events from anon, authenticated;
revoke all on table public.admin_audit_logs from anon, authenticated;

-- ============================================================
-- REVIEWS
-- ============================================================

-- Public users may read published reviews.
grant select on table public.reviews
to anon, authenticated;

create policy "reviews_public_read_published"
on public.reviews
for select
to anon, authenticated
using (
  status = 'PUBLISHED'
);

-- Authenticated users may read their own reviews,
-- including reviews hidden by moderation.
create policy "reviews_select_own"
on public.reviews
for select
to authenticated
using (
  user_id = (select auth.uid())
);

-- Customer may create a review only for their own
-- completed order item and matching product.
grant insert on table public.reviews
to authenticated;

create policy "reviews_insert_completed_purchase"
on public.reviews
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.order_items oi
    join public.orders o
      on o.id = oi.order_id
    where oi.id = order_item_id
      and oi.product_id = product_id
      and o.user_id = (select auth.uid())
      and o.order_status = 'COMPLETED'
  )
);

-- Only customer-owned content fields may be edited.
grant update (rating, title, content)
on table public.reviews
to authenticated;

create policy "reviews_update_own"
on public.reviews
for update
to authenticated
using (
  user_id = (select auth.uid())
)
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.order_items oi
    join public.orders o
      on o.id = oi.order_id
    where oi.id = order_item_id
      and oi.product_id = product_id
      and o.user_id = (select auth.uid())
      and o.order_status = 'COMPLETED'
  )
);

-- Customer may delete their own review.
grant delete on table public.reviews
to authenticated;

create policy "reviews_delete_own"
on public.reviews
for delete
to authenticated
using (
  user_id = (select auth.uid())
);

-- Admin can moderate reviews.
grant update (status)
on table public.reviews
to authenticated;

create policy "reviews_admin_moderate"
on public.reviews
for update
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================

grant select on table public.notifications
to authenticated;

create policy "notifications_select_own"
on public.notifications
for select
to authenticated
using (
  user_id = (select auth.uid())
);

-- Customer can only mark their own notification as read/unread.
grant update (is_read)
on table public.notifications
to authenticated;

create policy "notifications_update_own"
on public.notifications
for update
to authenticated
using (
  user_id = (select auth.uid())
)
with check (
  user_id = (select auth.uid())
);

-- No INSERT or DELETE grant for client roles.
-- Notifications are server-generated.

-- ============================================================
-- ANALYTICS EVENTS
-- ============================================================

-- Clients may submit only behavioral analytics.
grant insert on table public.analytics_events
to anon, authenticated;

create policy "analytics_insert_behavioral_anon"
on public.analytics_events
for insert
to anon
with check (
  event_name in (
    'PAGE_VIEWED',
    'PRODUCT_VIEWED',
    'SEARCH_PERFORMED',
    'ADD_TO_CART',
    'REMOVE_FROM_CART',
    'CART_VIEWED',
    'CHECKOUT_STARTED',
    'WISHLIST_ADDED',
    'WISHLIST_REMOVED'
  )
  and user_id is null
  and order_id is null
);

create policy "analytics_insert_behavioral_authenticated"
on public.analytics_events
for insert
to authenticated
with check (
  event_name in (
    'PAGE_VIEWED',
    'PRODUCT_VIEWED',
    'SEARCH_PERFORMED',
    'ADD_TO_CART',
    'REMOVE_FROM_CART',
    'CART_VIEWED',
    'CHECKOUT_STARTED',
    'WISHLIST_ADDED',
    'WISHLIST_REMOVED'
  )
  and (
    user_id is null
    or user_id = (select auth.uid())
  )
  and order_id is null
);

-- Client roles cannot read analytics directly.
-- Analytics reads are admin/server controlled.

grant select on table public.analytics_events
to authenticated;

create policy "analytics_admin_select"
on public.analytics_events
for select
to authenticated
using (
  (select private.is_admin())
);

-- ============================================================
-- ADMIN AUDIT LOGS
-- ============================================================

-- Admins may read audit logs.
-- INSERT/UPDATE/DELETE remain server-only.
grant select on table public.admin_audit_logs
to authenticated;

create policy "audit_logs_admin_select"
on public.admin_audit_logs
for select
to authenticated
using (
  (select private.is_admin())
);

-- No INSERT, UPDATE, or DELETE grants for anon/authenticated.
-- Audit logs must be generated by trusted server-side code.
