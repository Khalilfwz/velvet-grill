-- ============================================================
-- Velvet Grill
-- Development Seed Data
-- ============================================================

-- ------------------------------------------------------------
-- Categories
-- ------------------------------------------------------------

insert into public.categories (
  id,
  name,
  slug,
  description,
  sort_order,
  is_active
)
values
(
  '10000000-0000-0000-0000-000000000001',
  'Steak & Main Course',
  'steak-main-course',
  'Signature steak and main course selections from Velvet Grill.',
  1,
  true
),
(
  '10000000-0000-0000-0000-000000000002',
  'Fast Food & Casual Bites',
  'fast-food-casual-bites',
  'Burgers, fries, wings, and casual favorites.',
  2,
  true
),
(
  '10000000-0000-0000-0000-000000000003',
  'Drinks',
  'drinks',
  'Refreshing beverages, coffee, juice, and signature mocktails.',
  3,
  true
),
(
  '10000000-0000-0000-0000-000000000004',
  'Dessert',
  'dessert',
  'Sweet finishes for your Velvet Grill experience.',
  4,
  true
);

-- ------------------------------------------------------------
-- Products
-- ------------------------------------------------------------

insert into public.products (
  id,
  category_id,
  name,
  slug,
  description,
  base_price,
  stock,
  is_available,
  is_featured
)
values

-- Steak & Main Course
(
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Wagyu Ribeye Steak',
  'wagyu-ribeye-steak',
  'Premium wagyu ribeye grilled to order.',
  250000,
  20,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  'Tenderloin Steak with Truffle Sauce',
  'tenderloin-steak-truffle-sauce',
  'Tenderloin steak served with a rich truffle sauce.',
  225000,
  20,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000001',
  'Grilled Salmon Fillet',
  'grilled-salmon-fillet',
  'Grilled salmon fillet with a fresh savory finish.',
  180000,
  20,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000004',
  '10000000-0000-0000-0000-000000000001',
  'BBQ Baby Back Ribs',
  'bbq-baby-back-ribs',
  'Slow-cooked baby back ribs glazed with BBQ sauce.',
  195000,
  15,
  true,
  false
),

-- Fast Food & Casual Bites
(
  '20000000-0000-0000-0000-000000000005',
  '10000000-0000-0000-0000-000000000002',
  'Velvet Classic Burger',
  'velvet-classic-burger',
  'Classic beef burger with Velvet Grill house dressing.',
  75000,
  30,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000006',
  '10000000-0000-0000-0000-000000000002',
  'Double Cheese Burger',
  'double-cheese-burger',
  'Double beef patty with melted cheese.',
  95000,
  30,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000007',
  '10000000-0000-0000-0000-000000000002',
  'Crispy Chicken Burger',
  'crispy-chicken-burger',
  'Crispy chicken fillet with fresh toppings.',
  70000,
  30,
  true,
  false
),
(
  '20000000-0000-0000-0000-000000000008',
  '10000000-0000-0000-0000-000000000002',
  'French Fries',
  'french-fries',
  'Crispy golden fries.',
  35000,
  50,
  true,
  false
),
(
  '20000000-0000-0000-0000-000000000009',
  '10000000-0000-0000-0000-000000000002',
  'Chicken Wings',
  'chicken-wings',
  'Crispy chicken wings with your choice of sauce.',
  55000,
  40,
  true,
  false
),

-- Drinks
(
  '20000000-0000-0000-0000-000000000010',
  '10000000-0000-0000-0000-000000000003',
  'Velvet Sunset',
  'velvet-sunset',
  'Signature refreshing mocktail.',
  45000,
  40,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000011',
  '10000000-0000-0000-0000-000000000003',
  'Fresh Orange Juice',
  'fresh-orange-juice',
  'Freshly prepared orange juice.',
  30000,
  40,
  true,
  false
),
(
  '20000000-0000-0000-0000-000000000012',
  '10000000-0000-0000-0000-000000000003',
  'Iced Coffee',
  'iced-coffee',
  'Smooth iced coffee with a balanced finish.',
  35000,
  40,
  true,
  false
),
(
  '20000000-0000-0000-0000-000000000013',
  '10000000-0000-0000-0000-000000000003',
  'Soft Drink',
  'soft-drink',
  'Chilled carbonated soft drink.',
  25000,
  50,
  true,
  false
),

