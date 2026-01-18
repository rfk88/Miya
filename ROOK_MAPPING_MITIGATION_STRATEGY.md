# Rook User ID Mapping - Comprehensive Mitigation Strategy

## Problem Summary

During onboarding, there's a risk that wearable data gets assigned to the wrong user due to:
1. Rook SDK non-deterministic behavior
2. Race conditions during initial sync
3. Client UUID collisions
4. Webhook delivery timing issues

---

## Implemented Mitigations ✅

### 1. Smart Webhook Handler (DEPLOYED)

**File:** `supabase/functions/rook/index.ts`

The webhook handler now uses a 3-tier lookup strategy:

```typescript
// Tier 1: Check existing wearable_daily_metrics for this rook_user_id
// → Ensures consistency across webhooks for the same device

// Tier 2: Check rook_user_mapping table
// → Manual mappings or auto-created mappings

// Tier 3: Last resort - check if rook_user_id matches user_profiles.user_id
// → Handles cases where Rook SDK correctly uses Supabase user_id
```

**Benefit:** Prevents wrong user_id assignment even if Rook sends inconsistent device IDs.

---

## Additional Recommended Mitigations

### 2. Monitoring & Alerting 🔔

**Add SQL monitoring query** (run daily via cron job or scheduled function):

```sql
-- Detect users with 0 stress score but HRV data exists
SELECT 
  up.user_id,
  up.first_name,
  up.email,
  up.vitality_stress_pillar_score,
  COUNT(DISTINCT wdm.metric_date) as days_with_data,
  COUNT(CASE WHEN wdm.hrv_ms IS NOT NULL THEN 1 END) as days_with_hrv
FROM user_profiles up
LEFT JOIN wearable_daily_metrics wdm ON wdm.user_id = up.user_id
WHERE up.vitality_stress_pillar_score = 0
  AND wdm.created_at > NOW() - INTERVAL '7 days'
GROUP BY up.user_id, up.first_name, up.email, up.vitality_stress_pillar_score
HAVING COUNT(CASE WHEN wdm.hrv_ms IS NOT NULL THEN 1 END) > 0;
```

**If this returns any rows → Alert the team immediately!**

---

### 3. Orphaned Data Detection 🔍

**Detect wearable data that isn't assigned to any user:**

```sql
-- Find rook_user_ids with data but no valid user_id
SELECT 
  rook_user_id,
  user_id::text,
  COUNT(*) as row_count,
  MIN(created_at) as first_seen,
  MAX(created_at) as last_seen,
  COUNT(CASE WHEN hrv_ms IS NOT NULL THEN 1 END) as hrv_count
FROM wearable_daily_metrics
WHERE user_id IS NULL 
   OR user_id NOT IN (SELECT user_id FROM user_profiles)
GROUP BY rook_user_id, user_id
ORDER BY last_seen DESC;
```

**If this returns rows → Data is orphaned and needs manual mapping!**

---

### 4. Explicit User-Device Mapping Table 📊

**Create proactive mappings** when users connect wearables:

#### Option A: Poll After Sync (Client-Side)

After `syncHealthData()` completes, poll `wearable_daily_metrics` for new rows:

```swift
// In ContentView.swift, after line 2044
Task {
    // Wait for first webhook to arrive (max 60 seconds)
    for attempt in 1...12 {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Check if any data arrived for this user
        let supabase = SupabaseConfig.client
        struct MetricRow: Decodable {
            let rook_user_id: String
        }
        
        let rows: [MetricRow] = try? await supabase
            .from("wearable_daily_metrics")
            .select("rook_user_id")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        
        if let rookUserId = rows?.first?.rook_user_id {
            print("✅ RookConnect: Detected device ID \(rookUserId) - creating mapping")
            
            // Create explicit mapping (idempotent)
            struct MappingRow: Encodable {
                let rook_user_id: String
                let user_id: String
            }
            
            try? await supabase
                .from("rook_user_mapping")
                .upsert(MappingRow(rook_user_id: rookUserId, user_id: userId))
                .execute()
            
            break
        }
    }
}
```

#### Option B: Auto-Create in Webhook Handler (Server-Side)

Add this to the webhook handler after determining `userId`:

```typescript
// After line 600 in index.ts
if (userId && rookUserId && mappingSource === "direct_match") {
  // Auto-create mapping for future webhooks
  const { error: mappingInsertErr } = await supabase
    .from("rook_user_mapping")
    .upsert({ rook_user_id: rookUserId, user_id: userId })
    .select()
    .single();
  
  if (!mappingInsertErr) {
    console.log("🟢 MIYA_AUTO_CREATED_MAPPING", { rookUserId, userId });
  }
}
```

---

### 5. Race Condition Prevention ⏱️

**Ensure setUserId() completes before sync starts:**

Already implemented in `ContentView.swift` (line 1968), but add explicit delay:

