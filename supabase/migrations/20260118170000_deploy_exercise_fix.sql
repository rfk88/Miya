-- =============================================================================
-- DEPLOY EXERCISE CONTEXT FIX - Complete Backend Deployment via SQL
-- =============================================================================
-- Purpose: Deploy the entire exercise context fix without waiting for iOS update
-- This script:
--   1. Creates exercise_sessions table
--   2. Backfills historical workout data from webhooks
--   3. Clears any false recovery alerts on workout days
--   4. Provides verification queries
-- 
-- Run this in Supabase SQL Editor or via:
--   supabase db execute --file deploy_exercise_fix_now.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- STEP 1: Create exercise_sessions table
-- =============================================================================

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'exercise_sessions') THEN
        CREATE TABLE exercise_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          created_at TIMESTAMPTZ DEFAULT now(),
          
          -- User identification
          user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
          rook_user_id TEXT,
          
          -- Date context (for joining with daily metrics)
          metric_date DATE NOT NULL,
          
          -- Exercise timing
          activity_start_time TIMESTAMPTZ NOT NULL,
          activity_end_time TIMESTAMPTZ NOT NULL,
          activity_duration_seconds INT,
          
          -- Exercise type (e.g., "Walking", "Running", "Functional Strength Training", "Cycling")
          activity_type_name TEXT NOT NULL,
          
          -- Intensity breakdown (all in seconds)
          active_seconds INT,
          rest_seconds INT,
          low_intensity_seconds INT,
          moderate_intensity_seconds INT,
          vigorous_intensity_seconds INT,
          inactivity_seconds INT,
          
          -- Calorie data
          calories_burned_kcal DECIMAL,
          calories_active_kcal DECIMAL,
          
          -- Distance
          distance_meters DECIMAL,
          steps INT,
          
          -- Heart rate during exercise (optional)
          hr_avg_bpm INT,
          hr_max_bpm INT,
          hr_min_bpm INT,
          
          -- Source tracking
          source_of_data TEXT,
          was_under_physical_activity BOOLEAN DEFAULT true,
          
          -- Raw webhook data for debugging
          raw_webhook_data JSONB,
          
          CONSTRAINT exercise_sessions_user_date_time_unique 
            UNIQUE(user_id, activity_start_time, activity_end_time)
        );

        -- Indexes
        CREATE INDEX idx_exercise_sessions_user_date ON exercise_sessions(user_id, metric_date);
        CREATE INDEX idx_exercise_sessions_date ON exercise_sessions(metric_date);
        CREATE INDEX idx_exercise_sessions_activity_type ON exercise_sessions(activity_type_name);

        -- RLS policies
        ALTER TABLE exercise_sessions ENABLE ROW LEVEL SECURITY;

        CREATE POLICY "Users can view their own exercise sessions"
          ON exercise_sessions FOR SELECT
          USING (auth.uid() = user_id);

        CREATE POLICY "Users can insert their own exercise sessions"
          ON exercise_sessions FOR INSERT
          WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Service role can manage all exercise sessions"
          ON exercise_sessions FOR ALL
          USING (auth.role() = 'service_role');

        RAISE NOTICE '✅ Created exercise_sessions table';
    ELSE
        RAISE NOTICE '✅ exercise_sessions table already exists';
    END IF;
END $$;

-- =============================================================================
-- STEP 2: Backfill historical workout data from webhooks (last 90 days)
-- =============================================================================

RAISE NOTICE '🔄 Starting backfill of historical workout data...';

-- Create temporary view of activity events
CREATE TEMP VIEW temp_activity_events AS
SELECT 
  id as webhook_event_id,
  created_at as webhook_received_at,
  payload
FROM rook_webhook_events
WHERE 
  (payload->>'data_structure' = 'activity_event' 
   OR payload->>'dataStructure' = 'activity_event')
  AND created_at >= NOW() - INTERVAL '90 days'
ORDER BY created_at DESC;

