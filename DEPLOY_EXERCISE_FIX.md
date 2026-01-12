# Exercise Context Fix - Deployment Guide

**Date:** January 18, 2026  
**Issue:** False "poor recovery" alerts on workout days  
**Fix Status:** ✅ Implemented, Ready to Deploy

---

## Quick Summary

This fix ensures your wife's workouts (and all family members' workouts) are recognized as **healthy activity**, not poor recovery. It prevents exercise-induced heart rate spikes from being misinterpreted as stress.

---

## Deployment Steps (In Order)

### Step 1: Apply Database Migration ✅

This creates the `exercise_sessions` table.

```bash
cd /Users/ramikaawach/Desktop/Miya
supabase db push
```

**Expected Output:**
```
Applying migration 20260118160000_add_exercise_sessions_table.sql...
✓ Migration applied successfully
```

**Verify:**
```sql
-- Check table exists
SELECT COUNT(*) FROM exercise_sessions;
-- Should return 0 (empty table, ready for data)
```

---

### Step 2: Check Available Historical Data 📊

Before backfilling, see what activity data is available:

```bash
supabase db execute --file check_activity_events_available.sql
```

**What You'll See:**
- How many activity_event webhooks are stored
- Which users have workout data
- Date range of available workouts
- Sample activity types (Walking, Running, Strength Training, etc.)

**Example Output:**
```
Activity Events Available for Backfill
total_activity_webhooks: 847
unique_users: 8
earliest_event: 2025-10-15
latest_event: 2026-01-18
last_7_days: 142
last_30_days: 476
last_90_days: 847
```

---

### Step 3: Backfill Historical Exercise Sessions 📥

Extract and load historical workout data:

```bash
supabase db execute --file backfill_exercise_sessions.sql
```

**What This Does:**
- Searches `rook_webhook_events` for past `activity_event` webhooks
- Extracts workout details (type, duration, intensity, HR)
- Inserts into `exercise_sessions` table
- Backfills last 90 days (configurable in SQL if you want more/less)

**Expected Output:**
```
Backfill Complete
total_sessions_inserted: 847
unique_users: 8
unique_activity_types: 15
earliest_session: 2025-10-15
latest_session: 2026-01-18
activity_types_found: Walking, Running, Functional Strength Training, Cycling, Yoga, Pilates, ...
```

**Then shows:**
- Per-user summary (how many workouts each person has)
- Sample of inserted sessions with details

**Verify:**
```sql
-- Check your wife's workouts
SELECT 
  metric_date,
  activity_type_name,
  ROUND(activity_duration_seconds / 60.0, 1) as duration_minutes,
  hr_avg_bpm,
  hr_max_bpm
FROM exercise_sessions
WHERE user_id = 'YOUR_WIFE_UUID'  -- Replace with actual UUID
ORDER BY metric_date DESC
LIMIT 10;
```

---

### Step 4: Deploy Updated Rook Function 🚀

This updates the webhook parser to capture future activity events:

```bash
cd /Users/ramikaawach/Desktop/Miya
supabase functions deploy rook
```

**Expected Output:**
```
Deploying function rook...
✓ Function deployed successfully
URL: https://[your-project].supabase.co/functions/v1/rook
```

**Verify:**
```bash
# Test webhook endpoint is alive
curl https://[your-project].supabase.co/functions/v1/rook

# Should return: {"ok":true,"message":"rook webhook alive"}
```

---

### Step 5: Build & Deploy iOS App 📱

The iOS app has **2 critical updates** that need to be deployed:

**In Xcode:**

1. Open project: `/Users/ramikaawach/Desktop/Miya/Miya Health.xcodeproj`
2. Clean build folder: `⌘ + Shift + K`
3. Build: `⌘ + B`
4. Check for errors (should be none)
5. Run on device: `⌘ + R`

**What Changed:**

1. **`ROOKDataAdapter.swift` (Recovery Scoring Fix)**
   - Recovery scoring now **only** uses sleep-based HR/HRV
   - No more fallback to physical activity data
   - Prevents exercise contamination

