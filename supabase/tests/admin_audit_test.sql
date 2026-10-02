-- ============================================================
-- Velvet Grill
-- FR-25: record sensitive admin actions in audit logs.
--
-- Auditing is enforced by a single AFTER trigger function
-- (private.record_admin_audit, migration 20261002000002) attached
-- to every admin-mutable table. It records a row only when the
-- writing actor is an admin (private.is_admin()), so customer and
-- owner/service writes are not recorded as admin actions.
--
-- Verification context matters: "no audit row" proofs are taken
-- from the owner/superuser context (reset role) after executing the
-- action in the actor context. A customer-context count is only
-- used as an explicit RLS-isolation assertion (T7) after at least
-- one row exists.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table
-- owner before switching roles.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  (
    '11111111-1111-1111-1111-111111111111',
    'fr25-customer-a@test.local'
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'fr25-admin@test.local'
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'fr25-customer-b@test.local'
  );

update public.profiles
set full_name = 'Customer A'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Admin', role = 'ADMIN', is_active = true
where id = '22222222-2222-2222-2222-222222222222';

update public.profiles
set full_name = 'Customer B'
where id = '33333333-3333-3333-3333-333333333333';

insert into public.categories (
  id, name, slug, is_active
)
values (
  'aaaaaaaa-0000-4000-8000-000000000001',
  'Steak',
  'steak-fr25',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  'bbbbbbbb-0000-4000-8000-000000000001',
  'aaaaaaaa-0000-4000-8000-000000000001',
  'Wagyu Ribeye Steak',
  'wagyu-ribeye-fr25',
  250000,
  10,
  true
);

insert into public.product_images (
  id, product_id, storage_path, alt_text, sort_order, is_primary
)
values (
  'c0000000-0000-4000-8000-000000000001',
  'bbbbbbbb-0000-4000-8000-000000000001',
  'steak.svg',
  'Wagyu ribeye steak',
  0,
  true
);

-- Restaurant settings singleton (id = 1); tolerated if seeded.
insert into public.restaurant_settings (id, restaurant_name)
values (1, 'Velvet Grill')
on conflict (id) do nothing;

-- O1: customer A cash order, remains PENDING_PAYMENT/UNPAID for the
-- order-lifecycle tests.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  '90909090-0000-4000-8000-000000000001',
  'VG-FR25-001',
  '11111111-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'Customer A',
  '080000000001',
  250000,
  0,
  250000,
  'UNPAID',
  'PENDING_PAYMENT'
);

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values (
  '92929292-0000-4000-8000-000000000001',
  '90909090-0000-4000-8000-000000000001',
  'bbbbbbbb-0000-4000-8000-000000000001',
  'Wagyu Ribeye Steak',
  250000,
  250000,
  1,
  250000
);

insert into public.payments (id, order_id, method, status, amount)
values (
  '93939393-0000-4000-8000-000000000001',
  '90909090-0000-4000-8000-000000000001',
  'CASH',
  'UNPAID',
  250000
);

-- O2: customer A digital order for the customer self-confirm case.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  '90909090-0000-4000-8000-000000000002',
  'VG-FR25-002',
  '11111111-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'Customer A',
  '080000000001',
  250000,
  0,
  250000,
  'PENDING',
  'PENDING_PAYMENT'
);

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values (
  '92929292-0000-4000-8000-000000000002',
  '90909090-0000-4000-8000-000000000002',
  'bbbbbbbb-0000-4000-8000-000000000001',
  'Wagyu Ribeye Steak',
  250000,
  250000,
  1,
  250000
);

insert into public.payments (id, order_id, method, status, amount)
values (
  '93939393-0000-4000-8000-000000000002',
  '90909090-0000-4000-8000-000000000002',
  'DUMMY_QRIS',
  'PENDING',
  250000
);

-- O3: customer A COMPLETED purchase, giving A an eligible review.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  '90909090-0000-4000-8000-000000000003',
  'VG-FR25-003',
  '11111111-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'Customer A',
  '080000000001',
  250000,
  0,
  250000,
  'PAID',
  'COMPLETED'
);

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values (
  '92929292-0000-4000-8000-000000000003',
  '90909090-0000-4000-8000-000000000003',
  'bbbbbbbb-0000-4000-8000-000000000001',
  'Wagyu Ribeye Steak',
  250000,
  250000,
  1,
  250000
);

insert into public.reviews (
  id, user_id, product_id, order_item_id, rating, title, content, status
)
values (
  'a1000000-0000-4000-8000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'bbbbbbbb-0000-4000-8000-000000000001',
  '92929292-0000-4000-8000-000000000003',
  5,
  'Excellent',
  'Very good.',
  'PUBLISHED'
);

-- ============================================================
-- CLIENT WRITE DENIAL
-- ============================================================