-- Dessert
(
  '20000000-0000-0000-0000-000000000014',
  '10000000-0000-0000-0000-000000000004',
  'Molten Chocolate Lava Cake',
  'molten-chocolate-lava-cake',
  'Warm chocolate cake with a molten center.',
  55000,
  20,
  true,
  true
),
(
  '20000000-0000-0000-0000-000000000015',
  '10000000-0000-0000-0000-000000000004',
  'Cheesecake Slice',
  'cheesecake-slice',
  'Creamy cheesecake served by the slice.',
  45000,
  20,
  true,
  false
),
(
  '20000000-0000-0000-0000-000000000016',
  '10000000-0000-0000-0000-000000000004',
  'Ice Cream Sundae',
  'ice-cream-sundae',
  'Classic ice cream sundae with toppings.',
  40000,
  25,
  true,
  false
),
(
  '20000000-0000-0000-0000-000000000017',
  '10000000-0000-0000-0000-000000000004',
  'Tiramisu',
  'tiramisu',
  'Classic Italian-style tiramisu.',
  50000,
  20,
  true,
  false
);

-- ------------------------------------------------------------
-- Product Option Groups
-- ------------------------------------------------------------

insert into public.product_option_groups (
  id,
  product_id,
  name,
  selection_type,
  min_selections,
  max_selections,
  is_required,
  sort_order,
  is_active
)
values
(
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'Doneness',
  'SINGLE',
  1,
  1,
  true,
  1,
  true
),
(
  '30000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000001',
  'Sauce',
  'SINGLE',
  1,
  1,
  true,
  2,
  true
),
(
  '30000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000008',
  'Fries Flavor',
  'SINGLE',
  1,
  1,
  true,
  1,
  true
),
(
  '30000000-0000-0000-0000-000000000009',
  '20000000-0000-0000-0000-000000000009',
  'Wing Sauce',
  'SINGLE',
  1,
  1,
  true,
  1,
  true
);

-- ------------------------------------------------------------
-- Product Options
-- ------------------------------------------------------------

insert into public.product_options (
  id,
  group_id,
  name,
  price_delta,
  is_available,
  sort_order
)
values
(
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  'Medium Rare',
  0,
  true,
  1
),
(
  '40000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000001',
  'Medium',
  0,
  true,
  2
),
(
  '40000000-0000-0000-0000-000000000003',
  '30000000-0000-0000-0000-000000000001',
  'Medium Well',
  0,
  true,
  3
),
(
  '40000000-0000-0000-0000-000000000004',
  '30000000-0000-0000-0000-000000000001',
  'Well Done',
  0,
  true,
  4
),
(
  '40000000-0000-0000-0000-000000000005',
  '30000000-0000-0000-0000-000000000002',
  'Black Pepper',
  0,
  true,
  1
),
(
  '40000000-0000-0000-0000-000000000006',
  '30000000-0000-0000-0000-000000000002',
  'Mushroom',
  10000,
  true,
  2
),
(
  '40000000-0000-0000-0000-000000000007',
  '30000000-0000-0000-0000-000000000002',
  'Truffle',
  20000,
  true,
  3
),
(
  '40000000-0000-0000-0000-000000000008',
  '30000000-0000-0000-0000-000000000003',
  'Original',
  0,
  true,
  1
),
(
  '40000000-0000-0000-0000-000000000009',
  '30000000-0000-0000-0000-000000000003',
  'Cheese',
  10000,
  true,
  2
),
(
  '40000000-0000-0000-0000-000000000010',
  '30000000-0000-0000-0000-000000000003',
  'Spicy',
  5000,
  true,
  3
),
(
  '40000000-0000-0000-0000-000000000011',
  '30000000-0000-0000-0000-000000000009',
  'BBQ',
  0,
  true,
  1
),
(
  '40000000-0000-0000-0000-000000000012',
  '30000000-0000-0000-0000-000000000009',
  'Spicy',
  5000,
  true,
  2
);

