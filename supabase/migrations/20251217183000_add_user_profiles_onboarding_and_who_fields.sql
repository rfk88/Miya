-- =====================================================
-- PATCH: user_profiles missing columns (onboarding + WHO risk + vitality snapshot + champion/prefs)
-- Idempotent: safe to run multiple times
-- =====================================================

-- Core onboarding tracking
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS onboarding_step INTEGER DEFAULT 1;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN DEFAULT FALSE;

-- Basic profile fields referenced by app code
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS first_name TEXT;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS last_name TEXT;

-- WHO Risk fields referenced by DataManager.saveUserProfile(...)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS blood_pressure_status TEXT
CHECK (blood_pressure_status IN ('normal', 'elevated_untreated', 'elevated_treated', 'unknown'));

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS diabetes_status TEXT
CHECK (diabetes_status IN ('none', 'pre_diabetic', 'type_1', 'type_2', 'unknown'));

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS has_prior_heart_attack BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS has_prior_stroke BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS family_heart_disease_early BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS family_stroke_early BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS family_type2_diabetes BOOLEAN DEFAULT FALSE;

-- Calculated risk outputs referenced by DataManager.saveRiskAssessment(...)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS risk_band TEXT
CHECK (risk_band IN ('low', 'moderate', 'high', 'very_high', 'critical'));

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS risk_points INTEGER;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS optimal_vitality_target INTEGER;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS risk_calculated_at TIMESTAMP WITH TIME ZONE;

-- Current vitality snapshot fields referenced by DataManager.saveVitalitySnapshot(...)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS vitality_score_current INTEGER;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS vitality_score_source TEXT;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS vitality_score_updated_at TIMESTAMP WITH TIME ZONE;

-- Champion settings referenced by DataManager.saveChampionSettings(...)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS champion_name TEXT;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS champion_email TEXT;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS champion_phone TEXT;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS champion_enabled BOOLEAN DEFAULT FALSE;

-- Notification preferences referenced by DataManager.saveAlertSettings(...)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS notify_inapp BOOLEAN DEFAULT TRUE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS notify_push BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS notify_email BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS champion_notify_email BOOLEAN DEFAULT TRUE;

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS champion_notify_sms BOOLEAN DEFAULT FALSE;


