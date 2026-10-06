-- ============================================================
-- Velvet Grill
-- FR-26: administrators manage categories / products / options /
-- images through the authoritative admin_* RPCs.
--
-- The direct catalog write grants are revoked from authenticated,
-- so this suite asserts:
--   * direct table writes are denied for every catalog table;
--   * the admin_* RPCs are the write path and require an active
--     ADMIN (authorization is explicit inside the RPC);
--   * in-RPC validation and parent scoping reject bad input;
--   * DB constraints/FKs remain the final backstop;
--   * FR-25 audit triggers receive the real auth.uid() and record
--     exactly one row per successful admin write (none when the
--     write is denied or rejected);
--   * public/customer catalog reads stay compatible.
--
-- Fixtures are inserted as the table owner before switching roles.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('a2600000-0000-4000-8000-000000000001', 'fr26-admin@test.local'),
  ('a2600000-0000-4000-8000-000000000002', 'fr26-customer@test.local');

update public.profiles
set full_name = 'FR-26 Admin', role = 'ADMIN', is_active = true
where id = 'a2600000-0000-4000-8000-000000000001';

update public.profiles
set full_name = 'FR-26 Customer'
where id = 'a2600000-0000-4000-8000-000000000002';

insert into public.categories (id, name, slug, sort_order, is_active)
values
  ('c2600000-0000-4000-8000-000000000001', 'FR-26 Steak', 'fr26-steak', 1, true),
  ('c2600000-0000-4000-8000-000000000002', 'FR-26 Dessert', 'fr26-dessert', 2, true);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available, is_featured
)
values
  (
    'd2600000-0000-4000-8000-000000000001',
    'c2600000-0000-4000-8000-000000000001',
    'FR-26 Steak One', 'fr26-steak-1', 100000, 10, true, false
  ),
  (
    'd2600000-0000-4000-8000-000000000002',
    'c2600000-0000-4000-8000-000000000002',
    'FR-26 Dessert One', 'fr26-dessert-1', 50000, 5, true, false
  );

insert into public.product_images (
  id, product_id, storage_path, alt_text, sort_order, is_primary
)
values (
  'e2600000-0000-4000-8000-000000000001',
  'd2600000-0000-4000-8000-000000000001',
  'fr26.svg', 'FR-26 steak', 0, true
);

insert into public.product_option_groups (
  id, product_id, name, selection_type, min_selections, max_selections,
  is_required, sort_order, is_active
)
values
  (
    'f2600000-0000-4000-8000-000000000001',
    'd2600000-0000-4000-8000-000000000001',
    'FR-26 Doneness', 'SINGLE', 1, 1, true, 1, true
  ),
  (
    'f2600000-0000-4000-8000-000000000002',
    'd2600000-0000-4000-8000-000000000002',
    'FR-26 Topping', 'SINGLE', 1, 1, true, 1, true
  );

insert into public.product_options (
  id, group_id, name, price_delta, is_available, sort_order
)
values (
  '12600000-0000-4000-8000-000000000001',
  'f2600000-0000-4000-8000-000000000001',
  'Medium Rare', 0, true, 1
);

-- Historical order snapshot referencing P1 at its original price.
insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  '22600000-0000-4000-8000-000000000001', 'VG-FR26-001',
  'a2600000-0000-4000-8000-000000000002', 'PICKUP',
  now() + interval '2 hours', 'FR-26 Customer', '080000000026',
  100000, 0, 100000, 'UNPAID', 'PENDING_PAYMENT'
);

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values (
  '32600000-0000-4000-8000-000000000001',
  '22600000-0000-4000-8000-000000000001',
  'd2600000-0000-4000-8000-000000000001',
  'FR-26 Steak One', 100000, 100000, 1, 100000
);

-- ============================================================
-- A. DIRECT CATALOG WRITES ARE DENIED (admin identity included)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'a2600000-0000-4000-8000-000000000001';

-- TEST 1
select throws_ok(
  $$
    insert into public.categories (name, slug, is_active)
    values ('Direct', 'fr26-direct', true)
  $$,
  '42501', null,
  'Admin direct category insert is denied'
);

-- TEST 2
select throws_ok(
  $$
    update public.products
    set base_price = 1
    where id = 'd2600000-0000-4000-8000-000000000001'
  $$,
  '42501', null,
  'Admin direct product update is denied'
);

