-- Add onboarding progress tracking columns to user_profiles
-- Run this in Supabase SQL Editor

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS onboarding_step INTEGER DEFAULT 1;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN DEFAULT FALSE;

-- Update existing users to step 1 if null
UPDATE user_profiles 
SET onboarding_step = 1 
WHERE onboarding_step IS NULL;

UPDATE user_profiles 
SET onboarding_complete = FALSE 
WHERE onboarding_complete IS NULL;

COMMENT ON COLUMN user_profiles.onboarding_step IS 'Current onboarding step (1-8)';
COMMENT ON COLUMN user_profiles.onboarding_complete IS 'Whether user has completed onboarding';

