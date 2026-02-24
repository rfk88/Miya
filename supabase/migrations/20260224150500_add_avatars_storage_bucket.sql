-- 20260224150500_add_avatars_storage_bucket.sql
-- Create a public Storage bucket for user avatar images and configure basic RLS policies.
-- Idempotent and safe to run multiple times.

-- 1) Create bucket (if it doesn't already exist)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 2) Policies for avatars bucket
do $$
begin
  -- Public read access for avatar images
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Avatar images are publicly accessible'
  ) then
    create policy "Avatar images are publicly accessible"
    on storage.objects
    for select
    using (bucket_id = 'avatars');
  end if;

  -- Authenticated users can upload their own avatars
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Users can upload avatars'
  ) then
    create policy "Users can upload avatars"
    on storage.objects
    for insert
    to authenticated
    with check (
      bucket_id = 'avatars'
      and owner = auth.uid()
    );
  end if;

  -- Authenticated users can update their own avatars
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'Users can update avatars'
  ) then
    create policy "Users can update avatars"
    on storage.objects
    for update
    to authenticated
    using (
      bucket_id = 'avatars'
      and owner = auth.uid()
    )
    with check (
      bucket_id = 'avatars'
      and owner = auth.uid()
    );
  end if;
end
$$;

