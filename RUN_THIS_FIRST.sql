-- STEP 1: See what's currently in the table
SELECT DISTINCT condition_type FROM health_conditions;

-- STEP 2: Delete ALL existing health_conditions (they have old format)
-- This is safe - users will re-enter on next onboarding
DELETE FROM health_conditions;

-- STEP 3: Now drop the old constraint
ALTER TABLE health_conditions
DROP CONSTRAINT IF EXISTS health_conditions_condition_type_check;

-- STEP 4: Add the new constraint (will work now since table is empty)
ALTER TABLE health_conditions
ADD CONSTRAINT health_conditions_condition_type_check 
CHECK (condition_type IN (
    'bp_normal', 'bp_elevated_untreated', 'bp_elevated_treated', 'bp_unknown',
    'diabetes_none', 'diabetes_pre_diabetic', 'diabetes_type_1', 'diabetes_type_2', 'diabetes_unknown',
    'prior_heart_attack', 'prior_stroke',
    'family_history_heart_early', 'family_history_stroke_early', 'family_history_type2_diabetes',
    'chronic_kidney_disease', 'atrial_fibrillation', 'high_cholesterol',
    'heart_health_unsure', 'medical_history_unsure',
    'hypertension', 'diabetes', 'cholesterol', 'prior_heart_stroke', 'ckd',
    'family_history_heart', 'family_history_stroke', 'family_history_diabetes'
));

-- STEP 5: Add last_name column to user_profiles
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS last_name TEXT;

-- STEP 6: Verify constraint was added
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'health_conditions'::regclass;

