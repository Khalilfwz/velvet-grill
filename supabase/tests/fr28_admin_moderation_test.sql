-- ============================================================
-- Velvet Grill
-- FR-28: admins manage orders and moderate reviews.
--
-- Order status management reuses the existing admin-gated
-- public.update_order_status RPC and is covered by the FR-18/FR-19
-- suites. This suite covers the new review-moderation boundary:
-- public.admin_moderate_review (migration 20261003000000).
--
-- It proves the RPC is the only usable review-status writer, is
-- explicitly admin-gated, keeps customer mutation capability at
-- zero, and is audited by the FR-25 trigger. Two fixtures are
-- kept separate: R1 for behavioral hide/republish, and R2 for the
-- audit/idempotency group, whose assertions use an explicit
-- per-review baseline so R1's audit rows cannot interfere.
--
-- Profiles are provisioned by the on_auth_user_created trigger
-- (migration 20260929000000); fixtures are inserted as the table
-- owner before switching to the `authenticated` role.
-- ============================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ============================================================
-- TEST FIXTURES (owner)
-- ============================================================

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'fr28-customer-a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'fr28-admin@test.local');

update public.profiles
set full_name = 'Customer A'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles
set full_name = 'Admin', role = 'ADMIN', is_active = true
where id = '22222222-2222-2222-2222-222222222222';

insert into public.categories (id, name, slug, is_active)
values (
  'aaaaaaaa-0000-4000-8000-000000000028',
  'FR-28 Steak',
  'fr28-steak',
  true
);

insert into public.products (
  id, category_id, name, slug, base_price, stock, is_available
)
values (
  'bbbbbbbb-0000-4000-8000-000000000028',
  'aaaaaaaa-0000-4000-8000-000000000028',
  'FR-28 Wagyu',
  'fr28-wagyu',
  250000,
  10,
  true
);

insert into public.orders (
  id, order_number, user_id, fulfillment_type, pickup_at,
  customer_name_snapshot, customer_phone_snapshot,
  subtotal, discount_total, final_total, payment_status, order_status
)
values (
  'd1000000-0000-4000-8000-000000000028',
  'VG-FR28-001',
  '11111111-1111-1111-1111-111111111111',
  'PICKUP',
  now() + interval '2 hours',
  'Customer A',
  '080000000028',
  500000,
  0,
  500000,
  'PAID',
  'COMPLETED'
);

insert into public.order_items (
  id, order_id, product_id, product_name_snapshot,
  base_price_snapshot, final_unit_price, quantity, subtotal
)
values
  (
    'e1000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000028',
    'bbbbbbbb-0000-4000-8000-000000000028',
    'FR-28 Wagyu',
    250000,
    250000,
    1,
    250000
  ),
  (
    'e1000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000028',
    'bbbbbbbb-0000-4000-8000-000000000028',
    'FR-28 Wagyu',
    250000,
    250000,
    1,
    250000
  );

-- R1: behavioral hide/republish fixture.
-- R2: dedicated audit/idempotency fixture. Separate order items keep
-- the reviews_user_order_item_unique constraint satisfied.
insert into public.reviews (
  id, user_id, product_id, order_item_id, rating, title, content, status
)
values
  (
    'a1000000-0000-4000-8000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'bbbbbbbb-0000-4000-8000-000000000028',
    'e1000000-0000-4000-8000-000000000001',
    5,
    'R1',
    'Behavioral fixture.',
    'PUBLISHED'
  ),
  (
    'a1000000-0000-4000-8000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'bbbbbbbb-0000-4000-8000-000000000028',
    'e1000000-0000-4000-8000-000000000002',
    4,
    'R2',
    'Audit fixture.',
    'PUBLISHED'
  );

-- ============================================================
-- A. BEHAVIORAL HIDE / REPUBLISH (R1)
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- A1
select lives_ok(
  $$
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000001',
      'HIDDEN'
    )
  $$,
  'Admin can hide a published review'
);

reset role;

-- A2
select is(
  (
    select status
    from public.reviews
    where id = 'a1000000-0000-4000-8000-000000000001'
  ),
  'HIDDEN'::public.review_status,
  'Review status is HIDDEN after moderation'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- A3
select is(
  (
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000001',
      'PUBLISHED'
    )
  ),
  'PUBLISHED'::public.review_status,
  'Admin can republish a hidden review'
);

-- ============================================================
-- B. RPC AUTHORIZATION
-- ============================================================

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- B1
select throws_ok(
  $$
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000001',
      'HIDDEN'
    )
  $$,
  '42501',
  null,
  'Customer cannot moderate a review'
);

