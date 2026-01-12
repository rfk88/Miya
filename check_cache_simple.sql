-- Check if ANY row exists for this alert
SELECT 
  count(*) as total_rows,
  max(created_at) as latest_created_at
FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80';

-- Show all rows for this alert
SELECT 
  id,
  created_at,
  evaluated_end_date,
  prompt_version,
  headline,
  summary IS NOT NULL as has_summary
FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
ORDER BY created_at DESC;
