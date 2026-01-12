# Activity Event Data Flow - Complete System Overview

**Date:** January 18, 2026  
**Purpose:** Document how workout/exercise data flows from wearables to Miya database

---

## Overview: Two Parallel Data Paths

Activity event data (workouts, exercises) reaches Miya through **TWO parallel paths**:

1. **iOS SDK Direct Sync** → App fetches from Rook SDK → Sends to Rook servers → Rook webhooks to Supabase
2. **Rook Background Sync** → Automatic background sync → Rook webhooks to Supabase

Both paths ultimately deliver `activity_event` webhooks to our Supabase edge function.

---

## Path 1: iOS SDK Direct Sync (Manual/Onboarding)

### When It Happens
- During onboarding (after user grants HealthKit permissions)
- When user taps "Sync Now" in the app
- On app launch (if continuous upload enabled)

### Flow Diagram

```
┌─────────────────┐
│  Apple Health   │
│   (HealthKit)   │
└────────┬────────┘
         │
         │ iOS SDK reads health data
         ▼
┌─────────────────┐
│   Miya iOS App  │
│  RookService    │
└────────┬────────┘
         │
         │ syncHealthData(backfillDays: 7)
         ▼
┌─────────────────────────────────────┐
│     Rook SDK (RookEventManager)     │
│  • eventManager.syncPendingEvents() │
│  • eventManager.sync(date, .physical)│
└────────┬────────────────────────────┘
         │
         │ Uploads to Rook servers
         ▼
┌─────────────────┐
│  Rook Servers   │
│  (Cloud API)    │
└────────┬────────┘
         │
         │ Webhook delivery (activity_event)
         ▼
┌──────────────────────────────────────┐
│  Supabase Edge Function: rook        │
│  /Users/.../supabase/functions/rook  │
└────────┬─────────────────────────────┘
         │
         │ Parse activity_event webhook
         ▼
┌──────────────────────────────────────┐
│  Database: exercise_sessions         │
│  Stores: type, duration, intensity,  │
│          calories, HR during workout │
└──────────────────────────────────────┘
```

### Code Implementation

**File:** `Miya Health/Services/RookService.swift`

```swift
func syncHealthData(backfillDays requestedDays: Int = 7) {
    let summaryManager = RookSummaryManager()
    let eventManager = RookEventManager()  // ✅ NEW
    
    // Sync pending events
    eventManager.syncPendingEvents { result in
        // Handles any events the SDK queued
    }
    
    // Sync events for each day in backfill range
    let eventTypes: [EventTypeToUpload] = [.physical, .body]
    
    eventManager.sync(date, eventType: eventTypes) { result in
        // Fetches workouts and body measurements for specific date
    }
}
```

**What It Syncs:**
- `.physical` events = **Workouts** (Walking, Running, Strength Training, etc.)
- `.body` events = Body measurements (weight, blood glucose, etc.)

**Backfill Range:**
- Default: 7 days
- Maximum: 29 days (Apple Health limitation)
- Configurable during onboarding

---

## Path 2: Rook Background Sync (Automatic)

### When It Happens
- Continuously in the background (iOS manages timing)
- When new workout is recorded in Apple Health
- Periodic sync (every few hours, OS-dependent)

### Flow Diagram

```
┌─────────────────┐
│  Apple Health   │
│   (HealthKit)   │
└────────┬────────┘
         │
         │ New workout recorded
         ▼
┌─────────────────┐
│   Rook SDK      │
│ (Background)    │
└────────┬────────┘
         │
         │ Auto-detects new data
         │ (enableEventsBackgroundSync: true)
         ▼
┌─────────────────┐
│  Rook Servers   │
└────────┬────────┘
         │
         │ Webhook delivery (activity_event)
         ▼
┌──────────────────────────────────────┐
│  Supabase Edge Function: rook        │
└────────┬─────────────────────────────┘
         │
         │ Parse activity_event webhook
         ▼
┌──────────────────────────────────────┐
│  Database: exercise_sessions         │
└──────────────────────────────────────┘
```

### Code Configuration

