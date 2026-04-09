-- Apple 5.1.1(i) / 5.1.2(i): third-party AI (OpenAI) data sharing consent.
-- Idempotent-friendly: only backfills rows where the flag is still NULL (pre-feature rows).

ALTER TABLE privacy_settings
  ADD COLUMN IF NOT EXISTS ai_third_party_sharing_enabled BOOLEAN;

ALTER TABLE privacy_settings
  ADD COLUMN IF NOT EXISTS ai_consent_at TIMESTAMPTZ;

ALTER TABLE privacy_settings
  ADD COLUMN IF NOT EXISTS ai_consent_source TEXT;

-- Allow only known audit values (no PII).
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

-- Legacy backfill: any row that predates this column (NULL) is opted in once.
UPDATE privacy_settings
SET
  ai_third_party_sharing_enabled = true,
  ai_consent_at = COALESCE(ai_consent_at, now()),
  ai_consent_source = COALESCE(ai_consent_source, 'legacy_migration')
WHERE ai_third_party_sharing_enabled IS NULL;

ALTER TABLE privacy_settings
  ALTER COLUMN ai_third_party_sharing_enabled SET DEFAULT false;

ALTER TABLE privacy_settings
  ALTER COLUMN ai_third_party_sharing_enabled SET NOT NULL;

COMMENT ON COLUMN privacy_settings.ai_third_party_sharing_enabled IS 'When false, client and edge functions must not send user/family health context to OpenAI.';
COMMENT ON COLUMN privacy_settings.ai_consent_at IS 'Last time ai_third_party_sharing_enabled was explicitly set (agree/decline/settings/migration).';
COMMENT ON COLUMN privacy_settings.ai_consent_source IS 'Audit: how the current consent state was last written.';
