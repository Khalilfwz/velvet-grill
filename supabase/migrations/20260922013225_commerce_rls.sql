-- ============================================================
-- Velvet Grill
-- Commerce Row Level Security and Grants
-- ============================================================

-- ------------------------------------------------------------
-- Enable RLS
-- ------------------------------------------------------------

alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.cart_item_options enable row level security;

alter table public.wishlists enable row level security;
alter table public.wishlist_items enable row level security;

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_item_options enable row level security;

alter table public.payments enable row level security;
alter table public.order_status_history enable row level security;

alter table public.coupons enable row level security;
alter table public.coupon_usages enable row level security;

-- ------------------------------------------------------------
-- Revoke default client privileges
-- ------------------------------------------------------------

revoke all on table public.carts from anon, authenticated;
revoke all on table public.cart_items from anon, authenticated;
revoke all on table public.cart_item_options from anon, authenticated;

revoke all on table public.wishlists from anon, authenticated;
revoke all on table public.wishlist_items from anon, authenticated;

revoke all on table public.orders from anon, authenticated;
revoke all on table public.order_items from anon, authenticated;
revoke all on table public.order_item_options from anon, authenticated;

revoke all on table public.payments from anon, authenticated;
revoke all on table public.order_status_history from anon, authenticated;

revoke all on table public.coupons from anon, authenticated;
revoke all on table public.coupon_usages from anon, authenticated;

-- ------------------------------------------------------------
-- CARTS
-- ------------------------------------------------------------

grant select, insert, update, delete
on table public.carts
to authenticated;

create policy "carts_select_own"
on public.carts
for select
to authenticated
using (
  user_id = (select auth.uid())
);

create policy "carts_insert_own"
on public.carts
for insert
to authenticated
with check (
  user_id = (select auth.uid())
);

create policy "carts_update_own"
on public.carts
for update
to authenticated
using (
  user_id = (select auth.uid())
)
with check (
  user_id = (select auth.uid())
);

create policy "carts_delete_own"
on public.carts
for delete
to authenticated
using (
  user_id = (select auth.uid())
);

-- ------------------------------------------------------------
-- CART ITEMS
-- ------------------------------------------------------------

grant select, insert, update, delete
on table public.cart_items
to authenticated;

create policy "cart_items_select_own"
on public.cart_items
for select
to authenticated
using (
  exists (
    select 1
    from public.carts c
    where c.id = cart_id
      and c.user_id = (select auth.uid())
  )
);

create policy "cart_items_insert_own"
on public.cart_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.carts c
    where c.id = cart_id
      and c.user_id = (select auth.uid())
  )
);

create policy "cart_items_update_own"
on public.cart_items
for update
to authenticated
using (
  exists (
    select 1
    from public.carts c
    where c.id = cart_id
      and c.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.carts c
    where c.id = cart_id
      and c.user_id = (select auth.uid())
  )
);

create policy "cart_items_delete_own"
on public.cart_items
for delete
to authenticated
using (
  exists (
    select 1
    from public.carts c
    where c.id = cart_id
      and c.user_id = (select auth.uid())
  )
);

-- ------------------------------------------------------------
-- CART ITEM OPTIONS
-- ------------------------------------------------------------

grant select, insert, delete
on table public.cart_item_options
to authenticated;

create policy "cart_item_options_select_own"
on public.cart_item_options
for select
to authenticated
using (
  exists (
    select 1
    from public.cart_items ci
    join public.carts c
      on c.id = ci.cart_id
    where ci.id = cart_item_id
      and c.user_id = (select auth.uid())
  )
);

create policy "cart_item_options_insert_valid"
on public.cart_item_options
for insert
to authenticated
with check (
  exists (
    select 1
    from public.cart_items ci
    join public.carts c
      on c.id = ci.cart_id
    join public.product_option_groups pog
      on pog.product_id = ci.product_id
    join public.product_options po
      on po.group_id = pog.id
    where ci.id = cart_item_id
      and c.user_id = (select auth.uid())
      and po.id = product_option_id
      and po.is_available = true
      and pog.is_active = true
  )
);

create policy "cart_item_options_delete_own"
on public.cart_item_options
for delete
to authenticated
using (
  exists (
    select 1
    from public.cart_items ci
    join public.carts c
      on c.id = ci.cart_id
    where ci.id = cart_item_id
      and c.user_id = (select auth.uid())
  )
);

-- ------------------------------------------------------------
-- WISHLISTS
-- ------------------------------------------------------------

grant select, insert, update, delete
on table public.wishlists
to authenticated;

