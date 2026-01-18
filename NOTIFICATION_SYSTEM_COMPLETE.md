# Notification System - Complete Documentation

## Overview

Miya has a **two-tier notification system**:

1. **Server-Side Pattern Alerts** - Baseline-driven alerts based on wearable metrics (sleep, steps, HRV, resting HR, etc.)
2. **Client-Side Trend Insights** - Dashboard-generated alerts based on vitality pillar score trends

Both systems analyze health patterns and notify family caregivers about member health changes.

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
- `recipient_user_id` - Who receives the notification (caregiver/admin)
- `member_user_id` - Who the alert is about
- `alert_state_id` - Links to `pattern_alert_state.id`
- `channel` - `push`, `whatsapp`, `sms`, `email`
- `payload` - JSONB with alert details
- `status` - `pending`, `sent`, `failed`
- `attempts`, `last_error`, `sent_at` - Retry tracking

**Status**: ⚠️ **Queue is populated but not yet processed** - No worker/cron job currently processes `notification_queue` to send push notifications. Notifications are displayed directly from `pattern_alert_state` via the RPC.

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

### Champion Settings

**Location**: `Miya Health/EditProfileView.swift:472-475`

- **Champion email alerts**: `championNotifyEmail` (default: `true`)
- **Champion SMS alerts**: `championNotifySms` (default: `false`)

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

⚠️ **NOT IMPLEMENTED** - The `notification_queue` table is populated but no worker/cron job processes it to send push notifications.

### What Exists

1. **Queue Population**: Pattern evaluation inserts records into `notification_queue` with `status='pending'`
2. **Queue Schema**: Table has fields for retry logic (`attempts`, `last_error`, `sent_at`)

### What's Missing

1. **Worker Function**: No Supabase Edge Function or external service processes pending notifications
2. **Push Notification Service**: No integration with APNs (Apple Push Notification service) or FCM (Firebase Cloud Messaging)
3. **Channel Handlers**: No code to send via WhatsApp, SMS, or email

### Future Implementation

To implement push notifications:

1. **Create Worker Function**: `supabase/functions/process_notifications/index.ts`
   - Query `notification_queue` where `status='pending'`
   - For each notification:
     - Check user preferences (`notifyPush`, quiet hours, etc.)
     - Send via appropriate channel (push, WhatsApp, SMS, email)
     - Update `status='sent'` or `status='failed'`
     - Increment `attempts`, store `last_error` on failure

2. **Set Up Cron**: Schedule worker to run every 1-5 minutes

3. **Integrate Push Service**: 
   - Register device tokens in database
   - Use APNs for iOS or FCM for cross-platform
   - Send push notifications with alert details

4. **Channel Integrations**:
   - **WhatsApp**: Use WhatsApp Business API
   - **SMS**: Use Twilio, AWS SNS, or similar
   - **Email**: Use SendGrid, AWS SES, or similar

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

- **`MIYA_PATTERN_SHADOW_MODE`**: `true` (default) or `false`
  - `true`: Evaluate patterns but don't enqueue notifications (testing)
  - `false`: Enable notifications (production)

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

**Current Status**: Push notifications are **not implemented**. The `notification_queue` table is populated but no worker processes it.

**To Enable**:
1. Create worker function to process `notification_queue`
2. Set up push notification service (APNs/FCM)
3. Register device tokens
4. Schedule cron job to run worker

### Alerts Disappearing

**Common Cause**: Relevance filter removes alerts when current score improves to 85+.

**Solution**: Check `isStillRelevantNegativeAlert()` logic in `DashboardView.swift:6003`

---

## 11. Future Enhancements

### Planned

1. **Notification Queue Worker**: Process `notification_queue` to send push notifications
2. **Push Notification Integration**: APNs/FCM setup
3. **Multi-Channel Support**: WhatsApp, SMS, Email handlers
4. **Quiet Hours Enforcement**: Respect user quiet hours when sending
5. **Notification Preferences**: Honor `notifyPush`, `notifyEmail` settings

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

Both systems analyze health patterns and notify caregivers, but:
- **Server alerts** are more granular (specific metrics like sleep minutes, HRV)
- **Client insights** are higher-level (pillar scores like Sleep, Movement, Stress)

**Current Limitation**: Notifications are displayed in-app but **not sent as push notifications** yet. The infrastructure exists (`notification_queue` table) but needs a worker function to process it.
