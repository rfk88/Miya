-- Backfill exercise_sessions from historical rook_webhook_events
-- This extracts activity_event webhooks that were received but not parsed before the fix

-- Step 1: Create a temporary view of activity events from webhook history
CREATE TEMP VIEW temp_activity_events AS
SELECT 
  id as webhook_event_id,
  created_at as webhook_received_at,
  payload
FROM rook_webhook_events
WHERE 
  (payload->>'data_structure' = 'activity_event' 
   OR payload->>'dataStructure' = 'activity_event')
  AND created_at >= NOW() - INTERVAL '90 days'  -- Only backfill last 90 days
ORDER BY created_at DESC;

-- Step 2: Extract and insert exercise sessions
-- This handles the nested JSON structure from Rook's activity_event webhooks
WITH parsed_events AS (
  SELECT 
    webhook_event_id,
    webhook_received_at,
    payload,
    
    -- Extract user identification
    COALESCE(
      payload->>'user_id',
      payload->>'userId',
      payload#>>'{physical_health,events,activity_event,0,metadata,user_id_string}'
    ) as rook_user_id,
    
    -- Extract activity event array (could be nested differently)
    COALESCE(
      payload#>'{physical_health,events,activity_event}',
      payload#>'{activity_event}'
    ) as activity_events_array
    
  FROM temp_activity_events
),
flattened_events AS (
  SELECT 
    pe.webhook_event_id,
    pe.webhook_received_at,
    pe.rook_user_id,
    jsonb_array_elements(pe.activity_events_array) as event_data
  FROM parsed_events pe
  WHERE pe.activity_events_array IS NOT NULL
    AND jsonb_typeof(pe.activity_events_array) = 'array'
),
extracted_sessions AS (
  SELECT
    fe.webhook_event_id,
    fe.webhook_received_at,
    fe.rook_user_id,
    
    -- Map rook_user_id to Miya user_id
    CASE 
      -- If rook_user_id is already a UUID, use it directly
      WHEN fe.rook_user_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' 
        THEN fe.rook_user_id::uuid
      -- Otherwise look up in mapping table
      ELSE (
        SELECT user_id 
        FROM rook_user_mapping 
        WHERE rook_user_id = fe.rook_user_id 
        LIMIT 1
      )
    END as user_id,
    
    -- Extract metadata
    event_data#>>'{metadata,sources_of_data_array,0}' as source_raw,
    (event_data#>>'{metadata,was_the_user_under_physical_activity_bool}')::boolean as was_under_physical_activity,
    
    -- Extract activity timing
    (event_data#>>'{activity,activity_start_datetime_string}')::timestamptz as activity_start_time,
    (event_data#>>'{activity,activity_end_datetime_string}')::timestamptz as activity_end_time,
    
    -- Extract activity details
    event_data#>>'{activity,activity_type_name_string}' as activity_type_name,
    (event_data#>>'{activity,activity_duration_seconds_int}')::integer as activity_duration_seconds,
    (event_data#>>'{activity,active_seconds_int}')::integer as active_seconds,
    (event_data#>>'{activity,rest_seconds_int}')::integer as rest_seconds,
    (event_data#>>'{activity,low_intensity_seconds_int}')::integer as low_intensity_seconds,
    (event_data#>>'{activity,moderate_intensity_seconds_int}')::integer as moderate_intensity_seconds,
    (event_data#>>'{activity,vigorous_intensity_seconds_int}')::integer as vigorous_intensity_seconds,
    (event_data#>>'{activity,inactivity_seconds_int}')::integer as inactivity_seconds,
    
    -- Extract calories
    (event_data#>>'{calories,calories_expenditure_kcal_float}')::decimal as calories_burned_kcal,
    (event_data#>>'{calories,calories_net_active_kcal_float}')::decimal as calories_active_kcal,
    
    -- Extract distance
    COALESCE(
      (event_data#>>'{distance,traveled_distance_meters_float}')::decimal,
      (event_data#>>'{distance,walked_distance_meters_float}')::decimal
    ) as distance_meters,
    (event_data#>>'{distance,steps_int}')::integer as steps,
    
    -- Extract heart rate
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
    
    -- Store raw event data for debugging
    event_data as raw_webhook_data
    
  FROM flattened_events fe
  WHERE event_data#>>'{activity,activity_type_name_string}' IS NOT NULL
    AND event_data#>>'{activity,activity_start_datetime_string}' IS NOT NULL
    AND event_data#>>'{activity,activity_end_datetime_string}' IS NOT NULL
)
-- Step 3: Insert into exercise_sessions table
INSERT INTO exercise_sessions (
  user_id,
  rook_user_id,
  metric_date,
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
  source_of_data,
  was_under_physical_activity,
  raw_webhook_data
)
SELECT 
  es.user_id,
  es.rook_user_id,
  DATE(es.activity_start_time) as metric_date,
  es.activity_start_time,
  es.activity_end_time,
  es.activity_duration_seconds,
  es.activity_type_name,
  es.active_seconds,
  es.rest_seconds,
  es.low_intensity_seconds,
  es.moderate_intensity_seconds,
  es.vigorous_intensity_seconds,
  es.inactivity_seconds,
  es.calories_burned_kcal,
  es.calories_active_kcal,
  es.distance_meters,
  es.steps,
  es.hr_avg_bpm,
  es.hr_max_bpm,
  es.hr_min_bpm,
  -- Normalize source name
  CASE 
    WHEN LOWER(es.source_raw) LIKE '%apple%' THEN 'apple_health'
    WHEN LOWER(es.source_raw) LIKE '%whoop%' THEN 'whoop'
    WHEN LOWER(es.source_raw) LIKE '%oura%' THEN 'oura'
    WHEN LOWER(es.source_raw) LIKE '%fitbit%' THEN 'fitbit'
    WHEN LOWER(es.source_raw) LIKE '%garmin%' THEN 'garmin'
    WHEN LOWER(es.source_raw) LIKE '%withings%' THEN 'withings'
    WHEN LOWER(es.source_raw) LIKE '%polar%' THEN 'polar'
    ELSE LOWER(REPLACE(es.source_raw, ' ', '_'))
  END as source_of_data,
  COALESCE(es.was_under_physical_activity, true),
  es.raw_webhook_data
FROM extracted_sessions es
WHERE es.user_id IS NOT NULL
  AND es.activity_start_time IS NOT NULL
  AND es.activity_end_time IS NOT NULL
  AND es.activity_type_name IS NOT NULL
ON CONFLICT (user_id, activity_start_time, activity_end_time) 
DO UPDATE SET
  -- Update fields if backfill has more complete data
  activity_duration_seconds = COALESCE(EXCLUDED.activity_duration_seconds, exercise_sessions.activity_duration_seconds),
  moderate_intensity_seconds = COALESCE(EXCLUDED.moderate_intensity_seconds, exercise_sessions.moderate_intensity_seconds),
  vigorous_intensity_seconds = COALESCE(EXCLUDED.vigorous_intensity_seconds, exercise_sessions.vigorous_intensity_seconds),
  calories_active_kcal = COALESCE(EXCLUDED.calories_active_kcal, exercise_sessions.calories_active_kcal),
  hr_avg_bpm = COALESCE(EXCLUDED.hr_avg_bpm, exercise_sessions.hr_avg_bpm),
  hr_max_bpm = COALESCE(EXCLUDED.hr_max_bpm, exercise_sessions.hr_max_bpm)
RETURNING *;

-- Step 4: Summary statistics
SELECT 
  'Backfill Complete' as status,
  COUNT(*) as total_sessions_inserted,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT activity_type_name) as unique_activity_types,
  MIN(metric_date) as earliest_session,
  MAX(metric_date) as latest_session,
  STRING_AGG(DISTINCT activity_type_name, ', ' ORDER BY activity_type_name) as activity_types_found
FROM exercise_sessions
WHERE created_at >= NOW() - INTERVAL '5 minutes';  -- Just the newly inserted rows

-- Step 5: Show per-user summary
SELECT 
  user_id,
  rook_user_id,
  COUNT(*) as session_count,
  MIN(metric_date) as first_workout,
  MAX(metric_date) as last_workout,
  COUNT(DISTINCT activity_type_name) as activity_variety,
  STRING_AGG(DISTINCT activity_type_name, ', ' ORDER BY activity_type_name) as activities
FROM exercise_sessions
WHERE created_at >= NOW() - INTERVAL '5 minutes'
GROUP BY user_id, rook_user_id
ORDER BY session_count DESC;

-- Step 6: Show sample of inserted sessions
SELECT 
  user_id,
  metric_date,
  activity_type_name,
  ROUND(activity_duration_seconds / 60.0, 1) as duration_minutes,
  ROUND(moderate_intensity_seconds / 60.0, 1) as moderate_min,
  ROUND(vigorous_intensity_seconds / 60.0, 1) as vigorous_min,
  calories_active_kcal,
  hr_avg_bpm,
  hr_max_bpm
FROM exercise_sessions
WHERE created_at >= NOW() - INTERVAL '5 minutes'
ORDER BY metric_date DESC, activity_start_time DESC
LIMIT 20;

-- Cleanup temp view
DROP VIEW IF EXISTS temp_activity_events;
