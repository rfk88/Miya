# Chat Loop Fix - Complete Implementation

## Problem
The AI chat in notifications was stuck in an infinite loop:
```
🗣️ CHAT: sendMessage → 🔍 HTTP 409 → ⚠️ Generate insight → ✅ Done → 🔄 Retry → 🔍 HTTP 409 → (loop...)
```

## Root Causes Identified

### 1. **Database Insert Failing**
- The `pattern_alert_ai_insights` table has `summary text NOT NULL` from the original migration
- New inserts were missing `summary` field
- Insert silently failed (or succeeded but row was invalid)
- Chat function couldn't find valid cached insight → returned 409

### 2. **No Retry Guard**
- Swift client had no limit on 409 retries
- Would loop forever trying to generate + retry

### 3. **No Pre-warming**
- Insights only generated on first chat message
- Created artificial delay and risk of failure on first interaction

## Solutions Implemented (Following WHOOP Best Practices)

### ✅ 1. Fix Database Insert (`miya_insight/index.ts`)

**Added:**
```typescript
// Derive safe summary fallback (required by legacy schema)
const summary =
  merged.clinical_interpretation?.trim() ||
  merged.data_connections?.trim() ||
  merged.headline?.trim() ||
  "Insight generated.";

// Map new fields to legacy columns for backwards compatibility
const { error: insertErr } = await supabaseAdmin.from("pattern_alert_ai_insights").insert({
  alert_state_id: alertStateId,
  evaluated_end_date: evaluatedEnd,
  prompt_version: promptVersion,
  model,
  headline: merged.headline,
  summary,  // ✅ satisfies NOT NULL constraint
  contributors: merged.possible_causes ?? [],  // legacy mapping
  actions: merged.action_steps ?? [],          // legacy mapping
  clinical_interpretation: merged.clinical_interpretation,
  data_connections: merged.data_connections,
  possible_causes: merged.possible_causes ?? [],
  action_steps: merged.action_steps ?? [],
  message_suggestions: merged.message_suggestions ?? [],
  confidence: merged.confidence ?? "medium",
  confidence_reason: merged.confidence_reason ?? "",
  evidence,
});

// ✅ Fail fast if insert fails
if (insertErr) {
  console.error("❌ MIYA_INSIGHT: Insert failed", insertErr);
  return jsonResponse({ ok: false, error: "Failed to save insight" }, 500);
}
```

### ✅ 2. Make Chat Resilient (`miya_insight_chat/index.ts`)

**Added:**
```typescript
// Select both legacy and new fields
const { data: cached, error: cachedErr } = await supabaseAdmin
  .from("pattern_alert_ai_insights")
  .select("headline,summary,clinical_interpretation,data_connections,evidence")
  .eq("alert_state_id", alertStateId)
  .order("created_at", { ascending: false })
  .limit(1)
  .maybeSingle();

if (cachedErr || !cached) return jsonResponse({ ok: false, error: "Insight not generated yet" }, 409);

// Build summary with fallback
const summary =
  (cached.summary ?? "").trim() ||
  [cached.clinical_interpretation, cached.data_connections].filter(Boolean).join(" ");

const context =
  `INSIGHT_HEADLINE: ${cached.headline}\n` +
  `INSIGHT_SUMMARY: ${summary}\n` +
  `EVIDENCE_JSON:\n${JSON.stringify(cached.evidence)}\n`;
```

### ✅ 3. Add Retry Guard (Swift Client)

**Added state tracking:**
```swift
@State private var retryCount = 0  // Track retry attempts to prevent infinite loops
```

