-- =====================================================================
-- Backfill wearable_daily_metrics.user_id and exercise_sessions.user_id
-- using rook_user_mapping for ALL users (one-time cleanup).
--
-- This script is safe to run multiple times; it only fills in NULLs.
-- It DOES NOT change any existing non-null user_id values.
--
-- PRECONDITIONS
-- - rook_user_mapping has trusted mappings (user_id, rook_user_id)
-- - rook_user_mapping.rook_user_id has a unique index (already created)
--
-- EFFECT
-- - Any wearable_daily_metrics row with:
--     user_id IS NULL
--     AND rook_user_id matches a mapping
--   will be updated to set user_id from rook_user_mapping.user_id.
--
-- - Same for exercise_sessions.
--
-- After running this:
-- - MIYA_SCORE_SKIP_NO_USER_ID should fire less often.
-- - Historical data becomes visible to the scoring engine / app.
-- =====================================================================

-- 1) Backfill wearable_daily_metrics.user_id from rook_user_mapping
UPDATE public.wearable_daily_metrics AS wdm
SET user_id = rum.user_id
FROM public.rook_user_mapping AS rum
WHERE
  wdm.user_id IS NULL
  AND wdm.rook_user_id IS NOT NULL
  AND rum.rook_user_id = wdm.rook_user_id;

-- Optional sanity check
-- SELECT
--   count(*) AS remaining_orphans
-- FROM public.wearable_daily_metrics
-- WHERE user_id IS NULL AND rook_user_id IS NOT NULL;

-- 2) Backfill exercise_sessions.user_id from rook_user_mapping
--    (only if this table exists in your schema)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'exercise_sessions'
  ) THEN
    UPDATE public.exercise_sessions AS es
    SET user_id = rum.user_id
    FROM public.rook_user_mapping AS rum
    WHERE
      es.user_id IS NULL
      AND es.rook_user_id IS NOT NULL
      AND rum.rook_user_id = es.rook_user_id;
  END IF;
END $$;

-- Optional sanity check
-- SELECT
--   count(*) AS remaining_orphans
-- FROM public.exercise_sessions
-- WHERE user_id IS NULL AND rook_user_id IS NOT NULL;