set local role anon;

-- TEST 1
select throws_ok(
  $$
    insert into public.admin_audit_logs (actor_user_id, action, entity_type)
    values (null, 'FAKE_ACTION', 'products')
  $$,
  '42501',
  null,
  'Anonymous users cannot write audit logs'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 2
select throws_ok(
  $$
    insert into public.admin_audit_logs (actor_user_id, action, entity_type)
    values (
      '11111111-1111-1111-1111-111111111111',
      'FAKE_ACTION',
      'products'
    )
  $$,
  '42501',
  null,
  'Customers cannot insert audit logs'
);

-- TEST 3
select throws_ok(
  $$ update public.admin_audit_logs set action = 'FAKE_ACTION' $$,
  '42501',
  null,
  'Customers cannot update audit logs'
);

-- TEST 4
select throws_ok(
  $$ delete from public.admin_audit_logs $$,
  '42501',
  null,
  'Customers cannot delete audit logs'
);

-- ============================================================
-- ADMIN WRITE -> AUDIT (products)
-- ============================================================

set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 5
select lives_ok(
  $$
    select public.admin_save_product(
      'bbbbbbbb-0000-4000-8000-000000000001',
      'aaaaaaaa-0000-4000-8000-000000000001',
      'Wagyu Ribeye Steak',
      'wagyu-ribeye-fr25',
      null,
      275000,
      10,
      true,
      false
    )
  $$,
  'Admin product update via RPC succeeds'
);

reset role;

-- TEST 6
select is(
  (
    select
      count(*)::text || '|' ||
      coalesce(max(action), '') || '|' ||
      coalesce(max(entity_type), '') || '|' ||
      coalesce(max(entity_id::text), '') || '|' ||
      coalesce(max(actor_user_id::text), '') || '|' ||
      coalesce(max(before_data ->> 'base_price'), '') || '|' ||
      coalesce(max(after_data ->> 'base_price'), '')
    from public.admin_audit_logs
  ),
  '1|PRODUCTS_UPDATE|products|bbbbbbbb-0000-4000-8000-000000000001|22222222-2222-2222-2222-222222222222|250000.00|275000.00',
  'Admin product update recorded once with actor and before/after'
);

-- ============================================================
-- READ ISOLATION
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

-- TEST 7
select is(
  (select count(*) from public.admin_audit_logs),
  0::bigint,
  'Customers cannot read audit logs (RLS hides rows)'
);

set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 8
select is(
  (select count(*) from public.admin_audit_logs),
  1::bigint,
  'Admin can read audit logs'
);

-- ============================================================
-- MORE ADMIN TABLES -> AUDIT (actions run as admin, verified as owner)
-- ============================================================

-- TEST 9: categories INSERT (via authoritative RPC)
select public.admin_save_category(
  null,
  'Dessert',
  'dessert-fr25',
  null,
  null,
  0,
  true
);

reset role;

select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where action = 'CATEGORIES_INSERT'
          and entity_type = 'categories'
      )::text
    from public.admin_audit_logs
  ),
  '2|1',
  'Admin category insert recorded'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 10: product_images DELETE (via authoritative RPC)
select public.admin_delete_product_image(
  'c0000000-0000-4000-8000-000000000001',
  'bbbbbbbb-0000-4000-8000-000000000001'
);

reset role;

select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where action = 'PRODUCT_IMAGES_DELETE'
          and entity_type = 'product_images'
      )::text
    from public.admin_audit_logs
  ),
  '3|1',
  'Admin product image delete recorded'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 11: restaurant_settings UPDATE (non-uuid singleton id)
update public.restaurant_settings
set restaurant_name = 'Velvet Grill FR25'
where id = 1;

reset role;

select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where action = 'RESTAURANT_SETTINGS_UPDATE'
          and entity_id is null
      )::text
    from public.admin_audit_logs
  ),
  '4|1',
  'Admin settings update recorded with null entity_id'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 12: order_items INSERT
insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values (
  '92929292-0000-4000-8000-000000000009',
  '90909090-0000-4000-8000-000000000001',
  'bbbbbbbb-0000-4000-8000-000000000001',
  'Wagyu Ribeye Steak',
  250000,
  250000,
  1,
  250000
);

reset role;

select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where action = 'ORDER_ITEMS_INSERT'
          and entity_type = 'order_items'
      )::text
    from public.admin_audit_logs
  ),
  '5|1',
  'Admin order item insert recorded'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 13: reviews UPDATE (admin moderation of another user's review)
update public.reviews
set rating = 4
where id = 'a1000000-0000-4000-8000-000000000001';

reset role;

select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where action = 'REVIEWS_UPDATE'
          and entity_type = 'reviews'
      )::text
    from public.admin_audit_logs
  ),
  '6|1',
  'Admin review content update recorded'
);

