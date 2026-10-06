-- ============================================================
-- Velvet Grill
-- GAP-05: complete FR-25 coverage for payment confirmation.
--
-- confirm_order_payment updates public.payments, but payments had
-- no fr25 audit trigger, so the payments row change (amount,
-- method, paid_at) was not recorded. The existing
-- private.record_admin_audit() SECURITY DEFINER trigger function
-- is reused unchanged; no grants, RLS, or table definitions change.
--
-- The trigger is is_admin()-gated, so customer paths that also
-- write payments (create_order, customer digital
-- confirm_order_payment) remain un-audited by design. Only an
-- admin cash/digital confirmation records PAYMENTS_UPDATE.
-- ============================================================

create trigger fr25_audit_payments
after insert or update or delete on public.payments
for each row execute function private.record_admin_audit();
