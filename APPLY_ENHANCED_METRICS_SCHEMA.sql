-- ===================================================================
-- APPLY ENHANCED WEARABLE METRICS SCHEMA
-- ===================================================================
-- This script adds columns for rich Apple Health data extraction.
-- Run this in Supabase SQL Editor.
--
-- WHAT IT DOES:
-- - Adds movement quality metrics (movement_minutes, active_steps, etc.)
-- - Adds sleep quality metrics (deep/REM/light sleep, efficiency, etc.)
-- - Adds respiratory metrics (breathing rate, SpO2)
-- - Creates indexes for efficient queries
--
-- SAFE TO RUN MULTIPLE TIMES (uses IF NOT EXISTS)
-- ===================================================================

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

-- Verification: show updated column list
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'wearable_daily_metrics'
  AND table_schema = 'public'
ORDER BY ordinal_position;

-- Success message
SELECT '✅ Schema updated successfully! New columns added for rich wearable metrics.' as status;