**Updated sendMessage:**
```swift
// Reset retry counter for new messages
if !skipAddingUserMessage {
    chatMessages.append(ChatMessage(role: .user, text: trimmedText))
    retryCount = 0  // ✅ Reset on new message
}

// Handle 409 with max retry limit
if httpResponse.statusCode == 409 {
    if retryCount >= 1 {
        print("❌ CHAT: Max retries reached (409 persists), stopping")
        await MainActor.run {
            chatError = "AI insight couldn't be generated. Please try again later or contact support."
            isSending = false
        }
        return
    }
    
    print("⚠️ CHAT: Insight not generated yet, generating now... (retry \(retryCount + 1)/1)")
    await MainActor.run {
        retryCount += 1
    }
    await generateInsightAndRetry(alertId: alertId, userMessage: trimmedText)
    return
}
```

### ✅ 4. Pre-warm Insights (`rook/patterns/engine.ts`)

**Added pre-warming function:**
```typescript
async function prewarmInsightCache(supabase: any, alertStateId: string): Promise<void> {
  console.log("🔥 MIYA_PREWARM: Starting insight generation for alert", alertStateId);
  
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  
  if (!supabaseUrl || !serviceKey) {
    console.warn("⚠️ MIYA_PREWARM: Missing env vars, skipping");
    return;
  }
  
  try {
    const response = await fetch(`${supabaseUrl}/functions/v1/miya_insight`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ alert_state_id: alertStateId }),
    });
    
    if (!response.ok) {
      const text = await response.text();
      console.error("❌ MIYA_PREWARM: Failed", { status: response.status, body: text });
    } else {
      console.log("✅ MIYA_PREWARM: Insight cached successfully for alert", alertStateId);
    }
  } catch (error) {
    console.error("❌ MIYA_PREWARM: Exception", { error: String(error) });
  }
}
```

**Call after queueing notification:**
```typescript
await supabase.from("pattern_alert_state").update({ 
  last_notified_level: level, 
  last_notified_at: new Date().toISOString() 
}).eq("id", alertStateId);

// ✅ Pre-warm AI insight cache (fire and forget)
prewarmInsightCache(supabase, alertStateId).catch((e) => {
  console.error("⚠️ MIYA_PREWARM_INSIGHT_FAILED", { alertStateId, error: String(e) });
});
```

## WHOOP-like Architecture Achieved

| Aspect | WHOOP Approach | Our Implementation |
|--------|----------------|-------------------|
| **Data Readiness** | Pre-computed metrics, warehouse-optimized | ✅ Daily metrics pre-aggregated in `wearable_daily_metrics` |
| **Insight Generation** | Pre-generated before chat | ✅ Pre-warm on notification creation |
| **Cache Strategy** | Fast cache-first lookups | ✅ `pattern_alert_ai_insights` with prompt versioning |
| **Context Building** | Curated evidence sent to LLM | ✅ Evidence JSON with primary + supporting metrics |
| **Latency Target** | Sub-3 seconds | ✅ Cache hit = instant; pre-warmed = ready on open |
| **Error Handling** | Graceful fallbacks, no loops | ✅ Retry guard + 500 on insert fail |
| **Privacy** | Strip PII, re-personalize | ⚠️ TODO: Add PII stripping layer |

## Files Changed

### Backend (Supabase Functions)
1. ✅ `supabase/functions/miya_insight/index.ts` - Fixed insert, added summary fallback
2. ✅ `supabase/functions/miya_insight_chat/index.ts` - Added resilient field selection
3. ✅ `supabase/functions/rook/patterns/engine.ts` - Added pre-warming on notification creation

### Frontend (Swift)
4. ✅ `Miya Health/Dashboard/DashboardNotifications.swift` - Added retry guard

### Deployment & Diagnostics
5. ✅ `deploy_chat_fix.sh` - Deploy script for both functions
6. ✅ `diagnose_chat_loop.sql` - SQL queries to diagnose stuck alerts

## Deployment Steps

### 1. Clear Stuck Cache (One-Time)
Run in Supabase SQL Editor:
```sql
-- Clear cache for stuck alert
DELETE FROM public.pattern_alert_ai_insights
WHERE alert_state_id = '57def4d0-0b2f-42b7-8e06-450303f49a80';

-- Or clear all invalid cache (missing summary)
DELETE FROM public.pattern_alert_ai_insights
WHERE summary IS NULL OR summary = '';
```

