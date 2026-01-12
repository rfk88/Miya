-- =============================================================================
-- DEPLOY EXERCISE CONTEXT FIX - Simple Version
-- =============================================================================
-- Run this in Supabase SQL Editor
-- =============================================================================

-- Step 1: Create exercise_sessions table
CREATE TABLE IF NOT EXISTS exercise_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rook_user_id TEXT,
  metric_date DATE NOT NULL,
  
  activity_start_time TIMESTAMPTZ NOT NULL,
  activity_end_time TIMESTAMPTZ NOT NULL,
  activity_duration_seconds INT,
  activity_type_name TEXT NOT NULL,
  
  active_seconds INT,
  rest_seconds INT,
  low_intensity_seconds INT,
  moderate_intensity_seconds INT,
  vigorous_intensity_seconds INT,
  inactivity_seconds INT,
  
  calories_burned_kcal DECIMAL,
  calories_active_kcal DECIMAL,
  
  distance_meters DECIMAL,
  steps INT,
  
  hr_avg_bpm INT,
  hr_max_bpm INT,
  hr_min_bpm INT,
  
  source_of_data TEXT,
  was_under_physical_activity BOOLEAN DEFAULT true,
  raw_webhook_data JSONB,
  
  CONSTRAINT exercise_sessions_user_date_time_unique 
    UNIQUE(user_id, activity_start_time, activity_end_time)
);

CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user_date ON exercise_sessions(user_id, metric_date);
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_date ON exercise_sessions(metric_date);
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_activity_type ON exercise_sessions(activity_type_name);

ALTER TABLE exercise_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own exercise sessions" ON exercise_sessions;
CREATE POLICY "Users can view their own exercise sessions"
  ON exercise_sessions FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own exercise sessions" ON exercise_sessions;
CREATE POLICY "Users can insert their own exercise sessions"
  ON exercise_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all exercise sessions" ON exercise_sessions;
CREATE POLICY "Service role can manage all exercise sessions"
  ON exercise_sessions FOR ALL
  USING (auth.role() = 'service_role');