-- ------------------------------------------------------------
-- Restaurant Tables
-- ------------------------------------------------------------

insert into public.restaurant_tables (
  id,
  table_number,
  capacity,
  is_active
)
values
(
  '50000000-0000-0000-0000-000000000001',
  'T01',
  2,
  true
),
(
  '50000000-0000-0000-0000-000000000002',
  'T02',
  2,
  true
),
(
  '50000000-0000-0000-0000-000000000003',
  'T03',
  4,
  true
),
(
  '50000000-0000-0000-0000-000000000004',
  'T04',
  4,
  true
),
(
  '50000000-0000-0000-0000-000000000005',
  'T05',
  6,
  true
);

-- ------------------------------------------------------------
-- Business Hours
-- PostgreSQL day_of_week:
-- 0 = Sunday
-- 1 = Monday
-- ...
-- 6 = Saturday
-- ------------------------------------------------------------

insert into public.business_hours (
  id,
  day_of_week,
  opens_at,
  closes_at,
  is_closed
)
values
(
  '60000000-0000-0000-0000-000000000000',
  0,
  '11:00',
  '22:00',
  false
),
(
  '60000000-0000-0000-0000-000000000001',
  1,
  '11:00',
  '22:00',
  false
),
(
  '60000000-0000-0000-0000-000000000002',
  2,
  '11:00',
  '22:00',
  false
),
(
  '60000000-0000-0000-0000-000000000003',
  3,
  '11:00',
  '22:00',
  false
),
(
  '60000000-0000-0000-0000-000000000004',
  4,
  '11:00',
  '22:00',
  false
),
(
  '60000000-0000-0000-0000-000000000005',
  5,
  '11:00',
  '23:00',
  false
),
(
  '60000000-0000-0000-0000-000000000006',
  6,
  '11:00',
  '23:00',
  false
);

-- ------------------------------------------------------------
-- Restaurant Settings
-- ------------------------------------------------------------

insert into public.restaurant_settings (
  id,
  restaurant_name,
  address,
  phone,
  currency_code,
  timezone
)
values (
  1,
  'Velvet Grill',
  'Jakarta, Indonesia',
  '+62 21 0000 0000',
  'IDR',
  'Asia/Jakarta'
);

-- ------------------------------------------------------------
-- Product Images
--
-- Real storefront product images are seeded into the product-images
-- storage bucket from supabase/images/products via config.toml.
-- Each catalog product has one primary image.
-- ------------------------------------------------------------

insert into public.product_images (
  id,
  product_id,
  storage_path,
  alt_text,
  sort_order,
  is_primary
)
values

-- Steak & Main Course
(
  '70000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'products/wagyu-ribeye-steak/main.webp',
  'Wagyu Ribeye Steak',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000002',
  'products/tenderloin-steak-truffle-sauce/main.webp',
  'Tenderloin Steak with Truffle Sauce',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000004',
  '20000000-0000-0000-0000-000000000003',
  'products/grilled-salmon-fillet/main.webp',
  'Grilled Salmon Fillet',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000010',
  '20000000-0000-0000-0000-000000000004',
  'products/bbq-baby-back-ribs/main.webp',
  'BBQ Baby Back Ribs',
  0,
  true
),

-- Fast Food & Casual Bites
(
  '70000000-0000-0000-0000-000000000005',
  '20000000-0000-0000-0000-000000000005',
  'products/velvet-classic-burger/main.webp',
  'Velvet Classic Burger',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000006',
  '20000000-0000-0000-0000-000000000006',
  'products/double-cheese-burger/main.webp',
  'Double Cheese Burger',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000011',
  '20000000-0000-0000-0000-000000000007',
  'products/crispy-chicken-burger/main.webp',
  'Crispy Chicken Burger',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000012',
  '20000000-0000-0000-0000-000000000008',
  'products/french-fries/main.webp',
  'French Fries',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000013',
  '20000000-0000-0000-0000-000000000009',
  'products/chicken-wings/main.webp',
  'Chicken Wings',
  0,
  true
),

