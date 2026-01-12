-- STEP 1: Create exercise_sessions table
-- Run this first in Supabase SQL Editor

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

-- Verify
SELECT 'Table created successfully' as status;
