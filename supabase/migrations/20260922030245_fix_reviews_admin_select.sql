-- ============================================================
-- Velvet Grill
-- Allow Admin to Read All Reviews for Moderation
-- ============================================================

create policy "reviews_admin_select"
on public.reviews
for select
to authenticated
using (
  (select private.is_admin())
);