set local role anon;
set local request.jwt.claim.sub = '';

-- B2
select throws_ok(
  $$
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000001',
      'HIDDEN'
    )
  $$,
  '42501',
  null,
  'Anon cannot execute the moderation RPC'
);

-- ============================================================
-- C. VALIDATION / EDGES
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- C1
select throws_ok(
  $$
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-0000000000ff',
      'HIDDEN'
    )
  $$,
  '42501',
  null,
  'Missing review is indistinguishable from unauthorized'
);

-- C2
select throws_ok(
  $$
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000002',
      null::public.review_status
    )
  $$,
  '22023',
  null,
  'Null review status is rejected'
);

-- ============================================================
-- D. AUDIT + IDEMPOTENCY (R2, explicit per-review baseline)
-- ============================================================

reset role;

create temp table fr28_r2_baseline as
select count(*)::bigint as audit_count
from public.admin_audit_logs
where entity_type = 'reviews'
  and entity_id = 'a1000000-0000-4000-8000-000000000002';

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- D1
select lives_ok(
  $$
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000002',
      'HIDDEN'
    )
  $$,
  'Admin moderates the audit fixture once'
);

reset role;

-- D2
select is(
  (
    select count(*)::bigint
    from public.admin_audit_logs
    where entity_type = 'reviews'
      and entity_id = 'a1000000-0000-4000-8000-000000000002'
  ),
  (select audit_count + 1 from fr28_r2_baseline),
  'Moderation adds exactly one REVIEWS_UPDATE row'
);

-- D3
select is(
  (
    select actor_user_id
    from public.admin_audit_logs
    where entity_type = 'reviews'
      and entity_id = 'a1000000-0000-4000-8000-000000000002'
    order by created_at desc
    limit 1
  ),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'Audit actor is the admin'
);

-- D4
select is(
  (
    select after_data ->> 'status'
    from public.admin_audit_logs
    where entity_type = 'reviews'
      and entity_id = 'a1000000-0000-4000-8000-000000000002'
    order by created_at desc
    limit 1
  ),
  'HIDDEN',
  'Audit after_data records HIDDEN'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

-- D5
select is(
  (
    select public.admin_moderate_review(
      'a1000000-0000-4000-8000-000000000002',
      'HIDDEN'
    )
  ),
  'HIDDEN'::public.review_status,
  'Same-status replay is a no-op'
);

reset role;

-- D6
select is(
  (
    select count(*)::bigint
    from public.admin_audit_logs
    where entity_type = 'reviews'
      and entity_id = 'a1000000-0000-4000-8000-000000000002'
  ),
  (select audit_count + 1 from fr28_r2_baseline),
  'Same-status replay adds no audit row'
);

-- ============================================================
-- E. PRESERVED FR-22 RULES
-- ============================================================

-- E1: direct status writes stay revoked.
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select throws_ok(
  $$
    update public.reviews
    set status = 'HIDDEN'
    where id = 'a1000000-0000-4000-8000-000000000001'
  $$,
  '42501',
  null,
  'Review status remains RPC-only (direct update revoked)'
);

-- E2: customer content updates still work.
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select lives_ok(
  $$
    update public.reviews
    set rating = 3
    where id = 'a1000000-0000-4000-8000-000000000001'
  $$,
  'Customer can still update their own review content'
);

-- E3: hidden review stays unreadable to anon.
set local role anon;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)::bigint
    from public.reviews
    where id = 'a1000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'Anon cannot read a hidden review'
);

-- E4: admin can read hidden reviews for moderation.
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (
    select count(*)::bigint
    from public.reviews
    where id = 'a1000000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'Admin can read a hidden review'
);

-- ============================================================
-- F. FUNCTION METADATA / GRANTS
-- ============================================================

reset role;

-- F1
select ok(
  (
    select p.prosecdef
      and array_to_string(p.proconfig, ',') like '%search_path=%'
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_moderate_review'
  ),
  'admin_moderate_review is SECURITY DEFINER with a pinned search_path'
);

-- F2
select ok(
  not has_function_privilege(
    'anon',
    'public.admin_moderate_review(uuid, public.review_status)',
    'EXECUTE'
  ),
  'Anon cannot execute admin_moderate_review'
);

-- F3
select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_moderate_review(uuid, public.review_status)',
    'EXECUTE'
  ),
  'Authenticated can execute admin_moderate_review'
);

select * from finish();

rollback;
