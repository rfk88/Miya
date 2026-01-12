# Diagnostic Logging Guide

## Problem
AI insights were not generating, and there were NO logs in either:
- Xcode console (iOS app)
- Supabase Edge Function logs

This made it impossible to diagnose the issue.

## Solution: Comprehensive Logging Added

### iOS App Logging (DashboardView.swift)

**Added logging to `fetchAIInsightIfPossible()`:**

1. **Entry point:**
   ```
   🤖 AI_INSIGHT: fetchAIInsightIfPossible() called for [member name]
   🤖 AI_INSIGHT: debugWhy = [value]
   ```

2. **Guard checks (previously silent failures):**
   ```
   ❌ AI_INSIGHT: No debugWhy found - exiting
   ❌ AI_INSIGHT: debugWhy does not contain 'serverPattern' - exiting
   ❌ AI_INSIGHT: Could not extract alertStateId from debugWhy - exiting
   ```

3. **Success path:**
   ```
   ✅ AI_INSIGHT: Found alertStateId = [uuid]
   🌐 AI_INSIGHT: Calling Edge Function at [url]
   🌐 AI_INSIGHT: Payload = {"alert_state_id": "[uuid]"}
   ```

4. **Response logging:**
   ```
   📥 AI_INSIGHT: Response status = [code]
   📥 AI_INSIGHT: Response data = [json]
   ```

5. **Data parsing:**
   ```
   📊 AI_INSIGHT: Parsed fields:
     - headline: [value]
     - clinical_interpretation: [preview]...
     - data_connections: [preview]...
     - possible_causes: [count] items
     - action_steps: [count] items
     - evidence baseline: [value]
     - evidence recent: [value]
     - evidence deviation: [value]
     - message_suggestions: [count] items
   ```

6. **Error handling:**
   ```
   ❌ AI_INSIGHT: Error occurred: [error]
   ❌ AI_INSIGHT: Error description: [description]
   ❌ AI_INSIGHT: Error type: [type]
   ❌ AI_INSIGHT: URLError code: [code] (if URLError)
   ❌ AI_INSIGHT: NSError domain: [domain] (if NSError)
   ❌ AI_INSIGHT: NSError code: [code] (if NSError)
   ❌ AI_INSIGHT: NSError userInfo: [info] (if NSError)
   ```

### Edge Function Logging (miya_insight/index.ts)

**Added logging at every critical step:**

1. **Entry point:**
   ```
   🎯 MIYA_INSIGHT: Request received
   🔧 MIYA_INSIGHT: Config { enabled, logPayloads }
   ```

2. **Authentication:**
   ```
   ✅ MIYA_INSIGHT: Authenticated { callerId }
   OR
   ❌ MIYA_INSIGHT: Missing bearer token
   ❌ MIYA_INSIGHT: Auth failed { error }
   ```

3. **Request parsing:**
   ```
   📦 MIYA_INSIGHT: Request body { body, alertStateId }
   OR
   ❌ MIYA_INSIGHT: Missing alert_state_id
   ```

4. **Cache check:**
   ```
   💾 MIYA_INSIGHT: Cache hit { alertStateId, promptVersion }
   OR
   🔄 MIYA_INSIGHT: Cache miss, generating new insight { alertStateId, promptVersion }
   ```

5. **Evidence preparation:**
   ```
   📊 MIYA_INSIGHT: Evidence prepared {
     alertStateId,
     metricType,
     level,
     consecutiveDays,
     primaryMetric,
     supportingMetrics,
     daysPresent
   }
   ```

6. **AI call:**
   ```
   🤖 MIYA_INSIGHT: Calling OpenAI { model, alertStateId, metricType }
   ✅ MIYA_INSIGHT: OpenAI call succeeded {
     headline,
     hasInterpretation,
     hasConnections,
     causesCount,
     actionsCount
   }
   OR
   ❌ MIYA_AI_CALL_FAILED { error, stack, alertStateId, metricType, level }
   ```

7. **Database save:**
   ```
   💾 MIYA_INSIGHT: Saving to database { alertStateId, promptVersion }
   ```

8. **Final response:**
   ```
   ✅ MIYA_INSIGHT: Returning final response {
     alertStateId,
     headline (preview),
     hasInterpretation
   }
   ```

