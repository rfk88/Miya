# Cache Validation Fix - AI Insights

## Problem Identified

**Root Cause:** The AI insight was returning a **cached response in the OLD format** instead of generating a new one.

### The Evidence

From the iOS log:
```
📥 AI_INSIGHT: Response data = {
  "ok": true,
  "cached": true,  // ← CACHED RESPONSE
  "summary": "...",        // ← OLD FORMAT
  "contributors": [...],   // ← OLD FORMAT
  "actions": [...],        // ← OLD FORMAT
  ...
}

📊 AI_INSIGHT: Parsed fields:
  - clinical_interpretation: nil...  // ← iOS app looking for NEW format
  - data_connections: nil...         // ← But it's not there!
  - possible_causes: 0 items
  - action_steps: 0 items
```

The cached entry was generated with an older prompt version (v2 or v3) that used:
- `summary` (not `clinical_interpretation`)
- `contributors` (not `possible_causes`)
- `actions` (not `action_steps`)
- No `data_connections` field

### Why This Happened

1. **Migration Timeline:**
   - Original schema had: `headline`, `summary`, `contributors`, `actions`
   - Later migration (20260111000000) ADDED: `clinical_interpretation`, `data_connections`, `possible_causes`, `action_steps`
   - Database now has **both sets of columns**

2. **Cache Problem:**
   - An old insight was cached with `prompt_version = 'v4'` (or an earlier version)
   - The new columns existed in the schema but were **NULL** in that cached row
   - The Edge Function found a cache hit and returned it
   - iOS app expected the new fields but got NULLs

3. **UI Behavior:**
   - iOS app checks for `clinical_interpretation` - it's `nil`
   - Falls back to showing the raw `debugWhy` text
   - User sees the technical debug string instead of the AI insight

## The Fix

Updated `miya_insight/index.ts` to **validate cached responses**:

### 1. Enhanced Cache Logging
```typescript
console.log("🔍 MIYA_INSIGHT: Cache query result", {
  alertStateId,
  found: !!cached,
  cachedPromptVersion: cached?.prompt_version,
  hasClinical: !!cached?.clinical_interpretation,
  hasConnections: !!cached?.data_connections,
  hasCauses: !!cached?.possible_causes,
  hasActions: !!cached?.action_steps,
  createdAt: cached?.created_at,
});
```

### 2. Cache Validation Logic
```typescript
if (cached && !cacheErr) {
  // Validate that the cached entry has the new format fields
  const hasNewFields = cached.clinical_interpretation && 
                       cached.data_connections && 
                       cached.possible_causes && 
                       cached.action_steps;
  
  if (hasNewFields) {
    console.log("💾 MIYA_INSIGHT: Cache hit (valid)");
    return jsonResponse({ ok: true, cached: true, ...cached });
  } else {
    console.log("⚠️ MIYA_INSIGHT: Cache hit but missing new fields, regenerating");
    
    // Delete the invalid cached entry
    await supabaseAdmin
      .from("pattern_alert_ai_insights")
      .delete()
      .eq("alert_state_id", alertStateId)
      .eq("evaluated_end_date", evaluatedEnd)
      .eq("prompt_version", promptVersion);
  }
}
```

### 3. Flow After Fix

1. **Cache Query:** Finds cached entry
2. **Validation:** Checks if `clinical_interpretation`, `data_connections`, `possible_causes`, `action_steps` are present
3. **If Valid:** Returns cached response (fast path)
4. **If Invalid:** 
   - Logs warning
   - Deletes invalid cache entry
   - Falls through to regeneration logic
5. **Regeneration:** Calls OpenAI with new prompt
6. **Cache Update:** Saves new response with all required fields
7. **Return:** Sends new response to iOS app

## How to Test

### 1. Pull to Refresh
In the iOS app, **swipe down** on the dashboard to refresh the family notifications.

### 2. Tap on Ahmed's Notification Again
This will trigger `fetchAIInsightIfPossible()`.

