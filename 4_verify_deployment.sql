-- STEP 4: Verify everything worked
-- Run this to check the deployment

-- Check table exists
SELECT 
  'exercise_sessions table exists' as status,
  COUNT(*) as total_workouts
FROM exercise_sessions;

-- Top activity types
SELECT 
  activity_type_name,
  COUNT(*) as workout_count
FROM exercise_sessions
GROUP BY activity_type_name
ORDER BY workout_count DESC
LIMIT 10;

-- Per-user summary
SELECT 
  u.email,
  COUNT(*) as total_workouts,
  COUNT(DISTINCT es.activity_type_name) as activity_variety,
  MIN(es.metric_date) as first_workout,
  MAX(es.metric_date) as last_workout
FROM exercise_sessions es
JOIN auth.users u ON u.id = es.user_id
GROUP BY u.email, es.user_id
ORDER BY total_workouts DESC;

-- Recent workouts (last 7 days)
SELECT 
  u.email,
  es.metric_date,
  es.activity_type_name,
  ROUND(es.activity_duration_seconds / 60.0) as duration_minutes,
  es.hr_avg_bpm,
  es.calories_active_kcal
FROM exercise_sessions es
JOIN auth.users u ON u.id = es.user_id
WHERE es.metric_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY es.metric_date DESC, es.activity_start_time DESC
LIMIT 20;
