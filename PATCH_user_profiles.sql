-- =====================================================
-- PATCH_user_profiles.sql
-- Idempotent patch to align public.user_profiles with what the iOS app writes in DataManager.saveUserProfile(...)
-- =====================================================

-- Basic profile fields
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS last_name TEXT;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS gender TEXT;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS date_of_birth DATE;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS ethnicity TEXT;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS smoking_status TEXT;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS height_cm DOUBLE PRECISION;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS weight_kg DOUBLE PRECISION;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS nutrition_quality INTEGER;

-- WHO risk fields (statuses + flags)
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS blood_pressure_status TEXT
CHECK (blood_pressure_status IN ('normal', 'elevated_untreated', 'elevated_treated', 'unknown'));

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS diabetes_status TEXT
CHECK (diabetes_status IN ('none', 'pre_diabetic', 'type_1', 'type_2', 'unknown'));

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS has_prior_heart_attack BOOLEAN;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS has_prior_stroke BOOLEAN;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS family_heart_disease_early BOOLEAN;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS family_stroke_early BOOLEAN;

ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS family_type2_diabetes BOOLEAN;

-- Onboarding progress fields
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS onboarding_step INTEGER;


