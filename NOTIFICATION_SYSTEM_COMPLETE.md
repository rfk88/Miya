# Notification System - Complete Documentation

## Overview

Miya has a **two-tier notification system**:

1. **Server-Side Pattern Alerts** - Baseline-driven alerts based on wearable metrics (sleep, steps, HRV, resting HR, etc.)
2. **Client-Side Trend Insights** - Dashboard-generated alerts based on vitality pillar score trends

Both systems analyze health patterns. **Server pattern alerts** at higher escalation levels (about one week and beyond) also notify **other accepted family members on Miya**, not only the person whose metrics changed.

---

## Architecture

### Database Tables

#### 1. `pattern_alert_state`
**Location**: `supabase/migrations/20260109120000_add_pattern_alerts.sql`

Stores active and resolved pattern alert episodes.

**Key Fields**:
- `user_id` - The family member whose metrics triggered the alert
- `metric_type` - `sleep_minutes`, `steps`, `hrv_ms`, `resting_hr`, `sleep_efficiency_pct`, `movement_minutes`, `deep_sleep_minutes`
- `pattern_type` - `drop_vs_baseline` or `rise_vs_baseline`
- `episode_status` - `active` or `resolved`
- `current_level` - Alert level: `3`, `7`, `14`, or `21` (days)
- `last_notified_level` - Last level that triggered a notification
- `active_since` - Date when the pattern episode started
- `baseline_value`, `recent_value`, `deviation_percent` - Metrics for explainability

**Indexes**:
- Unique constraint on `(user_id, metric_type, pattern_type, active_since)` - prevents duplicate active episodes
- Index on `(user_id, episode_status, current_level)` - fast lookups for active alerts

#### 2. `notification_queue`
**Location**: `supabase/migrations/20260109120000_add_pattern_alerts.sql`

Queue for pending notifications to be sent via push, WhatsApp, SMS, etc.

**Key Fields**:
- `recipient_user_id` - Who receives the row (the member themselves, another family member, or an admin depending on `payload` / notification kind)
- `member_user_id` - Who the alert is about
- `alert_state_id` - Links to `pattern_alert_state.id`
- `channel` - `push`, `whatsapp`, `sms`, `email`
- `payload` - JSONB with alert details
- `status` - `pending`, `sent`, `failed`, `skipped` (preferences, missing APNs config, or no push template)
- `attempts`, `last_error`, `sent_at` - Retry tracking

**Status**: The **`process_notifications`** Edge Function (`supabase/functions/process_notifications/index.ts`) processes pending rows: checks `notify_push`, quiet hours, snooze/dismiss; sends **iOS push via APNs** when configured; marks rows `sent`, `failed`, or `skipped`. Schedule a cron (or external job) to **POST** this function every 1–5 minutes with header `x-miya-admin-secret`. In-app bell items come from **`get_bell_notifications`** (typically `pending` / `sent` only). Ops checklist: `supabase/ops/notifications-environment.txt`.

---

## 1. Server-Side Pattern Alerts (Baseline-Driven)

### How They Work

Pattern alerts detect when a user's daily metrics deviate significantly from their baseline average.

**Baseline Calculation**:
- Uses 14-21 days of historical data
- Calculates average for baseline period
- Compares recent 3-day average to baseline
- Triggers if deviation exceeds threshold (typically 20%+ drop or rise)

**Alert Levels** (escalation based on duration):
- **Level 3**: 3-6 consecutive days of pattern
- **Level 7**: 7-13 consecutive days
- **Level 14**: 14-20 consecutive days  
- **Level 21**: 21+ consecutive days

**Severity Mapping**:
- Level ≤6 → `watch`
- Level 7-13 → `attention`
- Level ≥14 → `critical`

### Trigger Points

#### 1. **Rook Webhook** (`supabase/functions/rook/index.ts`)
**When**: Every time Rook sends wearable data (daily summaries, events)

**Flow**:
```
Rook webhook received
  ↓
Parse and store metrics in wearable_daily_metrics
  ↓
Recompute vitality scores
  ↓
Evaluate patterns for user (evaluatePatternsForUser)
  ↓
If pattern detected → Create/update pattern_alert_state
  ↓
If should notify → Insert into notification_queue
```

**Code Location**: `supabase/functions/rook/index.ts:760-767`

```typescript
// After storing metrics and recomputing scores
const res = await evaluatePatternsForUser(supabase, { 
  userId, 
  endDate: metricDate 
});
```