-- Extract and insert exercise sessions
WITH parsed_events AS (
  SELECT 
    webhook_event_id,
    webhook_received_at,
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
    fe.rook_user_id,
    CASE 
      WHEN fe.rook_user_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' 
        THEN fe.rook_user_id::uuid
      ELSE (SELECT user_id FROM rook_user_mapping WHERE rook_user_id = fe.rook_user_id LIMIT 1)
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
  FROM flattened_events fe
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
  CASE 
    WHEN LOWER(es.source_raw) LIKE '%apple%' THEN 'apple_health'
    WHEN LOWER(es.source_raw) LIKE '%whoop%' THEN 'whoop'
    WHEN LOWER(es.source_raw) LIKE '%oura%' THEN 'oura'
    WHEN LOWER(es.source_raw) LIKE '%fitbit%' THEN 'fitbit'
    WHEN LOWER(es.source_raw) LIKE '%garmin%' THEN 'garmin'
    WHEN LOWER(es.source_raw) LIKE '%withings%' THEN 'withings'
    WHEN LOWER(es.source_raw) LIKE '%polar%' THEN 'polar'
    ELSE LOWER(REPLACE(es.source_raw, ' ', '_'))
  END,
  COALESCE(es.was_under_physical_activity, true),
  es.raw_webhook_data
FROM extracted_sessions es
WHERE es.user_id IS NOT NULL
  AND es.activity_start_time IS NOT NULL
  AND es.activity_end_time IS NOT NULL
  AND es.activity_type_name IS NOT NULL
ON CONFLICT (user_id, activity_start_time, activity_end_time) 
DO UPDATE SET
  activity_duration_seconds = COALESCE(EXCLUDED.activity_duration_seconds, exercise_sessions.activity_duration_seconds),
  moderate_intensity_seconds = COALESCE(EXCLUDED.moderate_intensity_seconds, exercise_sessions.moderate_intensity_seconds),
  vigorous_intensity_seconds = COALESCE(EXCLUDED.vigorous_intensity_seconds, exercise_sessions.vigorous_intensity_seconds),
  calories_active_kcal = COALESCE(EXCLUDED.calories_active_kcal, exercise_sessions.calories_active_kcal),
  hr_avg_bpm = COALESCE(EXCLUDED.hr_avg_bpm, exercise_sessions.hr_avg_bpm),
  hr_max_bpm = COALESCE(EXCLUDED.hr_max_bpm, exercise_sessions.hr_max_bpm);

DROP VIEW temp_activity_events;

RAISE NOTICE '✅ Backfill completed';

-- =============================================================================
-- STEP 3: Clear false recovery alerts on workout days
-- =============================================================================

RAISE NOTICE '🔄 Clearing false recovery alerts on workout days...';

-- Resolve any active recovery alerts that occurred on days with workouts
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

RAISE NOTICE '✅ False recovery alerts cleared';

COMMIT;

-- =============================================================================
-- VERIFICATION QUERIES
-- =============================================================================

DO $$
DECLARE
  total_sessions INT;
  unique_users INT;
  unique_activities INT;
  earliest_date DATE;
  latest_date DATE;
  alerts_cleared INT;
  activity_summary TEXT;
  user_summary TEXT;
  recent_workouts TEXT;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '=============================================================================';
  RAISE NOTICE 'DEPLOYMENT COMPLETE - Verification Results:';
  RAISE NOTICE '=============================================================================';

  -- Summary statistics
  SELECT 
    COUNT(*),
    COUNT(DISTINCT user_id),
    COUNT(DISTINCT activity_type_name),
    MIN(metric_date),
    MAX(metric_date)
  INTO total_sessions, unique_users, unique_activities, earliest_date, latest_date
  FROM exercise_sessions;
  
  SELECT COUNT(*)
  INTO alerts_cleared
  FROM pattern_alert_state
  WHERE episode_status = 'resolved'
    AND computed_at >= NOW() - INTERVAL '5 minutes';
  
  RAISE NOTICE '';
  RAISE NOTICE '📊 EXERCISE SESSIONS BACKFILLED:';
  RAISE NOTICE '   Total Sessions: %', total_sessions;
  RAISE NOTICE '   Unique Users: %', unique_users;
  RAISE NOTICE '   Activity Types: %', unique_activities;
  RAISE NOTICE '   Date Range: % to %', earliest_date, latest_date;
  RAISE NOTICE '';
  RAISE NOTICE '🔧 ALERTS CLEARED:';
  RAISE NOTICE '   False Recovery Alerts Resolved: %', alerts_cleared;
  RAISE NOTICE '';
  
  -- Top activity types
  RAISE NOTICE '🏃 TOP ACTIVITY TYPES:';
  FOR activity_summary IN 
    SELECT '   ' || activity_type_name || ': ' || COUNT(*) || ' sessions'
    FROM exercise_sessions
    GROUP BY activity_type_name
    ORDER BY COUNT(*) DESC
    LIMIT 10
  LOOP
    RAISE NOTICE '%', activity_summary;
  END LOOP;
  
  -- Per-user summary
  RAISE NOTICE '';
  RAISE NOTICE '👥 PER-USER SUMMARY:';
  FOR user_summary IN
    SELECT '   User ' || SUBSTRING(u.email FROM 1 FOR 20) || ': ' || 
           COUNT(*) || ' workouts, ' ||
           COUNT(DISTINCT es.activity_type_name) || ' activity types'
    FROM exercise_sessions es
    JOIN auth.users u ON u.id = es.user_id
    GROUP BY u.email, es.user_id
    ORDER BY COUNT(*) DESC
  LOOP
    RAISE NOTICE '%', user_summary;
  END LOOP;
  
  -- Recent workouts
  RAISE NOTICE '';
  RAISE NOTICE '📅 RECENT WORKOUTS (Last 7 Days):';
  FOR recent_workouts IN
    SELECT '   ' || TO_CHAR(es.metric_date, 'YYYY-MM-DD') || ' | ' ||
           RPAD(SUBSTRING(u.email FROM 1 FOR 15), 15) || ' | ' ||
           RPAD(SUBSTRING(es.activity_type_name FROM 1 FOR 25), 25) || ' | ' ||
           ROUND(es.activity_duration_seconds / 60.0, 0)::text || ' min'
    FROM exercise_sessions es
    JOIN auth.users u ON u.id = es.user_id
    WHERE es.metric_date >= CURRENT_DATE - INTERVAL '7 days'
    ORDER BY es.metric_date DESC, es.activity_start_time DESC
    LIMIT 15
  LOOP
    RAISE NOTICE '%', recent_workouts;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '=============================================================================';
  RAISE NOTICE '✅ BACKEND EXERCISE CONTEXT FIX DEPLOYED SUCCESSFULLY';
  RAISE NOTICE '';
  RAISE NOTICE 'Next Steps:';
  RAISE NOTICE '  1. Deploy updated edge function: supabase functions deploy rook';
  RAISE NOTICE '  2. (Optional) Update iOS app when ready for event syncing';
  RAISE NOTICE '  3. Monitor logs for: 🏃 MIYA_ACTIVITY_EVENT_DETECTED';
  RAISE NOTICE '  4. Test: Have someone do a workout and verify no false alert';
  RAISE NOTICE '=============================================================================';
END $$;