-- Drinks
(
  '70000000-0000-0000-0000-000000000007',
  '20000000-0000-0000-0000-000000000010',
  'products/velvet-sunset/main.webp',
  'Velvet Sunset',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000014',
  '20000000-0000-0000-0000-000000000011',
  'products/fresh-orange-juice/main.webp',
  'Fresh Orange Juice',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000008',
  '20000000-0000-0000-0000-000000000012',
  'products/iced-coffee/main.webp',
  'Iced Coffee',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000015',
  '20000000-0000-0000-0000-000000000013',
  'products/soft-drink/main.webp',
  'Soft Drink',
  0,
  true
),

-- Dessert
(
  '70000000-0000-0000-0000-000000000009',
  '20000000-0000-0000-0000-000000000014',
  'products/molten-chocolate-lava-cake/main.webp',
  'Molten Chocolate Lava Cake',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000016',
  '20000000-0000-0000-0000-000000000015',
  'products/cheesecake-slice/main.webp',
  'Cheesecake Slice',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000017',
  '20000000-0000-0000-0000-000000000016',
  'products/ice-cream-sundae/main.webp',
  'Ice Cream Sundae',
  0,
  true
),
(
  '70000000-0000-0000-0000-000000000018',
  '20000000-0000-0000-0000-000000000017',
  'products/tiramisu/main.webp',
  'Tiramisu',
  0,
  true
);

-- ------------------------------------------------------------
-- Demo accounts
--
-- STRICTLY LOCAL / DEMO ONLY. Provisioned only by this seed file
-- for local development and portfolio review.
-- Security requirement: do not execute this demo seed in production
-- or shared environments, and never reuse these credentials —
-- production/shared access must be provisioned through proper
-- operator account management instead.
--
-- Passwords are bcrypt-hashed via pgcrypto and documented in
-- README.md. The on_auth_user_created trigger (FR-07) provisions
-- the matching public.profiles rows; the admin row is promoted
-- to ADMIN below. auth.identities rows mirror what GoTrue writes
-- for email/password signups: provider_id is the user UUID, which is
-- how GoTrue looks email identities up (e.g. during email-change
-- confirmation), not the email address. GoTrue reads the auth.users
-- token string columns (confirmation_token, recovery_token,
-- email_change, email_change_token_new) as non-nullable strings
-- during sign-in:
-- NULL breaks password grants with HTTP 500 "converting NULL to
-- string is unsupported" and those columns have no defaults, so the
-- seed writes '' (what GoTrue itself stores on signup), never NULL.
-- UUIDs use the a0000000- family and
-- emails the velvetgrill.test domain so they never collide with
-- pgTAP fixtures (@test.local) or catalog seeds (10000000- …).
-- ------------------------------------------------------------

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  confirmation_token,
  recovery_token,
  email_change,
  email_change_token_new,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
(
  '00000000-0000-0000-0000-000000000000',
  'a0000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'demo@velvetgrill.test',
  extensions.crypt('velvet-demo-2026', extensions.gen_salt('bf')),
  now(),
  '',
  '',
  '',
  '',
  '{"provider":"email","providers":["email"]}',
  '{}',
  now(),
  now()
),
(
  '00000000-0000-0000-0000-000000000000',
  'a0000000-0000-4000-8000-000000000002',
  'authenticated',
  'authenticated',
  'admin@velvetgrill.test',
  extensions.crypt('velvet-admin-2026', extensions.gen_salt('bf')),
  now(),
  '',
  '',
  '',
  '',
  '{"provider":"email","providers":["email"]}',
  '{}',
  now(),
  now()
);

insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  u.id::text,
  u.id,
  jsonb_build_object(
    'sub', u.id::text,
    'email', u.email,
    'email_verified', true
  ),
  'email',
  u.created_at,
  u.created_at,
  u.created_at
from auth.users u
where u.email in ('demo@velvetgrill.test', 'admin@velvetgrill.test');

-- Profile display names + the demo admin role grant. Customers
-- cannot self-promote (FR-08); this is the documented local
-- development equivalent of an operator granting the role.
update public.profiles
set full_name = 'Demo Customer'
where id = 'a0000000-0000-4000-8000-000000000001';

update public.profiles
set role = 'ADMIN', full_name = 'Demo Admin'
where id = 'a0000000-0000-4000-8000-000000000002';
