-- ============================================================
-- CRITICAL: RUN THIS SQL IMMEDIATELY IN SUPABASE SQL EDITOR
-- This fixes all constraint issues causing "data already exists"
-- ============================================================

-- 1. Fix health_conditions constraint to allow all our condition types
ALTER TABLE health_conditions
DROP CONSTRAINT IF EXISTS health_conditions_condition_type_check;

ALTER TABLE health_conditions
ADD CONSTRAINT health_conditions_condition_type_check 
CHECK (condition_type IN (
    -- Blood Pressure Status (exact)
    'bp_normal',
    'bp_elevated_untreated',
    'bp_elevated_treated',
    'bp_unknown',
    
    -- Diabetes Status (exact)
    'diabetes_none',
    'diabetes_pre_diabetic',
    'diabetes_type_1',
    'diabetes_type_2',
    'diabetes_unknown',
    
    -- Prior Cardiovascular Events (separate)
    'prior_heart_attack',
    'prior_stroke',
    
    -- Family History (exact)
    'family_history_heart_early',
    'family_history_stroke_early',
    'family_history_type2_diabetes',
    
    -- Medical Conditions (to be added)
    'chronic_kidney_disease',
    'atrial_fibrillation',
    'high_cholesterol',
    
    -- Unsure flags
    'heart_health_unsure',
    'medical_history_unsure',
    
    -- Legacy values (for existing data)
    'hypertension',
    'diabetes',
    'cholesterol',
    'prior_heart_stroke',
    'ckd',
    'family_history_heart',
    'family_history_stroke',
    'family_history_diabetes'
));

-- 2. Fix smoking_status constraint (in case it's still wrong)
ALTER TABLE user_profiles
DROP CONSTRAINT IF EXISTS user_profiles_smoking_status_check;

ALTER TABLE user_profiles
ADD CONSTRAINT user_profiles_smoking_status_check 
CHECK (smoking_status IN ('Never', 'Former', 'Current'));

-- 3. Fix ethnicity constraint
ALTER TABLE user_profiles
DROP CONSTRAINT IF EXISTS user_profiles_ethnicity_check;

ALTER TABLE user_profiles
ADD CONSTRAINT user_profiles_ethnicity_check 
CHECK (ethnicity IN ('White', 'Asian', 'Black', 'Hispanic', 'Other'));

-- 4. Add last_name column if it doesn't exist
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS last_name TEXT;

-- 5. Clear any duplicate health conditions that might exist
-- (This deletes duplicates keeping only the most recent)
DELETE FROM health_conditions a
USING health_conditions b
WHERE a.created_at < b.created_at 
AND a.user_id = b.user_id 
AND a.condition_type = b.condition_type;

-- Verify constraints
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'health_conditions'::regclass;

SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'user_profiles'::regclass;