-- TEST 3
select throws_ok(
  $$
    insert into public.product_images (product_id, storage_path)
    values ('d2600000-0000-4000-8000-000000000001', 'fr26-direct.svg')
  $$,
  '42501', null,
  'Admin direct product image insert is denied'
);

-- TEST 4
select throws_ok(
  $$
    update public.product_option_groups
    set name = 'Direct'
    where id = 'f2600000-0000-4000-8000-000000000001'
  $$,
  '42501', null,
  'Admin direct option group update is denied'
);

-- TEST 5
select throws_ok(
  $$
    update public.product_options
    set name = 'Direct'
    where id = '12600000-0000-4000-8000-000000000001'
  $$,
  '42501', null,
  'Admin direct option update is denied'
);

-- TEST 6
select throws_ok(
  $$
    delete from public.product_images
    where id = 'e2600000-0000-4000-8000-000000000001'
  $$,
  '42501', null,
  'Admin direct product image delete is denied'
);

-- ============================================================
-- B. RPC AUTHORIZATION
-- ============================================================

-- TEST 7: customer cannot invoke an admin RPC
set local request.jwt.claim.sub =
  'a2600000-0000-4000-8000-000000000002';

select throws_ok(
  $$
    select public.admin_save_category(
      null, 'Hack', 'fr26-hack', null, null, 0, true
    )
  $$,
  '42501', null,
  'Customer cannot invoke an admin RPC'
);

-- TEST 8: anon cannot invoke an admin RPC
reset role;
set local role anon;

