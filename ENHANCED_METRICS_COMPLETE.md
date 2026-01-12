# ✅ COMPLETE: Enhanced Wearable Metrics Implementation

## Summary
Implemented intelligent extraction of rich Apple Health data from Rook webhooks to dramatically improve vitality scoring accuracy, especially for the Movement pillar.

## What Was Wrong

### Movement Pillar Showing 0/100
**Root Cause**: The webhook parser was extracting `steps`, but the scoring engine's Movement pillar requires **3 sub-metrics**:
1. ❌ **Movement Minutes** (40% weight) - was always `nil`
2. ✅ **Steps** (30% weight) - working
3. ❌ **Active Calories** (30% weight) - was always `nil`

So even with steps data, Movement only had 30% of its components, resulting in near-zero scores.

### Sleep Pillar Accuracy
Sleep was scoring, but lacked quality metrics like:
- Deep sleep vs REM sleep percentages
- Sleep efficiency
- Time to fall asleep

## What Was Fixed

### 1. Database Schema Enhancement
**File**: `APPLY_ENHANCED_METRICS_SCHEMA.sql`

Added columns to `wearable_daily_metrics`:
- **Movement Quality**: `movement_minutes`, `active_steps`, `floors_climbed`, `distance_meters`
- **Sleep Quality**: `deep_sleep_minutes`, `rem_sleep_minutes`, `light_sleep_minutes`, `awake_minutes`, `sleep_efficiency_pct`, `time_to_fall_asleep_minutes`
- **Heart Detail**: `hrv_rmssd_ms` (alternative HRV measure)
- **Respiratory**: `breaths_avg_per_min`, `spo2_avg_pct`

### 2. Webhook Parser Enhancement
**File**: `supabase/functions/rook/index.ts`

Now extracts from Rook `physical_summary`:
```typescript
// Movement Minutes = active_seconds_int / 60
const activeSeconds = asNumber(deepFindByKey(body, "active_seconds_int"));
const movementMinutes = activeSeconds != null ? Math.round(activeSeconds / 60) : null;

// Active Calories = calories_net_active_kcal_float
const caloriesActive = asNumber(deepFindByKey(body, "calories_net_active_kcal_float"));

// Sleep Quality
const deepSleepMinutes = ...
const remSleepMinutes = ...
const sleepEfficiencyPct = (sleep_duration / time_in_bed) * 100
```

### 3. App Code Updates
**Files**: 
- `Miya Health/DataManager.swift`
- `Miya Health/RiskResultsView.swift`

Updated to:
- Fetch new columns from `wearable_daily_metrics`
- Calculate restorative sleep % (deep + REM / total)
- Pass `movementMinutes` to `VitalityRawMetrics` instead of `nil`
- Pass sleep quality metrics for more accurate scoring

## Impact on Vitality Scores

### Before
- Movement pillar: **0-10/100** (only had steps = 30% of components)
- Sleep pillar: **basic** (only total duration)
- Stress pillar: **OK** (had HRV + resting HR)

### After
- Movement pillar: **accurate 0-100** (movement minutes + steps + active calories = 100% of components)
- Sleep pillar: **rich** (duration + deep/REM % + efficiency)
- Stress pillar: **same** (HRV + resting HR)

**Result**: More accurate vitality scores, fewer false "not enough data" errors, better movement tracking.

## What You Need to Do

### 1. Apply Database Schema (REQUIRED)
Run this SQL in Supabase SQL Editor:
```bash
# File: APPLY_ENHANCED_METRICS_SCHEMA.sql
```

Just copy the entire file contents and paste into Supabase SQL Editor, then click **Run**.

### 2. Rebuild the App (REQUIRED)
The app code has been updated to fetch and use the new metrics.

In Xcode:
1. **Clean Build** (⇧⌘K)
2. **Build** (⌘B)
3. **Run** on your device

### 3. Test Flow
1. **Existing User**: Click "Connect a device" in the dashboard sidebar → reconnect Apple Health → watch for improved vitality score with proper movement pillar
2. **New User**: Complete onboarding with Apple Health → should see accurate vitality score with all 3 pillars scoring properly

## Files Changed

### Database
- ✅ `supabase/migrations/20260117200000_enhance_wearable_metrics.sql` (migration file)
- ✅ `APPLY_ENHANCED_METRICS_SCHEMA.sql` (manual SQL to run)

### Backend
- ✅ `supabase/functions/rook/index.ts` (webhook parser)

### App
- ✅ `Miya Health/DataManager.swift` (data fetching & scoring)
- ✅ `Miya Health/RiskResultsView.swift` (onboarding vitality computation)

## Next Webhooks

Once you apply the schema SQL, **all future Rook webhooks** will automatically populate these new columns. Within 24 hours, you'll see:
- `movement_minutes` populated with Apple's "active time" data
- `deep_sleep_minutes` and `rem_sleep_minutes` from Apple sleep stages
- `sleep_efficiency_pct` calculated from time in bed vs actual sleep

The Movement pillar will immediately start scoring accurately.

## Verification SQL

Check if new data is flowing:
```sql
SELECT 
  metric_date,
  steps,
  movement_minutes,
  sleep_minutes,
  deep_sleep_minutes,
  rem_sleep_minutes,
  sleep_efficiency_pct
FROM wearable_daily_metrics
WHERE user_id = (SELECT id FROM auth.users WHERE email = '001@1.com')
  AND created_at > NOW() - INTERVAL '1 hour'
ORDER BY metric_date DESC
LIMIT 10;
```

You should see `movement_minutes` and sleep quality metrics populated alongside `steps` and `sleep_minutes`.