### 3. Expected Logs (Xcode)
```
🤖 AI_INSIGHT: fetchAIInsightIfPossible() called for Ahmed
✅ AI_INSIGHT: Found alertStateId = 6a4b42d3-2be9-4bcf-ab70-6cc2a31d37d8
🌐 AI_INSIGHT: Calling Edge Function...
📥 AI_INSIGHT: Response status = 200
📊 AI_INSIGHT: Parsed fields:
  - clinical_interpretation: Over the last 21 days...  ← NOT nil!
  - data_connections: Ahmed's recent average...        ← NOT nil!
  - possible_causes: 3 items                           ← NOT 0!
  - action_steps: 4 items                              ← NOT 0!
```

### 4. Expected Logs (Edge Function)
```bash
supabase functions logs miya_insight --follow
```

```
🎯 MIYA_INSIGHT: Request received
✅ MIYA_INSIGHT: Authenticated
📦 MIYA_INSIGHT: Request body { alertStateId: "6a4b42d3-..." }
🔍 MIYA_INSIGHT: Cache query result {
  found: true,
  hasClinical: false,  ← Old cache found with missing fields
  hasConnections: false,
  hasCauses: false,
  hasActions: false
}
⚠️ MIYA_INSIGHT: Cache hit but missing new fields, regenerating
📊 MIYA_INSIGHT: Evidence prepared { metricType: "steps", level: 3, ... }
🤖 MIYA_INSIGHT: Calling OpenAI { model: "gpt-4.1-mini" }
✅ MIYA_INSIGHT: OpenAI call succeeded {
  headline: "...",
  hasInterpretation: true,
  hasConnections: true,
  causesCount: 3,
  actionsCount: 4
}
💾 MIYA_INSIGHT: Saving to database
✅ MIYA_INSIGHT: Returning final response
```

### 5. Expected UI
The "What's going on?" section should now display:
- ✅ **Metric Comparison Card** (Baseline, Current, Optimal)
- ✅ **Clinical Interpretation** section (with clinical context)
- ✅ **Data Connections** section (explaining the metrics)
- ✅ **Possible Causes** section (3 items with light red background)
- ✅ **Action Steps** section (4 items with severity-specific colors)

**NOT** the raw `debugWhy` text.

## Monitoring

### Watch for Future Issues
```bash
# Monitor for cache validation warnings
supabase functions logs miya_insight --follow | grep "⚠️"

# Monitor for errors
supabase functions logs miya_insight --follow | grep "❌"
```

### Health Check
After deploying, check that new insights are being generated:
```sql
-- Check recent insights
SELECT 
  alert_state_id,
  prompt_version,
  created_at,
  clinical_interpretation IS NOT NULL as has_clinical,
  data_connections IS NOT NULL as has_connections,
  possible_causes IS NOT NULL as has_causes,
  action_steps IS NOT NULL as has_actions
FROM public.pattern_alert_ai_insights
ORDER BY created_at DESC
LIMIT 10;
```

All recent entries should have:
- `prompt_version = 'v4'`
- All "has_*" columns = `true`

## Prevention

This fix ensures that:
1. **No more silent cache failures** - Invalid cache entries are detected and logged
2. **Auto-healing** - Invalid cache entries are deleted and regenerated automatically
3. **Forward compatibility** - Future prompt updates will automatically invalidate old caches
4. **Observability** - Comprehensive logging shows exactly what's happening

## Files Changed

- `/Users/ramikaawach/Desktop/Miya/supabase/functions/miya_insight/index.ts`
  - Added cache validation logic
  - Added cache query result logging
  - Added automatic invalid cache deletion

## Deployment

```bash
./deploy_cache_fix.sh
```

This deploys the updated `miya_insight` Edge Function with:
- ✅ Cache validation
- ✅ Auto-cleanup of invalid cache
- ✅ Enhanced logging
- ✅ All previous hotfixes (null checks, error handling)
