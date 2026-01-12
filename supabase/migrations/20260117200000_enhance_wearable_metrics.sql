-- Enhance wearable_daily_metrics with rich Apple Health data
-- This migration adds columns for movement quality, sleep quality, and other detailed metrics

-- Add movement quality metrics
ALTER TABLE wearable_daily_metrics 
ADD COLUMN IF NOT EXISTS movement_minutes integer,  -- Active seconds converted to minutes
ADD COLUMN IF NOT EXISTS active_steps integer,      -- Steps taken during active periods
ADD COLUMN IF NOT EXISTS floors_climbed numeric,    -- Floors climbed
ADD COLUMN IF NOT EXISTS distance_meters numeric;   -- Total distance traveled

-- Add sleep quality metrics
ALTER TABLE wearable_daily_metrics
ADD COLUMN IF NOT EXISTS deep_sleep_minutes integer,    -- Deep sleep duration
ADD COLUMN IF NOT EXISTS rem_sleep_minutes integer,     -- REM sleep duration  
ADD COLUMN IF NOT EXISTS light_sleep_minutes integer,   -- Light sleep duration
ADD COLUMN IF NOT EXISTS awake_minutes integer,         -- Time awake during sleep
ADD COLUMN IF NOT EXISTS sleep_efficiency_pct numeric,  -- Sleep efficiency percentage
ADD COLUMN IF NOT EXISTS time_to_fall_asleep_minutes integer; -- Sleep latency

-- Add heart rate variability details
ALTER TABLE wearable_daily_metrics
ADD COLUMN IF NOT EXISTS hrv_rmssd_ms numeric;  -- HRV RMSSD (alternative HRV measure)

-- Add respiratory metrics  
ALTER TABLE wearable_daily_metrics
ADD COLUMN IF NOT EXISTS breaths_avg_per_min numeric,  -- Average breathing rate
ADD COLUMN IF NOT EXISTS spo2_avg_pct numeric;         -- Average blood oxygen saturation

-- Add indexes for commonly queried fields
CREATE INDEX IF NOT EXISTS idx_wearable_metrics_movement 
  ON wearable_daily_metrics (user_id, metric_date) 
  WHERE movement_minutes IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wearable_metrics_sleep_quality
  ON wearable_daily_metrics (user_id, metric_date)
  WHERE deep_sleep_minutes IS NOT NULL OR rem_sleep_minutes IS NOT NULL;

-- Comment for documentation
COMMENT ON COLUMN wearable_daily_metrics.movement_minutes IS 'Active minutes per day from active_seconds_int (Apple Health)';
COMMENT ON COLUMN wearable_daily_metrics.deep_sleep_minutes IS 'Deep sleep duration in minutes';
COMMENT ON COLUMN wearable_daily_metrics.rem_sleep_minutes IS 'REM sleep duration in minutes';
COMMENT ON COLUMN wearable_daily_metrics.sleep_efficiency_pct IS 'Sleep efficiency: (sleep_duration / time_in_bed) * 100';