#### 2. **Daily Recompute Cron** (`supabase/functions/rook_daily_recompute/index.ts`)
**When**: Scheduled daily (via Supabase cron or external scheduler)

**Flow**:
```
Cron triggers rook_daily_recompute
  ↓
Find users with recent metrics (last 2 days)
  ↓
For each user:
  - Recompute vitality scores
  - Evaluate patterns (if pattern evaluation added)
```

**Note**: Currently only recomputes scores, but could be extended to evaluate patterns.

**Code Location**: `supabase/functions/rook_daily_recompute/index.ts`

### Pattern Evaluation Logic

**File**: `supabase/functions/rook/patterns/engine.ts`

**Function**: `evaluatePatternsForUser(supabase, { userId, endDate })`

**Process**:

1. **Fetch Metrics** (last 60 days)
   - Queries `wearable_daily_metrics` table
   - Merges multiple sources per day (takes max value)
   - Metrics: `steps`, `sleep_minutes`, `hrv_ms`, `resting_hr`, `sleep_efficiency_pct`, `movement_minutes`, `deep_sleep_minutes`

2. **Fetch Exercise Context**
   - Queries `exercise_sessions` to get workout dates
   - **Important**: Skips recovery alerts (HRV/resting HR) on workout days
   - Prevents false "poor recovery" alerts when exercise is healthy

3. **For Each Metric**:
   - Build time series from merged data
   - Evaluate pattern on `endDate` using `evaluateMetricOnDate()`
   - Check if pattern is true (deviation exceeds threshold)
   
4. **If Pattern Detected**:
   - Walk backwards to find episode start date
   - Calculate duration in days
   - Determine alert level (3, 7, 14, 21)
   - Upsert `pattern_alert_state` record
   - Check if notification should be enqueued

5. **Notification Enqueueing**:
   ```typescript
   const enqueue = shouldEnqueueNotification({
     shadowMode,
     newLevel: level,
     lastNotifiedLevel: lastNotifiedLevel,
   });
   ```
   
   **Rules** (`supabase/functions/rook/patterns/episode.ts:19-28`):
   - If `shadowMode=true` → Never enqueue (testing mode)
   - If `lastNotifiedLevel=null` → Always enqueue (first alert)
   - If `newLevel > lastNotifiedLevel` → Enqueue (escalation)
   - Otherwise → Skip (already notified at this level)

6. **If Enqueueing**:
   - Fetch family admin recipients (superadmin/admin roles)
   - For each recipient, insert into `notification_queue`
   - Update `pattern_alert_state.last_notified_level` and `last_notified_at`
   - Pre-warm AI insight cache (fire and forget)

7. **Resolution Logic**:
   - If pattern is no longer true for 2-3 consecutive days → Mark episode as `resolved`
   - Uses hysteresis (5% threshold) to prevent flip-flopping

### Shadow Mode

**Environment Variable**: `MIYA_PATTERN_SHADOW_MODE`

- **Default**: `true` (alerts are evaluated but not enqueued)
- **Production**: Set to `false` to enable notifications
- **Purpose**: Allows testing pattern detection without sending notifications

**Code Location**: `supabase/functions/rook/patterns/engine.ts:321`

```typescript
const shadowMode = (Deno.env.get("MIYA_PATTERN_SHADOW_MODE") ?? "true").toLowerCase() !== "false";
```

### Metrics Evaluated

1. **Sleep Minutes** (`sleep_minutes`)
   - Pattern: `drop_vs_baseline`
   - Threshold: 20%+ drop

2. **Steps** (`steps`)
   - Pattern: `drop_vs_baseline`
   - Threshold: 20%+ drop

3. **HRV (Heart Rate Variability)** (`hrv_ms`)
   - Pattern: `drop_vs_baseline`
   - Threshold: 20%+ drop
   - **Special**: Skipped on workout days (exercise context)

4. **Resting Heart Rate** (`resting_hr`)
   - Pattern: `rise_vs_baseline` (higher is worse)
   - Threshold: 20%+ rise
   - **Special**: Skipped on workout days (exercise context)

5. **Sleep Efficiency** (`sleep_efficiency_pct`) - NEW
   - Pattern: `drop_vs_baseline`

6. **Movement Minutes** (`movement_minutes`) - NEW
   - Pattern: `drop_vs_baseline`

7. **Deep Sleep Minutes** (`deep_sleep_minutes`) - NEW
   - Pattern: `drop_vs_baseline`

