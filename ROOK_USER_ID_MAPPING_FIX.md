# Rook User ID Mapping Bug - Root Cause & Fix

## The Problem

When users onboard and connect their Apple Watch:
1. App calls `RookService.setUserId("46ded9db-5488-49ac-92b2-ffd2937e5e16")` with the Supabase user_id
2. **Rook SDK generates its own device UUID** (e.g., `AB99CA15-2490-4692-90CF-26D03576068E`)
3. Webhooks arrive with this device UUID instead of the Supabase user_id
4. The webhook handler incorrectly assumes "this looks like a UUID, it must be the user_id"
5. Result: `wearable_daily_metrics.user_id` stores the wrong value
6. Server-side vitality scoring queries by Supabase user_id and finds ZERO DATA
7. **Stress pillar score = 0** even though HRV data exists

---

## The Fix

### 1. Fixed Webhook Handler Logic ✅

**File:** `supabase/functions/rook/index.ts`

**Change:** The webhook handler now:
1. FIRST checks if this `rook_user_id` has existing metrics with a valid `user_id`
2. THEN checks the `rook_user_mapping` table
3. LAST RESORT: checks if `rook_user_id` exactly matches a `user_profiles.user_id`

This prevents the bug where device UUIDs are mistaken for Supabase user_ids.

---

### 2. Migration Script for Existing Bad Data

Run this SQL to fix existing users with incorrect `user_id` assignments:

\`\`\`sql
-- Find users with mismatched data
SELECT 
  wdm.user_id as wrong_user_id,
  wdm.rook_user_id,
  up.user_id as correct_user_id,
  up.first_name,
  COUNT(*) as affected_rows
FROM wearable_daily_metrics wdm
LEFT JOIN user_profiles up ON up.user_id != wdm.user_id
WHERE 
  -- Find cases where user_id looks like a rook device ID
  wdm.user_id = LOWER(wdm.rook_user_id)
  AND up.user_id IS NOT NULL
GROUP BY wdm.user_id, wdm.rook_user_id, up.user_id, up.first_name;

-- Fix each affected user (replace values below)
UPDATE wearable_daily_metrics
SET user_id = 'CORRECT_SUPABASE_USER_ID'
WHERE rook_user_id = 'DEVICE_ROOK_USER_ID';
\`\`\`

---

### 3. Long-term Solution: Auto-create Mapping During Onboarding

**TODO:** Add this to the onboarding flow after HealthKit permissions are granted:

\`\`\`swift
// After RookService.shared.setUserId(userId) succeeds
// and after syncHealthData() completes, create the mapping

// Wait for first webhook to arrive (contains the actual rook_user_id)
// Then create/update the mapping in rook_user_mapping table

// This requires either:
// Option A: Poll wearable_daily_metrics for new rows and extract rook_user_id
// Option B: Have Rook SDK expose a method to get the current device ID
// Option C: Accept that first-time users may have a brief delay while mapping is auto-created
\`\`\`

---

### 4. Monitoring & Detection

**SQL to detect this bug in production:**

\`\`\`sql
-- Find users with 0 stress pillar score but HRV data exists
SELECT 
  up.user_id,
  up.first_name,
  up.vitality_stress_pillar_score,
  COUNT(DISTINCT wdm.metric_date) as days_with_data,
  COUNT(CASE WHEN wdm.hrv_ms IS NOT NULL THEN 1 END) as days_with_hrv,
  -- Check if user_id mismatch
  CASE 
    WHEN up.user_id = wdm.user_id THEN 'OK'
    ELSE 'MISMATCH'
  END as data_integrity
FROM user_profiles up
LEFT JOIN wearable_daily_metrics wdm ON wdm.user_id = up.user_id
WHERE up.vitality_stress_pillar_score = 0
GROUP BY up.user_id, up.first_name, up.vitality_stress_pillar_score
HAVING COUNT(CASE WHEN wdm.hrv_ms IS NOT NULL THEN 1 END) > 0;
\`\`\`

---

## Why This Happened

The Rook SDK **does NOT use the user_id provided to `setUserId()`** for Apple Health syncing. Instead:

1. For **API-based sources** (Oura, Whoop, Fitbit), it uses the provided user_id ✅
2. For **Apple Health**, it generates a **device-specific UUID** and uses that

This is likely by design from Rook, as multiple devices for the same user need unique identifiers. But our webhook handler didn't account for this.

---

## Testing the Fix

After deploying the updated webhook handler:

1. Create a new test user
2. Complete onboarding with Apple Watch
3. Check `wearable_daily_metrics`:
   \`\`\`sql
   SELECT user_id, rook_user_id FROM wearable_daily_metrics 
   WHERE user_id = 'NEW_USER_ID' LIMIT 1;
   \`\`\`
4. Verify `user_id` matches the Supabase user_id (not the device ID)
5. Check vitality scores are calculated correctly

---

## Deploy Checklist

- [x] Fix webhook handler logic in `supabase/functions/rook/index.ts`
- [ ] Deploy Edge Function update
- [ ] Run migration SQL to fix existing users
- [ ] Test with a new user onboarding
- [ ] Monitor for any new occurrences
- [ ] Consider adding automated mapping creation in iOS app

---

## Related Files

- `supabase/functions/rook/index.ts` (webhook handler)
- `Miya Health/Services/RookService.swift` (SDK wrapper)
- `Miya Health/ContentView.swift` (onboarding flow, line 1968)
- `supabase/migrations/20260117000000_create_rook_user_mapping.sql` (mapping table)
