-- =====================================================
-- WHO RISK SYSTEM MIGRATION
-- =====================================================
-- Run this in Supabase SQL Editor to add WHO risk fields
-- =====================================================

-- =====================================================
-- STEP 1: Add new columns to user_profiles
-- =====================================================

-- Blood pressure status (awareness-based, not numeric)
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS blood_pressure_status TEXT 
CHECK (blood_pressure_status IN ('normal', 'elevated_untreated', 'elevated_treated', 'unknown'));

-- Diabetes status (expanded from boolean)
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS diabetes_status TEXT 
CHECK (diabetes_status IN ('none', 'pre_diabetic', 'type_1', 'type_2', 'unknown'));

-- Prior cardiovascular events (split into separate fields)
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS has_prior_heart_attack BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS has_prior_stroke BOOLEAN DEFAULT FALSE;

-- Family history (specific conditions)
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS family_heart_disease_early BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS family_stroke_early BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS family_type2_diabetes BOOLEAN DEFAULT FALSE;

-- Calculated risk data
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS risk_band TEXT 
CHECK (risk_band IN ('low', 'moderate', 'high', 'very_high', 'critical'));

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS risk_points INTEGER;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS optimal_vitality_target INTEGER;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS risk_calculated_at TIMESTAMP WITH TIME ZONE;

-- Champion settings
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS champion_name TEXT;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS champion_email TEXT;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS champion_phone TEXT;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS champion_enabled BOOLEAN DEFAULT FALSE;

-- User notification preferences
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS notify_inapp BOOLEAN DEFAULT TRUE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS notify_push BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS notify_email BOOLEAN DEFAULT FALSE;

-- Champion notification preferences
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS champion_notify_email BOOLEAN DEFAULT TRUE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS champion_notify_sms BOOLEAN DEFAULT FALSE;

-- Quiet hours
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS quiet_hours_start TIME DEFAULT '22:00';

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS quiet_hours_end TIME DEFAULT '07:00';

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS quiet_hours_apply_critical BOOLEAN DEFAULT FALSE;

-- Baseline tracking
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS baseline_start_date TIMESTAMP WITH TIME ZONE;


-- =====================================================
-- STEP 2: Update health_conditions valid types
-- =====================================================
-- Add new family history types to health_conditions

-- Drop existing constraint
ALTER TABLE health_conditions 
DROP CONSTRAINT IF EXISTS health_conditions_condition_type_check;

-- Add updated constraint with new types
ALTER TABLE health_conditions 
ADD CONSTRAINT health_conditions_condition_type_check 
CHECK (condition_type IN (
    -- Heart health conditions (Step 5)
    'hypertension',
    'diabetes',
    'prior_heart_attack',
    'prior_stroke',
    -- Family history (Step 6)
    'family_heart_disease_early',
    'family_stroke_early', 
    'family_type2_diabetes',
    -- Unsure flags
    'heart_health_unsure',
    'medical_history_unsure',
    -- Legacy (for backwards compatibility)
    'cholesterol',
    'prior_heart_stroke',
    'ckd',
    'atrial_fibrillation',
    'family_history_heart'
));


-- =====================================================
-- STEP 3: Add alert level to family_members
-- =====================================================
-- For per-member notification preferences

ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS alert_level TEXT DEFAULT 'full'
CHECK (alert_level IN ('full', 'day14_plus', 'dashboard_only'));


-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================
-- If you see "Success. No rows returned" - that's correct!
-- All WHO risk columns have been added.
-- =====================================================