### Threshold Configuration

**File**: `supabase/functions/rook/patterns/thresholds.v1.json`

Defines thresholds and pattern types for each metric.

---

## 2. Client-Side Trend Insights (Dashboard-Generated)

### How They Work

Trend insights analyze **vitality pillar scores** (Sleep, Movement, Stress) over a 21-day window to detect trends.

**Key Difference**: Pattern alerts use raw metrics (steps, sleep minutes), while trend insights use computed vitality scores (0-100 scale).

### Trigger Points

#### 1. **Dashboard Initial Load** (`DashboardView.swift`)
**When**: App launches, user opens dashboard

**Code Location**: `Miya Health/DashboardView.swift:528-557`

```swift
.task {
    await computeTrendInsights()
}
```

#### 2. **Pull-to-Refresh**
**When**: User pulls down on dashboard

**Code Location**: `Miya Health/DashboardView.swift:360-387`

```swift
.refreshable {
    await computeTrendInsights()
}
```

#### 3. **After Debug Record Creation**
**When**: User adds test data via debug tools

**Code Location**: `Miya Health/DashboardView.swift:783` (approximate)

#### 4. **After API Wearable Connection**
**When**: User connects Oura/Whoop/Fitbit via API

**Code Location**: `Miya Health/RiskResultsView.swift:865-875`

```swift
.onReceive(NotificationCenter.default.publisher(for: .apiWearableConnected)) { _ in
    await computeWearableVitalityIfAvailable()
}
```

### Eligibility Requirements

**Location**: `Miya Health/DashboardView.swift:1606-1615`

Member must pass **ALL** of these:
- ✅ `!member.isPending` - Not a pending invite
- ✅ `member.hasScore` - Has at least one vitality score
- ✅ `member.isScoreFresh` - Score updated within last 3 days
- ✅ `!member.isMe` - **EXCLUDES the logged-in user** (only family members)
- ✅ `member.userId != nil` - Has a valid user ID

### Data Requirements

**Location**: `Miya Health/FamilyVitalityTrendEngine.swift:169`

- **Minimum**: 7 days of history data
- **Window**: 21 days analyzed
- **Source**: `vitality_scores` table via `dataManager.fetchMemberVitalityScoreHistory(userIds:days:21)`

If coverage insufficient → Returns empty insights, sets `hasMinimumCoverage = false`

### Alert Rules

**Location**: `Miya Health/FamilyVitalityTrendEngine.swift:352-463` (`analyzePillar`)

For each pillar (Sleep, Movement, Stress), checks 3 rules:

#### Rule 1: "3-Day Streak Low" → `.attention` severity
- **Condition**: Last 3 days are ALL in the bottom quartile of the 14-day range
- **AND**: Has a consecutive streak of at least 3 days

#### Rule 2: "20%+ Drop vs Baseline" → `.attention` severity
- **Condition**: Recent 3-day average is >= 20% lower than baseline 7-day average
- **Requires**: At least 5 days of baseline data

#### Rule 3: "15%+ Rebound" → `.celebrate` severity
- **Condition**: Recent 3-day average is >= 15% higher than baseline 7-day average
- **Requires**: At least 5 days of baseline data

**Important**: Rules checked in order. First match wins. Only ONE insight per pillar per member.

### Insight Selection

**Location**: `Miya Health/FamilyVitalityTrendEngine.swift:520-547` (`selectTopInsights`)

After all insights generated:
- **Up to 2 `.attention` insights** (prefer different members)
- **If no attention insights**: Add 1 `.celebrate` insight
- **Maximum 2 insights total** returned

### Filtering

**Location**: `Miya Health/DashboardView.swift:6019-6065` (`FamilyNotificationItem.build`)

#### Filter 1: Coverage Gate
```swift
if trendCoverage?.hasMinimumCoverage == true, !trendInsights.isEmpty {
    // Only proceed if coverage is sufficient
}
```

#### Filter 2: Name Filter
```swift
.filter { !$0.memberName.isEmpty }
```

#### Filter 3: Relevance Filter
```swift
.filter { ins in
    switch ins.severity {
    case .attention, .watch:
        return isStillRelevantNegativeAlert(memberUserId: ins.memberUserId, pillar: ins.pillar)
    case .celebrate:
        return true
    }
}
```

**`isStillRelevantNegativeAlert`** (line 6003):
- Gets current pillar score from `vitalityFactors`
- **If current score >= 85**: **FILTERS OUT** the alert
- **If current score < 85**: Keeps the alert
- **If no current score available**: Keeps the alert