**File:** `Miya Health/Services/RookService.swift`

```swift
RookConnectConfigurationManager.shared.setConfiguration(
    clientUUID: clientUUID,
    secretKey: secretKey,
    enableBackgroundSync: true,
    enableEventsBackgroundSync: true  // ✅ Enables automatic event sync
)
```

**What It Does:**
- Monitors Apple Health for new data
- Automatically uploads when network available
- No user interaction required
- Respects iOS background execution limits

---

## Webhook Processing (Both Paths Converge Here)

### Webhook Payload Structure

When Rook sends an `activity_event` webhook, it looks like this:

```json
{
  "data_structure": "activity_event",
  "user_id": "user-uuid",
  "physical_health": {
    "events": {
      "activity_event": [{
        "metadata": {
          "datetime_string": "2026-01-18T10:00:00Z",
          "was_the_user_under_physical_activity_bool": true,
          "sources_of_data_array": ["Apple Health"]
        },
        "activity": {
          "activity_type_name_string": "Functional Strength Training",
          "activity_start_datetime_string": "2026-01-18T10:00:00Z",
          "activity_end_datetime_string": "2026-01-18T10:48:00Z",
          "activity_duration_seconds_int": 2880,
          "moderate_intensity_seconds_int": 1200,
          "vigorous_intensity_seconds_int": 900
        },
        "calories": {
          "calories_net_active_kcal_float": 320
        },
        "heart_rate": {
          "hr_avg_bpm_int": 145,
          "hr_max_bpm_int": 172
        }
      }]
    }
  }
}
```

### Processing Logic

**File:** `supabase/functions/rook/index.ts` (lines 177-321)

```typescript
if (dataStructure === "activity_event") {
  console.log("🏃 MIYA_ACTIVITY_EVENT_DETECTED");
  
  // Extract activity events array
  const activityEvents = deepFindByKey(body, "activity_event");
  
  for (const event of eventsArray) {
    // Extract workout details
    const activityTypeName = asString(activity.activity_type_name_string);
    const startTime = asString(activity.activity_start_datetime_string);
    const endTime = asString(activity.activity_end_datetime_string);
    const duration = asNumber(activity.activity_duration_seconds_int);
    
    // Store in exercise_sessions table
    await supabase.from("exercise_sessions").upsert({
      user_id: userId,
      metric_date: metricDate,
      activity_type_name: activityTypeName,
      activity_start_time: startTime,
      activity_end_time: endTime,
      activity_duration_seconds: duration,
      moderate_intensity_seconds: asNumber(activity.moderate_intensity_seconds_int),
      vigorous_intensity_seconds: asNumber(activity.vigorous_intensity_seconds_int),
      calories_active_kcal: asNumber(calories.calories_net_active_kcal_float),
      hr_avg_bpm: asNumber(heartRate.hr_avg_bpm_int),
      ...
    });
  }
}
```

### What Gets Stored

**Table:** `exercise_sessions`

Each workout is stored with:
- **Identification:** user_id, rook_user_id, metric_date
- **Timing:** activity_start_time, activity_end_time, duration
- **Type:** activity_type_name (e.g., "Walking", "Running", "Functional Strength Training")
- **Intensity:** low/moderate/vigorous seconds breakdown
- **Calories:** calories_burned_kcal, calories_active_kcal
- **Distance:** distance_meters, steps
- **Heart Rate:** hr_avg_bpm, hr_max_bpm, hr_min_bpm
- **Source:** source_of_data (apple_health, whoop, oura, etc.)

---

## Why Two Paths Are Necessary

### Path 1 (iOS SDK) Strengths:
✅ **Immediate** - Syncs right after onboarding  
✅ **Controllable** - App triggers sync when needed  
✅ **Backfill** - Can fetch 7-29 days of historical data  
✅ **User-initiated** - "Sync Now" button works  

### Path 1 Limitations:
❌ Requires app to be running  
❌ User must manually sync for updates  
❌ Limited to 29 days max backfill  

