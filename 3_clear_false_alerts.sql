-- STEP 3: Clear false recovery alerts on workout days
-- Run this AFTER backfilling data

-- Resolve any active recovery alerts that occurred on days with workouts
UPDATE pattern_alert_state ps
SET 
  episode_status = 'resolved',
  last_evaluated_date = CURRENT_DATE::text,
  computed_at = NOW()
FROM (
  SELECT DISTINCT user_id, metric_date
  FROM exercise_sessions
  WHERE metric_date >= CURRENT_DATE - INTERVAL '30 days'
) workout_days
WHERE ps.user_id = workout_days.user_id
  AND ps.active_since::date = workout_days.metric_date
  AND ps.metric_type IN ('hrv_ms', 'resting_hr')
  AND ps.episode_status = 'active';

-- Show what was cleared
SELECT 
  COUNT(*) as alerts_resolved,
  'False recovery alerts on workout days cleared' as message
FROM pattern_alert_state
WHERE episode_status = 'resolved'
  AND computed_at >= NOW() - INTERVAL '1 minute';
