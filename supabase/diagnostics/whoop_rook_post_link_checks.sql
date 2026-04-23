-- WHOOP + ROOK post-link diagnostics (Supabase SQL editor)
-- Replace every '00000000-0000-0000-0000-000000000001' below with a real auth.users UUID.

-- 1) App-side record (onboarding writes connected_wearables)
SELECT id, user_id, wearable_type, is_connected, connected_at
FROM connected_wearables
WHERE user_id = '00000000-0000-0000-0000-000000000001'::uuid
  AND wearable_type = 'whoop';

-- 2) Raw webhook traffic (any source; filter payload if needed)
SELECT id, created_at, source,
       payload->>'data_structure' AS data_structure,
       LEFT(COALESCE(raw_body, payload::text), 200) AS payload_preview
FROM rook_webhook_events
ORDER BY created_at DESC
LIMIT 25;

-- 3) WHOOP-normalized daily rows (after successful parse/upsert)
SELECT metric_date, source, user_id, rook_user_id,
       steps, sleep_minutes, hrv_ms, resting_hr, score_raw, updated_at
FROM wearable_daily_metrics
WHERE user_id = '00000000-0000-0000-0000-000000000001'::uuid
  AND source = 'whoop'
ORDER BY metric_date DESC
LIMIT 30;

-- 4) Optional: recent WHOOP-ish events by text search in raw JSON
SELECT id, created_at
FROM rook_webhook_events
WHERE raw_body ILIKE '%whoop%' OR payload::text ILIKE '%whoop%'
ORDER BY created_at DESC
LIMIT 15;
