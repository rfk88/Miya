-- =====================================================
-- GUIDED SETUP MIGRATION
-- =====================================================
-- Adds columns to support "Guided Setup" invite flow
-- where superadmin fills out health data for invited users
--
-- Run this in Supabase SQL Editor

BEGIN;

-- Add guided setup columns to family_members table
ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_data_complete BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS guided_health_data JSONB;

-- Add comments for documentation
COMMENT ON COLUMN family_members.guided_data_complete IS 
  'TRUE when superadmin has completed health data entry for guided setup users. Invite code is only usable when this is TRUE.';

COMMENT ON COLUMN family_members.guided_health_data IS 
  'JSON storage for health data filled by superadmin for guided users. Contains: about_you, heart_health, medical_history sections.';

-- Set guided_data_complete to TRUE for existing Self Setup invites (they don't need guided data)
UPDATE family_members
SET guided_data_complete = TRUE
WHERE onboarding_type = 'Self Setup' AND guided_data_complete IS NULL;

-- Set guided_data_complete to FALSE for existing Guided Setup invites (they need data entry)
UPDATE family_members
SET guided_data_complete = FALSE
WHERE onboarding_type = 'Guided Setup' AND guided_data_complete IS NULL;

COMMIT;

-- =====================================================
-- Example JSON structure for guided_health_data:
-- =====================================================
-- {
--   "about_you": {
--     "gender": "Male",
--     "date_of_birth": "1980-05-15",
--     "height_cm": 180,
--     "weight_kg": 80,
--     "ethnicity": "White",
--     "smoking_status": "Never"
--   },
--   "heart_health": {
--     "blood_pressure_status": "normal",
--     "diabetes_status": "none",
--     "has_prior_heart_attack": false,
--     "has_prior_stroke": false,
--     "has_chronic_kidney_disease": false,
--     "has_atrial_fibrillation": false,
--     "has_high_cholesterol": false
--   },
--   "medical_history": {
--     "family_heart_disease_early": false,
--     "family_stroke_early": false,
--     "family_type2_diabetes": true
--   }
-- }

