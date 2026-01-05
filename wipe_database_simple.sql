-- Database Wipe - ONLY deletes tables that actually exist
-- Based on database_schema.sql
-- Run in Supabase SQL Editor

BEGIN;

-- Delete in order (respecting foreign key constraints)

-- 1. Vitality scores (no dependencies)
DELETE FROM vitality_scores;

-- 2. Health conditions (references user_profiles)
DELETE FROM health_conditions;

-- 3. Connected wearables (references user_profiles)
DELETE FROM connected_wearables;

-- 4. Privacy settings (references user_profiles)
DELETE FROM privacy_settings;

-- 5. Family members (references families and users)
DELETE FROM family_members;

-- 6. Families (references users via created_by)
DELETE FROM families;

-- 7. User profiles (references users via user_id)
-- This clears all onboarding data, risk assessments, vitality targets, etc.
DELETE FROM user_profiles;

COMMIT;

-- Verify deletion
SELECT 
    (SELECT COUNT(*) FROM vitality_scores) as vitality_scores_count,
    (SELECT COUNT(*) FROM health_conditions) as health_conditions_count,
    (SELECT COUNT(*) FROM connected_wearables) as connected_wearables_count,
    (SELECT COUNT(*) FROM privacy_settings) as privacy_settings_count,
    (SELECT COUNT(*) FROM family_members) as family_members_count,
    (SELECT COUNT(*) FROM families) as families_count,
    (SELECT COUNT(*) FROM user_profiles) as user_profiles_count;

-- Expected: All counts should be 0

