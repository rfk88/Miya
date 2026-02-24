-- 20260224150000_add_avatar_to_user_profiles.sql
-- Add avatar_url column to public.user_profiles for storing profile image URLs.
-- Idempotent and safe to run multiple times.

alter table if exists public.user_profiles
  add column if not exists avatar_url text;

comment on column public.user_profiles.avatar_url is
  'Public URL of user''s profile image in Supabase Storage; nullable; fallback to initials when null.';

