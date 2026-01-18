-- =====================================================
-- Production Validation Queries
-- Run these to verify all systems are working correctly
-- =====================================================

-- 1) Verify progress score trigger is active
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as is_enabled,
  CASE tgenabled
    WHEN 'O' THEN 'Enabled'
    WHEN 'D' THEN 'Disabled'
    WHEN 'R' THEN 'Replica'
    WHEN 'A' THEN 'Always'
    ELSE 'Unknown'
  END as status
FROM pg_trigger 
WHERE tgname = 'set_vitality_progress_score_current';

-- Expected: 1 row with is_enabled = 'O' (Enabled)

-- 2) Verify vitality_progress_score function exists
SELECT 
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as arguments,
  pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'vitality_progress_score';

-- Expected: 1 row with function definition

-- 3) Check progress score coverage (users with scores but missing progress)
SELECT 
  COUNT(*) as total_users_with_scores,
  COUNT(vitality_progress_score_current) as users_with_progress,
  COUNT(vitality_score_current) - COUNT(vitality_progress_score_current) as missing_progress_count,
  ROUND(
    100.0 * COUNT(vitality_progress_score_current) / NULLIF(COUNT(vitality_score_current), 0),
    2
  ) as progress_coverage_percent
FROM user_profiles
WHERE vitality_score_current IS NOT NULL;

-- Expected: progress_coverage_percent should be close to 100%
-- If < 95%, investigate users with NULL date_of_birth or risk_band

-- 4) Find users with scores but missing progress (for investigation)
SELECT 
  user_id,
  vitality_score_current,
  vitality_progress_score_current,
  date_of_birth,
  risk_band,
  vitality_score_updated_at
FROM user_profiles
WHERE vitality_score_current IS NOT NULL
  AND vitality_progress_score_current IS NULL
ORDER BY vitality_score_updated_at DESC
LIMIT 20;

-- Expected: Should be empty or very few rows
-- If many rows, check if date_of_birth or risk_band are NULL

-- 5) Verify vitality_optimal_targets table has data
SELECT 
  COUNT(*) as total_targets,
  COUNT(DISTINCT age_group) as age_groups,
  COUNT(DISTINCT risk_band) as risk_bands
FROM vitality_optimal_targets;

-- Expected: Should have data for all age groups and risk bands

-- 6) Check family score freshness consistency
-- This query tests the RPC with a sample family
-- Replace 'YOUR_FAMILY_ID' with an actual family_id
/*
SELECT 
  family_vitality_score,
  members_with_data,
  members_total,
  last_updated_at,
  has_recent_data,
  family_progress_score
FROM get_family_vitality('YOUR_FAMILY_ID'::uuid);
*/

-- 7) Verify serial backfill behavior (check activity_events timestamps)
-- This helps verify that backfill is happening sequentially
SELECT 
  user_id,
  DATE(created_at) as event_date,
  COUNT(*) as events_per_day,
  MIN(created_at) as first_event,
  MAX(created_at) as last_event,
  EXTRACT(EPOCH FROM (MAX(created_at) - MIN(created_at))) as duration_seconds
FROM activity_events
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY user_id, DATE(created_at)
ORDER BY user_id, event_date DESC
LIMIT 50;

-- Expected: For recent backfills, events should be spread over time (not all at once)
-- Duration should be reasonable (not 0 seconds for 30 days of data)

-- 8) Check for stale scores (older than 7 days)
SELECT 
  COUNT(*) as stale_score_count,
  AVG(EXTRACT(EPOCH FROM (NOW() - vitality_score_updated_at)) / 86400) as avg_days_stale
FROM user_profiles
WHERE vitality_score_current IS NOT NULL
  AND vitality_score_updated_at < NOW() - INTERVAL '7 days';

-- Expected: Should be low (only users who haven't synced recently)
-- High count might indicate auto-refresh not working

-- 9) Verify trigger fires correctly (test update)
-- WARNING: This will update a test user's score
-- Only run on a test user_id
/*
BEGIN;
  UPDATE user_profiles
  SET vitality_score_current = vitality_score_current  -- No-op update to trigger
  WHERE user_id = 'TEST_USER_ID'::uuid
    AND vitality_score_current IS NOT NULL;
  
  SELECT 
    vitality_score_current,
    vitality_progress_score_current,
    vitality_progress_score_updated_at
  FROM user_profiles
  WHERE user_id = 'TEST_USER_ID'::uuid;
ROLLBACK;
*/

-- Expected: vitality_progress_score_current should be computed automatically
-- vitality_progress_score_updated_at should be updated

-- 10) Summary report
SELECT 
  'Progress Score Coverage' as metric,
  ROUND(
    100.0 * COUNT(vitality_progress_score_current) / NULLIF(COUNT(vitality_score_current), 0),
    2
  ) as value,
  CASE 
    WHEN ROUND(100.0 * COUNT(vitality_progress_score_current) / NULLIF(COUNT(vitality_score_current), 0), 2) >= 95 
    THEN '✅ Good'
    ELSE '⚠️ Needs attention'
  END as status
FROM user_profiles
WHERE vitality_score_current IS NOT NULL

UNION ALL

SELECT 
  'Stale Scores (>7 days)' as metric,
  COUNT(*)::numeric as value,
  CASE 
    WHEN COUNT(*) < 10 THEN '✅ Good'
    ELSE '⚠️ High count'
  END as status
FROM user_profiles
WHERE vitality_score_current IS NOT NULL
  AND vitality_score_updated_at < NOW() - INTERVAL '7 days'

UNION ALL

SELECT 
  'Users Missing DOB/Risk' as metric,
  COUNT(*)::numeric as value,
  CASE 
    WHEN COUNT(*) = 0 THEN '✅ Good'
    ELSE '⚠️ Needs onboarding'
  END as status
FROM user_profiles
WHERE vitality_score_current IS NOT NULL
  AND (date_of_birth IS NULL OR risk_band IS NULL);
