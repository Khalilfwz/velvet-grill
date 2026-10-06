begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- ============================================================
-- GAP-04: avatars bucket + owner-scoped storage.objects policies.
--
-- The bucket may be created by config.toml or by the migration's idempotent
-- upsert; either way the metadata below must hold.
-- ============================================================

-- TEST 1
select is(
  (select public from storage.buckets where id = 'avatars'),
  true,
  'avatars bucket is public'
);

-- TEST 2
select is(
  (select file_size_limit from storage.buckets where id = 'avatars'),
  2097152::bigint,
  'avatars bucket file size limit is 2 MiB'
);

-- TEST 3
select is(
  (
    select allowed_mime_types
    from storage.buckets
    where id = 'avatars'
  ),
  array['image/jpeg', 'image/png', 'image/webp'],
  'avatars bucket allows only jpeg/png/webp'
);

-- ============================================================
-- OWNER BEHAVIOR
-- ============================================================

set local role authenticated;
set local request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000001';

-- TEST 4
select lives_ok(
  $$
    insert into storage.objects (bucket_id, name)
    values (
      'avatars',
      'd0000000-0000-0000-0000-000000000001/avatar-1.jpg'
    )
  $$,
  'Owner can insert into own avatar folder'
);

-- TEST 5
select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'avatars'
      and name = 'd0000000-0000-0000-0000-000000000001/avatar-1.jpg'
  ),
  1::bigint,
  'Owner can select own avatar object'
);

-- TEST 6
select throws_ok(
  $$
    insert into storage.objects (bucket_id, name)
    values (
      'avatars',
      'd0000000-0000-0000-0000-000000000002/avatar-x.jpg'
    )
  $$,
  '42501',
  null,
  'Cross-user insert into another avatar folder is denied'
);

-- TEST 7
-- Behavioral WITH CHECK: renaming an owned object into another user's folder
-- must be rejected, proving avatars_update_own.with_check prevents namespace
-- transfer (the old row passes USING, the new row fails WITH CHECK).
select throws_ok(
  $$
    update storage.objects
    set name = 'd0000000-0000-0000-0000-000000000002/stolen.jpg'
    where name = 'd0000000-0000-0000-0000-000000000001/avatar-1.jpg'
  $$,
  '42501',
  null,
  'Owner cannot move own avatar object into another user folder (WITH CHECK)'
);

-- ============================================================
-- CROSS-USER ISOLATION
-- ============================================================

set local request.jwt.claim.sub = 'd0000000-0000-0000-0000-000000000002';

-- TEST 8
select is(
  (
    select count(*)
    from storage.objects
    where bucket_id = 'avatars'
  ),
  0::bigint,
  'Cross-user cannot select another avatar object'
);

-- TEST 9
-- Data-modifying CTEs must be top-level, so the affected-row count is stashed
-- in a transaction-local setting (mirrors profile_authorization_test.sql).
with updated as (
  update storage.objects
  set name = 'd0000000-0000-0000-0000-000000000002/stolen.jpg'
  where name = 'd0000000-0000-0000-0000-000000000001/avatar-1.jpg'
  returning id
)
select set_config(
  'gap04.cross_user_update_rows',
  (select count(*)::text from updated),
  true
);

select is(
  current_setting('gap04.cross_user_update_rows')::bigint,
  0::bigint,
  'Cross-user update affects 0 rows'
);

-- ============================================================
-- DELETE POLICY SEMANTICS
--
-- Direct DELETE on storage.objects is refused by storage.protect_delete()
-- ("Use the Storage API instead"), so the delete policy is inspected from the
-- catalog instead. The catalog qual is:
--   ((bucket_id = 'avatars'::text) AND
--    ((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text))
-- These assertions check the relevant scoping semantics, not an exact string.
-- ============================================================

-- TEST 10
select ok(
  (
    select position('bucket_id = ''avatars''' in qual) > 0
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'avatars_delete_own'
  ),
  'avatars_delete_own is scoped to bucket_id = avatars'
);

-- TEST 11
select ok(
  (
    select
      position('storage.foldername(name))[1]' in qual) > 0
      and position('auth.uid()' in qual) > 0
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'avatars_delete_own'
  ),
  'avatars_delete_own binds the first path segment to auth.uid()'
);

-- ============================================================
-- ANON DEFENSE
-- ============================================================

set local role anon;

-- TEST 12
select throws_ok(
  $$
    insert into storage.objects (bucket_id, name)
    values (
      'avatars',
      'd0000000-0000-0000-0000-000000000001/anon.jpg'
    )
  $$,
  '42501',
  null,
  'Anonymous insert is denied'
);

select * from finish();

rollback;
