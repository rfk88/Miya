-- =====================================================
-- DIAGNOSTIC: Check member vitality data availability
-- Run this in Supabase SQL Editor to verify:
--   1. RLS policies on user_profiles
--   2. Actual data for your test family members
--   3. Family member -> user_profiles linkage
-- =====================================================

-- Step 1: Check if RLS is enabled on user_profiles
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'user_profiles'
AND schemaname = 'public';

-- Step 2: List all existing RLS policies on user_profiles
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd as command,
    qual as using_expression,
    with_check as with_check_expression
FROM pg_policies
WHERE tablename = 'user_profiles'
AND schemaname = 'public';

-- Step 3: Check actual vitality data for your test family members
-- Replace 'TESTINGG Family' with your actual family name, or use the family_id from your logs
WITH test_family AS (
    SELECT id as family_id
    FROM families
    WHERE name LIKE '%TESTINGG%' OR name LIKE '%Testing%'
    LIMIT 1
),
family_user_ids AS (
    SELECT DISTINCT fm.user_id, fm.first_name, fm.role
    FROM family_members fm
    CROSS JOIN test_family tf
    WHERE fm.family_id = tf.family_id
    AND fm.user_id IS NOT NULL
)
SELECT 
    fui.first_name,
    fui.role,
    fui.user_id,
    up.vitality_score_current,
    up.optimal_vitality_target,
    up.vitality_sleep_pillar_score,
    up.vitality_movement_pillar_score,
    up.vitality_stress_pillar_score,
    up.vitality_score_updated_at,
    CASE 
        WHEN up.user_id IS NULL THEN '❌ NO user_profiles ROW'
        WHEN up.vitality_score_current IS NULL THEN '⚠️ vitality_score_current is NULL'
        WHEN up.optimal_vitality_target IS NULL THEN '⚠️ optimal_vitality_target is NULL'
        ELSE '✅ Data exists'
    END as status
FROM family_user_ids fui
LEFT JOIN user_profiles up ON up.user_id = fui.user_id
ORDER BY fui.first_name;

-- Step 4: Count how many user_profiles rows exist vs how many family members have user_ids
WITH test_family AS (
    SELECT id as family_id
    FROM families
    WHERE name LIKE '%TESTINGG%' OR name LIKE '%Testing%'
    LIMIT 1
),
family_stats AS (
    SELECT 
        COUNT(*) FILTER (WHERE user_id IS NOT NULL) as members_with_user_id,
        COUNT(*) FILTER (WHERE user_id IS NULL) as members_without_user_id,
        COUNT(*) as total_members
    FROM family_members fm
    CROSS JOIN test_family tf
    WHERE fm.family_id = tf.family_id
),
profile_stats AS (
    SELECT COUNT(*) as profiles_with_vitality
    FROM user_profiles
    WHERE vitality_score_current IS NOT NULL
)
SELECT 
    fs.total_members,
    fs.members_with_user_id,
    fs.members_without_user_id,
    ps.profiles_with_vitality,
    CASE 
        WHEN fs.members_with_user_id = 0 THEN '❌ No members have user_ids'
        WHEN ps.profiles_with_vitality = 0 THEN '❌ No user_profiles have vitality_score_current'
        WHEN ps.profiles_with_vitality < fs.members_with_user_id THEN '⚠️ Some members missing vitality data'
        ELSE '✅ All members have vitality data'
    END as summary
FROM family_stats fs
CROSS JOIN profile_stats ps;

-- Step 5: Test query that Dashboard is trying to run (simulate authenticated user)
-- Replace 'YOUR_USER_ID_HERE' with one of the user_ids from Step 3
-- This will show you what the app can actually read
SELECT 
    user_id,
    vitality_score_current,
    optimal_vitality_target,
    vitality_sleep_pillar_score,
    vitality_movement_pillar_score,
    vitality_stress_pillar_score
FROM user_profiles
WHERE user_id IN (
    -- Replace these UUIDs with actual user_ids from your family
    '531ABD95-A007-4122-9EEB-4EBBCBBBF2F3'::uuid,
    '1DA2F84E-29E0-489D-B3D8-7AA3289AD068'::uuid,
    '5282AB87-D255-4D28-BEFC-86BE18DE0623'::uuid,
    'A7CA1606-810A-4B14-8E46-4F68932D5DA0'::uuid,
    '15F08528-5FE1-4E6A-9E89-B06944499A62'::uuid,
    '9D49FB0B-5FF4-4707-A20B-FE987FE9EE00'::uuid
)
ORDER BY user_id;

-- =====================================================
-- FIX: Create RLS policy to allow family members to read each other's vitality data
-- =====================================================
-- Uncomment and run this if Step 2 shows no policies exist:

/*
-- First, enable RLS if it's not already enabled
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Create policy: family members can read vitality snapshot columns from other family members
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
*/