9. **Top-level error:**
   ```
   ❌ MIYA_INSIGHT_ERROR { error, stack, message }
   ```

## How to Use

### 1. Deploy the changes:
```bash
./deploy_diagnostic_logs.sh
```

### 2. Rebuild iOS app:
In Xcode: **Cmd+B**

### 3. Run the app and trigger an AI insight:
- Open dashboard
- Tap on a family notification
- Wait for the "What's going on?" section to load

### 4. Check Xcode console:
Look for logs starting with:
- `🤖 AI_INSIGHT:`
- `❌ AI_INSIGHT:`
- `✅ AI_INSIGHT:`
- `📊 AI_INSIGHT:`
- `🌐 AI_INSIGHT:`
- `📥 AI_INSIGHT:`

### 5. Check Supabase Edge Function logs:
```bash
supabase functions logs miya_insight --follow
```

Look for logs starting with:
- `🎯 MIYA_INSIGHT:`
- `📊 MIYA_INSIGHT:`
- `🤖 MIYA_INSIGHT:`
- `✅ MIYA_INSIGHT:`
- `❌ MIYA_INSIGHT:`
- `💾 MIYA_INSIGHT:`

## What to Look For

### Scenario 1: iOS app never calls Edge Function
**Symptoms:**
- Xcode shows: `❌ AI_INSIGHT: No debugWhy found - exiting`
- OR: `❌ AI_INSIGHT: debugWhy does not contain 'serverPattern' - exiting`
- OR: `❌ AI_INSIGHT: Could not extract alertStateId from debugWhy - exiting`
- No Edge Function logs

**Root cause:** The notification is not a server pattern alert, or `debugWhy` is malformed.

**Fix:** Check why the alert doesn't have the correct `debugWhy` format. Look at `fetchServerPatternAlerts()`.

### Scenario 2: Edge Function never receives request
**Symptoms:**
- Xcode shows: `🌐 AI_INSIGHT: Calling Edge Function at [url]`
- No Edge Function logs with `🎯 MIYA_INSIGHT: Request received`

**Root cause:** Network issue, Edge Function not deployed, or wrong URL.

**Fix:** Check deployment status, network connectivity.

### Scenario 3: Edge Function receives request but fails auth
**Symptoms:**
- Edge Function shows: `❌ MIYA_INSIGHT: Missing bearer token`
- OR: `❌ MIYA_INSIGHT: Auth failed`

**Root cause:** JWT token issue.

**Fix:** Check Supabase auth session in iOS app.

### Scenario 4: Edge Function fails to prepare evidence
**Symptoms:**
- Edge Function shows: `📦 MIYA_INSIGHT: Request body { ... }`
- Then immediately: `❌ MIYA_INSIGHT_ERROR`
- No `📊 MIYA_INSIGHT: Evidence prepared`

**Root cause:** Database query failure, missing data, or logic error in evidence preparation.

**Fix:** Check the error details in the log to see what failed.

### Scenario 5: AI call fails
**Symptoms:**
- Edge Function shows: `🤖 MIYA_INSIGHT: Calling OpenAI`
- Then: `❌ MIYA_AI_CALL_FAILED`

**Root cause:** OpenAI API issue, invalid prompt, or JSON parsing error.

**Fix:** Check OpenAI API key, quota, and the error details in the log.

### Scenario 6: Success but iOS doesn't show it
**Symptoms:**
- Edge Function shows: `✅ MIYA_INSIGHT: Returning final response`
- Xcode shows: `📥 AI_INSIGHT: Response status = 200`
- But UI still shows raw `debugWhy`

**Root cause:** UI rendering issue, or data not being assigned to state variables.

**Fix:** Check the `📊 AI_INSIGHT: Parsed fields` log to see if data was extracted correctly.

## Monitoring Commands

**Watch Edge Function logs:**
```bash
supabase functions logs miya_insight --follow
```

**Filter for errors only:**
```bash
supabase functions logs miya_insight --follow | grep "❌"
```

**Watch Xcode console:**
Use Xcode's console filter: `AI_INSIGHT`

## Cleanup

Once the issue is diagnosed and fixed, you can remove some of the verbose logging if desired, but it's recommended to keep:
- Entry/exit logs
- Error logs
- Key decision point logs (guard failures, cache hits/misses)