-- Step 2: Backfill historical workout data
WITH parsed_events AS (
  SELECT 
    payload,
    COALESCE(
      payload->>'user_id',
      payload->>'userId',
      payload#>>'{physical_health,events,activity_event,0,metadata,user_id_string}'
    ) as rook_user_id,
    COALESCE(
      payload#>'{physical_health,events,activity_event}',
      payload#>'{activity_event}'
    ) as activity_events_array
  FROM rook_webhook_events
  WHERE (payload->>'data_structure' = 'activity_event' OR payload->>'dataStructure' = 'activity_event')
    AND created_at >= NOW() - INTERVAL '90 days'
),
flattened_events AS (
  SELECT 
    rook_user_id,
    jsonb_array_elements(activity_events_array) as event_data
  FROM parsed_events
  WHERE activity_events_array IS NOT NULL
    AND jsonb_typeof(activity_events_array) = 'array'
),
extracted_sessions AS (
  SELECT
    rook_user_id,
    CASE 
      WHEN rook_user_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' 
        THEN rook_user_id::uuid
      ELSE (SELECT user_id FROM rook_user_mapping WHERE rook_user_mapping.rook_user_id = flattened_events.rook_user_id LIMIT 1)
    END as user_id,
    event_data#>>'{metadata,sources_of_data_array,0}' as source_raw,
    (event_data#>>'{metadata,was_the_user_under_physical_activity_bool}')::boolean as was_under_physical_activity,
    (event_data#>>'{activity,activity_start_datetime_string}')::timestamptz as activity_start_time,
    (event_data#>>'{activity,activity_end_datetime_string}')::timestamptz as activity_end_time,
    event_data#>>'{activity,activity_type_name_string}' as activity_type_name,
    (event_data#>>'{activity,activity_duration_seconds_int}')::integer as activity_duration_seconds,
    (event_data#>>'{activity,active_seconds_int}')::integer as active_seconds,
    (event_data#>>'{activity,rest_seconds_int}')::integer as rest_seconds,
    (event_data#>>'{activity,low_intensity_seconds_int}')::integer as low_intensity_seconds,
    (event_data#>>'{activity,moderate_intensity_seconds_int}')::integer as moderate_intensity_seconds,
    (event_data#>>'{activity,vigorous_intensity_seconds_int}')::integer as vigorous_intensity_seconds,
    (event_data#>>'{activity,inactivity_seconds_int}')::integer as inactivity_seconds,
    (event_data#>>'{calories,calories_expenditure_kcal_float}')::decimal as calories_burned_kcal,
    (event_data#>>'{calories,calories_net_active_kcal_float}')::decimal as calories_active_kcal,
    COALESCE(
      (event_data#>>'{distance,traveled_distance_meters_float}')::decimal,
      (event_data#>>'{distance,walked_distance_meters_float}')::decimal
    ) as distance_meters,
    (event_data#>>'{distance,steps_int}')::integer as steps,
    COALESCE(
      (event_data#>>'{heart_rate,hr_avg_bpm_int}')::integer,
      (event_data#>>'{hr_avg_bpm_int}')::integer
    ) as hr_avg_bpm,
    COALESCE(
      (event_data#>>'{heart_rate,hr_max_bpm_int}')::integer,
      (event_data#>>'{hr_max_bpm_int}')::integer
    ) as hr_max_bpm,
    COALESCE(
      (event_data#>>'{heart_rate,hr_min_bpm_int}')::integer,
      (event_data#>>'{hr_min_bpm_int}')::integer
    ) as hr_min_bpm,
    event_data as raw_webhook_data
  FROM flattened_events
  WHERE event_data#>>'{activity,activity_type_name_string}' IS NOT NULL
    AND event_data#>>'{activity,activity_start_datetime_string}' IS NOT NULL
    AND event_data#>>'{activity,activity_end_datetime_string}' IS NOT NULL
)
INSERT INTO exercise_sessions (
  user_id, rook_user_id, metric_date,
  activity_start_time, activity_end_time, activity_duration_seconds,
  activity_type_name, active_seconds, rest_seconds,
  low_intensity_seconds, moderate_intensity_seconds, vigorous_intensity_seconds,
  inactivity_seconds, calories_burned_kcal, calories_active_kcal,
  distance_meters, steps, hr_avg_bpm, hr_max_bpm, hr_min_bpm,
  source_of_data, was_under_physical_activity, raw_webhook_data
)
SELECT 
  user_id,
  rook_user_id,
  DATE(activity_start_time) as metric_date,
  activity_start_time,
  activity_end_time,
  activity_duration_seconds,
  activity_type_name,
  active_seconds,
  rest_seconds,
  low_intensity_seconds,
  moderate_intensity_seconds,
  vigorous_intensity_seconds,
  inactivity_seconds,
  calories_burned_kcal,
  calories_active_kcal,
  distance_meters,
  steps,
  hr_avg_bpm,
  hr_max_bpm,
  hr_min_bpm,
  CASE 
    WHEN LOWER(source_raw) LIKE '%apple%' THEN 'apple_health'
    WHEN LOWER(source_raw) LIKE '%whoop%' THEN 'whoop'
    WHEN LOWER(source_raw) LIKE '%oura%' THEN 'oura'
    WHEN LOWER(source_raw) LIKE '%fitbit%' THEN 'fitbit'
    WHEN LOWER(source_raw) LIKE '%garmin%' THEN 'garmin'
    WHEN LOWER(source_raw) LIKE '%withings%' THEN 'withings'
    WHEN LOWER(source_raw) LIKE '%polar%' THEN 'polar'
    ELSE LOWER(REPLACE(source_raw, ' ', '_'))
  END,
  COALESCE(was_under_physical_activity, true),
  raw_webhook_data
FROM extracted_sessions
WHERE user_id IS NOT NULL
  AND activity_start_time IS NOT NULL
  AND activity_end_time IS NOT NULL
  AND activity_type_name IS NOT NULL
ON CONFLICT (user_id, activity_start_time, activity_end_time) DO NOTHING;

-- Step 3: Clear false recovery alerts on workout days
WITH workout_days AS (
  SELECT DISTINCT user_id, metric_date::text as date_str
  FROM exercise_sessions
  WHERE metric_date >= CURRENT_DATE - INTERVAL '30 days'
),
false_alerts AS (
  SELECT ps.id
  FROM pattern_alert_state ps
  INNER JOIN workout_days wd 
    ON ps.user_id = wd.user_id 
    AND ps.active_since = wd.date_str
  WHERE ps.metric_type IN ('hrv_ms', 'resting_hr')
    AND ps.episode_status = 'active'
)
UPDATE pattern_alert_state
SET 
  episode_status = 'resolved',
  last_evaluated_date = CURRENT_DATE::text,
  computed_at = NOW()
FROM false_alerts fa
WHERE pattern_alert_state.id = fa.id;

-- Step 4: Show summary
SELECT 
  COUNT(*) as total_sessions,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT activity_type_name) as activity_types,
  MIN(metric_date) as earliest_workout,
  MAX(metric_date) as latest_workout
FROM exercise_sessions;

SELECT 
  activity_type_name,
  COUNT(*) as count
FROM exercise_sessions
GROUP BY activity_type_name
ORDER BY count DESC
LIMIT 10;

SELECT 
  u.email,
  COUNT(*) as workout_count,
  COUNT(DISTINCT es.activity_type_name) as activity_variety
FROM exercise_sessions es
JOIN auth.users u ON u.id = es.user_id
GROUP BY u.email
ORDER BY workout_count DESC;