2. **`RookService.swift` (Event Syncing Added)**
   - ✅ Added `RookEventManager` for syncing activity events
   - ✅ Added `syncPendingEvents()` call during manual sync
   - ✅ Added per-day event syncing alongside summaries
   - ✅ Now syncs `.physical` events (workouts) and `.body` events (measurements)
   - **Impact:** Historical workouts will now be fetched during onboarding

**Test on Device:**
1. Open app
2. Pull to refresh dashboard
3. Check recovery scores are stable
4. Have someone do a workout
5. Sync data
6. Verify recovery score doesn't drop incorrectly

---

### Step 6: Verify Fix is Working ✅

Run these verification queries:

#### A. Check Exercise Sessions Are Being Stored

```sql
-- Recent exercise sessions (last 7 days)
SELECT 
  u.email,
  es.metric_date,
  es.activity_type_name,
  ROUND(es.activity_duration_seconds / 60.0, 1) as duration_min,
  es.hr_avg_bpm,
  es.source_of_data
FROM exercise_sessions es
JOIN auth.users u ON u.id = es.user_id
WHERE es.metric_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY es.metric_date DESC, es.activity_start_time DESC;
```

#### B. Check Recovery Alerts on Workout Days

```sql
-- Should be minimal - recovery alerts should be suppressed on workout days
SELECT 
  u.email,
  ps.metric_type,
  ps.active_since,
  ps.current_level,
  ps.severity,
  es.activity_type_name as workout_on_same_day,
  ROUND(es.activity_duration_seconds / 60.0, 1) as workout_duration_min
FROM pattern_alert_state ps
JOIN auth.users u ON u.id = ps.user_id
LEFT JOIN exercise_sessions es 
  ON ps.user_id = es.user_id 
  AND ps.active_since = es.metric_date::text
WHERE ps.metric_type IN ('hrv_ms', 'resting_hr')
  AND ps.episode_status = 'active'
  AND ps.active_since >= CURRENT_DATE - INTERVAL '14 days'
ORDER BY ps.active_since DESC;
```

**Expected:** Very few (or zero) recovery alerts on days with workouts.

#### C. Check Backend Logs

Look for these log entries in Supabase logs:

```
🏃 MIYA_ACTIVITY_EVENT_DETECTED - Activity event webhook received
🟢 MIYA_EXERCISE_SESSIONS_STORED - {userId: "...", count: 1, types: ["Walking"]}
🏃 MIYA_EXERCISE_DATES_FOUND - {userId: "...", count: 5, dates: ["2026-01-18", ...]}
🏃 MIYA_RECOVERY_ALERT_SKIPPED_WORKOUT_DAY - Recovery alert suppressed due to workout
```

---

## Testing Checklist

### Test Case 1: Workout Day Recovery ✅

**Steps:**
1. Have a family member complete a workout (any type)
2. Wait for Rook to sync (usually within minutes)
3. Check `exercise_sessions` table - session should appear
4. Check recovery score - should use sleep-based HR only
5. Run pattern alert evaluation
6. Verify no false "poor recovery" alert

**Expected Result:**
- Exercise session stored ✅
- Recovery score stable (not affected by workout HR) ✅
- No false alert ✅

### Test Case 2: Non-Workout Day with Poor Recovery ✅

**Steps:**
1. Simulate poor sleep (or wait for a naturally poor sleep night)
2. No workout that day
3. Check recovery metrics (low HRV, high resting HR)
4. Run pattern alert evaluation

**Expected Result:**
- Alert SHOULD trigger correctly ✅
- System still detects genuine recovery issues ✅

### Test Case 3: Multiple Workouts Per Day ✅

**Steps:**
1. Have someone do 2+ workouts in one day (e.g., morning walk + evening gym)
2. Check `exercise_sessions` table

**Expected Result:**
- Both sessions stored separately ✅
- Each with correct timing and activity type ✅

---

## Rollback Plan (If Needed)

If something goes wrong, you can roll back:

### Rollback Step 1: Revert Rook Function
```bash
# Check previous deployment
supabase functions list --show-versions

# Deploy previous version
supabase functions deploy rook --version [previous-version-number]
```

### Rollback Step 2: Revert iOS App
- Deploy previous build from Xcode archive
- Or checkout previous commit in Git

