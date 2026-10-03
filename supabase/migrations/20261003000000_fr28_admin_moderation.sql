-- ============================================================
-- Velvet Grill
-- FR-28: admins manage orders and moderate reviews.
--
-- Order status management already has an authoritative, admin-
-- gated SECURITY DEFINER path (public.update_order_status,
-- FR-18/FR-19) and is reused unchanged. The missing backend piece
-- is review moderation: authenticated UPDATE(status) was revoked
-- (migration 20260926133000), leaving no usable client mutation
-- path. This migration adds one explicit admin-gated RPC instead
-- of restoring a broad direct client write path.
--
-- admin_moderate_review is SECURITY DEFINER with a pinned
-- search_path, re-checks private.is_admin(), validates its target,
-- and is the only status writer. Because it executes in the
-- authenticated admin context, auth.uid() is preserved and the
-- FR-25 fr25_audit_reviews trigger records REVIEWS_UPDATE. The
-- RPC writes no audit rows itself. No service role is used, and
-- the reviews RLS/grants (including the status revoke) are
-- unchanged.
-- ============================================================

create or replace function public.admin_moderate_review(
  p_review_id uuid,
  p_status public.review_status
)
returns public.review_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.review_status;
begin
  if (select auth.uid()) is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if not (select private.is_admin()) then
    raise exception 'Review cannot be moderated' using errcode = '42501';
  end if;

  if p_status is null then
    raise exception 'Review status is invalid' using errcode = '22023';
  end if;

  select r.status into v_current
  from public.reviews r
  where r.id = p_review_id
  for update;

  if not found then
    raise exception 'Review cannot be moderated' using errcode = '42501';
  end if;

  -- Idempotent same-status no-op: no UPDATE, so no audit row.
  if v_current = p_status then
    return v_current;
  end if;

  update public.reviews
  set status = p_status
  where id = p_review_id;

  return p_status;
end;
$$;

revoke all on function public.admin_moderate_review(uuid, public.review_status) from public;
revoke all on function public.admin_moderate_review(uuid, public.review_status) from anon;
grant execute on function public.admin_moderate_review(uuid, public.review_status) to authenticated;