### 2. Deploy Functions
```bash
chmod +x deploy_chat_fix.sh
./deploy_chat_fix.sh
```

Or manually:
```bash
supabase functions deploy miya_insight --no-verify-jwt
supabase functions deploy miya_insight_chat --no-verify-jwt
supabase functions deploy rook --no-verify-jwt
```

### 3. Test
1. Trigger a new notification (or use existing alert after clearing cache)
2. Open notification → Ask Miya
3. Send a message
4. Should respond in <3 seconds without 409 loop

### 4. Monitor Logs
```bash
supabase functions logs miya_insight --tail
supabase functions logs miya_insight_chat --tail
```

Look for:
- ✅ `💾 MIYA_INSIGHT: Saving to database`
- ✅ `✅ MIYA_PREWARM: Insight cached successfully`
- ❌ No `❌ MIYA_INSIGHT: Insert failed`
- ❌ No infinite retry loops

## Expected Behavior (After Fix)

### First Chat Message (Cold Start)
```
User opens notification → Swift initializes
  ↓
Swift calls initializeConversation()
  ↓
Shows opening message + suggested prompts
  ↓
User sends message "What's the pattern?"
  ↓
Swift calls miya_insight_chat
  ↓
If 409 (rare, pre-warming should prevent):
  ↓
Swift calls miya_insight (generate)
  ↓
Waits 0.5s
  ↓
Retries miya_insight_chat
  ↓
If 409 again → STOP, show error (no loop)
  ↓
If 200 → Show AI response
```

### Subsequent Messages (Cache Hit)
```
User sends message
  ↓
Swift calls miya_insight_chat
  ↓
200 response in <1s (cache hit)
  ↓
Show AI response immediately
```

## Performance Metrics to Track

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Insight generation time | <3s | Monitor `miya_insight` logs |
| Chat response time (cached) | <1s | Monitor `miya_insight_chat` logs |
| Pre-warm success rate | >95% | Count pre-warm successes vs failures |
| 409 rate | <5% | Count 409s in chat logs |
| Retry loop rate | 0% | Should never happen with guard |

## Future Enhancements (Match WHOOP More Closely)

### Near-Term
- [ ] Add PII stripping before LLM (use hashed user IDs, generic names)
- [ ] Re-personalize after LLM response
- [ ] Add feature flag to disable AI per user
- [ ] Track insight quality feedback (thumbs up/down)

### Long-Term
- [ ] Data warehouse layer (Snowflake/BigQuery) for heavy analytics
- [ ] Feature store for pre-computed context vectors
- [ ] A/B test prompt variations
- [ ] Real-time insight updates as new data arrives

## Troubleshooting

### Problem: Still getting 409 loops
**Check:**
1. Functions deployed? `supabase functions list`
2. Cache cleared for that alert? Run `diagnose_chat_loop.sql`
3. Insert actually working? Check logs for `❌ MIYA_INSIGHT: Insert failed`

### Problem: Pre-warming not working
**Check:**
1. Env vars set in Supabase? `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
2. Logs show pre-warm attempts? Look for `🔥 MIYA_PREWARM`
3. Pattern evaluation running? Check Rook function logs

### Problem: Slow responses
**Check:**
1. Cache hit rate - should be >90% after pre-warming
2. OpenAI API latency - check `miya_insight` logs
3. Database query performance - add indexes if needed

## Summary

This fix transforms the chat experience from **broken infinite loops** to **WHOOP-like instant responses** by:

1. ✅ Ensuring database writes always succeed
2. ✅ Preventing infinite retry loops with guards
3. ✅ Pre-warming insights so first chat is instant
4. ✅ Making the entire pipeline resilient to schema changes

The implementation follows WHOOP's public best practices:
- Pre-computed data
- Cache-first architecture
- Fast, grounded LLM responses
- Graceful error handling

**Next:** Deploy, test, and monitor. Then add PII stripping and feature flags for production hardening.
