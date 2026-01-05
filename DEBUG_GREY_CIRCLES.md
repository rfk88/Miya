# Debug: Why Are Member Circles Still Grey?

## Quick Answer

Member circles appear grey when their `guided_setup_status` in the database is NOT `"reviewed_complete"`.

## The Logic

From `DashboardView.swift` (lines 30-37):

```swift
var isPending: Bool {
    if onboardingType == "Guided Setup" {
        return guidedSetupStatus != "reviewed_complete"  // ← THIS IS THE CHECK
    }
    return (inviteStatus ?? "").lowercased() == "pending"
}
```

When `isPending = true`:
- Circle opacity = 0.35 (greyed out)
- Clock badge appears
- Name text is grey

## Check Your Database

Run this query in Supabase:

```sql
SELECT 
    first_name,
    onboarding_type,
    guided_setup_status,
    invite_status
FROM family_members
WHERE family_id = 'YOUR_FAMILY_ID'
AND onboarding_type = 'Guided Setup';
```

**What you should see**:

| first_name | onboarding_type | guided_setup_status | Expected Appearance |
|------------|----------------|---------------------|---------------------|
| 5g@5.com | Guided Setup | accepted_awaiting_data | ⏰ Grey (waiting for admin) |
| 6Guided 2 | Guided Setup | data_complete_pending_review | ⏰ Grey (waiting for member) |
| 4Guide | Guided Setup | reviewed_complete | ✅ Colored (complete!) |

## Why Members Stay Grey After "Completing"

### Scenario 1: Member hasn't actually approved yet
- Status is still `data_complete_pending_review`
- Admin filled data, but member hasn't logged in to approve

### Scenario 2: Approval didn't save
- Check the console logs when member clicks "Confirm & Continue"
- Look for errors in `confirmGuidedDataReview`
- Check if status transition succeeded

### Scenario 3: Dashboard not refreshing after approval
- Pull down to refresh after member approves
- Dashboard reloads member data from database
- If still grey, status in DB is not `reviewed_complete`

## Force Refresh Test

1. Open Supabase Dashboard
2. Manually set `guided_setup_status = 'reviewed_complete'` for a member
3. Go back to app
4. Pull down to refresh dashboard
5. Circle should now be colored (not grey)

If this works ✅ → The problem is in the approval flow (not saving status correctly)
If this doesn't work ❌ → The problem is in the refresh logic (not loading status correctly)

## Console Logs to Check

When member approves guided data, you should see:

```
✅ DataManager: Updated guided setup status to 'reviewed_complete' for member {memberId}
GUIDED_STATUS_WRITE: memberId={memberId} old=data_complete_pending_review new=reviewed_complete
```

If you DON'T see these logs, the status transition failed.

When dashboard loads, you should see:

```
📥 DataManager: Found {N} family members for family {familyId}
```

Then check what `guided_setup_status` values are loaded.

## Quick Fix If Status Isn't Saving

If the status isn't transitioning to `reviewed_complete` after member approves:

1. Check `GuidedSetupReviewView.confirmData()` - does it call `confirmGuidedDataReview`?
2. Check `DataManager.confirmGuidedDataReview()` - does it call `updateGuidedSetupStatus`?
3. Check database logs in Supabase - are UPDATE statements succeeding?

## The Real Question

**After rebuild, when you pull to refresh**:
- Does the console show it's reloading family members?
- What `guided_setup_status` values are in the database for these members?

The circles are showing the CORRECT data based on the database. If they're grey, the database says they're not complete yet.






