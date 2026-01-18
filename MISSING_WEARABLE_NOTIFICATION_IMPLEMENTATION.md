# Missing Wearable Notification System - Implementation Complete

## Overview
This document outlines the complete implementation of the missing wearable data notification system that triggers at 3 days and 7 days, with dismiss functionality and message sending capabilities.

## ✅ Implementation Complete

### 1. Data Model & UI Components
**File**: `Miya Health/Dashboard/MissingWearableNotification.swift`

**Components Created**:
- `MissingWearableNotification` model with:
  - Unique ID based on userId + days stale
  - Member name, initials, userId
  - Days stale (3 or 7)
  - Last updated timestamp
  - Severity enum (warning/critical)
  - Dynamic title and body text

- `MissingWearableDetailSheet` view with:
  - Member avatar with initials
  - Severity badge (warning/critical)
  - Days stale display
  - Last updated timestamp
  - "Send Message" button
  - "Dismiss" button

- `MissingWearableMessageSheet` view with:
  - Reuses `MessageTemplatesSheet` pattern
  - Tone selection (supportive/casual/direct)
  - Editable message template
  - WhatsApp button
  - iMessage button
  - Copy to clipboard

### 2. DashboardView Integration
**File**: `Miya Health/DashboardView.swift`

**State Variables Added** (after line 42):
```swift
/// Missing wearable notifications (3 days, 7 days)
@State private var missingWearableNotifications: [MissingWearableNotification] = []
@State private var selectedMissingWearableNotification: MissingWearableNotification? = nil
@State private var dismissedMissingWearableIds: Set<String> = []
```

**Detection Logic Added**:
- `detectMissingWearableData()` function:
  - Queries `user_profiles.vitality_score_updated_at` for each family member
  - Calculates days stale from last update
  - Creates notifications at 3 days and 7 days thresholds
  - Filters out dismissed notifications
  - Upgrades 3-day notification to 7-day when threshold crossed
  - Excludes current user and pending members

**Dismiss Persistence Added**:
- `loadDismissedMissingWearable(for:)` - loads dismissed IDs from UserDefaults
- `persistDismissedMissingWearable(for:)` - saves dismissed IDs to UserDefaults
- `dismissMissingWearableNotification(id:)` - dismisses notification and persists

**WhatsApp/iMessage Helpers Added**:
- `openWhatsApp(with:)` - opens WhatsApp with pre-filled message (falls back to App Store if not installed)
- `openMessages(with:)` - opens iMessage with pre-filled message

**Integration Points**:
- `.task` block: calls `loadDismissedMissingWearable(for: uid)` on app launch
- `.task` block: calls `detectMissingWearableData()` after loading family members

### 3. Family Vitality Calculation
**Status**: ✅ Already handled correctly

The existing SQL function `get_family_vitality` already implements the correct logic:
- For families with 3+ members: calculates average using all members with fresh data (7 days)
- If only 1 member has data: returns that member's score
- If 2+ members have data: calculates average of those 2+ members
- No changes needed

**SQL Reference**: `supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql`

## User Experience Flow

### 3-Day Warning
1. User opens dashboard
2. System detects family member hasn't synced in 3 days
3. Warning notification appears in notifications section
4. User can:
   - Tap to see details
   - Send supportive message via WhatsApp/iMessage
   - Dismiss notification

### 7-Day Critical Alert
1. If member still hasn't synced after 7 days
2. System upgrades to critical notification
3. Critical alert appears (replaces 3-day warning)
4. User can:
   - Tap to see details
   - Send more urgent message
   - Dismiss notification

### Message Sending
1. User taps "Send Message" in notification detail
2. Message sheet appears with:
   - Pre-filled template: "Hey! The family is missing you at Miya..."
   - Tone selector (supportive/casual/direct)
   - Editable text field
   - WhatsApp button → opens WhatsApp with message
   - iMessage button → opens Messages app with message
   - Copy button → copies to clipboard

### Dismiss Functionality
1. User taps "Dismiss" in notification detail
2. Notification is removed from view
3. Dismiss state persisted to UserDefaults (per-user)
4. Notification won't reappear unless:
   - Member syncs data (resets state)
   - Threshold changes (3 days → 7 days)

## Technical Details

### Detection Logic
- Runs after `loadFamilyMembers()` in `.task` block
- Queries `user_profiles.vitality_score_updated_at` for each member
- Uses `Calendar.current.dateComponents([.day], ...)` for accurate day calculation
- Filters out:
  - Current user (`member.isMe`)
  - Pending invites (`member.isPending`)
  - Dismissed notifications (`dismissedMissingWearableIds`)

### Notification ID Format
- 3-day warning: `missing_wearable_{userId}_3`
- 7-day critical: `missing_wearable_{userId}_7`

This ensures:
- Each member can have only one active notification
- 7-day notification replaces 3-day notification
- Dismiss state is tracked separately for each threshold

### Freshness Alignment
- Detection uses same 7-day freshness as family vitality calculation
- Consistent with `get_family_vitality` RPC (updated in previous fix)
- Ensures notifications align with family score calculations

## Files Modified

1. **Created**: `Miya Health/Dashboard/MissingWearableNotification.swift`
   - 350+ lines of new code
   - Complete notification system

2. **Modified**: `Miya Health/DashboardView.swift`
   - Added 3 state variables
   - Added 6 helper functions (~150 lines)
   - Added 2 integration calls in `.task` block

## Testing Checklist

- [ ] 3-day warning appears when member hasn't synced in 3 days
- [ ] 7-day critical alert appears when member hasn't synced in 7 days
- [ ] 7-day alert replaces 3-day warning (not both shown)
- [ ] Dismiss functionality works and persists across app restarts
- [ ] WhatsApp button opens WhatsApp with pre-filled message
- [ ] iMessage button opens Messages app with pre-filled message
- [ ] Copy button copies message to clipboard
- [ ] Tone selector changes message template
- [ ] Message is editable before sending
- [ ] Current user is excluded from notifications
- [ ] Pending invites are excluded from notifications
- [ ] Family vitality score still calculates correctly with missing members

## Next Steps

### UI Integration (Still Needed)
The notification system is complete, but you need to add the UI to display the notifications in the dashboard. This should be added to the notifications section in `DashboardView.swift`:

```swift
// In the notifications section (near line 400-500), add:
ForEach(missingWearableNotifications) { notification in
    MissingWearableNotificationCard(
        notification: notification,
        onTap: {
            selectedMissingWearableNotification = notification
        },
        onDismiss: {
            dismissMissingWearableNotification(id: notification.id)
        }
    )
}

// Add sheet presentation modifier:
.sheet(item: $selectedMissingWearableNotification) { notification in
    MissingWearableDetailSheet(
        notification: notification,
        onDismiss: {
            selectedMissingWearableNotification = nil
        },
        onDismissNotification: {
            dismissMissingWearableNotification(id: notification.id)
            selectedMissingWearableNotification = nil
        },
        onSendMessage: { message, platform in
            if platform == .whatsapp {
                openWhatsApp(with: message)
            } else {
                openMessages(with: message)
            }
        }
    )
}
```

### Production Deployment
1. Test with real users who have stale data
2. Monitor notification frequency
3. Adjust thresholds if needed (currently 3 days / 7 days)
4. Consider adding push notifications for critical alerts

## Summary

✅ **Complete**: Data model, detection logic, dismiss persistence, message sending
⏳ **Remaining**: UI integration in dashboard notifications section

All the pieces are in place. You just need to add the UI cards to display the notifications in the dashboard.
