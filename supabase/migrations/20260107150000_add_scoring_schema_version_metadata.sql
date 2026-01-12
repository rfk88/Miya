-- =====================================================
-- Add schema version + computed timestamp metadata for server-side scoring
-- Safe/idempotent.
-- =====================================================

ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS schema_version text;

ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS computed_at timestamptz;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS vitality_schema_version text;