**This is why alerts disappear!** If member's current score improved to 85+, the alert is suppressed even though the trend still exists.

### UI Display Conditions

**Location**: `Miya Health/DashboardView.swift:581-594`

All of these must be true:
1. ✅ `familySnapshot != nil`
2. ✅ `familyVitalityScore != nil`
3. ✅ `!isComputingTrendInsights` (computation finished)
4. ✅ `notifications.isEmpty == false` (after filtering)

If ANY condition fails, no notifications card is shown.

---

## 3. Notification Display & Refresh

### Server Pattern Alerts Display

**RPC Function**: `get_family_pattern_alerts(family_id)`

**Location**: `supabase/migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql`

**Returns**: Active pattern alerts for all family members

**Authorization**: Caller must be a family member

**Client Fetch**:
- **Function**: `fetchServerPatternAlerts()` in `DashboardView.swift:1655`
- **Called from**: `loadServerPatternAlerts()` in `DashboardView.swift:1476`

**Refresh Triggers**:
1. **App Launch** (`.task` modifier)
2. **Pull-to-Refresh**
3. **After Family Member Load**
4. **After Vitality Update**

**Code Locations**:
- `DashboardView.swift:538` - Initial load
- `DashboardView.swift:370` - Pull-to-refresh
- `DashboardView.swift:479, 498, 520` - After various updates

### Client Trend Insights Display

**Function**: `computeTrendInsights()` in `DashboardView.swift:1597`

**Refresh Triggers**: Same as above (app launch, pull-to-refresh, etc.)

### Notification Priority

**Location**: `DashboardView.swift:270`

```swift
let notifications = serverPatternAlerts.isEmpty ? trendNotifications : serverPatternAlerts
```

**Logic**: Server pattern alerts take priority. If server alerts exist, show those. Otherwise, show client trend insights.

---

## 4. Notification Preferences

### User Settings

**Location**: `Miya Health/EditProfileView.swift:460-486`

**Settings Available**:
- **In-app notifications**: `notifyInApp` (default: `true`)
- **Push notifications**: `notifyPush` (default: `false`)
- **Email notifications**: `notifyEmail` (default: `false`)

### Legacy champion columns (`user_profiles`)

The database still has optional `champion_*` columns from an older **health-advocate** feature. The app no longer exposes that UI; completing **Privacy & Alerts** onboarding calls `saveAlertPreferences`, which clears champion flags and contact fields and disables champion notify columns.

### Quiet Hours

**Location**: `Miya Health/EditProfileView.swift:479-484`

- **Quiet hours start**: `quietHoursStart` (default: 22:00)
- **Quiet hours end**: `quietHoursEnd` (default: 07:00)
- **Apply to critical alerts**: `quietHoursApplyCritical` (default: `false`)

**Storage**: `user_profiles` table

**Migration**: `supabase/migrations/20260109183000_edit_profile_foundations.sql`

---

## 5. Notification Queue Processing

### Current Status

**Implemented** — Worker: `supabase/functions/process_notifications/index.ts`.

- **Auth**: POST requires non-empty `MIYA_ADMIN_SECRET`; caller sends `x-miya-admin-secret`.
- **Batching**: Default `batchSize` 50, default `maxAge` 72 hours (override in JSON body).
- **Push (iOS)**: JWT auth to Apple APNs; production host by default; set **`APNS_USE_SANDBOX=true`** for sandbox tokens (common for some dev/TestFlight setups).
- **Outcomes**: `sent` after at least one successful APNs delivery; `skipped` when push is not sent because APNs env is missing, there is no template for the kind, or user prefs/quiet hours block (see `shouldSendNotification`); `failed` / retry with `attempts` when delivery fails.
- **Pattern alerts**: Rook pattern engine calls RPC **`miya_pattern_alert_enqueue_and_bump`**. For escalation **level ≥ 7**, it enqueues the **member** row plus one row per **other accepted family member on Miya** (same family, invite accepted), after subtracting **`pattern_alert_recipient_exclusions`** for **Self Setup** subjects (ignored for **Guided Setup**). Member payload includes **`family_notified_in_app`** for copy when no other family rows were enqueued. Early levels enqueue **only the member**. **`last_notified_level`** bumps in the same transaction.
- **Recipient prefs**: Table **`pattern_alert_recipient_exclusions`**; writes only via **`set_pattern_alert_excluded_recipients`** (Edit profile → Notifications, collapsed section). **Guided Setup** users cannot save exclusions.

