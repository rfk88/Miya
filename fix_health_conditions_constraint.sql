-- Fix health_conditions constraint to include ALL exact condition types
-- Run this in Supabase SQL Editor

ALTER TABLE health_conditions
DROP CONSTRAINT IF EXISTS health_conditions_condition_type_check;

ALTER TABLE health_conditions
ADD CONSTRAINT health_conditions_condition_type_check 
CHECK (condition_type IN (
    -- Blood Pressure (exact)
    'bp_normal',
    'bp_elevated_untreated',
    'bp_elevated_treated',
    'bp_unknown',
    
    -- Diabetes (exact types for WHO scoring)
    'diabetes_none',
    'diabetes_pre_diabetic',
    'diabetes_type_1',
    'diabetes_type_2',
    'diabetes_unknown',
    
    -- Prior Cardiovascular Events (separate)
    'prior_heart_attack',
    'prior_stroke',
    
    -- Family History (separate - for WHO scoring)
    'family_history_heart_early',
    'family_history_stroke_early',
    'family_history_type2_diabetes',
    
    -- Unsure flags
    'heart_health_unsure',
    'medical_history_unsure',
    
    -- Legacy (keep for backwards compatibility)
    'hypertension',
    'diabetes',
    'cholesterol',
    'prior_heart_stroke',
    'ckd',
    'atrial_fibrillation',
    'family_history_heart',
    'family_history_stroke',
    'family_history_diabetes'
));

