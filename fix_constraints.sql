-- =====================================================
-- CRITICAL FIX: Update database constraints
-- =====================================================
-- Run this in Supabase SQL Editor
-- =====================================================

-- Fix ethnicity constraint (use simple values)
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_ethnicity_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_ethnicity_check CHECK (ethnicity IN ('White', 'Asian', 'Black', 'Hispanic', 'Other'));

-- Fix smoking status constraint
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_smoking_status_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_smoking_status_check CHECK (smoking_status IN ('Never', 'Former', 'Current'));

-- Done!