### Still not implemented in the worker

- **WhatsApp / SMS / email** channels are logged and return failure (not production-ready).

### Operations

See **`supabase/ops/notifications-environment.txt`** for secrets, cron URL, and smoke checks.

---

## 6. Notification Detail View

### Component

**File**: `Miya Health/Dashboard/DashboardNotifications.swift`

**Component**: `FamilyNotificationDetailSheet`

### Features

1. **AI Insight Chat**
   - Fetches AI-generated insight for the alert
   - Allows user to chat with AI about the health concern
   - Pre-warmed cache prevents 409 loops

2. **Message Templates**
   - Pre-written messages for reaching out to family member
   - Categories: Gentle encouragement, Direct concern, Celebrate improvement

3. **Share Options**
   - **WhatsApp**: Deep link to WhatsApp with pre-filled message
   - **SMS/Text**: Deep link to Messages app
   - **More Options**: Standard iOS share sheet

4. **History View**
   - Shows historical data for the metric
   - Allows user to see trend over time

### AI Insight Fetching

**Function**: `fetchAIInsightIfPossible()` in `DashboardNotifications.swift:932`

**Edge Function**: `supabase/functions/miya_insight_chat/index.ts`

**Cache Pre-warming**: When pattern alert is created, `prewarmInsightCache()` is called to generate and cache the insight.

**Code Location**: `supabase/functions/rook/patterns/engine.ts:52-84`

---

## 7. Key Files Reference

### Backend (Supabase)

1. **Pattern Alert Schema**: `supabase/migrations/20260109120000_add_pattern_alerts.sql`
2. **Pattern Evaluation Engine**: `supabase/functions/rook/patterns/engine.ts`
3. **Episode Logic**: `supabase/functions/rook/patterns/episode.ts`
4. **Rook Webhook**: `supabase/functions/rook/index.ts` (triggers pattern evaluation)
5. **Daily Recompute**: `supabase/functions/rook_daily_recompute/index.ts`
6. **Get Alerts RPC**: `supabase/migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql`
7. **AI Insight Function**: `supabase/functions/miya_insight_chat/index.ts`

### Frontend (Swift)

1. **Dashboard View**: `Miya Health/DashboardView.swift`
   - `computeTrendInsights()` - Client-side trend analysis
   - `loadServerPatternAlerts()` - Fetch server alerts
   - `fetchServerPatternAlerts()` - RPC call

2. **Notification Components**: `Miya Health/Dashboard/DashboardNotifications.swift`
   - `FamilyNotificationItem` - Notification data model
   - `FamilyNotificationDetailSheet` - Detail view with chat

3. **Trend Engine**: `Miya Health/FamilyVitalityTrendEngine.swift`
   - `computeTrends()` - Main analysis function
   - `analyzePillar()` - Per-pillar rule checking

4. **Settings**: `Miya Health/EditProfileView.swift`
   - Notification preferences UI

5. **Onboarding**: `Miya Health/OnboardingManager.swift`
   - Notification preference defaults

---

## 8. Complete Flow Diagrams

### Server Pattern Alert Flow

```
Rook Webhook Receives Data
  ↓
Store in wearable_daily_metrics
  ↓
Recompute Vitality Scores
  ↓
evaluatePatternsForUser()
  ↓
For each metric (sleep, steps, HRV, etc.):
  ├─ Fetch 60 days of data
  ├─ Fetch exercise sessions (for context)
  ├─ Evaluate pattern on endDate
  ├─ If pattern detected:
  │   ├─ Find episode start date
  │   ├─ Calculate duration & level
  │   ├─ Upsert pattern_alert_state
  │   ├─ Check shouldEnqueueNotification()
  │   └─ If yes:
  │       ├─ Fetch family admin recipients
  │       ├─ Insert into notification_queue (status='pending')
  │       ├─ Update last_notified_level
  │       └─ Pre-warm AI insight cache
  └─ If pattern not detected:
      └─ Check if should resolve active episode
```

### Client Trend Insight Flow

