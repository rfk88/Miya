-- Wipe Database for Fresh Testing
-- ⚠️ WARNING: This will DELETE ALL DATA
-- Run in Supabase SQL Editor
-- 
-- This script safely deletes all app data while preserving:
-- - Auth users (so you can still log in)
-- - Database schema (tables, columns, constraints)
--
-- After running this:
-- 1. Users will need to complete onboarding again
-- 2. All vitality scores will be deleted
-- 3. All family data will be deleted
-- 4. All health conditions will be deleted
-- 5. All user profiles will be reset

BEGIN;

-- Delete in order (respecting foreign key constraints)

-- 1. Vitality scores (no dependencies)
DO $$ BEGIN
    DELETE FROM vitality_scores;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table vitality_scores does not exist, skipping';
END $$;

-- 2. Health conditions (references user_profiles)
DO $$ BEGIN
    DELETE FROM health_conditions;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table health_conditions does not exist, skipping';
END $$;

-- 3. Family members (references families and users)
DO $$ BEGIN
    DELETE FROM family_members;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table family_members does not exist, skipping';
END $$;

-- 4. Family invites (references families) - may not exist
DO $$ BEGIN
    DELETE FROM family_invites;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table family_invites does not exist, skipping';
END $$;

-- 5. Families (references users via created_by)
DO $$ BEGIN
    DELETE FROM families;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table families does not exist, skipping';
END $$;

-- 6. User profiles (references users via user_id)
-- This will also clear risk_band, risk_points, optimal_vitality_target, vitality_score_current, etc.
DO $$ BEGIN
    DELETE FROM user_profiles;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table user_profiles does not exist, skipping';
END $$;

-- 7. Alert preferences (references users)
DO $$ BEGIN
    DELETE FROM alert_preferences;
EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE 'Table alert_preferences does not exist, skipping';
END $$;

-- Reset any sequences if needed (optional)
-- ALTER SEQUENCE IF EXISTS families_id_seq RESTART WITH 1;

COMMIT;

-- Verify deletion (only check tables that exist)
DO $$
DECLARE
    vitality_count INT := 0;
    health_count INT := 0;
    members_count INT := 0;
    invites_count INT := 0;
    families_count INT := 0;
    profiles_count INT := 0;
    alerts_count INT := 0;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO vitality_count FROM vitality_scores;
    EXCEPTION WHEN undefined_table THEN
        vitality_count := -1;
    END;
    
    BEGIN
        SELECT COUNT(*) INTO health_count FROM health_conditions;
    EXCEPTION WHEN undefined_table THEN
        health_count := -1;
    END;
    
    BEGIN
        SELECT COUNT(*) INTO members_count FROM family_members;
    EXCEPTION WHEN undefined_table THEN
        members_count := -1;
    END;
    
    BEGIN
        SELECT COUNT(*) INTO invites_count FROM family_invites;
    EXCEPTION WHEN undefined_table THEN
        invites_count := -1;
    END;
    
    BEGIN
        SELECT COUNT(*) INTO families_count FROM families;
    EXCEPTION WHEN undefined_table THEN
        families_count := -1;
    END;
    
    BEGIN
        SELECT COUNT(*) INTO profiles_count FROM user_profiles;
    EXCEPTION WHEN undefined_table THEN
        profiles_count := -1;
    END;
    
    BEGIN
        SELECT COUNT(*) INTO alerts_count FROM alert_preferences;
    EXCEPTION WHEN undefined_table THEN
        alerts_count := -1;
    END;
    
    RAISE NOTICE 'Deletion complete. Counts:';
    RAISE NOTICE '  vitality_scores: %', CASE WHEN vitality_count = -1 THEN 'N/A (table does not exist)' ELSE vitality_count::TEXT END;
    RAISE NOTICE '  health_conditions: %', CASE WHEN health_count = -1 THEN 'N/A (table does not exist)' ELSE health_count::TEXT END;
    RAISE NOTICE '  family_members: %', CASE WHEN members_count = -1 THEN 'N/A (table does not exist)' ELSE members_count::TEXT END;
    RAISE NOTICE '  family_invites: %', CASE WHEN invites_count = -1 THEN 'N/A (table does not exist)' ELSE invites_count::TEXT END;
    RAISE NOTICE '  families: %', CASE WHEN families_count = -1 THEN 'N/A (table does not exist)' ELSE families_count::TEXT END;
    RAISE NOTICE '  user_profiles: %', CASE WHEN profiles_count = -1 THEN 'N/A (table does not exist)' ELSE profiles_count::TEXT END;
    RAISE NOTICE '  alert_preferences: %', CASE WHEN alerts_count = -1 THEN 'N/A (table does not exist)' ELSE alerts_count::TEXT END;
END $$;

-- Expected output: All counts should be 0
-- Auth users remain intact (check auth.users separately if needed)

