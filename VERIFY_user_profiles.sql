-- =====================================================
-- VERIFY_user_profiles.sql
-- Verifies that public.user_profiles contains the columns written by DataManager.saveUserProfile(...)
-- =====================================================

-- 1) Confirm columns exist
SELECT
  c.column_name,
  c.data_type,
  c.is_nullable
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name = 'user_profiles'
  AND c.column_name IN (
    'last_name',
    'gender',
    'date_of_birth',
    'ethnicity',
    'smoking_status',
    'height_cm',
    'weight_kg',
    'nutrition_quality',
    'blood_pressure_status',
    'diabetes_status',
    'has_prior_heart_attack',
    'has_prior_stroke',
    'family_heart_disease_early',
    'family_stroke_early',
    'family_type2_diabetes',
    'onboarding_step'
  )
ORDER BY c.column_name;

-- 2) Sample rows
SELECT
  user_id,
  last_name,
  gender,
  date_of_birth,
  ethnicity,
  smoking_status,
  height_cm,
  weight_kg,
  nutrition_quality,
  blood_pressure_status,
  diabetes_status,
  has_prior_heart_attack,
  has_prior_stroke,
  family_heart_disease_early,
  family_stroke_early,
  family_type2_diabetes,
  onboarding_step
FROM public.user_profiles
ORDER BY user_id
LIMIT 5;


