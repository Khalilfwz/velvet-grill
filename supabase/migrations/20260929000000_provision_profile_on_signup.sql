-- ============================================================
-- Velvet Grill
-- FR-07: Provision a profile for every auth user
--
-- Guarantees the 1:1 relationship between auth.users and
-- public.profiles. Security-sensitive: the trigger function is
-- SECURITY DEFINER because GoTrue inserts auth users as
-- supabase_auth_admin, which has no privileges on
-- public.profiles.
-- ============================================================

-- ------------------------------------------------------------
-- Provisioning function
--
-- Lives in the private schema so it is never reachable through
-- the API (config.toml exposes only public/graphql_public), and
-- runs as the migration owner, matching private.is_admin().
-- ------------------------------------------------------------

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Strict insert by design: this trigger enforces the
  -- auth.users -> public.profiles invariant, so an unexpected
  -- conflicting row must surface as an error rather than be
  -- silently swallowed. Conflict handling belongs only in the
  -- reconciliation step below.
  insert into public.profiles (id)
  values (new.id);

  return new;
end;
$$;

revoke all on function private.handle_new_user() from public;
revoke all on function private.handle_new_user() from anon, authenticated;

-- ------------------------------------------------------------
-- Trigger
-- ------------------------------------------------------------

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function private.handle_new_user();

-- ------------------------------------------------------------
-- Reconciliation for pre-existing auth users
--
-- This is reconciliation over existing data, not invariant
-- enforcement, so idempotent conflict handling is appropriate
-- here. No-op locally: auth.users is empty.
-- ------------------------------------------------------------

insert into public.profiles (id)
select u.id
from auth.users u
on conflict (id) do nothing;