create policy "wishlists_select_own"
on public.wishlists
for select
to authenticated
using (
  user_id = (select auth.uid())
);

create policy "wishlists_insert_own"
on public.wishlists
for insert
to authenticated
with check (
  user_id = (select auth.uid())
);

create policy "wishlists_update_own"
on public.wishlists
for update
to authenticated
using (
  user_id = (select auth.uid())
)
with check (
  user_id = (select auth.uid())
);

create policy "wishlists_delete_own"
on public.wishlists
for delete
to authenticated
using (
  user_id = (select auth.uid())
);

-- ------------------------------------------------------------
-- WISHLIST ITEMS
-- ------------------------------------------------------------

grant select, insert, delete
on table public.wishlist_items
to authenticated;

create policy "wishlist_items_select_own"
on public.wishlist_items
for select
to authenticated
using (
  exists (
    select 1
    from public.wishlists w
    where w.id = wishlist_id
      and w.user_id = (select auth.uid())
  )
);

create policy "wishlist_items_insert_own"
on public.wishlist_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.wishlists w
    where w.id = wishlist_id
      and w.user_id = (select auth.uid())
  )
);

create policy "wishlist_items_delete_own"
on public.wishlist_items
for delete
to authenticated
using (
  exists (
    select 1
    from public.wishlists w
    where w.id = wishlist_id
      and w.user_id = (select auth.uid())
  )
);

-- ------------------------------------------------------------
-- ORDERS
-- Customer: read own orders
-- Admin: manage orders
-- Customer order creation remains server-controlled.
-- ------------------------------------------------------------

grant select, insert, update
on table public.orders
to authenticated;

create policy "orders_select_own"
on public.orders
for select
to authenticated
using (
  user_id = (select auth.uid())
);

create policy "orders_admin_select"
on public.orders
for select
to authenticated
using (
  (select private.is_admin())
);

create policy "orders_admin_insert"
on public.orders
for insert
to authenticated
with check (
  (select private.is_admin())
);

create policy "orders_admin_update"
on public.orders
for update
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- ORDER ITEMS
-- ------------------------------------------------------------

grant select, insert, update
on table public.order_items
to authenticated;

create policy "order_items_select_own"
on public.order_items
for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.user_id = (select auth.uid())
  )
);

create policy "order_items_admin_manage"
on public.order_items
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- ORDER ITEM OPTIONS
-- ------------------------------------------------------------

grant select, insert, update
on table public.order_item_options
to authenticated;

create policy "order_item_options_select_own"
on public.order_item_options
for select
to authenticated
using (
  exists (
    select 1
    from public.order_items oi
    join public.orders o
      on o.id = oi.order_id
    where oi.id = order_item_id
      and o.user_id = (select auth.uid())
  )
);

create policy "order_item_options_admin_manage"
on public.order_item_options
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- PAYMENTS
-- Customer: read own payments
-- Admin: manage payments
-- ------------------------------------------------------------

grant select, insert, update
on table public.payments
to authenticated;

create policy "payments_select_own"
on public.payments
for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.user_id = (select auth.uid())
  )
);

create policy "payments_admin_manage"
on public.payments
for all
to authenticated
using (
  (select private.is_admin())
)
with check (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- ORDER STATUS HISTORY
-- Customer: read own history
-- Admin: read + insert
-- ------------------------------------------------------------

grant select, insert
on table public.order_status_history
to authenticated;

create policy "order_status_history_select_own"
on public.order_status_history
for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.user_id = (select auth.uid())
  )
);

create policy "order_status_history_admin_insert"
on public.order_status_history
for insert
to authenticated
with check (
  (select private.is_admin())
);

create policy "order_status_history_admin_select"
on public.order_status_history
for select
to authenticated
using (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- COUPONS
-- Client roles receive no direct access.
-- Coupon validation stays server-controlled.
-- ------------------------------------------------------------

grant select
on table public.coupons
to authenticated;

create policy "coupons_admin_select"
on public.coupons
for select
to authenticated
using (
  (select private.is_admin())
);

-- ------------------------------------------------------------
-- COUPON USAGES
-- Customer: read own usage
-- Admin: read usages
-- Writing is server-controlled.
-- ------------------------------------------------------------

grant select
on table public.coupon_usages
to authenticated;

create policy "coupon_usages_select_own"
on public.coupon_usages
for select
to authenticated
using (
  user_id = (select auth.uid())
);

create policy "coupon_usages_admin_select"
on public.coupon_usages
for select
to authenticated
using (
  (select private.is_admin())
);