### Path 2 (Background Sync) Strengths:
✅ **Automatic** - No user action needed  
✅ **Real-time** - New workouts sync within hours  
✅ **Continuous** - Works even when app closed  
✅ **Battery-efficient** - iOS optimizes timing  

### Path 2 Limitations:
❌ iOS controls timing (not instant)  
❌ May delay if device offline  
❌ No control over when sync happens  
❌ Doesn't backfill old data  

### Combined System:
🎯 **Best of both worlds:**
- Onboarding: Path 1 fetches last 7-29 days
- Ongoing: Path 2 keeps data fresh automatically
- Manual: Path 1 handles "Sync Now" requests

---

## Data Deduplication

### How We Handle Duplicates

Both paths might send the same workout. We prevent duplicates using:

```sql
CONSTRAINT exercise_sessions_user_date_time_unique 
  UNIQUE(user_id, activity_start_time, activity_end_time)
```

**Upsert Logic:**
```typescript
await supabase.from("exercise_sessions").upsert(exerciseRecords, {
  onConflict: "user_id,activity_start_time,activity_end_time",
  ignoreDuplicates: false,  // Update if duplicate found
});
```

**Result:**
- Same workout from both paths → Only one database record
- Later sync with more complete data → Updates existing record
- No duplicate workout entries

---

## Timeline Example: New User Onboarding

### Day 1 - User Installs App

**Time: 09:00 AM**
- User completes onboarding
- Grants HealthKit permissions
- `RookService.syncHealthData(backfillDays: 7)` triggered

**Time: 09:01 AM - 09:05 AM**
- iOS SDK fetches last 7 days of data from HealthKit
- Uploads summaries (sleep, physical, body)
- **Uploads events** (workouts from past 7 days) ✅ **NEW**
- Rook receives data

**Time: 09:06 AM - 09:10 AM**
- Rook processes uploads
- Sends webhooks to Supabase
- Multiple `activity_event` webhooks arrive
- Our edge function parses and stores each workout

**Database State:**
```
exercise_sessions table now has:
- 12 workouts from past 7 days
- Activity types: 5 Walking, 4 Running, 2 Strength Training, 1 Cycling
- Complete details: duration, intensity, HR, calories
```

### Day 1 - User Does Evening Workout

**Time: 06:00 PM - 06:45 PM**
- User completes workout (Functional Strength Training)
- Apple Health records workout

