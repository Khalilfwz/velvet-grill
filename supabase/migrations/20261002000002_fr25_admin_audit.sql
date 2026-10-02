-- ============================================================
-- Velvet Grill
-- FR-25: record sensitive admin actions in audit logs.
--
-- The admin_audit_logs table already exists with admin-only read
-- RLS and no client write grant, but nothing wrote to it. Every
-- currently callable authenticated-admin mutation path is a
-- direct Data-API table write (catalog/settings) or a trusted
-- RPC whose effect lands on public.orders. The minimal
-- authoritative mechanism that covers all of them is a single
-- AFTER trigger function attached to the admin-mutable tables.
--
-- Only admin-originated writes are recorded: the trigger gates on
-- private.is_admin(), so customer writes (create_order, customer
-- digital confirm_order_payment) and owner/service writes are not
-- treated as admin actions. Writes are handled by the existing
-- admin_audit_logs table; no grants/RLS on it change.
--
-- No RPC bodies are modified, so the FR-17/FR-18/FR-19 function
-- signatures, SECURITY DEFINER, search_path, privileges and replay
-- semantics are preserved.
-- ============================================================

-- ------------------------------------------------------------
-- Admin audit trigger function
-- ------------------------------------------------------------

create or replace function private.record_admin_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_entity_id uuid;
begin
  -- Only admin-originated writes are sensitive admin actions.
  if not (select private.is_admin()) then
    return null;
  end if;

  if tg_op <> 'INSERT' then
    v_old := to_jsonb(old);
  end if;

  if tg_op <> 'DELETE' then
    v_new := to_jsonb(new);
  end if;

  -- All audited tables use a uuid primary key except
  -- restaurant_settings, whose smallint singleton id cannot map
  -- to admin_audit_logs.entity_id (uuid).
  if tg_table_name = 'restaurant_settings' then
    v_entity_id := null;
  else
    v_entity_id := coalesce(
      case when tg_op = 'DELETE' then null else (v_new ->> 'id')::uuid end,
      case when tg_op = 'INSERT' then null else (v_old ->> 'id')::uuid end
    );
  end if;

  insert into public.admin_audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  values (
    (select auth.uid()),
    upper(tg_table_name) || '_' || tg_op,
    tg_table_name,
    v_entity_id,
    v_old,
    v_new
  );

  return null;
end;
$$;

revoke all on function private.record_admin_audit() from public;
revoke all on function private.record_admin_audit() from anon, authenticated;

-- ------------------------------------------------------------
-- Attach to every admin-mutable table
-- ------------------------------------------------------------

create trigger fr25_audit_categories
after insert or update or delete on public.categories
for each row execute function private.record_admin_audit();

create trigger fr25_audit_products
after insert or update or delete on public.products
for each row execute function private.record_admin_audit();

create trigger fr25_audit_product_images
after insert or update or delete on public.product_images
for each row execute function private.record_admin_audit();

create trigger fr25_audit_product_option_groups
after insert or update or delete on public.product_option_groups
for each row execute function private.record_admin_audit();

create trigger fr25_audit_product_options
after insert or update or delete on public.product_options
for each row execute function private.record_admin_audit();

create trigger fr25_audit_restaurant_tables
after insert or update or delete on public.restaurant_tables
for each row execute function private.record_admin_audit();

create trigger fr25_audit_business_hours
after insert or update or delete on public.business_hours
for each row execute function private.record_admin_audit();

create trigger fr25_audit_restaurant_settings
after insert or update or delete on public.restaurant_settings
for each row execute function private.record_admin_audit();

create trigger fr25_audit_orders
after insert or update or delete on public.orders
for each row execute function private.record_admin_audit();

create trigger fr25_audit_order_items
after insert or update or delete on public.order_items
for each row execute function private.record_admin_audit();

create trigger fr25_audit_order_item_options
after insert or update or delete on public.order_item_options
for each row execute function private.record_admin_audit();

create trigger fr25_audit_reviews
after insert or update or delete on public.reviews
for each row execute function private.record_admin_audit();