-- ============================================================
-- NON-ADMIN WRITES ARE NOT AUDITED
-- ============================================================

-- TEST 14: customer A updates their own eligible review
set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

update public.reviews
set rating = 3
where id = 'a1000000-0000-4000-8000-000000000001';

reset role;

select is(
  (select count(*) from public.admin_audit_logs),
  6::bigint,
  'Customer own-review update is not audited'
);

-- TEST 15: customer A confirms their own digital payment
set local role authenticated;
set local request.jwt.claim.sub =
  '11111111-1111-1111-1111-111111111111';

do $do$
begin
  perform public.confirm_order_payment(
    '90909090-0000-4000-8000-000000000002'
  );
end;
$do$;

reset role;

select is(
  (
    select
      (select payment_status::text
       from public.orders
       where id = '90909090-0000-4000-8000-000000000002') || '|' ||
      (select count(*) from public.admin_audit_logs)::text
  ),
  'PAID|6',
  'Customer digital payment confirmation is not audited'
);

-- TEST 16: owner-context write with no admin identity
reset role;
set local request.jwt.claim.sub = '';

update public.products
set stock = 7
where id = 'bbbbbbbb-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.admin_audit_logs),
  6::bigint,
  'Owner-context write is not audited'
);

-- ============================================================
-- ADMIN ORDER LIFECYCLE (via the orders trigger)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 17: invalid transition is rejected and writes nothing
select throws_ok(
  $$
    select public.update_order_status(
      '90909090-0000-4000-8000-000000000001',
      'READY'
    )
  $$,
  '22023',
  null,
  'Invalid order status transition is rejected'
);

reset role;

-- TEST 18
select is(
  (select count(*) from public.admin_audit_logs),
  6::bigint,
  'Rejected order status transition wrote no audit row'
);

set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

-- TEST 19: real transition
select is(
  (
    select public.update_order_status(
      '90909090-0000-4000-8000-000000000001',
      'CONFIRMED'
    )::text
  ),
  'CONFIRMED',
  'Admin order status transition succeeds'
);

reset role;

-- TEST 20
select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where entity_type = 'orders'
          and action = 'ORDERS_UPDATE'
          and after_data ->> 'order_status' = 'CONFIRMED'
      )::text
    from public.admin_audit_logs
  ),
  '7|1',
  'Order status transition recorded once'
);

-- TEST 21: same-status replay is an idempotent no-op with no audit row
set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

do $do$
begin
  perform public.update_order_status(
    '90909090-0000-4000-8000-000000000001',
    'CONFIRMED'
  );
end;
$do$;

reset role;

select is(
  (select count(*) from public.admin_audit_logs),
  7::bigint,
  'Same-status replay wrote no duplicate audit row'
);

-- TEST 22: admin cash payment confirmation
set local role authenticated;
set local request.jwt.claim.sub =
  '22222222-2222-2222-2222-222222222222';

select is(
  (
    select public.confirm_order_payment(
      '90909090-0000-4000-8000-000000000001'
    )::text
  ),
  'PAID',
  'Admin cash payment confirmation succeeds'
);

-- TEST 23: payment confirm replay adds no duplicate audit row
do $do$
begin
  perform public.confirm_order_payment(
    '90909090-0000-4000-8000-000000000001'
  );
end;
$do$;

reset role;

select is(
  (
    select
      count(*)::text || '|' ||
      count(*) filter (
        where entity_type = 'orders'
          and action = 'ORDERS_UPDATE'
          and after_data ->> 'payment_status' = 'PAID'
      )::text
    from public.admin_audit_logs
  ),
  '8|1',
  'Payment confirmation recorded once; replay wrote no duplicate'
);

-- ============================================================
-- TRIGGER ATTACHMENT METADATA
-- ============================================================

-- TEST 24
select is(
  (
    select
      count(*)::text || '|' ||
      coalesce(
        string_agg(tgname || ':' || relname, ',' order by tgname),
        ''
      )
    from (
      select t.tgname, c.relname
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and not t.tgisinternal
        and t.tgname like 'fr25_audit_%'
    ) s
  ),
  '12|fr25_audit_business_hours:business_hours,fr25_audit_categories:categories,fr25_audit_order_item_options:order_item_options,fr25_audit_order_items:order_items,fr25_audit_orders:orders,fr25_audit_product_images:product_images,fr25_audit_product_option_groups:product_option_groups,fr25_audit_product_options:product_options,fr25_audit_products:products,fr25_audit_restaurant_settings:restaurant_settings,fr25_audit_restaurant_tables:restaurant_tables,fr25_audit_reviews:reviews',
  'Exactly the 12 expected FR-25 audit triggers are attached to their tables'
);

select * from finish();

rollback;
