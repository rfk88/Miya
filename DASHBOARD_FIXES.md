# Dashboard Fixes - Member Circles & Guided Notifications

## Issues Fixed

### ✅ Issue 1: Member circles greyed out and not updating

**Problem**: Super admin fills guided member's data, but member circles at top of dashboard stay greyed out even after member completes setup.

**Root Cause**: Dashboard only loads family members once on initial load (`.task` modifier). When guided members complete setup (status changes to `reviewed_complete`), the dashboard doesn't know to refresh.

**Fixes Applied**:

1. **Added pull-to-refresh** (`.refreshable` modifier)
   - Super admin can now pull down on dashboard to reload member data
   - Triggers `loadFamilyMembers()` and refreshes the display
   - Updates member circles to show correct status (no longer greyed out)

2. **Added refresh ID** (`familyMembersRefreshID`)
   - Forces family members strip to re-render when data changes
   - Ensures UI updates immediately after refresh

**User Action Required**: After completing guided setup for a member, pull down on the dashboard to refresh. Member circles will update to show they're no longer pending.

---

### ✅ Issue 2: Can't clear completed guided member notifications

**Problem**: Guided setup card shows all guided members, including those who have completed. Super admin has no way to dismiss/clear these notifications.

**Fix Applied**:

**Added dismiss button for completed members**:
- Members with status `reviewed_complete` now show an X button
- Clicking X removes them from the guided setup card
- Dismissed members are tracked in `dismissedGuidedMemberIds` set
- Dismissed members stay hidden until app restart (or dashboard reload)

**Location**: Dashboard → "Guided setup" card → Completed members → X button

---

## Code Changes

### File: `DashboardView.swift`

#### 1. Added state variables (lines ~145-155)
```swift
/// Refresh ID to force family members strip to update
@State private var familyMembersRefreshID = UUID()

/// IDs of dismissed guided members (don't show in card)
@State private var dismissedGuidedMemberIds: Set<String> = []
```

#### 2. Added pull-to-refresh (line ~263)
```swift
.refreshable {
    await loadFamilyMembers()
    familyMembersRefreshID = UUID()
}
```

#### 3. Updated FamilyMembersStrip with refresh ID (line ~214)
```swift
FamilyMembersStrip(members: familyMembers)
    .padding(.top, 12)
    .id(familyMembersRefreshID)  // Forces re-render on refresh
```

#### 4. Updated GuidedSetupStatusCard to filter dismissed members (lines ~220-230)
```swift
GuidedSetupStatusCard(
    members: familyMemberRecords.filter { 
        $0.onboardingType == "Guided Setup" && 
        !dismissedGuidedMemberIds.contains($0.id.uuidString)
    },
    familyName: resolvedFamilyName.isEmpty ? familyName : resolvedFamilyName,
    onDismiss: { memberId in
        dismissedGuidedMemberIds.insert(memberId)
    }
) { member, action in
    handleGuidedStatusAction(member: member, action: action)
}
```

#### 5. Added dismiss parameter to GuidedSetupStatusCard (line ~635)
```swift
private struct GuidedSetupStatusCard: View {
    let members: [FamilyMemberRecord]
    let familyName: String
    let onDismiss: (String) -> Void  // NEW
    let onAction: (FamilyMemberRecord, DashboardView.GuidedAdminAction) -> Void
```

#### 6. Added dismiss parameter to GuidedSetupMemberRow (line ~682)
```swift
private struct GuidedSetupMemberRow: View {
    let member: FamilyMemberRecord
    let familyName: String
    let onDismiss: (String) -> Void  // NEW
    let onAction: (FamilyMemberRecord, DashboardView.GuidedAdminAction) -> Void
```

#### 7. Added dismiss button for completed members (lines ~761-785)
```swift
case .reviewedComplete:
    HStack(spacing: 12) {
        NavigationLink {
            ProfileView(...)
        } label: {
            Text("View profile")
                .font(.caption.bold())
                .foregroundColor(.miyaPrimary)
        }
        
        // NEW: Dismiss button
        Button {
            onDismiss(member.id.uuidString)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
```

---

## User Workflow

### Scenario: Admin completes guided setup for a member

**Before fixes**:
1. Admin fills guided member's data ✅
2. Member logs in and approves ✅
3. Admin's dashboard still shows member as greyed out ❌
4. Admin can't clear the "Complete" notification ❌

**After fixes**:
1. Admin fills guided member's data ✅
2. Member logs in and approves ✅
3. Admin pulls down on dashboard to refresh ✅
4. Member circle is no longer greyed out ✅
5. Admin clicks X on the "Complete" notification to dismiss it ✅

---

## Why member circles are greyed out

From `FamilyMemberScore.isPending` (lines 30-37):

```swift
var isPending: Bool {
    // Guided members are pending until reviewed_complete
    if onboardingType == "Guided Setup" {
        return guidedSetupStatus != "reviewed_complete"
    }
    // Self Setup / normal: use invite status
    return (inviteStatus ?? "").lowercased() == "pending"
}
```

When `isPending = true`:
- Vitality ring opacity = 0.35 (35% = greyed out)
- Name text color = secondary (grey)
- Pending clock badge shown

When `isPending = false` (after `guided_setup_status = "reviewed_complete"`):
- Vitality ring opacity = 1.0 (100% = full color)
- Name text color = primary (black)
- No badge shown

**The circles ARE clickable** (NavigationLink has no `.disabled()` modifier), but the greyed out appearance makes them LOOK disabled, which confuses users.

---

## Future Enhancements

### Auto-refresh on navigation return
Currently requires manual pull-to-refresh. Could add automatic refresh when:
- Returning from GuidedHealthDataEntryFlow
- App comes to foreground
- Using `.task(id: someValue)` that changes when guided members update

### Persistent dismissed state
Currently dismissed members reset on app restart. Could:
- Save to UserDefaults
- Save to database (new column: `admin_dismissed_notification`)
- Add "Show all" button to un-dismiss

### Real-time updates
Could use Supabase Realtime subscriptions to update dashboard when:
- Member approves guided data
- Member completes onboarding
- Any family member's status changes

---

## Testing Checklist

### Member Circles
- [ ] Admin completes guided setup for member
- [ ] Member logs in and approves
- [ ] Admin pulls down to refresh dashboard
- [ ] Member circle is no longer greyed out
- [ ] Member circle is fully colored with vitality ring
- [ ] Tapping member circle navigates to profile

### Guided Setup Card
- [ ] Card shows all guided members (pending, waiting, complete)
- [ ] Completed member shows "Complete" label
- [ ] Completed member shows X button
- [ ] Clicking X removes member from card
- [ ] Dismissed member stays hidden
- [ ] Card updates after pull-to-refresh

### Edge Cases
- [ ] Multiple completed members can all be dismissed
- [ ] Dismissing all members leaves card empty or hides it
- [ ] Pull-to-refresh brings back dismissed members
- [ ] App restart brings back dismissed members