### Rollback Step 3: Keep Database Changes
- **Don't drop `exercise_sessions` table** - it's harmless and contains valuable data
- You can always re-run the backfill later

---

## Monitoring After Deployment

### Day 1-3: Watch for Issues

**Check Daily:**
```sql
-- How many exercise sessions today?
SELECT COUNT(*) FROM exercise_sessions 
WHERE metric_date = CURRENT_DATE;

-- Any recovery alerts on workout days?
SELECT COUNT(*) FROM pattern_alert_state ps
JOIN exercise_sessions es 
  ON ps.user_id = es.user_id 
  AND ps.active_since = es.metric_date::text
WHERE ps.metric_type IN ('hrv_ms', 'resting_hr')
  AND ps.episode_status = 'active'
  AND ps.active_since = CURRENT_DATE::text;
```

**Supabase Logs:**
- Go to Supabase Dashboard → Logs → Edge Functions
- Filter for "MIYA_" logs
- Look for exercise session parsing and alert skipping

### Week 1: User Feedback

**Ask Your Wife and Family:**
- "Are you still getting incorrect 'poor recovery' alerts after workouts?"
- "Does your recovery score seem more accurate now?"
- "Do you see your workouts being tracked?"

---

## Success Metrics

After 1 week, you should see:

✅ **90% reduction in false recovery alerts**  
✅ **Exercise sessions being stored daily**  
✅ **Recovery scores more stable on workout days**  
✅ **Improved user trust in recovery insights**

---

## Future Enhancements (Optional)

Once the fix is working, consider:

1. **Workout Badges**
   - "Completed 5 workouts this week"
   - "Most active family member"

2. **Exercise Insights**
   - "Your 3 strength training sessions are building resilience"
   - "Consider more rest days after intense workouts"

3. **Family Activity Dashboard**
   - Aggregate family workout stats
   - Shared workout challenges

4. **Recovery Context**
   - "Recovery lower than usual, but you had 3 intense workouts - this is expected"
   - "Great recovery despite yesterday's workout"

---

## Troubleshooting

### Issue: No exercise sessions appearing

**Check:**
1. Is Rook sending webhooks?
   ```sql
   SELECT COUNT(*) FROM rook_webhook_events 
   WHERE created_at >= NOW() - INTERVAL '1 day';
   ```

2. Are activity_event webhooks arriving?
   ```sql
   SELECT * FROM rook_webhook_events 
   WHERE payload->>'data_structure' = 'activity_event'
   ORDER BY created_at DESC LIMIT 5;
   ```

3. Check function logs for parsing errors

### Issue: User mapping not working

**Check:**
```sql
-- See unmapped users
SELECT DISTINCT 
  payload->>'user_id' as rook_user_id
FROM rook_webhook_events 
WHERE payload->>'data_structure' = 'activity_event'
  AND payload->>'user_id' NOT IN (
    SELECT rook_user_id FROM rook_user_mapping
  );
```

**Fix:**
```sql
-- Add mapping for unmapped user
INSERT INTO rook_user_mapping (rook_user_id, user_id)
VALUES ('rook-user-id', 'miya-user-uuid');
```

### Issue: Still getting false alerts

**Check:**
1. Pattern engine logs - is it skipping recovery alerts?
2. Is exercise_sessions populated for the alert date?
3. Is the alert for hrv_ms or resting_hr? (only these should be skipped)

---

## Support

If you encounter issues:

1. Check Supabase logs for error messages
2. Run verification SQL queries above
3. Check `EXERCISE_CONTEXT_FIX_SUMMARY.md` for detailed implementation
4. Review `backfill_exercise_sessions.sql` for data extraction logic

---

## Summary

**Deployment Time:** ~15 minutes  
**Backfill Time:** ~2 minutes (depends on data volume)  
**iOS Build Time:** ~5 minutes  
**Total Time:** ~25 minutes

**Complexity:** Low - all SQL scripts are self-contained  
**Risk:** Very low - changes are additive (new table, improved logic)  
**Impact:** High - fixes critical user experience issue

Your wife will finally get accurate recovery scores after her workouts! 🎉