```
User Opens Dashboard / Pulls to Refresh
  ↓
computeTrendInsights()
  ↓
Fetch Eligible Members (excludes "Me", requires hasScore, isScoreFresh)
  ↓
Fetch 21 days of vitality_scores history
  ↓
FamilyVitalityTrendEngine.computeTrends()
  ↓
For each eligible member:
  ├─ Analyze Sleep pillar → Check 3 rules → Generate insight if match
  ├─ Analyze Movement pillar → Check 3 rules → Generate insight if match
  └─ Analyze Stress pillar → Check 3 rules → Generate insight if match
  ↓
selectTopInsights() → Pick up to 2 insights (prefer attention, different members)
  ↓
FamilyNotificationItem.build() → Filter insights:
  ├─ Coverage check (must have 7+ days)
  ├─ Name check (must have name)
  └─ Relevance check (current score < 85 for negative alerts)
  ↓
UI checks conditions:
  ├─ snapshot exists?
  ├─ score exists?
  ├─ not computing?
  └─ notifications not empty?
  ↓
If all pass → Display FamilyNotificationsCard
```

### Notification Display Priority

```
Dashboard Loads
  ↓
loadServerPatternAlerts() → Fetch from get_family_pattern_alerts RPC
  ↓
computeTrendInsights() → Generate client-side insights
  ↓
Priority Logic:
  ├─ If serverPatternAlerts.isEmpty == false:
  │   └─ Display serverPatternAlerts
  └─ Else:
      └─ Display trendNotifications
```

---

## 9. Configuration & Environment Variables

### Pattern Evaluation

- **`MIYA_PATTERN_SHADOW_MODE`**: omit or `false` for normal enqueue; set to **`true`** only for dry-run (no `notification_queue` rows from the pattern engine).

### Thresholds

- **File**: `supabase/functions/rook/patterns/thresholds.v1.json`
- Defines deviation thresholds and pattern types per metric

---

## 10. Troubleshooting

### Alerts Not Appearing

**Check**:
1. Is `MIYA_PATTERN_SHADOW_MODE=false`? (if server alerts)
2. Does member have sufficient data? (7+ days for trends, 14+ days for patterns)
3. Is member eligible? (not pending, has score, score is fresh, not "Me")
4. Does pattern match rules? (20%+ deviation, consecutive days)
5. Is alert filtered out? (current score >= 85 for negative alerts)
6. Are UI conditions met? (snapshot exists, score exists, not computing)

### Notifications Not Sending

**Checklist**:
1. Cron or scheduler **POST**s `process_notifications` with valid `x-miya-admin-secret`.
2. Edge Function secrets: `APNS_BUNDLE_ID`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (PEM). Use **`APNS_USE_SANDBOX=true`** if tokens are sandbox.
3. User has **`notify_push`** true and an active **`device_tokens`** row (iOS).
4. Row is not older than worker **`maxAge`** (default 72h).
5. Not blocked by quiet hours / snooze / dismiss; not marked **`skipped`** with reason in `last_error`.
6. Pattern rows: **`MIYA_PATTERN_SHADOW_MODE`** must not be `true`; RPC **`miya_pattern_alert_enqueue_and_bump`** must be deployed.

### Alerts Disappearing

**Common Cause**: Relevance filter removes alerts when current score improves to 85+.

**Solution**: Check `isStillRelevantNegativeAlert()` logic in `DashboardView.swift:6003`

---

## 11. Future Enhancements

### Planned

1. **Multi-channel delivery**: WhatsApp, SMS, and email handlers (queue supports channels; worker does not send them yet)
2. **Optional**: FCM or unified push if Android ships
3. **Deeper observability**: Structured logging / metrics around skip reasons and APNs errors

### Potential

1. **Real-time Updates**: WebSocket or Supabase Realtime for instant notifications
2. **Notification History**: Track all sent notifications
3. **Custom Thresholds**: Allow users to adjust alert sensitivity
4. **Alert Grouping**: Combine multiple alerts for same member
5. **Snooze Functionality**: Allow users to snooze alerts for X days

---

## Summary

Miya's notification system has two parallel tracks:

1. **Server Pattern Alerts**: Baseline-driven, metric-specific alerts triggered by Rook webhooks
2. **Client Trend Insights**: Dashboard-generated alerts based on vitality score trends

Both systems surface health-pattern concerns to people in the family, but:
- **Server alerts** are more granular (specific metrics like sleep minutes, HRV)
- **Client insights** are higher-level (pillar scores like Sleep, Movement, Stress)

**Push path**: Pending rows in `notification_queue` are processed by **`process_notifications`** when scheduled with admin auth and APNs configured; the in-app bell reads from **`get_bell_notifications`** (generally `pending` / `sent` rows).
