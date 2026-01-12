-- Diagnose why chat is stuck in 409 loop for alert 57def4d0-0b2f-42b7-8e06-450303f49a80

-- 1. Check if alert exists
SELECT 
  id,
  user_id,
  metric_type,
  pattern_type,
  current_level,
  active_since,
  last_evaluated_date
FROM public.pattern_alert_state
WHERE id = '57def4d0-0b2f-42b7-8e06-450303f49a80';

-- 2. Check if any cached insight exists for this alert
SELECT 
  id,
  created_at,
  alert_state_id,
  evaluated_end_date,
  prompt_version,
  model,
  headline,
  summary IS NOT NULL as has_summary,
  clinical_interpretation IS NOT NULL as has_clinical,
  data_connections IS NOT NULL as has_data_connections,
  possible_causes IS NOT NULL as has_possible_causes,
  action_steps IS NOT NULL as has_action_steps
FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
ORDER BY created_at DESC;

-- 3. If stuck/invalid, clear it
DELETE FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80';

-- 4. Check notification_queue for this alert
SELECT 
  id,
  created_at,
  notification_type,
  payload->>'alert_state_id' as alert_id,
  status,
  delivered_at
FROM public.notification_queue
WHERE payload->>'alert_state_id' = '57def4d0-0b2f-42b7-8e06-450303f49a80'
ORDER BY created_at DESC
LIMIT 5;
