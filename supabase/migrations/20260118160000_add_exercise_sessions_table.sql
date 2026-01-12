-- Migration: Add exercise_sessions table for tracking workout/activity context
-- Purpose: Store individual exercise sessions from Rook activity_event webhooks
-- This prevents exercise-induced HR spikes from being misinterpreted as poor recovery

CREATE TABLE IF NOT EXISTS exercise_sessions (
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

-- Index for fast lookups by user and date
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user_date 
  ON exercise_sessions(user_id, metric_date);

-- Index for date-based queries
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_date 
  ON exercise_sessions(metric_date);

-- Index for activity type analysis
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_activity_type 
  ON exercise_sessions(activity_type_name);

-- RLS policies
ALTER TABLE exercise_sessions ENABLE ROW LEVEL SECURITY;

-- Users can read their own exercise sessions
CREATE POLICY "Users can view their own exercise sessions"
  ON exercise_sessions FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own exercise sessions (via webhook/sync)
CREATE POLICY "Users can insert their own exercise sessions"
  ON exercise_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Service role can do anything (for webhook processing)
CREATE POLICY "Service role can manage all exercise sessions"
  ON exercise_sessions FOR ALL
  USING (auth.role() = 'service_role');

COMMENT ON TABLE exercise_sessions IS 
  'Stores individual exercise/workout sessions from Rook activity_event webhooks. Used to provide context for recovery scoring and prevent exercise-induced HR spikes from being misinterpreted as poor recovery.';

COMMENT ON COLUMN exercise_sessions.activity_type_name IS 
  'Standardized activity type from Rook (e.g., Walking, Running, Cycling, Functional Strength Training, Pilates, etc.)';

COMMENT ON COLUMN exercise_sessions.was_under_physical_activity IS 
  'Flag from Rook metadata indicating user was under physical activity during this period';
