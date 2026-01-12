-- =====================================================
-- One-time backfill: user profile names (safe to run)
--
-- Goal:
-- - Ensure public.user_profiles.first_name is populated for all existing users.
-- - Prefer existing sources (family_members, auth metadata, email local-part).
-- - If still missing, generate a deterministic placeholder.
--
-- Notes:
-- - Canonical name lives in public.user_profiles.
-- - family_members.first_name is synced from user_profiles via trigger in migration:
--   supabase/migrations/20260109183000_edit_profile_foundations.sql
-- =====================================================

-- Ensure columns exist (older DBs may not have these yet)
ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS first_name TEXT;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS last_name TEXT;

-- 1) From family_members (most users will have this)
update public.user_profiles up
set first_name = fm.first_name
from public.family_members fm
where fm.user_id = up.user_id
  and (up.first_name is null or btrim(up.first_name) = '')
  and fm.first_name is not null
  and btrim(fm.first_name) <> '';

-- 2) From auth.users raw_user_meta_data (if present)
update public.user_profiles up
set first_name = nullif(btrim(au.raw_user_meta_data->>'first_name'), '')
from auth.users au
where au.id = up.user_id
  and (up.first_name is null or btrim(up.first_name) = '')
  and au.raw_user_meta_data ? 'first_name';

-- 3) From auth.users email local-part (e.g. "jane.doe" -> "Jane")
update public.user_profiles up
set first_name = initcap(split_part(au.email, '@', 1))
from auth.users au
where au.id = up.user_id
  and (up.first_name is null or btrim(up.first_name) = '')
  and au.email is not null
  and btrim(au.email) <> '';

-- 4) Deterministic placeholder (stable per user_id)
update public.user_profiles up
set first_name = 'Miya' || substring(md5(up.user_id::text), 1, 6)
where up.user_id is not null
  and (up.first_name is null or btrim(up.first_name) = '');

-- Optional: backfill last_name if you later decide you want a default there too
-- (we leave last_name as-is / nullable for now).

