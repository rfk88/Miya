-- Direct SQL to simulate a pattern alert for testing
-- This bypasses the Swift simulator and inserts data that WILL trigger a pattern alert
--
-- INSTRUCTIONS:
-- 1. Replace YOUR_USER_ID with the actual UUID of the test user (from auth.users)
-- 2. Choose ONE scenario by uncommenting the INSERT block you want
-- 3. Run this SQL in Supabase SQL Editor
-- 4. Refresh your dashboard - notification should appear

-- =====================================================
-- CONFIGURATION
-- =====================================================
DO $$
DECLARE
  test_user_id UUID := 'YOUR_USER_ID'; -- CHANGE THIS to your test user's UUID
  base_date DATE := CURRENT_DATE - INTERVAL '9 days'; -- Start 9 days ago, end today
  i INT;
  current_date_str TEXT;
BEGIN
  -- Clean up any existing debug data for this user (optional)
  DELETE FROM wearable_daily_metrics 
  WHERE user_id = test_user_id 
    AND source = 'debug_sql';

  -- =====================================================
  -- SCENARIO 1: SLEEP DROP (uncomment to use)
  -- =====================================================
  -- Baseline: 8 hours (480 min) for 7 days
  -- Decline: 6 hours (360 min) for 3 days
  
  FOR i IN 0..9 LOOP
    current_date_str := TO_CHAR(base_date + (i || ' days')::INTERVAL, 'YYYY-MM-DD');
    
    INSERT INTO wearable_daily_metrics (
      user_id,
      rook_user_id,
      metric_date,
      source,
      sleep_minutes
    ) VALUES (
      test_user_id,
      test_user_id::text,
      current_date_str::date,
      'debug_sql',
      CASE WHEN i < 7 THEN 480 ELSE 360 END -- 7 baseline, 3 decline
    )
    ON CONFLICT (rook_user_id, metric_date, source) DO UPDATE
    SET sleep_minutes = EXCLUDED.sleep_minutes,
        updated_at = NOW();
  END LOOP;
  
  RAISE NOTICE 'Inserted 10 days of sleep data for user %', test_user_id;

  -- =====================================================
  -- SCENARIO 2: STEPS DROP (comment out scenario 1, uncomment this)
  -- =====================================================
  /*
  FOR i IN 0..9 LOOP
    current_date_str := TO_CHAR(base_date + (i || ' days')::INTERVAL, 'YYYY-MM-DD');
    
    INSERT INTO wearable_daily_metrics (
      user_id,
      rook_user_id,
      metric_date,
      source,
      steps
    ) VALUES (
      test_user_id,
      test_user_id::text,
      current_date_str::date,
      'debug_sql',
      CASE WHEN i < 7 THEN 8000 ELSE 5000 END
    )
    ON CONFLICT (rook_user_id, metric_date, source) DO UPDATE
    SET steps = EXCLUDED.steps,
        updated_at = NOW();
  END LOOP;
  
  RAISE NOTICE 'Inserted 10 days of steps data for user %', test_user_id;
  */

  -- =====================================================
  -- SCENARIO 3: HRV DROP (comment others, uncomment this)
  -- =====================================================
  /*
  FOR i IN 0..9 LOOP
    current_date_str := TO_CHAR(base_date + (i || ' days')::INTERVAL, 'YYYY-MM-DD');
    
    INSERT INTO wearable_daily_metrics (
      user_id,
      rook_user_id,
      metric_date,
      source,
      hrv_ms
    ) VALUES (
      test_user_id,
      test_user_id::text,
      current_date_str::date,
      'debug_sql',
      CASE WHEN i < 7 THEN 60.0 ELSE 45.0 END
    )
    ON CONFLICT (rook_user_id, metric_date, source) DO UPDATE
    SET hrv_ms = EXCLUDED.hrv_ms,
        updated_at = NOW();
  END LOOP;
  
  RAISE NOTICE 'Inserted 10 days of HRV data for user %', test_user_id;
  */

  -- =====================================================
  -- SCENARIO 4: RESTING HR RISE (comment others, uncomment this)
  -- =====================================================
  /*
  FOR i IN 0..9 LOOP
    current_date_str := TO_CHAR(base_date + (i || ' days')::INTERVAL, 'YYYY-MM-DD');
    
    INSERT INTO wearable_daily_metrics (
      user_id,
      rook_user_id,
      metric_date,
      source,
      resting_hr
    ) VALUES (
      test_user_id,
      test_user_id::text,
      current_date_str::date,
      'debug_sql',
      CASE WHEN i < 7 THEN 55.0 ELSE 65.0 END
    )
    ON CONFLICT (rook_user_id, metric_date, source) DO UPDATE
    SET resting_hr = EXCLUDED.resting_hr,
        updated_at = NOW();
  END LOOP;
  
  RAISE NOTICE 'Inserted 10 days of resting HR data for user %', test_user_id;
  */

END $$;

-- =====================================================
-- VERIFY THE DATA WAS INSERTED
-- =====================================================
SELECT 
  metric_date,
  sleep_minutes,
  steps,
  hrv_ms,
  resting_hr
FROM wearable_daily_metrics
WHERE source = 'debug_sql'
ORDER BY metric_date DESC
LIMIT 15;

-- =====================================================
-- NEXT STEP: TRIGGER PATTERN EVALUATION
-- =====================================================
-- After running this script, you need to trigger the pattern evaluation.
-- You can either:
-- 1. Use the "Simulate alerts" button in your app's debug menu (it will call the rook function)
-- 2. Or manually call the rook function via Supabase Functions with a POST request
-- 3. Or wait for the next natural scoring/pattern evaluation cycle
--
-- Once pattern evaluation runs, check:
-- SELECT * FROM pattern_alert_state WHERE user_id = 'YOUR_USER_ID' ORDER BY created_at DESC;
