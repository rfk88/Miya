# Guided Setup V2 Implementation Complete

## Summary

Implemented the new flexible guided setup flow where:
1. Admin can choose to "Fill out now" or "Fill out later" when creating guided invites
2. Invited users can accept guided setup or choose to fill their own data
3. Users review and confirm data before finalizing

---

## Database Migration Required

**Run this SQL in Supabase SQL Editor:**

```sql
-- From: guided_setup_v2_migration.sql

BEGIN;

ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_setup_status TEXT DEFAULT NULL;

ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_data_filled_at TIMESTAMP DEFAULT NULL;

ALTER TABLE family_members 
ADD COLUMN IF NOT EXISTS guided_data_reviewed_at TIMESTAMP DEFAULT NULL;

-- Set status for existing guided setup invites
UPDATE family_members
SET guided_setup_status = CASE
    WHEN onboarding_type = 'Guided Setup' AND guided_data_complete = true THEN 'data_complete_pending_review'
    WHEN onboarding_type = 'Guided Setup' AND (guided_data_complete = false OR guided_data_complete IS NULL) THEN 'pending_acceptance'
    ELSE NULL
END
WHERE guided_setup_status IS NULL;

COMMIT;
```

---

## New Flow Diagrams

### Admin Creates Invite
```
Admin → Select "Guided Setup"
├─ "Fill out now" → GuidedHealthDataEntryFlow → Show invite code
└─ "Fill out later" → Show invite code (status: pending_acceptance)
```

### Invited User Enters Code
```
User enters code
├─ Self Setup → AboutYouView (full onboarding, skip family creation)
├─ Guided Setup (no data) → GuidedSetupAcceptancePrompt
│   ├─ "Accept" → WearableSelectionView (status: accepted_awaiting_data)
│   └─ "Fill myself" → AboutYouView (switch to self setup)
└─ Guided Setup (has data) → GuidedSetupReviewView
    ├─ "Confirm" → WearableSelectionView (status: reviewed_complete)
    └─ "Make Changes" → AboutYouView (edit mode)
```

### Admin Fills Pending Data
```
Admin Dashboard → PendingGuidedSetupsView
├─ Shows members with status = accepted_awaiting_data
└─ "Fill Out" → GuidedHealthDataEntryFlow
    └─ On complete: status = data_complete_pending_review
```

---

## Status Values

| Status | Description |
|--------|-------------|
| `NULL` | Self Setup (not applicable) |
| `pending_acceptance` | Invite created, user hasn't entered code yet |
| `accepted_awaiting_data` | User accepted guided, waiting for admin to fill data |
| `data_complete_pending_review` | Admin filled data, user needs to review |
| `reviewed_complete` | User confirmed, profile is done |

---

## New Views Created

### 1. GuidedSetupOptionsSheet
- Shown when admin selects "Guided Setup"
- Options: "Fill out now" / "Fill out later"

### 2. GuidedHealthDataEntryFlow
- 3-step form for admin to fill health data
- Step 1: About You (gender, DOB, height, weight, ethnicity, smoking)
- Step 2: Heart Health (BP, diabetes, conditions)
- Step 3: Medical History (family history)

### 3. GuidedSetupAcceptancePrompt
- Shown to invited user for guided invites without data
- Options: "Accept Guided Setup" / "Fill it myself"

### 4. GuidedSetupReviewView
- Shown when admin has pre-filled data
- Displays all health info in review format
- Options: "Confirm & Continue" / "Make Changes"

### 5. PendingGuidedSetupsView
- Admin dashboard showing members awaiting data entry
- Shows name, relationship, waiting status
- "Fill Out" button for each member

---

## DataManager Functions Added

```swift
// Update guided setup status
func updateGuidedSetupStatus(memberId: String, status: String) async throws

// Get pending guided setups for a family
func getPendingGuidedSetups(familyId: String) async throws -> [FamilyMemberRecord]

// User accepts guided setup
func acceptGuidedSetup(memberId: String) async throws

// Switch from guided to self setup
func switchToSelfSetup(memberId: String) async throws

// Confirm data review
func confirmGuidedDataReview(memberId: String) async throws

// Save invite with ID returned
func saveFamilyMemberInviteWithId(...) async throws -> (inviteCode: String, memberId: String)
```

---

## Files Modified

- `Miya Health/DataManager.swift` - New functions, updated InviteDetails struct
- `Miya Health/ContentView.swift` - New views, updated FamilyMembersInviteView and EnterCodeView
- `guided_setup_v2_migration.sql` - Database schema changes

---

## Testing Checklist

### Test 1: Fill Out Now Flow
1. Create guided invite → Click "Fill out now"
2. Complete 3-step form
3. Verify invite code shown
4. Invited user enters code → Should see review screen
5. Confirm → Goes to wearables

### Test 2: Fill Out Later Flow
1. Create guided invite → Click "Fill out later"
2. Verify invite code shown immediately
3. Invited user enters code → Should see acceptance prompt
4. Accept → Goes to wearables (status = accepted_awaiting_data)
5. Admin goes to PendingGuidedSetupsView
6. Admin fills data
7. User is notified (future: push notification)

### Test 3: User Switches to Self Setup
1. Create guided invite
2. Invited user enters code → Sees acceptance prompt
3. Click "Fill it myself"
4. Should go to AboutYouView (full self-setup)
5. Verify onboarding_type changed to "Self Setup"

### Test 4: Self Setup Invite
1. Create self setup invite
2. Invited user enters code
3. Should go directly to AboutYouView (skip family creation)

---

## Next Steps

1. **Run the database migration** (guided_setup_v2_migration.sql)
2. **Test all flows** in simulator
3. **Add dashboard navigation** to PendingGuidedSetupsView (from main dashboard)
4. **Add push notifications** when user accepts / admin completes data
5. **Add reminder logic** for incomplete guided setups

---

## Completed Tasks (9/10)

- ✅ Database migration for guided setup v2
- ✅ DataManager: Remove blocking check, add new functions
- ✅ FamilyMembersInviteView: Add Fill out now / Fill out later options
- ✅ EnterCodeView: Add acceptance prompt for guided invites
- ✅ Create GuidedSetupAcceptanceView
- ✅ Create GuidedSetupReviewView
- ✅ Create GuidedHealthDataEntryFlow
- ✅ Create PendingGuidedSetupsView
- ✅ Update self-setup flow to skip family creation
- ⏳ Test complete guided setup flow