**Time: 07:30 PM** (iOS Background Sync)
- Rook SDK detects new workout in background
- Automatically uploads to Rook servers
- (User doesn't see anything - happens silently)

**Time: 07:35 PM**
- Rook sends `activity_event` webhook
- Edge function parses and stores
- New workout appears in `exercise_sessions` table

**Result:**
- User didn't open app
- Workout still synced automatically
- Available immediately for pattern alerts and recovery scoring

### Day 2 - Morning Dashboard Check

**Time: 08:00 AM**
- User opens app
- Pulls to refresh dashboard
- Recovery score displays correctly (no false alert from yesterday's workout)
- Pattern alert engine sees workout on Day 1, skips recovery alert

---

## Verification Queries

### Check Recent Workouts
```sql
SELECT 
  metric_date,
  activity_type_name,
  ROUND(activity_duration_seconds / 60.0, 1) as duration_min,
  moderate_intensity_seconds / 60 as moderate_min,
  vigorous_intensity_seconds / 60 as vigorous_min,
  hr_avg_bpm,
  hr_max_bpm,
  source_of_data
FROM exercise_sessions
WHERE user_id = 'YOUR_USER_ID'
  AND metric_date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY activity_start_time DESC;
```

### Check Which Path Synced First
```sql
-- If created_at is close to onboarding timestamp → iOS SDK sync
-- If created_at is hours/day after workout → Background sync
SELECT 
  activity_type_name,
  activity_start_time as workout_time,
  created_at as stored_in_db_at,
  created_at - activity_start_time as sync_delay
FROM exercise_sessions
WHERE user_id = 'YOUR_USER_ID'
ORDER BY activity_start_time DESC
LIMIT 10;
```

### Monitor Sync Health
```sql
-- Should see activity_event webhooks coming in
SELECT 
  created_at,
  payload->>'data_structure' as webhook_type,
  payload#>>'{physical_health,events,activity_event,0,activity,activity_type_name_string}' as activity_type
FROM rook_webhook_events
WHERE payload->>'data_structure' = 'activity_event'
  AND created_at >= NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;
```

---

## Monitoring and Logs

### iOS App Logs (Xcode Console)

**During onboarding/manual sync:**
```
🟢 RookService: Enabling automatic sync + triggering manual backfill (7d)
✅ RookService: syncPendingEvents finished ok=true
✅ RookService: Synced events for 2026-01-18 ok=true
✅ RookService: Synced events for 2026-01-17 ok=true
...
```

### Backend Logs (Supabase Edge Functions)

**When webhook arrives:**
```
🔵 MIYA_PARSING_START {dataStructure: "activity_event", userId: "..."}
🏃 MIYA_ACTIVITY_EVENT_DETECTED
🟢 MIYA_EXERCISE_SESSIONS_STORED {userId: "...", count: 1, types: ["Walking"]}
```

**When pattern alerts run:**
```
🏃 MIYA_EXERCISE_DATES_FOUND {userId: "...", count: 3, dates: ["2026-01-18", "2026-01-17", "2026-01-15"]}
🏃 MIYA_RECOVERY_ALERT_SKIPPED_WORKOUT_DAY {metric: "hrv_ms", endDate: "2026-01-18"}
```

---

## Troubleshooting

### Issue: No workouts appearing after onboarding

**Check iOS SDK sync:**
```swift
// Look for this in Xcode console during sync
✅ RookService: Synced events for [date] ok=true
```

**If missing:**
- Verify `RookEventManager` is initialized
- Check HealthKit permissions include "Workouts"
- Ensure `enableEventsBackgroundSync: true` is set

### Issue: Old workouts not backfilled

**Cause:** Backfill only goes back 7 days by default

**Fix:**
```swift
// In onboarding code, increase backfill
RookService.shared.syncHealthData(backfillDays: 29)  // Max for iOS
```

### Issue: Background sync not working

**Check:**
1. iOS Settings → Miya → Background App Refresh (enabled?)
2. Supabase webhook URL configured correctly in Rook dashboard?
3. Device has network connectivity?

**Test manually:**
```swift
// In app, trigger manual sync
RookService.shared.syncHealthData(backfillDays: 1)
```

---

## Summary

### Complete Data Flow (Both Paths)

```
Apple Health/Wearable
      ↓
      ├─→ iOS SDK (Manual/Onboarding)
      │         ↓
      │   RookEventManager.sync()
      │         ↓
      └─→ Rook Background Sync (Automatic)
                ↓
          Rook Cloud Servers
                ↓
     activity_event webhooks
                ↓
    Supabase Edge Function
                ↓
     Parse & Extract Data
                ↓
    exercise_sessions table
                ↓
    ┌───────────┴───────────┐
    ↓                       ↓
Recovery Scoring      Pattern Alerts
(Skip exercise HR)    (Skip workout days)
```

### Key Takeaways

✅ **Two sync paths ensure complete coverage**  
✅ **iOS SDK handles onboarding and manual syncs**  
✅ **Background sync keeps data fresh automatically**  
✅ **Deduplication prevents double-counting**  
✅ **All workouts stored in `exercise_sessions` table**  
✅ **Recovery scoring uses clean sleep-based data**  
✅ **Pattern alerts skip false positives on workout days**

### What Changed in This Fix

**Before:**
- ❌ iOS SDK only synced summaries (not events)
- ❌ No workout context in database
- ❌ Exercise HR contaminated recovery scores
- ❌ False "poor recovery" alerts on workout days

**After:**
- ✅ iOS SDK syncs both summaries AND events
- ✅ Complete workout tracking in `exercise_sessions` table
- ✅ Recovery scoring uses only sleep-based HR/HRV
- ✅ Pattern alerts recognize workout days and skip false positives

Your wife's workouts will now be properly recognized and won't cause false recovery alerts! 🎉
