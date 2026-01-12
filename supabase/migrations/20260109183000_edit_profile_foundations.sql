-- =====================================================
-- Edit Profile foundations
-- - Canonical user name + onboarding profile lives in public.user_profiles
-- - RLS: allow authenticated users to select/insert/update their own profile
-- - Sync: keep family_members.first_name in sync from user_profiles.first_name
-- - Backfill: populate user_profiles.first_name from family_members for existing users
-- =====================================================

-- 1) Ensure required columns exist (idempotent)
ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS first_name TEXT;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS last_name TEXT;

-- Champion + notification preferences (required by app code)
ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS champion_name TEXT;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS champion_email TEXT;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS champion_phone TEXT;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS champion_enabled BOOLEAN DEFAULT FALSE;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS notify_inapp BOOLEAN DEFAULT TRUE;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS notify_push BOOLEAN DEFAULT FALSE;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS notify_email BOOLEAN DEFAULT FALSE;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS champion_notify_email BOOLEAN DEFAULT TRUE;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS champion_notify_sms BOOLEAN DEFAULT FALSE;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS quiet_hours_start TIME DEFAULT '22:00';

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS quiet_hours_end TIME DEFAULT '07:00';

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS quiet_hours_apply_critical BOOLEAN DEFAULT FALSE;

-- 2) updated_at auto-maintenance (reuse helper if present)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_updated_at_column') THEN
    CREATE OR REPLACE FUNCTION public.update_updated_at_column()
    RETURNS TRIGGER AS $fn$
    BEGIN
      NEW.updated_at = now();
      RETURN NEW;
    END;
    $fn$ language plpgsql;
  END IF;
END $$;

DROP TRIGGER IF EXISTS update_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER update_user_profiles_updated_at
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- 3) Enable RLS on user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- 4) RLS policies: own profile CRUD
DROP POLICY IF EXISTS "user_profiles_select_own" ON public.user_profiles;
CREATE POLICY "user_profiles_select_own"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user_profiles_insert_own" ON public.user_profiles;
CREATE POLICY "user_profiles_insert_own"
ON public.user_profiles
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "user_profiles_update_own" ON public.user_profiles;
CREATE POLICY "user_profiles_update_own"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 5) RLS policy: allow family members to read each other's vitality snapshot
-- Note: today this policy allows selecting rows across the family (not column-limited).
DROP POLICY IF EXISTS "family_can_read_user_profiles_vitality" ON public.user_profiles;
CREATE POLICY "family_can_read_user_profiles_vitality"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.family_members me
    JOIN public.family_members them
      ON them.family_id = me.family_id
     AND them.user_id = public.user_profiles.user_id
    WHERE me.user_id = auth.uid()
  )
);

-- 6) Sync trigger: user_profiles.first_name -> family_members.first_name
CREATE OR REPLACE FUNCTION public.sync_family_members_first_name_from_profile()
RETURNS TRIGGER AS $fn$
DECLARE
  trimmed_name TEXT;
BEGIN
  trimmed_name := NULLIF(btrim(NEW.first_name), '');
  IF trimmed_name IS NULL THEN
    -- Don't overwrite family_members with NULL/empty
    RETURN NEW;
  END IF;

  UPDATE public.family_members
     SET first_name = trimmed_name
   WHERE user_id = NEW.user_id;

  RETURN NEW;
END;
$fn$ language plpgsql;

DROP TRIGGER IF EXISTS sync_family_members_first_name_from_profile ON public.user_profiles;
CREATE TRIGGER sync_family_members_first_name_from_profile
AFTER INSERT OR UPDATE OF first_name ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_family_members_first_name_from_profile();

-- 7) Backfill: user_profiles.first_name from family_members.first_name (existing users)
UPDATE public.user_profiles up
   SET first_name = fm.first_name
  FROM public.family_members fm
 WHERE fm.user_id = up.user_id
   AND (up.first_name IS NULL OR btrim(up.first_name) = '')
   AND fm.first_name IS NOT NULL;

