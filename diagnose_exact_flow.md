# DIAGNOSIS: Why Chat Loop is Still Happening

## Key Finding: Query Mismatch Hypothesis

### miya_insight Cache Query (Line 635-643)
```typescript
const { data: cached, error: cacheErr } = await supabaseAdmin
  .from("pattern_alert_ai_insights")
  .select("...")
  .eq("alert_state_id", alertStateId)
  .eq("evaluated_end_date", evaluatedEnd)      // ⚠️ FILTERS BY DATE
  .eq("prompt_version", promptVersion)         // ⚠️ FILTERS BY VERSION
  .order("created_at", { ascending: false })
  .limit(1)
  .maybeSingle();
```

### miya_insight_chat Query (Line 132-138)
```typescript
const { data: cached, error: cachedErr } = await supabaseAdmin
  .from("pattern_alert_ai_insights")
  .select("headline,summary,clinical_interpretation,data_connections,evidence")
  .eq("alert_state_id", alertStateId)          // ✅ ONLY FILTERS BY ALERT ID
  .order("created_at", { ascending: false })
  .limit(1)
  .maybeSingle();
```

### Analysis
- miya_insight uses 3 filters: alert_state_id + evaluated_end_date + prompt_version
- miya_insight_chat uses 1 filter: alert_state_id only
- This SHOULD work because chat's query is less restrictive

## Possible Root Causes

### 1. **Unique Constraint Conflict** (MOST LIKELY)
The table has this unique index:
```sql
create unique index idx_pattern_alert_ai_insights_unique
  on pattern_alert_ai_insights(alert_state_id, evaluated_end_date, prompt_version);
```

If a row already exists with:
- alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
- evaluated_end_date = (whatever date)
- prompt_version = 'v4'

Then the insert will fail with a unique constraint violation.

**But:** We added error handling that should return 500 if insert fails. So either:
- The error handler isn't catching this type of error
- The function is crashing before reaching the error handler

### 2. **RLS Policy Blocking Read**
The RLS policy for pattern_alert_ai_insights:
```sql
create policy pattern_alert_ai_insights_read_family
on public.pattern_alert_ai_insights
for select
to authenticated
using (
  exists (
    select 1
    from public.pattern_alert_state pas
    join public.family_members me on me.user_id = auth.uid()
    join public.family_members them on them.family_id = me.family_id and them.user_id = pas.user_id
    where pas.id = pattern_alert_ai_insights.alert_state_id
  )
);
```

**But:** Both functions use `supabaseAdmin` which uses service role key and bypasses RLS.

### 3. **Insert Success But Validation Fails** (LIKELY)
Look at miya_insight lines 656-681:
```typescript
if (cached && !cacheErr) {
  const hasNewFields = cached.clinical_interpretation && cached.data_connections && 
                       cached.possible_causes && cached.action_steps;
  
  if (hasNewFields) {
    return jsonResponse({ ok: true, cached: true, ...cached });
  } else {
    // Delete the invalid cached entry
    await supabaseAdmin.from("pattern_alert_ai_insights").delete()...
  }
}
```

If the OpenAI response is missing any of these fields, miya_insight deletes the row and regenerates.
But what if OpenAI keeps returning incomplete responses?

### 4. **Timing Issue**
Swift waits 0.5s after calling miya_insight before retrying chat:
```swift
try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
```

What if the insert takes longer than 0.5s to commit?

### 5. **OpenAI API Failure**
If OpenAI is failing or timing out, the function might:
- Return fallback response (which we do)
- But the fallback might not have all required fields
- Or the insert might fail silently

## What We Need to Check

### Check 1: Is the insert actually being called?
Look for this log in miya_insight:
```
💾 MIYA_INSIGHT: Saving to database
```

### Check 2: Is the insert failing?
Look for this log:
```
❌ MIYA_INSIGHT: Insert failed
```

### Check 3: What does the 409 error body say?
The Swift logs show:
```
🔍 CHAT: HTTP status = 409
```

But we need to see what the error body contains. The code at line 1071-1072 should print it:
```swift
let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
print("❌ CHAT: Error body: \(errorBody)")
```

### Check 4: Is there already a stale row in the DB?
Query the database:
```sql
SELECT 
  id,
  created_at,
  alert_state_id,
  evaluated_end_date,
  prompt_version,
  headline,
  summary IS NOT NULL as has_summary,
  clinical_interpretation IS NOT NULL as has_clinical,
  data_connections IS NOT NULL as has_data
FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80'
ORDER BY created_at DESC;
```

### Check 5: What is evaluated_end_date for this alert?
Query:
```sql
SELECT 
  id,
  user_id,
  metric_type,
  pattern_type,
  active_since,
  last_evaluated_date
FROM public.pattern_alert_state
WHERE id = '57def4d0-0b2f-42b7-8e06-450303f49a80';
```

## Most Likely Diagnosis

Based on the code, the most likely cause is:

**The unique constraint is preventing the insert, but the error isn't being logged/returned properly.**

When miya_insight is called:
1. It checks for existing cache (lines 635-643)
2. Finds nothing (or invalid row)
3. Generates new insight
4. Tries to insert (line 979)
5. **Insert fails with unique violation** (row already exists)
6. Error handler should catch it (line 998-1001)
7. Should return 500
8. But Swift logs show it's getting "✅ CHAT: Insight generated" which means 200 response

**This suggests the insert is NOT failing, but the row that's inserted is somehow not being found by chat.**

## Next Steps for Real Diagnosis

1. Check Supabase function logs for miya_insight
2. Check if there's actually a row in the DB for this alert
3. Compare evaluated_end_date in the alert vs the cached insight
4. Check if OpenAI is returning complete responses