```swift
RookService.shared.setUserId(userId) { ok in
    guard ok else { return }
    
    // Add 2-second delay to ensure Rook backend processes the setUserId call
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        // Now request permissions and sync
        let permissionsManager = RookConnectPermissionsManager()
        permissionsManager.requestAllPermissions { _ in
            RookService.shared.syncHealthData(backfillDays: 29)
        }
    }
}
```

---

### 6. Client UUID Isolation 🔐

**Use per-user client UUIDs** instead of sharing one across all users.

⚠️ **Major change** - requires Rook account restructuring:
- Each user gets their own Rook client_uuid
- Store in `user_profiles.rook_client_uuid`
- Configure SDK dynamically per user

**Trade-off:** More complex, but eliminates cross-user contamination risk entirely.

---

### 7. Webhook Validation & Logging 📝

**Already implemented:** The webhook handler logs all mapping decisions.

**Add to monitoring:** Set up log aggregation (e.g., Sentry, LogRocket) to track:
- `🟡 MIYA_ROOK_USER_ID_UNMAPPED` warnings
- `🔴 MIYA_MAPPING_LOOKUP_ERROR` errors
- Patterns in `mappingSource` distribution

---

### 8. User-Facing Validation ✅

**Show user confirmation** after wearable connection:

```swift
// After successful sync, display:
"✅ Apple Watch Connected
Your data is syncing...
Device ID: AB99CA15... (first 8 chars)
Expected in 2-5 minutes"

// After first vitality score calculates:
"✅ Your vitality score is ready!
Score: 78/100
Data from: Apple Watch"
```

**If score doesn't appear after 5 minutes → Show error:**
```
"⚠️ We're having trouble syncing your wearable data.
Please reconnect your Apple Watch or contact support."
```

---

## Testing Checklist

After implementing mitigations:

- [ ] New user onboards with Apple Watch → Data maps correctly
- [ ] New user onboards with Oura/Whoop → Data maps correctly
- [ ] User reconnects wearable → Existing mapping preserved
- [ ] Two users onboard simultaneously → No cross-contamination
- [ ] User deletes account → Orphaned data cleanup works
- [ ] Monitoring queries run without errors
- [ ] Logs show correct `mappingSource` in all cases

---

## Priority Implementation Order

1. ✅ **Smart webhook handler** (DONE & DEPLOYED)
2. 🔔 **Monitoring & alerting** (30 mins - HIGH PRIORITY)
3. 🔍 **Orphaned data detection** (15 mins - HIGH PRIORITY)
4. 📊 **Auto-create mapping in webhook** (30 mins - MEDIUM PRIORITY)
5. ⏱️ **Race condition delay** (5 mins - LOW PRIORITY)
6. ✅ **User-facing validation** (1 hour - MEDIUM PRIORITY)
7. 🔐 **Client UUID isolation** (4-8 hours - FUTURE, if issue persists)

---

## Emergency Runbook

If the bug happens again:

### Step 1: Identify the affected user
```sql
SELECT user_id, first_name, vitality_stress_pillar_score
FROM user_profiles
WHERE vitality_stress_pillar_score = 0
  AND created_at > NOW() - INTERVAL '24 hours';
```

### Step 2: Find their rook_user_id
```sql
SELECT DISTINCT rook_user_id, user_id::text, COUNT(*) as rows
FROM wearable_daily_metrics
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY rook_user_id, user_id
ORDER BY COUNT(*) DESC;
```

### Step 3: Check if data is assigned to wrong user
```sql
-- Look for HRV data not assigned to the affected user
SELECT 
  wdm.rook_user_id,
  wdm.user_id::text as assigned_to,
  up.first_name as assigned_name,
  COUNT(CASE WHEN wdm.hrv_ms IS NOT NULL THEN 1 END) as hrv_count
FROM wearable_daily_metrics wdm
LEFT JOIN user_profiles up ON up.user_id = wdm.user_id
WHERE wdm.created_at > NOW() - INTERVAL '24 hours'
GROUP BY wdm.rook_user_id, wdm.user_id, up.first_name;
```

### Step 4: Fix the mapping
```sql
UPDATE wearable_daily_metrics
SET user_id = 'CORRECT_USER_ID'
WHERE rook_user_id = 'DEVICE_ID'
  AND user_id != 'CORRECT_USER_ID';
```

### Step 5: Trigger recalculation
```sql
-- Via Supabase Dashboard → Edge Functions → rook_daily_recompute
-- Or reconnect wearable in the app
```

---

## Success Metrics

Track these weekly:
- % of new users with 0 stress score after 24 hours (Target: <1%)
- % of wearable connections requiring manual intervention (Target: 0%)
- Average time from wearable connection to first vitality score (Target: <5 min)
- Number of orphaned `wearable_daily_metrics` rows (Target: 0)

---

## Notes

- The webhook handler fix is the **primary defense**
- Monitoring is the **early warning system**
- All other mitigations are **defense in depth**
- If the bug persists after all mitigations → Contact Rook support for SDK investigation
