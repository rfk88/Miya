# Family Vitality Score Not Loading - Debug Guide

## Symptoms
- ✅ Champions section WORKS (shows Vitality MVP, daily badges)
- ❌ Family Vitality card shows "Waiting for your family"
- ❌ `familyVitalityScore` is `nil`

## Root Cause Analysis

### The 3-Day Freshness Rule
The `get_family_vitality` RPC **excludes** scores older than 3 days:

```sql
where member_scores.vitality_score_current is not null
  and member_scores.vitality_score_updated_at >= now() - interval '3 days'
```

**This means:**
- If all family members' `vitality_score_updated_at` timestamps are > 3 days old
- The RPC returns `family_vitality_score: NULL`
- Dashboard shows placeholder card

### Why Champions Works But Family Vitality Doesn't

**Champions section** uses `get_family_vitality_scores(family_id, start_date, end_date)`:
- Queries `vitality_scores` table (historical daily scores)
- Uses date range filter, not freshness filter
- Can show badges even if current scores are stale

**Family Vitality** uses `get_family_vitality(family_id)`:
- Queries `user_profiles.vitality_score_current` (latest snapshot)
- Requires `vitality_score_updated_at` to be < 3 days old
- Returns NULL if all scores are stale

## Diagnostic Steps

### 1. Run SQL Diagnostic Query

Run `/Users/ramikaawach/Desktop/Miya/diagnose_family_vitality.sql` in Supabase SQL Editor.

This will show:
- Your family members
- Their current vitality scores
- How old each score is
- Which scores are FRESH vs STALE

### 2. Check Expected Results

**If query shows:**
```
first_name   | vitality_score_current | freshness_status | hours_old
-------------|------------------------|------------------|----------
Gulmira      | 82                     | STALE            | 96.5
Rami         | 75                     | STALE            | 120.3
```

**Problem:** All scores are > 72 hours (3 days) old
**Solution:** Trigger vitality recomputation (see below)

**If query shows:**
```
first_name   | vitality_score_current | freshness_status | hours_old
-------------|------------------------|------------------|----------
Gulmira      | 82                     | FRESH            | 12.5
Rami         | NULL                   | No score yet     | NULL
```

**Problem:** Some members have no scores yet
**Solution:** Those members need to complete onboarding + sync health data

### 3. Check RPC Output Directly

The diagnostic query includes:
```sql
SELECT * FROM get_family_vitality((SELECT family_id FROM your_family));
```

**Expected output if working:**
```
family_vitality_score | members_with_data | members_total | has_recent_data
----------------------|-------------------|---------------|----------------
78                    | 2                 | 2             | true
```

**If you see:**
```
family_vitality_score | members_with_data | members_total | has_recent_data
----------------------|-------------------|---------------|----------------
NULL                  | 0                 | 2             | false
```

**Problem confirmed:** No fresh data (all scores > 3 days old)

## Solutions

### Solution 1: Trigger Vitality Recomputation

Force the app to recompute vitality scores from recent health data:

#### Option A: Via App UI
1. Open app
2. Go to Dashboard
3. Pull to refresh (swipe down on dashboard)
4. App will check for new health data and recompute if needed

#### Option B: Via Supabase Edge Function
```bash
curl -X POST https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/recompute_vitality_scores \
  -H "Authorization: Bearer YOUR_SUPABASE_ANON_KEY" \
  -H "x-miya-admin-secret: YOUR_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "USER_ID_HERE",
    "startDate": "2026-01-23",
    "endDate": "2026-01-25"
  }'
```

#### Option C: Via SQL (Manual Update)
```sql
-- Update vitality_score_updated_at to NOW() to make scores "fresh"
-- (Only if scores are actually current, just timestamp is stale)
UPDATE user_profiles
SET vitality_score_updated_at = NOW()
WHERE user_id IN (
    SELECT user_id 
    FROM family_members 
    WHERE family_id = 'YOUR_FAMILY_ID_HERE'
);
```

### Solution 2: Adjust Freshness Window (If Needed)

If 3 days is too strict for your use case, you can modify the RPC:

**File:** `supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql`

Change line 182:
```sql
-- FROM:
and member_scores.vitality_score_updated_at >= now() - interval '3 days'

-- TO (7 days):
and member_scores.vitality_score_updated_at >= now() - interval '7 days'
```

Then redeploy the migration:
```bash
cd /Users/ramikaawach/Desktop/Miya
supabase db push
```

### Solution 3: Check for Missing Health Data

If scores are NULL (not just stale), members need to:
1. Complete onboarding
2. Connect a wearable (Apple Health, ROOK, etc.)
3. Sync health data
4. Wait for automatic vitality computation

## Code Flow Reference

### Where Family Vitality Loads

**File:** `Miya Health/DashboardView.swift`

**Line 540:** Initial load on dashboard open
```swift
await loadFamilyVitality()
```

**Line 1287-1337:** `loadFamilyVitality()` function
- Calls `dataManager.fetchFamilyVitalitySummary()`
- Sets `familyVitalityScore` to result
- If RPC returns `score: NULL`, sets `familyVitalityScore = nil`

**Line 285-301:** Display logic
```swift
if isLoadingFamilyVitality {
    FamilyVitalityLoadingCard()  // Spinner
} else if let score = familyVitalityScore {
    FamilyVitalityCard(...)  // Shows score
} else {
    FamilyVitalityPlaceholderCard()  // "Waiting for your family"
}
```

### Where Champions Load

**File:** `Miya Health/DashboardView.swift`

**Line 640:** Champions use different RPC
```swift
scoreRows = try await dataManager.fetchFamilyVitalityScores(
    familyId: familyId,
    startDate: startDateStr,
    endDate: endDateStr
)
```

This queries `vitality_scores` table (historical), not `user_profiles.vitality_score_current`.

## Quick Fix Checklist

- [ ] Run diagnostic SQL query
- [ ] Check if scores exist but are stale (> 3 days old)
- [ ] If stale: Pull to refresh in app OR run recompute function
- [ ] If NULL: Check if members completed onboarding + synced data
- [ ] Verify `vitality_score_updated_at` timestamps are recent
- [ ] Check Xcode console for errors: `FamilyVitality ERROR:`
- [ ] Verify RPC returns non-null score: `SELECT * FROM get_family_vitality(...)`

## Expected Timeline

After triggering recomputation:
1. **Immediate:** `vitality_scores` table gets new rows
2. **Within 1 second:** `user_profiles.vitality_score_current` updated
3. **Within 2 seconds:** `get_family_vitality` RPC returns score
4. **Within 3 seconds:** Dashboard shows family vitality card

## Still Not Working?

Check these edge cases:

1. **Authorization issue:** User not member of family
   - Error: "Not authorized to access family vitality"
   
2. **Migration not run:** `vitality_progress_score_current` column missing
   - RPC handles this gracefully, returns NULL for progress score
   
3. **No family_id:** User not in any family
   - Error: "No family ID available to compute vitality"
   
4. **RPC execution error:** Check Supabase logs
   - Dashboard → Logs → Filter by "get_family_vitality"

---

**Last Updated:** January 2026
**Related Files:**
- `supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql`
- `Miya Health/DashboardView.swift` (lines 1287-1337, 285-301)
- `Miya Health/DataManager.swift` (lines 2729-2774)
- `diagnose_family_vitality.sql`
