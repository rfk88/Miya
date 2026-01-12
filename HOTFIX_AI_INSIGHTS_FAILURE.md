# HOTFIX: AI Insights Generation Failure

## Problem

After the metric-specific AI insights update, insights were failing to generate. The UI was showing raw `debugWhy` text instead of formatted AI insights:

```
serverPattern metric=steps pattern=drop_vs_baseline level=3 severity=watch...
```

## Root Causes

### 1. **Undefined Primary Metric**

The `primaryMetric` could be `undefined` if the metric wasn't found in the computed data:

```typescript
const primaryMetric = metricsData.find((m) => m.name === metricType);
// If not found, primaryMetric = undefined ❌
```

When passed to the AI prompt generation, accessing `primaryMetric.percent_change` would fail.

### 2. **Unsafe Template Function Calls**

The template functions (`getClinicalTemplate()`, `getPossibleCauses()`, `getActionSteps()`) were called during string array construction without error handling. Any error in these functions would break the entire prompt generation.

### 3. **No Error Handling for AI Call**

If the AI call failed for any reason, the entire function would error out instead of providing a fallback response.

## Fixes Applied

### Fix 1: Fallback for Primary Metric

```typescript
// If metric wasn't found in computed data, use alert's baseline/recent values as fallback
const primaryMetric = primaryMetricFound || {
  name: metricType,
  current_value: recentVal,
  baseline_value: baselineVal,
  percent_change: dev != null ? Math.round(dev * 100 * 10) / 10 : null,
  absolute_change: (recentVal != null && baselineVal != null) 
    ? Math.round((recentVal - baselineVal) * 10) / 10 
    : null,
};
```

Now `primaryMetric` is always defined with valid data.

### Fix 2: Safe Template Function Execution

```typescript
let clinicalTemplate = "";
try {
  clinicalTemplate = getClinicalTemplate();
} catch (e) {
  console.error("getClinicalTemplate failed:", e);
  clinicalTemplate = `A significant change in ${metricName} over ${consecutiveDays} days requires attention.`;
}

let possibleCauses: string[] = [];
try {
  possibleCauses = getPossibleCauses();
} catch (e) {
  console.error("getPossibleCauses failed:", e);
  possibleCauses = ["Physical factors", "Mental factors", "Lifestyle changes"];
}

let actionSteps: string[] = [];
try {
  actionSteps = getActionSteps();
} catch (e) {
  console.error("getActionSteps failed:", e);
  actionSteps = [
    `Check in with ${memberFirstName} about how they're feeling`,
    "Monitor for any concerning symptoms",
    "Provide support as needed",
    "Consult healthcare provider if pattern persists"
  ];
}
```

Each template function is now wrapped in try-catch with fallback values.

### Fix 3: AI Call Error Handling

```typescript
let ai: Omit<InsightResponse, "evidence">;
try {
  ai = await callOpenAI({ apiKey: openaiKey, model, evidence });
} catch (aiError) {
  console.error("❌ MIYA_AI_CALL_FAILED", {
    error: String(aiError),
    stack: (aiError as Error).stack,
    alertStateId,
    metricType,
    level,
  });
  
  // Return deterministic fallback if AI fails
  const msg = buildMessageSuggestions({ 
    memberFirstName: memberFirst, 
    metric: metricType, 
    level, 
    severity: sev 
  });
  
  const resp: InsightResponse = {
    headline: `${metricDisplay(metricType)} ${verb.verb}`,
    clinical_interpretation: `A ${Math.abs(pctChange).toFixed(1)}% change...`,
    data_connections: `Based on ${daysPresent} days of data...`,
    possible_causes: [],
    action_steps: [],
    message_suggestions: msg,
    confidence: daysPresent >= 18 ? "high" : "medium",
    confidence_reason: `AI generation failed: ${String(aiError).substring(0, 100)}`,
    evidence,
  };
  return jsonResponse({ ok: true, cached: false, model: "fallback", ...resp });
}
```

Now if the AI call fails, we return a deterministic fallback response instead of crashing.

### Fix 4: Safe Template Value Access

```typescript
const pct = Math.abs(primaryMetric?.percent_change || 0);
const baseline = primaryMetric?.baseline_value || 0;
const current = primaryMetric?.current_value || 0;
```

Using optional chaining (`?.`) to safely access metric values.

## Testing Checklist

After deploying, verify:

1. ✅ AI insights generate successfully
2. ✅ No raw `debugWhy` text appears in UI
3. ✅ All 4 metrics are included in the insight
4. ✅ Metric-specific language appears
5. ✅ Fallback works if AI fails (check logs for "MIYA_AI_CALL_FAILED")

## Deployment

```bash
cd supabase
supabase functions deploy miya_insight
```

Then rebuild iOS app (no code changes needed).

## Monitoring

Check Edge Function logs for any errors:
- ❌ `MIYA_AI_CALL_FAILED` - AI call failed, fallback used
- ⚠️ `getClinicalTemplate failed` - Template function error, using fallback
- ⚠️ `getPossibleCauses failed` - Causes function error, using fallback
- ⚠️ `getActionSteps failed` - Actions function error, using fallback

## Lessons Learned

1. **Always provide fallbacks** for critical data structures
2. **Wrap template functions** in try-catch when called during construction
3. **Handle AI failures gracefully** instead of crashing
4. **Use optional chaining** when accessing nested properties
5. **Test edge cases** (missing data, undefined values, errors)

## Files Changed

- ✅ `supabase/functions/miya_insight/index.ts` - Added error handling and fallbacks

**Status:** ✅ Fixed and ready to deploy
