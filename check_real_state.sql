-- REAL STATE CHECK for alert 57def4d0-0b2f-42b7-8e06-450303f49a80
-- Run this in Supabase SQL Editor to see exactly what's in the database

-- 1. Check the alert itself
SELECT 
  '=== ALERT STATE ===' as section,
  id,
  user_id,
  metric_type,
  pattern_type,
  active_since,
  last_evaluated_date,
  current_level,
  episode_status
FROM public.pattern_alert_state
WHERE id = '57def4d0-0b2f-42b7-8e06-450303f49a80';

-- 2. Check ALL cached insights for this alert (including invalid ones)
SELECT 
  '=== CACHED INSIGHTS ===' as section,
  id,
  created_at,
  evaluated_end_date,
  prompt_version,
  model,
  headline,
  length(summary) as summary_length,
  summary IS NOT NULL as has_summary,
  clinical_interpretation IS NOT NULL as has_clinical_interpretation,
  data_connections IS NOT NULL as has_data_connections,
  possible_causes IS NOT NULL as has_possible_causes,
  action_steps IS NOT NULL as has_action_steps,
  message_suggestions IS NOT NULL as has_message_suggestions
FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
ORDER BY created_at DESC;

-- 3. If there are insights, show the actual summary content
SELECT 
  '=== SUMMARY CONTENT ===' as section,
  id,
  created_at,
  substring(summary, 1, 200) as summary_preview,
  substring(clinical_interpretation, 1, 200) as clinical_preview
FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
ORDER BY created_at DESC
LIMIT 1;

-- 4. Check if there are any chat threads for this alert
SELECT 
  '=== CHAT THREADS ===' as section,
  t.id as thread_id,
  t.created_by,
  t.created_at,
  count(m.id) as message_count
FROM public.pattern_alert_ai_threads t
LEFT JOIN public.pattern_alert_ai_messages m ON m.thread_id = t.id
WHERE t.alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
GROUP BY t.id, t.created_by, t.created_at;

-- 5. Show the unique constraint that might be blocking
SELECT 
  '=== UNIQUE CONSTRAINT ===' as section,
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'pattern_alert_ai_insights'
  AND indexname = 'idx_pattern_alert_ai_insights_unique';