select throws_ok(
  $$
    select public.admin_save_product(
      null, 'c2600000-0000-4000-8000-000000000001',
      'X', 'fr26-x', null, 1000, 1, true, false
    )
  $$,
  '42501', null,
  'Anon cannot invoke an admin RPC'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'a2600000-0000-4000-8000-000000000001';

-- TEST 9: admin RPC create returns the new id
select is(
  (
    select public.admin_save_category(
      null, 'FR-26 Created', 'fr26-created', null, null, 0, true
    ) is not null
  ),
  true,
  'Admin can create a category via RPC'
);

-- ============================================================
-- C. ADMIN CREATE / UPDATE VIA RPC
-- ============================================================

-- TEST 10
select lives_ok(
  $$
    select public.admin_save_category(
      'c2600000-0000-4000-8000-000000000001',
      'FR-26 Steak Updated', 'fr26-steak', null, null, 1, true
    )
  $$,
  'Admin can update a category via RPC'
);

-- TEST 11
select lives_ok(
  $$
    select public.admin_save_product(
      null, 'c2600000-0000-4000-8000-000000000001',
      'FR-26 New Product', 'fr26-new-product', null, 90000, 4, true, false
    )
  $$,
  'Admin can create a product via RPC'
);

-- TEST 12
select lives_ok(
  $$
    select public.admin_save_product(
      'd2600000-0000-4000-8000-000000000001',
      'c2600000-0000-4000-8000-000000000001',
      'FR-26 Steak One', 'fr26-steak-1', null, 123000, 7, true, false
    )
  $$,
  'Admin can update a product via RPC'
);

-- TEST 13
select lives_ok(
  $$
    select public.admin_save_product_image(
      null, 'd2600000-0000-4000-8000-000000000001',
      'fr26-new.svg', null, 2, false
    )
  $$,
  'Admin can create a product image via RPC'
);

-- TEST 14
select lives_ok(
  $$
    select public.admin_save_product_image(
      'e2600000-0000-4000-8000-000000000001',
      'd2600000-0000-4000-8000-000000000001',
      'fr26.svg', 'FR-26 steak primary', 0, true
    )
  $$,
  'Admin can update a product image via RPC'
);

-- TEST 15
select lives_ok(
  $$
    select public.admin_delete_product_image(
      (
        select id from public.product_images
        where product_id = 'd2600000-0000-4000-8000-000000000001'
          and storage_path = 'fr26-new.svg'
        limit 1
      ),
      'd2600000-0000-4000-8000-000000000001'
    )
  $$,
  'Admin can delete a product image via RPC'
);

-- TEST 16
select lives_ok(
  $$
    select public.admin_save_option_group(
      null, 'd2600000-0000-4000-8000-000000000001',
      'FR-26 Extras', 'MULTIPLE', 0, 3, false, 2, true
    )
  $$,
  'Admin can create an option group via RPC'
);

-- TEST 17
select lives_ok(
  $$
    select public.admin_save_option_group(
      'f2600000-0000-4000-8000-000000000001',
      'd2600000-0000-4000-8000-000000000001',
      'FR-26 Doneness Updated', 'SINGLE', 1, 1, true, 1, true
    )
  $$,
  'Admin can update an option group via RPC'
);

-- TEST 18
select lives_ok(
  $$
    select public.admin_save_option(
      null, 'f2600000-0000-4000-8000-000000000001',
      'd2600000-0000-4000-8000-000000000001',
      'FR-26 Cheese', 5000, true, 2
    )
  $$,
  'Admin can create an option via RPC'
);

-- TEST 19
select lives_ok(
  $$
    select public.admin_save_option(
      '12600000-0000-4000-8000-000000000001',
      'f2600000-0000-4000-8000-000000000001',
      'd2600000-0000-4000-8000-000000000001',
      'Medium Rare', 10000, true, 1
    )
  $$,
  'Admin can update an option via RPC'
);

-- ============================================================
-- D. IN-RPC VALIDATION + CONSTRAINT BACKSTOP (all rejected)
-- ============================================================

-- TEST 20: slug format
select throws_ok(
  $$
    select public.admin_save_category(
      null, 'Bad', 'Bad Slug', null, null, 0, true
    )
  $$,
  '22023', null,
  'RPC rejects an invalid slug'
);

-- TEST 21: unsafe relative path
select throws_ok(
  $$
    select public.admin_save_product_image(
      null, 'd2600000-0000-4000-8000-000000000001',
      '../secret', null, 0, false
    )
  $$,
  '22023', null,
  'RPC rejects an unsafe storage path'
);

-- TEST 22: negative price
select throws_ok(
  $$
    select public.admin_save_product(
      null, 'c2600000-0000-4000-8000-000000000001',
      'Neg', 'fr26-neg', null, -1, 1, true, false
    )
  $$,
  '22023', null,
  'RPC rejects a negative base price'
);

-- TEST 23: negative stock
select throws_ok(
  $$
    select public.admin_save_product(
      null, 'c2600000-0000-4000-8000-000000000001',
      'Neg2', 'fr26-neg2', null, 1000, -5, true, false
    )
  $$,
  '22023', null,
  'RPC rejects negative stock'
);

-- TEST 24: duplicate slug (constraint backstop)
select throws_ok(
  $$
    select public.admin_save_category(
      null, 'Dup', 'fr26-steak', null, null, 0, true
    )
  $$,
  '23505', null,
  'DB unique constraint rejects a duplicate category slug'
);

-- ============================================================
-- E. RELATIONSHIP SCOPING / TAMPERING (all rejected)
-- ============================================================

-- TEST 25: unknown category
select throws_ok(
  $$
    select public.admin_save_product(
      null, '00000000-0000-4000-8000-0000000000ff',
      'Ghost', 'fr26-ghost', null, 1000, 1, true, false
    )
  $$,
  '23503', null,
  'RPC rejects an unknown category'
);

-- TEST 26: unknown option group
select throws_ok(
  $$
    select public.admin_save_option(
      null, '00000000-0000-4000-8000-0000000000fe',
      'd2600000-0000-4000-8000-000000000001',
      'Ghost', 0, true, 0
    )
  $$,
  '23503', null,
  'RPC rejects an unknown option group'
);

-- TEST 27: option group belongs to a different product
select throws_ok(
  $$
    select public.admin_save_option(
      null, 'f2600000-0000-4000-8000-000000000002',
      'd2600000-0000-4000-8000-000000000001',
      'Cross', 0, true, 0
    )
  $$,
  '23503', null,
  'RPC rejects an option group that is not in the target product scope'
);

-- TEST 28: image update with a mismatched product scope
select throws_ok(
  $$
    select public.admin_save_product_image(
      'e2600000-0000-4000-8000-000000000001',
      'd2600000-0000-4000-8000-000000000002',
      'fr26.svg', null, 0, true
    )
  $$,
  'P0002', null,
  'RPC rejects an image update outside its product scope'
);

-- ============================================================
-- F. AUDIT VIA THE AUTHORITATIVE PATH
-- ============================================================

reset role;

-- TEST 29
select is(
  (
    select
      count(*)::text
      || '|' || count(*) filter (where action = 'CATEGORIES_INSERT')::text
      || '|' || count(*) filter (where action = 'CATEGORIES_UPDATE')::text
      || '|' || count(*) filter (where action = 'PRODUCTS_INSERT')::text
      || '|' || count(*) filter (where action = 'PRODUCTS_UPDATE')::text
      || '|' || count(*) filter (where action = 'PRODUCT_IMAGES_INSERT')::text
      || '|' || count(*) filter (where action = 'PRODUCT_IMAGES_UPDATE')::text
      || '|' || count(*) filter (where action = 'PRODUCT_IMAGES_DELETE')::text
      || '|' || count(*) filter (where action = 'PRODUCT_OPTION_GROUPS_INSERT')::text
      || '|' || count(*) filter (where action = 'PRODUCT_OPTION_GROUPS_UPDATE')::text
      || '|' || count(*) filter (where action = 'PRODUCT_OPTIONS_INSERT')::text
      || '|' || count(*) filter (where action = 'PRODUCT_OPTIONS_UPDATE')::text
    from public.admin_audit_logs
    where actor_user_id = 'a2600000-0000-4000-8000-000000000001'
  ),
  '11|1|1|1|1|1|1|1|1|1|1|1',
  'Each successful admin RPC write is audited exactly once; rejected writes none'
);

-- TEST 30
select is(
  (
    select
      count(*)::text
      || '|' || coalesce(max(before_data ->> 'base_price'), '')
      || '|' || coalesce(max(after_data ->> 'base_price'), '')
    from public.admin_audit_logs
    where action = 'PRODUCTS_UPDATE'
      and entity_id = 'd2600000-0000-4000-8000-000000000001'
      and actor_user_id = 'a2600000-0000-4000-8000-000000000001'
  ),
  '1|100000.00|123000.00',
  'RPC product update audited once with real actor and before/after'
);

-- TEST 31
select is(
  (select count(*) from public.admin_audit_logs where action = 'CATEGORIES_INSERT'),
  1::bigint,
  'Rejected / duplicate category writes wrote no audit row'
);

-- TEST 32
select is(
  (
    select count(*) from public.admin_audit_logs
    where actor_user_id = 'a2600000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'Denied non-admin write wrote no audit row'
);

-- ============================================================
-- G. PUBLIC / CUSTOMER COMPATIBILITY + DEACTIVATION
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub =
  'a2600000-0000-4000-8000-000000000001';

select public.admin_save_product(
  'd2600000-0000-4000-8000-000000000002',
  'c2600000-0000-4000-8000-000000000002',
  'FR-26 Dessert One', 'fr26-dessert-1', null, 50000, 5, false, false
);

reset role;
set local role anon;

-- TEST 33
select is(
  (
    select count(*) from public.products
    where id = 'd2600000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'Deactivated product is hidden from the public catalog'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'a2600000-0000-4000-8000-000000000001';

select public.admin_save_category(
  'c2600000-0000-4000-8000-000000000002',
  'FR-26 Dessert', 'fr26-dessert', null, null, 2, false
);

reset role;
set local role anon;

-- TEST 34
select is(
  (
    select count(*) from public.products
    where category_id = 'c2600000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'Products in a deactivated category are hidden from the public catalog'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub =
  'a2600000-0000-4000-8000-000000000001';

-- TEST 35
select is(
  (
    select count(*) from public.products
    where id = 'd2600000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'Admin still reads deactivated catalog rows for management'
);

-- ============================================================
-- H. IMAGE PRIMARY (NON-EXCLUSIVE) + HISTORICAL SNAPSHOT
-- ============================================================

-- TEST 36: a second primary is accepted (is_primary is non-exclusive metadata)
select lives_ok(
  $$
    select public.admin_save_product_image(
      null, 'd2600000-0000-4000-8000-000000000001',
      'fr26-second.svg', null, 3, true
    )
  $$,
  'A second primary image is accepted (non-exclusive metadata)'
);

reset role;

-- TEST 37
select is(
  (
    select base_price_snapshot::text
    from public.order_items
    where id = '32600000-0000-4000-8000-000000000001'
  ),
  '100000.00',
  'Historical order snapshot is unchanged after admin price update'
);

select * from finish();

rollback;
