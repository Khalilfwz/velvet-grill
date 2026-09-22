-- ============================================================
-- Velvet Grill
-- Fix Review RLS Product Ownership Check
-- ============================================================

drop policy if exists "reviews_insert_completed_purchase"
on public.reviews;

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
      and oi.product_id = public.reviews.product_id
      and o.user_id = (select auth.uid())
      and o.order_status = 'COMPLETED'
  )
);

drop policy if exists "reviews_update_own"
on public.reviews;

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
      and oi.product_id = public.reviews.product_id
      and o.user_id = (select auth.uid())
      and o.order_status = 'COMPLETED'
  )
);
