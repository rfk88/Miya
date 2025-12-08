-- Add new family history condition types to health_conditions table
-- Run this in Supabase SQL Editor

ALTER TABLE health_conditions
DROP CONSTRAINT IF EXISTS health_conditions_condition_type_check;

ALTER TABLE health_conditions
ADD CONSTRAINT health_conditions_condition_type_check 
CHECK (condition_type IN (
    'hypertension',
    'diabetes', 
    'cholesterol',
    'prior_heart_stroke',
    'ckd',
    'atrial_fibrillation',
    'family_history_heart',
    'family_history_stroke',      -- NEW
    'family_history_diabetes',    -- NEW
    'heart_health_unsure',
    'medical_history_unsure'
));

