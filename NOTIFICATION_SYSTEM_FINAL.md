# Miya Notification System - Complete Implementation Guide

## Table of Contents
1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Database Schema](#database-schema)
4. [Notification Worker](#notification-worker)
5. [User Preferences & Quiet Hours](#user-preferences--quiet-hours)
6. [Snooze & Dismiss Functionality](#snooze--dismiss-functionality)
7. [Complete Flow Diagrams](#complete-flow-diagrams)
8. [File Reference](#file-reference)
9. [Setup & Deployment](#setup--deployment)
10. [Testing Guide](#testing-guide)

---

## System Overview

Miya's notification system has **two parallel tracks** for generating alerts, plus a **unified delivery system** that respects user preferences:

### 1. **Server-Side Pattern Alerts** (Baseline-Driven)
- Triggered by: Rook webhooks when wearable data arrives
- Evaluates: Raw metrics (sleep minutes, steps, HRV, resting HR, etc.)
- Logic: Detects 20%+ deviations from baseline over 3-21+ days
- Storage: `pattern_alert_state` table

### 2. **Client-Side Trend Insights** (Dashboard-Generated)
- Triggered by: Dashboard load, pull-to-refresh, after wearable connection
- Evaluates: Vitality pillar scores (Sleep, Movement, Stress)
- Logic: Analyzes 21-day trends using 3 rules (streak low, drop, rebound)
- Storage: Computed on-the-fly in Swift

### 3. **Unified Notification Delivery**
- Queue: `notification_queue` table
- Worker: `process_notifications` Edge Function
- Respects: User preferences, quiet hours, snooze settings
- Channels: Push (APNs/FCM), WhatsApp, SMS, Email

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     NOTIFICATION GENERATION                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────┐         ┌──────────────────────┐     │
│  │  Server Pattern       │         │  Client Trend        │     │
│  │  Alerts               │         │  Insights            │     │
│  │                       │         │                      │     │
│  │  - Rook Webhook       │         │  - Dashboard Load    │     │
│  │  - Daily Recompute    │         │  - Pull-to-Refresh   │     │
│  │  - Baseline Analysis  │         │  - Score Trends      │     │
│  └──────────┬────────────┘         └──────────┬───────────┘     │
│             │                                  │                 │
│             v                                  v                 │
│  ┌──────────────────────┐         ┌──────────────────────┐     │
│  │ pattern_alert_state  │         │ In-Memory Display    │     │
│  │ (Database)           │         │ (Swift)              │     │
│  └──────────┬────────────┘         └──────────────────────┘     │
│             │                                                    │
│             v                                                    │
│  ┌──────────────────────┐                                       │
│  │ notification_queue   │                                       │
│  │ (status='pending')   │                                       │
│  └──────────┬────────────┘                                      │
└─────────────┼──────────────────────────────────────────────────┘
              │
              v
┌─────────────────────────────────────────────────────────────────┐
│                     NOTIFICATION DELIVERY                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  process_notifications Worker (Cron: Every 1-5 minutes)  │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │                                        │
│                         v                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Check User Preferences & Quiet Hours                    │   │
│  │  - notify_push enabled?                                  │   │
│  │  - In quiet hours? (timezone-aware)                      │   │
│  │  - Quiet hours level: all / critical_only / none        │   │
│  │  - Alert snoozed or dismissed?                           │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │                                        │
│                         v                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Send Notification                                        │   │
│  │  ├─ Push (APNs/FCM)                                       │   │
│  │  ├─ WhatsApp Business API                                │   │
│  │  ├─ SMS (Twilio/AWS SNS)                                 │   │
│  │  └─ Email (SendGrid/AWS SES)                             │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │                                        │
│                         v                                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Update notification_queue                                │   │
│  │  - status='sent' | 'failed' | 'skipped'                  │   │
│  │  - sent_at, attempts, last_error                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### 1. `pattern_alert_state`
**Purpose**: Stores active and resolved pattern alert episodes

**Key Fields**:
```sql
id                    uuid PRIMARY KEY
user_id               uuid NOT NULL (member who triggered alert)
metric_type           text (sleep_minutes, steps, hrv_ms, etc.)
pattern_type          text (drop_vs_baseline, rise_vs_baseline)
episode_status        text (active, resolved)
active_since          date (when pattern started)
current_level         int (3, 7, 14, 21 days)
severity              text (watch, attention, critical)
snooze_until          date (NULL if not snoozed)
snooze_days           int (1, 3, 7 days)
dismissed_at          timestamptz (NULL if not dismissed)
baseline_value        numeric
recent_value          numeric
deviation_percent     numeric
```

**Indexes**:
- Unique: `(user_id, metric_type, pattern_type, active_since)`
- Index: `(user_id, episode_status, current_level)`

### 2. `notification_queue`
**Purpose**: Queue for pending notifications

**Key Fields**:
```sql
id                    uuid PRIMARY KEY
recipient_user_id     uuid NOT NULL (who receives - caregiver)
member_user_id        uuid NOT NULL (who it's about)
alert_state_id        uuid (links to pattern_alert_state)
channel               text (push, whatsapp, sms, email)
payload               jsonb (alert details)
status                text (pending, sent, failed, skipped)
attempts              int DEFAULT 0
last_error            text
sent_at               timestamptz
```

**Indexes**:
- Index: `(status, created_at)`

### 3. `user_profiles` (Extended)
**Purpose**: User preferences and settings

**New Fields**:
```sql
quiet_hours_notification_level  text DEFAULT 'none'
  -- Options: 'all', 'critical_only', 'none'
timezone                        text DEFAULT 'UTC'
  -- IANA timezone (e.g., 'America/New_York')
```

**Existing Notification Fields**:
```sql
notify_in_app                   boolean DEFAULT true
notify_push                     boolean DEFAULT false
notify_email                    boolean DEFAULT false
champion_notify_email           boolean DEFAULT true
champion_notify_sms             boolean DEFAULT false
quiet_hours_start               time (e.g., '22:00:00')
quiet_hours_end                 time (e.g., '07:00:00')
quiet_hours_apply_critical      boolean (DEPRECATED)
```

### 4. `device_tokens`
**Purpose**: Store push notification device tokens

**Fields**:
```sql
id                    uuid PRIMARY KEY
user_id               uuid NOT NULL
device_token          text NOT NULL (APNs or FCM token)
platform              text (ios, android)
app_version           text
os_version            text
is_active             boolean DEFAULT true
last_used_at          timestamptz
```

**Indexes**:
- Unique: `(user_id, device_token)`
- Index: `(user_id, is_active)`

---

## Notification Worker

### File: `supabase/functions/process_notifications/index.ts`

### Purpose
Processes pending notifications from `notification_queue` table, respecting user preferences and quiet hours.

### Trigger
- **Cron Schedule**: Every 1-5 minutes (configurable)
- **Manual**: POST to `/functions/v1/process_notifications` with admin secret

### Process Flow

```
1. Query notification_queue WHERE status='pending' AND attempts < 5
   ↓
2. For each notification:
   ├─ Fetch user preferences (notify_push, quiet_hours, timezone)
   ├─ Check if alert is snoozed or dismissed
   ├─ Check if in quiet hours (timezone-aware)
   │  ├─ If quiet_hours_notification_level = 'none' → Skip
   │  ├─ If quiet_hours_notification_level = 'critical_only' → Check severity
   │  └─ If quiet_hours_notification_level = 'all' → Send
   ├─ Send notification via channel (push/whatsapp/sms/email)
   └─ Update notification_queue:
      ├─ status='sent' (success)
      ├─ status='failed' (error, retry if attempts < 5)
      └─ status='skipped' (blocked by preferences)
```

### Quiet Hours Logic

```typescript
function isInQuietHours(
  quietStart: string,    // "22:00:00"
  quietEnd: string,      // "07:00:00"
  userTimezone: string   // "America/New_York"
): boolean {
  // Get current time in user's timezone
  const userTime = new Intl.DateTimeFormat("en-US", {
    timeZone: userTimezone,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date());
  
  // Parse times to minutes since midnight
  const currentMinutes = parseTimeToMinutes(userTime);
  const startMinutes = parseTimeToMinutes(quietStart);
  const endMinutes = parseTimeToMinutes(quietEnd);
  
  // Handle quiet hours that span midnight
  if (startMinutes > endMinutes) {
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  } else {
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }
}
```

### Notification Decision Matrix

| Condition | notify_push | In Quiet Hours | Quiet Level | Severity | Action |
|-----------|-------------|----------------|-------------|----------|--------|
| 1 | false | - | - | - | **Skip** (push disabled) |
| 2 | true | false | - | - | **Send** (not quiet hours) |
| 3 | true | true | none | - | **Skip** (no notifications) |
| 4 | true | true | critical_only | watch | **Skip** (not critical) |
| 5 | true | true | critical_only | attention | **Skip** (not critical) |
| 6 | true | true | critical_only | critical | **Send** (is critical) |
| 7 | true | true | all | - | **Send** (all allowed) |
| 8 | true | - | - | - (snoozed) | **Skip** (alert snoozed) |
| 9 | true | - | - | - (dismissed) | **Skip** (alert dismissed) |

### Push Notification Integration (To Be Implemented)

```typescript
async function sendPushNotification(
  recipientUserId: string,
  payload: any
): Promise<{ success: boolean; error?: string }> {
  // 1. Fetch device tokens
  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("device_token, platform")
    .eq("user_id", recipientUserId)
    .eq("is_active", true);
  
  if (!tokens || tokens.length === 0) {
    return { success: false, error: "no_device_tokens" };
  }
  
  // 2. Format APNs payload
  const apnsPayload = {
    aps: {
      alert: {
        title: payload.kind === "pattern_alert" 
          ? `${payload.metric_type} Alert` 
          : "Health Alert",
        body: `Check on ${payload.member_user_id}`,
        sound: "default",
      },
      badge: 1,
      "content-available": 1,
    },
    data: payload,
  };
  
  // 3. Send to APNs endpoint
  // TODO: Integrate with APNs HTTP/2 API
  // - Use JWT authentication with Apple's auth key
  // - Send to production or sandbox endpoint
  // - Handle response and update device token status
  
  return { success: true };
}
```

---

## User Preferences & Quiet Hours

### UI: `Miya Health/EditProfileView.swift`

### Timezone Selection

**UI Component**:
```swift
Menu {
    ForEach(commonTimezones, id: \.self) { tz in
        Button(formatTimezoneForDisplay(tz)) {
            vm.timezone = tz
            vm.fieldDidChange()
        }
    }
} label: {
    HStack {
        Text(formatTimezoneForDisplay(vm.timezone))
        Spacer()
        Image(systemName: "chevron.down")
    }
}
```

**Common Timezones**:
- America/New_York (EST/EDT)
- America/Chicago (CST/CDT)
- America/Denver (MST/MDT)
- America/Los_Angeles (PST/PDT)
- America/Anchorage (AKST/AKDT)
- Pacific/Honolulu (HST)
- Europe/London (GMT/BST)
- Europe/Paris (CET/CEST)
- Europe/Berlin (CET/CEST)
- Europe/Moscow (MSK)
- Asia/Dubai (GST)
- Asia/Kolkata (IST)
- Asia/Shanghai (CST)
- Asia/Tokyo (JST)
- Australia/Sydney (AEDT/AEST)
- UTC

### Quiet Hours Configuration

**UI Component**:
```swift
DatePicker("Start time", selection: $vm.quietHoursStart, displayedComponents: .hourAndMinute)
DatePicker("End time", selection: $vm.quietHoursEnd, displayedComponents: .hourAndMinute)

Picker("Notification Level", selection: $vm.quietHoursNotificationLevel) {
    Text("No notifications").tag("none")
    Text("Critical alerts only").tag("critical_only")
    Text("All notifications").tag("all")
}
.pickerStyle(.segmented)
```

**Options Explained**:

1. **No notifications** (`none`)
   - Blocks ALL notifications during quiet hours
   - Use case: User wants uninterrupted sleep/work time
   - Even critical alerts are blocked

2. **Critical alerts only** (`critical_only`)
   - Only sends alerts with `severity='critical'`
   - Use case: User wants to know about serious health issues but not minor ones
   - Blocks `watch` and `attention` level alerts

3. **All notifications** (`all`)
   - Sends all notifications even during quiet hours
   - Use case: User is a caregiver who needs to be notified 24/7
   - No filtering applied

### Database Storage

**Update Payload**:
```swift
let notificationPayload: [String: AnyJSON] = [
    "notify_push": .bool(vm.notifyPush),
    "quiet_hours_start": .string(formatHm(vm.quietHoursStart)),
    "quiet_hours_end": .string(formatHm(vm.quietHoursEnd)),
    "quiet_hours_notification_level": .string(vm.quietHoursNotificationLevel),
    "timezone": .string(vm.timezone)
]
try await dataManager.updateUserProfile(notificationPayload)
```

---

## Snooze & Dismiss Functionality

### UI: `Miya Health/Dashboard/DashboardNotifications.swift`

### Snooze Button

**Location**: Notification detail sheet toolbar (left side)

**UI Component**:
```swift
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        if alertStateId != nil {
            Button {
                showSnoozeOptions = true
            } label: {
                Image(systemName: "bell.slash")
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

**Snooze Options Dialog**:
```swift
.confirmationDialog("Snooze this alert", isPresented: $showSnoozeOptions) {
    Button("Snooze for 1 day") {
        Task { await snoozeAlert(days: 1) }
    }
    Button("Snooze for 3 days") {
        Task { await snoozeAlert(days: 3) }
    }
    Button("Snooze for 7 days") {
        Task { await snoozeAlert(days: 7) }
    }
    Button("Dismiss permanently") {
        Task { await dismissAlert() }
    }
    .foregroundColor(.red)
    Button("Cancel", role: .cancel) {}
}
```

### Snooze Function

**Swift Implementation**:
```swift
private func snoozeAlert(days: Int) async {
    guard let alertId = alertStateId else { return }
    
    let supabase = SupabaseConfig.client
    
    struct SnoozeResult: Decodable {
        let success: Bool
        let alert_id: String?
        let snooze_until: String?
        let snooze_days: Int?
    }
    
    let result: SnoozeResult = try await supabase
        .rpc("snooze_pattern_alert", params: [
            "alert_id": AnyJSON.string(alertId),
            "snooze_for_days": AnyJSON.number(Double(days))
        ])
        .execute()
        .value
    
    if result.success {
        dismiss() // Close sheet
    }
}
```

### Database RPC: `snooze_pattern_alert`

**File**: `supabase/migrations/20260125120000_add_quiet_hours_and_snooze.sql`

**Function**:
```sql
create or replace function public.snooze_pattern_alert(
  alert_id uuid,
  snooze_for_days int
)
returns jsonb
language plpgsql
security definer
as $$
declare
  alert_user_id uuid;
  snooze_until_date date;
begin
  -- Verify caller has access (is family member)
  select pas.user_id
  from public.pattern_alert_state pas
  join public.family_members fm on fm.user_id = pas.user_id
  where pas.id = snooze_pattern_alert.alert_id
    and fm.family_id in (
      select family_id
      from public.family_members
      where user_id = auth.uid()
    )
  into alert_user_id;

  if alert_user_id is null then
    raise exception 'Not authorized to snooze this alert';
  end if;

  -- Calculate snooze until date
  snooze_until_date := current_date + snooze_for_days;

  -- Update alert state
  update public.pattern_alert_state
  set 
    snooze_until = snooze_until_date,
    snooze_days = snooze_for_days,
    updated_at = now()
  where id = snooze_pattern_alert.alert_id;

  return jsonb_build_object(
    'success', true,
    'alert_id', snooze_pattern_alert.alert_id,
    'snooze_until', snooze_until_date,
    'snooze_days', snooze_for_days
  );
end;
$$;
```

### Dismiss Function

**Swift Implementation**:
```swift
private func dismissAlert() async {
    guard let alertId = alertStateId else { return }
    
    let supabase = SupabaseConfig.client
    
    struct DismissResult: Decodable {
        let success: Bool
        let alert_id: String?
        let dismissed_at: String?
    }
    
    let result: DismissResult = try await supabase
        .rpc("dismiss_pattern_alert", params: [
            "alert_id": AnyJSON.string(alertId)
        ])
        .execute()
        .value
    
    if result.success {
        dismiss() // Close sheet
    }
}
```

### Database RPC: `dismiss_pattern_alert`

**Function**:
```sql
create or replace function public.dismiss_pattern_alert(
  alert_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
begin
  -- Verify caller has access (is family member)
  -- ... (same authorization check as snooze)

  -- Update alert state
  update public.pattern_alert_state
  set 
    dismissed_at = now(),
    updated_at = now()
  where id = dismiss_pattern_alert.alert_id;

  return jsonb_build_object(
    'success', true,
    'alert_id', dismiss_pattern_alert.alert_id,
    'dismissed_at', now()
  );
end;
$$;
```

### Updated RPC: `get_family_pattern_alerts`

**Filters out snoozed and dismissed alerts**:
```sql
return query
select
  pas.id,
  pas.user_id as member_user_id,
  pas.metric_type,
  -- ... other fields
from public.pattern_alert_state pas
where pas.user_id in (
  select fm.user_id
  from public.family_members fm
  where fm.family_id = get_family_pattern_alerts.family_id
)
  and pas.episode_status = 'active'
  and pas.dismissed_at is null
  and (pas.snooze_until is null or pas.snooze_until < current_date)
order by pas.current_level desc, pas.active_since desc;
```

---

## Complete Flow Diagrams

### 1. Server Pattern Alert Generation & Delivery

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Wearable Data Arrives                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
                    Rook Webhook Triggered
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Store & Compute                                         │
│ - Store in wearable_daily_metrics                               │
│ - Recompute vitality scores                                     │
│ - Call evaluatePatternsForUser()                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Pattern Evaluation                                      │
│ For each metric (sleep, steps, HRV, etc.):                      │
│   - Fetch 60 days of data                                       │
│   - Fetch exercise sessions (for context)                       │
│   - Evaluate pattern on endDate                                 │
│   - If pattern detected:                                        │
│     ├─ Find episode start date                                  │
│     ├─ Calculate duration & level (3, 7, 14, 21)                │
│     ├─ Upsert pattern_alert_state                               │
│     └─ Check shouldEnqueueNotification()                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              v
                    Should Enqueue? (shadowMode=false, 
                    newLevel > lastNotifiedLevel)
                              │
                    ┌─────────┴─────────┐
                    │ YES               │ NO
                    v                   v
┌─────────────────────────────────────────┐  (End)
│ STEP 4: Enqueue Notification            │
│ - Fetch family admin recipients         │
│ - For each recipient:                   │
│   └─ Insert into notification_queue     │
│      (status='pending')                 │
│ - Update last_notified_level            │
│ - Pre-warm AI insight cache             │
└─────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: Worker Processes Queue (Cron: Every 1-5 min)           │
│ - Query notification_queue WHERE status='pending'               │
│ - For each notification:                                        │
│   ├─ Fetch user preferences                                     │
│   ├─ Check if snoozed/dismissed                                 │
│   ├─ Check quiet hours (timezone-aware)                         │
│   ├─ Apply quiet_hours_notification_level filter                │
│   └─ Send or skip                                               │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ STEP 6: Send Notification                                       │
│ - Push (APNs/FCM)                                               │
│ - WhatsApp Business API                                         │
│ - SMS (Twilio/AWS SNS)                                          │
│ - Email (SendGrid/AWS SES)                                      │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ STEP 7: Update Queue Status                                     │
│ - status='sent' (success)                                       │
│ - status='failed' (error, retry if attempts < 5)                │
│ - status='skipped' (blocked by preferences)                     │
└─────────────────────────────────────────────────────────────────┘
```

### 2. User Snoozes Notification

```
┌─────────────────────────────────────────────────────────────────┐
│ User Opens Notification Detail Sheet                            │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ User Taps Snooze Button (bell.slash icon)                       │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ Confirmation Dialog Appears                                     │
│ Options:                                                         │
│   - Snooze for 1 day                                            │
│   - Snooze for 3 days                                           │
│   - Snooze for 7 days                                           │
│   - Dismiss permanently                                         │
│   - Cancel                                                      │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ User Selects "Snooze for 3 days"                                │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ Swift calls snoozeAlert(days: 3)                                │
│   ├─ RPC: snooze_pattern_alert(alert_id, snooze_for_days=3)    │
│   └─ Database updates:                                          │
│       ├─ snooze_until = current_date + 3                        │
│       ├─ snooze_days = 3                                        │
│       └─ updated_at = now()                                     │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ Sheet Dismisses, Alert Hidden from Dashboard                    │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ After 3 Days (snooze_until < current_date)                      │
│   ├─ get_family_pattern_alerts RPC returns alert again          │
│   └─ Alert reappears on dashboard                               │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Quiet Hours Decision Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Notification Worker Processes Pending Notification              │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────────────────────────────┐
│ Fetch User Preferences                                          │
│   - notify_push                                                 │
│   - quiet_hours_start                                           │
│   - quiet_hours_end                                             │
│   - quiet_hours_notification_level                              │
│   - timezone                                                    │
└─────────────────────────────────────────────────────────────────┘
                    │
                    v
              notify_push = true?
                    │
          ┌─────────┴─────────┐
          │ NO                │ YES
          v                   v
      SKIP (push disabled)   Continue
                              │
                              v
                    Check if in quiet hours
                    (timezone-aware)
                              │
                    ┌─────────┴─────────┐
                    │ NO                │ YES
                    v                   v
                SEND                Check quiet_hours_notification_level
                                        │
                          ┌─────────────┼─────────────┐
                          │             │             │
                          v             v             v
                       "none"    "critical_only"    "all"
                          │             │             │
                          v             v             v
                       SKIP      Check severity     SEND
                                        │
                              ┌─────────┼─────────┐
                              │         │         │
                              v         v         v
                          watch   attention  critical
                              │         │         │
                              v         v         v
                           SKIP      SKIP      SEND
```

---

## File Reference

### Backend (Supabase)

#### Database Migrations
1. **`supabase/migrations/20260109120000_add_pattern_alerts.sql`**
   - Creates `pattern_alert_state` table
   - Creates `notification_queue` table
   - Adds indexes and triggers

2. **`supabase/migrations/20260125120000_add_quiet_hours_and_snooze.sql`**
   - Adds `quiet_hours_notification_level` to `user_profiles`
   - Adds `timezone` to `user_profiles`
   - Adds `snooze_days` to `pattern_alert_state`
   - Creates `device_tokens` table
   - Creates `snooze_pattern_alert` RPC
   - Creates `dismiss_pattern_alert` RPC
   - Creates `register_device_token` RPC
   - Updates `get_family_pattern_alerts` RPC

3. **`supabase/migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql`**
   - Creates `get_family_pattern_alerts` RPC (original version)

#### Edge Functions
1. **`supabase/functions/rook/index.ts`**
   - Rook webhook handler
   - Stores wearable data
   - Triggers pattern evaluation
   - Lines 760-767: Calls `evaluatePatternsForUser()`

2. **`supabase/functions/rook/patterns/engine.ts`**
   - Pattern evaluation logic
   - Lines 317-444: `evaluatePatternsForUser()` function
   - Lines 407-440: Notification enqueueing logic
   - Lines 52-84: AI insight cache pre-warming

3. **`supabase/functions/rook/patterns/episode.ts`**
   - Episode level calculation
   - Lines 19-28: `shouldEnqueueNotification()` function
   - Lines 12-17: `severityForLevel()` function

4. **`supabase/functions/rook/patterns/evaluate.ts`**
   - Pattern evaluation rules
   - Baseline calculation
   - Deviation detection

5. **`supabase/functions/rook/patterns/thresholds.v1.json`**
   - Threshold configuration per metric
   - Pattern types and deviation percentages

6. **`supabase/functions/rook_daily_recompute/index.ts`**
   - Daily cron job for vitality recomputation
   - Lines 43-171: Batch processing logic

7. **`supabase/functions/process_notifications/index.ts`** ⭐ NEW
   - Notification queue worker
   - Lines 30-77: Quiet hours check
   - Lines 79-146: Notification decision logic
   - Lines 148-191: Send notification (placeholder)
   - Lines 193-257: Process single notification

8. **`supabase/functions/miya_insight_chat/index.ts`**
   - AI insight generation
   - Chat functionality

### Frontend (Swift)

#### Notification UI
1. **`Miya Health/Dashboard/DashboardNotifications.swift`**
   - Lines 1-230: `FamilyNotificationItem` model and builder
   - Lines 231-365: `FamilyNotificationsCard` component
   - Lines 366-3924: `FamilyNotificationDetailSheet` component
   - Lines 468-474: Snooze state variables ⭐ NEW
   - Lines 1316-1406: Snooze & dismiss functions ⭐ NEW
   - Lines 2746-2790: Snooze button in toolbar ⭐ NEW

2. **`Miya Health/DashboardView.swift`**
   - Lines 358-388: Pull-to-refresh logic
   - Lines 528-557: Initial load logic
   - Lines 1475-1484: `loadServerPatternAlerts()` function
   - Lines 1655-1750: `fetchServerPatternAlerts()` function

3. **`Miya Health/FamilyVitalityTrendEngine.swift`**
   - Client-side trend analysis
   - Lines 352-463: `analyzePillar()` function
   - Lines 520-547: `selectTopInsights()` function

#### Settings UI
4. **`Miya Health/EditProfileView.swift`**
   - Lines 62-65: Quiet hours state variables ⭐ UPDATED
   - Lines 466-584: Notifications card UI ⭐ UPDATED
   - Lines 485-543: Quiet hours settings ⭐ NEW
   - Lines 548-584: Timezone picker & formatter ⭐ NEW
   - Lines 653-654: Load timezone & notification level ⭐ NEW
   - Lines 748-761: Save notification preferences ⭐ UPDATED

5. **`Miya Health/OnboardingManager.swift`**
   - Lines 138-187: Onboarding notification preferences
   - Default values for new users

6. **`Miya Health/DataManager.swift`**
   - Lines 1727-1770: `saveAlertPreferences()` function
   - Database update logic

#### Other
7. **`Miya Health/FamilyMemberProfileView.swift`**
   - Lines 373-405: Fetch alerts for member profile

8. **`Miya Health/RookAuthorizationView.swift`**
   - Lines 258-294: Post notification on wearable connection

9. **`Miya Health/RiskResultsView.swift`**
   - Lines 865-875: Listen for wearable connection notification

10. **`Miya Health/Miya_HealthApp.swift`**
    - Lines 12-21: Notification names definition

### Documentation
1. **`NOTIFICATION_SYSTEM_COMPLETE.md`**
   - Original documentation (pre-implementation)

2. **`NOTIFICATION_SYSTEM_FINAL.md`** ⭐ THIS FILE
   - Complete implementation guide

3. **`ALERT_TRIGGER_FLOW.md`**
   - Client-side trend insights flow
   - Detailed rule documentation

4. **`WHATSAPP_SMS_INTEGRATION.md`**
   - WhatsApp & SMS deep link integration

---

## Setup & Deployment

### 1. Database Migration

```bash
# Apply migrations in order
cd supabase

# Pattern alerts schema
psql $DATABASE_URL -f migrations/20260109120000_add_pattern_alerts.sql

# Quiet hours & snooze
psql $DATABASE_URL -f migrations/20260125120000_add_quiet_hours_and_snooze.sql

# Get family pattern alerts RPC
psql $DATABASE_URL -f migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql
```

### 2. Deploy Edge Functions

```bash
# Deploy notification worker
supabase functions deploy process_notifications

# Deploy Rook webhook (if not already deployed)
supabase functions deploy rook

# Deploy daily recompute (if not already deployed)
supabase functions deploy rook_daily_recompute

# Deploy AI insight chat (if not already deployed)
supabase functions deploy miya_insight_chat
```

### 3. Set Environment Variables

```bash
# In Supabase Dashboard → Edge Functions → Settings

# Pattern alert shadow mode (set to 'false' for production)
MIYA_PATTERN_SHADOW_MODE=false

# Admin secret for worker authentication
MIYA_ADMIN_SECRET=your-secure-random-secret-here

# Supabase credentials (auto-populated)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key
```

### 4. Set Up Cron Job

**Option A: Supabase Cron (Recommended)**

In Supabase Dashboard → Database → Cron Jobs:

```sql
-- Run notification worker every 5 minutes
SELECT cron.schedule(
  'process-notifications',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://your-project.supabase.co/functions/v1/process_notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-miya-admin-secret', 'your-secure-random-secret-here'
    ),
    body := jsonb_build_object('batchSize', 50, 'maxAge', 24)
  );
  $$
);
```

**Option B: External Cron (e.g., GitHub Actions, AWS EventBridge)**

```yaml
# .github/workflows/process-notifications.yml
name: Process Notifications
on:
  schedule:
    - cron: '*/5 * * * *'  # Every 5 minutes
jobs:
  process:
    runs-on: ubuntu-latest
    steps:
      - name: Call Edge Function
        run: |
          curl -X POST \
            -H "Content-Type: application/json" \
            -H "x-miya-admin-secret: ${{ secrets.MIYA_ADMIN_SECRET }}" \
            -d '{"batchSize": 50, "maxAge": 24}' \
            https://your-project.supabase.co/functions/v1/process_notifications
```

### 5. Configure Push Notifications (Future)

**iOS (APNs)**:
1. Generate APNs auth key in Apple Developer Portal
2. Store auth key in Supabase secrets
3. Update `sendPushNotification()` in `process_notifications/index.ts`
4. Register device tokens in app using `register_device_token` RPC

**Android (FCM)**:
1. Set up Firebase project
2. Add FCM credentials to Supabase secrets
3. Update `sendPushNotification()` to support FCM
4. Register device tokens in app

### 6. Update Swift App

**No additional setup required** - all changes are already in the codebase:
- Quiet hours UI is in `EditProfileView.swift`
- Snooze button is in `DashboardNotifications.swift`
- RPCs are called automatically

---

## Testing Guide

### 1. Test Pattern Alert Generation

```sql
-- 1. Create test user with wearable data
INSERT INTO wearable_daily_metrics (user_id, metric_date, sleep_minutes, steps)
VALUES 
  ('test-user-id', '2026-01-20', 480, 10000),
  ('test-user-id', '2026-01-21', 450, 9500),
  ('test-user-id', '2026-01-22', 420, 9000),
  -- ... (add 14+ days of baseline)
  ('test-user-id', '2026-01-23', 300, 5000),  -- Drop
  ('test-user-id', '2026-01-24', 280, 4500),  -- Drop
  ('test-user-id', '2026-01-25', 260, 4000);  -- Drop

-- 2. Manually trigger pattern evaluation
SELECT * FROM evaluatePatternsForUser('test-user-id', '2026-01-25');

-- 3. Check if alert was created
SELECT * FROM pattern_alert_state WHERE user_id = 'test-user-id';

-- 4. Check if notification was enqueued
SELECT * FROM notification_queue WHERE member_user_id = 'test-user-id';
```

### 2. Test Notification Worker

```bash
# Manually trigger worker
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-miya-admin-secret: your-secret" \
  -d '{"batchSize": 10}' \
  https://your-project.supabase.co/functions/v1/process_notifications

# Check response
{
  "ok": true,
  "processed": 5,
  "sent": 2,
  "skipped": 3,
  "failed": 0
}
```

### 3. Test Quiet Hours

```sql
-- 1. Set user's quiet hours and timezone
UPDATE user_profiles
SET 
  quiet_hours_start = '22:00:00',
  quiet_hours_end = '07:00:00',
  quiet_hours_notification_level = 'critical_only',
  timezone = 'America/New_York'
WHERE user_id = 'test-user-id';

-- 2. Create notification at 11 PM EST (in quiet hours)
INSERT INTO notification_queue (
  recipient_user_id,
  member_user_id,
  alert_state_id,
  channel,
  payload,
  status
) VALUES (
  'test-user-id',
  'family-member-id',
  'alert-state-id',
  'push',
  '{"kind": "pattern_alert", "metric_type": "sleep_minutes"}',
  'pending'
);

-- 3. Run worker
-- Should skip if severity != 'critical'
-- Should send if severity = 'critical'
```

### 4. Test Snooze Functionality

```swift
// In Xcode:
// 1. Open notification detail sheet
// 2. Tap snooze button (bell.slash icon)
// 3. Select "Snooze for 3 days"
// 4. Verify sheet dismisses
// 5. Verify alert is hidden from dashboard

// Check database:
SELECT snooze_until, snooze_days 
FROM pattern_alert_state 
WHERE id = 'alert-id';

// Expected:
// snooze_until = current_date + 3
// snooze_days = 3
```

### 5. Test Timezone Handling

```sql
-- 1. Create users in different timezones
UPDATE user_profiles SET timezone = 'America/Los_Angeles' WHERE user_id = 'user-1';
UPDATE user_profiles SET timezone = 'Europe/London' WHERE user_id = 'user-2';
UPDATE user_profiles SET timezone = 'Asia/Tokyo' WHERE user_id = 'user-3';

-- 2. Set same quiet hours for all (22:00-07:00)
UPDATE user_profiles 
SET quiet_hours_start = '22:00:00', quiet_hours_end = '07:00:00'
WHERE user_id IN ('user-1', 'user-2', 'user-3');

-- 3. Create notifications at same UTC time (e.g., 2026-01-25 03:00 UTC)
-- user-1 (LA): 7 PM PST (not quiet hours) → SEND
-- user-2 (London): 3 AM GMT (quiet hours) → SKIP/FILTER
-- user-3 (Tokyo): 12 PM JST (not quiet hours) → SEND
```

### 6. Test Notification Preferences

```swift
// Test Matrix:
// 1. notify_push = false → All notifications skipped
// 2. notify_push = true, quiet_hours_notification_level = 'none' → Skipped in quiet hours
// 3. notify_push = true, quiet_hours_notification_level = 'critical_only' → Only critical sent
// 4. notify_push = true, quiet_hours_notification_level = 'all' → All sent
```

---

## Summary

### What Was Implemented

✅ **Notification Queue Worker** (`process_notifications`)
- Processes pending notifications from `notification_queue`
- Respects user preferences and quiet hours
- Timezone-aware quiet hours calculation
- Retry logic with max 5 attempts
- Status tracking (pending, sent, failed, skipped)

✅ **Granular Quiet Hours Control**
- Three levels: `none`, `critical_only`, `all`
- Timezone selection (16 common timezones)
- UI in `EditProfileView.swift`
- Database fields in `user_profiles`

✅ **Snooze & Dismiss Functionality**
- Snooze for 1, 3, or 7 days
- Dismiss permanently
- UI button in notification detail sheet
- Database RPCs: `snooze_pattern_alert`, `dismiss_pattern_alert`
- Updated `get_family_pattern_alerts` to filter snoozed/dismissed

✅ **Device Token Management**
- `device_tokens` table for APNs/FCM tokens
- `register_device_token` RPC
- Platform tracking (iOS/Android)
- Active status management

✅ **Database Schema Updates**
- `quiet_hours_notification_level` field
- `timezone` field
- `snooze_days` field
- `device_tokens` table
- Updated indexes and constraints

### What Needs Implementation

⚠️ **Push Notification Integration**
- APNs HTTP/2 API integration
- FCM integration for Android
- Device token registration in Swift app
- Actual notification sending in `sendPushNotification()`

⚠️ **Multi-Channel Support**
- WhatsApp Business API integration
- SMS via Twilio/AWS SNS
- Email via SendGrid/AWS SES

⚠️ **Monitoring & Analytics**
- Notification delivery metrics
- User engagement tracking
- Error rate monitoring
- Quiet hours effectiveness analysis

### Key Files Created/Modified

**New Files**:
- `supabase/functions/process_notifications/index.ts`
- `supabase/migrations/20260125120000_add_quiet_hours_and_snooze.sql`
- `NOTIFICATION_SYSTEM_FINAL.md` (this file)

**Modified Files**:
- `Miya Health/EditProfileView.swift` (quiet hours UI)
- `Miya Health/Dashboard/DashboardNotifications.swift` (snooze button)

**Total Lines Added**: ~1,500 lines of code + documentation

---

## Next Steps

1. **Set up cron job** to run `process_notifications` every 1-5 minutes
2. **Integrate APNs** for iOS push notifications
3. **Test thoroughly** with real users in different timezones
4. **Monitor queue** for failed notifications and adjust retry logic
5. **Implement analytics** to track notification effectiveness
6. **Add multi-channel support** (WhatsApp, SMS, Email) as needed

---

**End of Documentation**
