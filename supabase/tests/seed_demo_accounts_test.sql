begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- ============================================================
-- Seed regression: demo accounts (supabase/seed.sql, local/demo-only)
--
-- GoTrue (v2.197.0) reads the auth.users token string columns
-- confirmation_token, recovery_token, email_change and
-- email_change_token_new as non-nullable strings during sign-in.
-- Those columns have no defaults, so a seed INSERT that omits them
-- stores NULL and breaks password grants with HTTP 500
-- "converting NULL to string is unsupported". The seed must write
-- '' explicitly, mirroring what GoTrue itself stores on API signup.
--
-- Assertions cover exactly the four confirmed columns (T4/T5) plus
-- the pre-existing demo-account invariants: roles, confirmation,
-- bcrypt passwords, identities, and trigger-provisioned profiles.
-- ============================================================

-- ------------------------------------------------------------
-- ACCOUNTS
-- ------------------------------------------------------------

-- T1
select is(
  (
    select count(*)
    from auth.users
    where email in ('demo@velvetgrill.test', 'admin@velvetgrill.test')
  ),
  2::bigint,
  'Seed provisions exactly two demo accounts'
);

-- T2
select is(
  (
    select aud || '/' || role
    from auth.users
    where email = 'demo@velvetgrill.test'
  ),
  'authenticated/authenticated',
  'Demo customer uses the authenticated aud/role'
);

-- T3
select is(
  (
    select aud || '/' || role
    from auth.users
    where email = 'admin@velvetgrill.test'
  ),
  'authenticated/authenticated',
  'Demo admin uses the authenticated aud/role'
);

-- ------------------------------------------------------------
-- GOTRUE TOKEN COLUMNS (the four confirmed columns only)
-- ------------------------------------------------------------

-- T4
select is(
  (
    select count(*)
    from auth.users
    where email in ('demo@velvetgrill.test', 'admin@velvetgrill.test')
      and (
        confirmation_token is null
        or recovery_token is null
        or email_change is null
        or email_change_token_new is null
      )
  ),
  0::bigint,
  'Demo accounts have no NULL auth token columns (GoTrue sign-in blocker)'
);

-- T5
select is(
  (
    select count(*)
    from auth.users
    where email in ('demo@velvetgrill.test', 'admin@velvetgrill.test')
      and confirmation_token = ''
      and recovery_token = ''
      and email_change = ''
      and email_change_token_new = ''
  ),
  2::bigint,
  'Demo accounts write empty strings for all four auth token columns'
);

-- ------------------------------------------------------------
-- CONFIRMATION / PASSWORDS / IDENTITIES
-- ------------------------------------------------------------

-- T6
select is(
  (
    select count(*)
    from auth.users
    where email in ('demo@velvetgrill.test', 'admin@velvetgrill.test')
      and email_confirmed_at is not null
  ),
  2::bigint,
  'Demo accounts are email-confirmed (local enable_confirmations)'
);

-- T7
select is(
  (
    select extensions.crypt('velvet-demo-2026', encrypted_password) = encrypted_password
    from auth.users
    where email = 'demo@velvetgrill.test'
  ),
  true,
  'Demo customer bcrypt hash verifies the documented password'
);

-- T8
select is(
  (
    select extensions.crypt('velvet-admin-2026', encrypted_password) = encrypted_password
    from auth.users
    where email = 'admin@velvetgrill.test'
  ),
  true,
  'Demo admin bcrypt hash verifies the documented password'
);

-- T9
select is(
  (
    select count(*)
    from auth.identities i
    join auth.users u on u.id = i.user_id
    where u.email = 'demo@velvetgrill.test'
      and i.provider = 'email'
      and i.identity_data ->> 'email_verified' = 'true'
  ),
  1::bigint,
  'Demo customer has exactly one verified email identity'
);

-- T10
select is(
  (
    select count(*)
    from auth.identities i
    join auth.users u on u.id = i.user_id
    where u.email = 'admin@velvetgrill.test'
      and i.provider = 'email'
      and i.identity_data ->> 'email_verified' = 'true'
  ),
  1::bigint,
  'Demo admin has exactly one verified email identity'
);

-- ------------------------------------------------------------
-- PROFILES (provisioned by the on_auth_user_created trigger, FR-07)
-- ------------------------------------------------------------

-- T11
select is(
  (
    select role::text || '/' || full_name
    from public.profiles
    where id = 'a0000000-0000-4000-8000-000000000001'
  ),
  'CUSTOMER/Demo Customer',
  'Demo customer profile is provisioned with the CUSTOMER role'
);

-- T12
select is(
  (
    select role::text || '/' || full_name
    from public.profiles
    where id = 'a0000000-0000-4000-8000-000000000002'
  ),
  'ADMIN/Demo Admin',
  'Demo admin profile is promoted to ADMIN'
);

select * from finish();

rollback;
