-- =============================================================================
-- Miya: AI third-party (OpenAI) consent — ONE FILE TO RUN IN SUPABASE
-- Guidelines 5.1.1(i) / 5.1.2(i)
--
-- PREREQUISITE: Table `privacy_settings` must already exist (see
-- migrations/20251203202306_create_miya_tables.sql in the repo if you
-- are bootstrapping a brand-new project).
--
-- WHERE TO RUN: Supabase Dashboard → SQL Editor → New query → paste → Run
--
-- SAFE TO RE-RUN: Mostly idempotent. The UPDATE only touches rows where
-- ai_third_party_sharing_enabled IS NULL (so users who already chose
-- settings_off / onboarding_decline are NOT reset to true).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Columns
-- -----------------------------------------------------------------------------
ALTER TABLE privacy_settings
  ADD COLUMN IF NOT EXISTS ai_third_party_sharing_enabled BOOLEAN;

ALTER TABLE privacy_settings
  ADD COLUMN IF NOT EXISTS ai_consent_at TIMESTAMPTZ;

ALTER TABLE privacy_settings
  ADD COLUMN IF NOT EXISTS ai_consent_source TEXT;

-- -----------------------------------------------------------------------------
-- 2) Check constraint on audit source (drop + re-add so re-runs work)
-- -----------------------------------------------------------------------------
ALTER TABLE privacy_settings
  DROP CONSTRAINT IF EXISTS privacy_settings_ai_consent_source_check;

ALTER TABLE privacy_settings
  ADD CONSTRAINT privacy_settings_ai_consent_source_check
  CHECK (
    ai_consent_source IS NULL
    OR ai_consent_source IN (
      'legacy_migration',
      'onboarding_agree',
      'onboarding_decline',
      'settings_on',
      'settings_off'
    )
  );

-- -----------------------------------------------------------------------------
-- 3) Legacy backfill: existing rows (flag still NULL) → opted in once
-- -----------------------------------------------------------------------------
UPDATE privacy_settings
SET
  ai_third_party_sharing_enabled = true,
  ai_consent_at = COALESCE(ai_consent_at, now()),
  ai_consent_source = COALESCE(ai_consent_source, 'legacy_migration')
WHERE ai_third_party_sharing_enabled IS NULL;

-- -----------------------------------------------------------------------------
-- 4) New rows default OFF; enforce NOT NULL
-- -----------------------------------------------------------------------------
ALTER TABLE privacy_settings
  ALTER COLUMN ai_third_party_sharing_enabled SET DEFAULT false;

ALTER TABLE privacy_settings
  ALTER COLUMN ai_third_party_sharing_enabled SET NOT NULL;

-- -----------------------------------------------------------------------------
-- 5) Documentation
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN privacy_settings.ai_third_party_sharing_enabled IS
  'When false, client and edge functions must not send user/family health context to OpenAI.';
COMMENT ON COLUMN privacy_settings.ai_consent_at IS
  'Last time ai_third_party_sharing_enabled was explicitly set (agree/decline/settings/migration).';
COMMENT ON COLUMN privacy_settings.ai_consent_source IS
  'Audit: how the current consent state was last written.';

-- =============================================================================
-- 6) OPTIONAL: verify (read-only — comment out if you do not want extra output)
-- =============================================================================
-- SELECT column_name, data_type, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'privacy_settings'
--   AND column_name IN (
--     'ai_third_party_sharing_enabled',
--     'ai_consent_at',
--     'ai_consent_source'
--   )
-- ORDER BY column_name;

-- SELECT
--   COUNT(*) AS total_rows,
--   COUNT(*) FILTER (WHERE ai_third_party_sharing_enabled = true) AS opted_in,
--   COUNT(*) FILTER (WHERE ai_third_party_sharing_enabled = false) AS opted_out,
--   COUNT(*) FILTER (WHERE ai_consent_source = 'legacy_migration') AS legacy_source
-- FROM privacy_settings;

-- =============================================================================
-- DONE
-- =============================================================================
