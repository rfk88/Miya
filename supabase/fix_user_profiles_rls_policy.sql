-- =====================================================
-- FIX: Enable RLS and create policy for family members to read vitality data
-- Run this in Supabase SQL Editor if diagnostic shows missing policies
-- =====================================================

-- Step 1: Enable RLS on user_profiles (idempotent)
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Step 2: Drop existing policy if it exists (to avoid conflicts)
DROP POLICY IF EXISTS "family_can_read_user_profiles_vitality" ON public.user_profiles;

-- Step 3: Create policy allowing family members to read each other's vitality snapshot
CREATE POLICY "family_can_read_user_profiles_vitality"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (
    -- User can always read their own profile
    user_id = auth.uid()
    OR
    -- User can read profiles of other members in the same family
    EXISTS (
        SELECT 1
        FROM public.family_members me
        JOIN public.family_members them
            ON them.family_id = me.family_id
           AND them.user_id = user_profiles.user_id
        WHERE me.user_id = auth.uid()
    )
);

-- Step 4: Verify the policy was created
SELECT 
    policyname,
    cmd as command,
    qual as using_expression
FROM pg_policies
WHERE tablename = 'user_profiles'
AND schemaname = 'public'
AND policyname = 'family_can_read_user_profiles_vitality';

-- Expected output: 1 row showing the policy details

