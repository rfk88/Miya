-- ===================================================================
-- ROOK USER ID BACKFILL AND MAPPING FIX
-- ===================================================================
-- This script fixes the issue where Rook webhook data is not being
-- tied to Miya auth UUIDs, preventing vitality scores from computing.
--
-- PROBLEM:
-- - Rook webhooks arrive with user_id = Rook's internal ID (not Miya UUID)
-- - client_user_id field is NULL
-- - wearable_daily_metrics stores data under wrong rook_user_id
-- - App can't find data → no vitality score
--
-- SOLUTION:
-- 1. Create mapping from Rook internal ID → Miya auth UUID
-- 2. Update existing wearable_daily_metrics rows
-- 3. Future webhooks will use this mapping automatically
-- ===================================================================

-- Step 1: Find all webhook events with non-UUID user_id
-- This identifies Rook's internal user IDs that need mapping
SELECT DISTINCT
  payload->>'user_id' as rook_internal_id,
  payload->>'client_user_id' as client_user_id,
  payload->>'client_user_id_string' as client_user_id_string,
  count(*) as event_count
FROM rook_webhook_events
WHERE payload->>'user_id' IS NOT NULL
  AND payload->>'user_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
GROUP BY 1, 2, 3
ORDER BY event_count DESC;

-- Step 2: For user 001@1.com specifically
-- Get the Miya auth UUID
SELECT id as miya_user_id, email
FROM auth.users
WHERE email = '001@1.com';

-- MANUAL STEP: Copy the UUID from above and use it in the commands below
-- Replace <MIYA_USER_UUID> with the actual UUID

-- Step 3: Insert mapping for this user
-- This tells the webhook handler to map Rook ID → Miya UUID
INSERT INTO rook_user_mapping (user_id, rook_user_id, mapping_source)
VALUES (
  'e65b1c02-c383-4f00-9d8d-837265c4c098',  -- Miya auth UUID for 001@1.com
  'F86F855C-A272-4C01-828B-C01DC841D06F',  -- Rook internal ID from webhook
  'manual_backfill'
)
ON CONFLICT (rook_user_id) DO UPDATE
  SET user_id = EXCLUDED.user_id,
      mapping_source = EXCLUDED.mapping_source,
      last_verified_at = NOW();

-- Step 4: Update existing wearable_daily_metrics rows
-- This fixes visibility so the app can see existing data
UPDATE wearable_daily_metrics
SET user_id = 'e65b1c02-c383-4f00-9d8d-837265c4c098',
    rook_user_id = 'e65b1c02-c383-4f00-9d8d-837265c4c098'
WHERE rook_user_id = 'F86F855C-A272-4C01-828B-C01DC841D06F';

-- Step 5: Verify the fix
-- Should now return rows for this user
SELECT 
  metric_date,
  source,
  steps,
  sleep_minutes,
  hrv_ms,
  resting_hr,
  user_id,
  rook_user_id
FROM wearable_daily_metrics
WHERE user_id = 'e65b1c02-c383-4f00-9d8d-837265c4c098'
  OR rook_user_id = 'e65b1c02-c383-4f00-9d8d-837265c4c098'
ORDER BY metric_date DESC
LIMIT 20;

-- Step 6: Check if we can now compute vitality
-- After running this, trigger recompute from the app or run:
-- curl -X POST "https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/rook_daily_recompute" \
--   -H "Authorization: Bearer <SUPABASE_ANON_KEY>" \
--   -H "apikey: <SUPABASE_ANON_KEY>" \
--   -H "x-miya-admin-secret: <MIYA_ADMIN_SECRET>" \
--   -H "Content-Type: application/json" \
--   -d '{"daysBack":7,"maxUsers":200}'

-- ===================================================================
-- GENERAL BACKFILL (for all users with this issue)
-- ===================================================================
-- This assumes you can identify which Rook ID belongs to which user
-- by some other means (e.g., timing, manual verification, etc.)
--
-- IF you need to backfill multiple users:
--
-- 1. Create a temporary mapping table:
-- CREATE TEMP TABLE temp_rook_mappings (
--   miya_uuid uuid,
--   rook_id text,
--   user_email text
-- );
--
-- 2. Insert known mappings:
-- INSERT INTO temp_rook_mappings VALUES
--   ('e65b1c02-c383-4f00-9d8d-837265c4c098', 'F86F855C-A272-4C01-828B-C01DC841D06F', '001@1.com');
--
-- 3. Bulk insert into rook_user_mapping:
-- INSERT INTO rook_user_mapping (user_id, rook_user_id, mapping_source)
-- SELECT miya_uuid, rook_id, 'bulk_backfill'
-- FROM temp_rook_mappings
-- ON CONFLICT (rook_user_id) DO UPDATE
--   SET user_id = EXCLUDED.user_id,
--       last_verified_at = NOW();
--
-- 4. Bulk update wearable_daily_metrics:
-- UPDATE wearable_daily_metrics wdm
-- SET user_id = tm.miya_uuid,
--     rook_user_id = tm.miya_uuid
-- FROM temp_rook_mappings tm
-- WHERE wdm.rook_user_id = tm.rook_id;
-- ===================================================================
