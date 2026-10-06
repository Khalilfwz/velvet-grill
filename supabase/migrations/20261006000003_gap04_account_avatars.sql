-- ============================================================
-- Velvet Grill
-- GAP-04: account avatars storage bucket + owner-scoped policies
--
-- The bucket is made reproducible here with an idempotent upsert so an
-- already-created local bucket (from config.toml) does not raise a
-- duplicate-key failure. The Supabase-owned storage schema is not altered.
-- ============================================================

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ------------------------------------------------------------
-- Owner-scoped object policies
--
-- Object paths are `<auth.uid()>/<file>`, so the first path segment must equal
-- the caller. No anon policy: unauthenticated access is denied by default.
-- ------------------------------------------------------------

create policy "avatars_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "avatars_update_own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "avatars_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "avatars_select_own"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
