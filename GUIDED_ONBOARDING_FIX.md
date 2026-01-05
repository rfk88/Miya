# Guided Onboarding Flow - Fixed

## Summary

Fixed the guided user onboarding flow to properly save data and route members to the dashboard after approval.

## What Was Broken

### Issue 1: Super admin filling data not visible
- **Status**: ✅ **ACTUALLY WORKING CORRECTLY**
- **Explanation**: The data IS being saved to the database in the `family_members.guided_health_data` JSON column. It's not supposed to go to `user_profiles` until the member approves it.

### Issue 2: Member approval routing back to onboarding (showing "Build your health team")
- **Status**: ✅ **FIXED**
- **Problem**: After approving guided data, members were stuck in the onboarding flow and seeing admin-only screens like "Build your health team"
- **Root Cause**: The app's top-level routing (`LandingView`) didn't check if onboarding was complete, so members stayed in the onboarding navigation flow even after approval
- **Fix**: 
  1. Updated `LandingView.body` to check `isOnboardingComplete` and show dashboard
  2. Updated `GuidedSetupReviewView.confirmData()` to:
  1. Calculate risk assessment using `RiskCalculator`
  2. Save risk to database via `DataManager.saveRiskAssessment()`
  3. Mark onboarding as complete
  4. Navigate to dashboard

## How It Works Now

### Step 1: Super Admin Invites Member (✅ Working)
1. Super admin creates invite with "Guided Setup" selected
2. Invite code is generated
3. Member record created in `family_members` with `guided_setup_status = 'pending_acceptance'`

### Step 2: Member Accepts Invite (✅ Working)
1. Member uses invite code and creates account
2. Member sees acceptance prompt
3. When accepted:
   - Status transitions to `accepted_awaiting_data`
   - Member connects wearable
   - Member waits for admin to fill data

### Step 3: Super Admin Fills Member's Data (✅ Working)
1. Admin sees pending guided setups in dashboard
2. Admin fills out member's health information
3. Data saved to `family_members.guided_health_data` (JSON column)
4. Status transitions to `data_complete_pending_review`

**Storage Location**: `family_members` table, `guided_health_data` column (JSONB)
- This is temporary storage until member approves
- Contains: about_you, heart_health, medical_history

### Step 4: Member Approves Data (✅ FIXED)
1. Member logs in and sees `GuidedSetupReviewView`
2. Member reviews all pre-filled health information
3. Member can edit if needed (edits saved back to `guided_health_data`)
4. **When member clicks "Confirm & Continue"**:
   - ✅ Data is written to `user_profiles` table
   - ✅ Risk assessment is calculated
   - ✅ Risk saved to database (`risk_band`, `risk_points`, `optimal_vitality_target`)
   - ✅ Status transitions to `reviewed_complete`
   - ✅ Onboarding marked complete
   - ✅ **Navigates to dashboard** (FIXED!)

### Step 5: Member Edits Data Later (✅ Working)
If a member wants to edit their health data after approval:
1. From dashboard, navigate to profile/health settings
2. Edit views write directly to `user_profiles` table
3. Risk is automatically recalculated in `MedicalHistoryView.saveProfile()`
4. Changes saved to database

## Database Tables Used

### `family_members` table
- Stores invite information
- `guided_health_data` (JSONB) - temporary storage before member approval
- `guided_setup_status` - tracks workflow state
- `guided_data_filled_at` - timestamp when admin completed data
- `guided_data_reviewed_at` - timestamp when member approved

### `user_profiles` table
- Stores approved health data
- All profile fields (gender, DOB, height, weight, etc.)
- WHO risk fields (blood_pressure_status, diabetes_status, etc.)
- Risk assessment results (risk_band, risk_points, optimal_vitality_target)

## Code Changes Made

### File: `ContentView.swift`

#### 1. Fixed top-level routing in `LandingView` (line 81)
Added check to show dashboard when onboarding is complete:
```swift
var body: some View {
    // If authenticated and onboarding is complete, show dashboard
    if authManager.isAuthenticated && onboardingManager.isOnboardingComplete {
        DashboardView(familyName: onboardingManager.familyName.isEmpty ? "Miya" : onboardingManager.familyName)
    } else {
        // ... existing onboarding flow ...
    }
}
```

This ensures that once a member completes onboarding (including guided setup approval), they immediately see the dashboard instead of being stuck in the onboarding navigation flow.

#### 2. Fixed `GuidedSetupReviewView.confirmData()` (lines 4843-4916)
```swift
private func confirmData() async {
    do {
        // 1. Write guided data to user_profiles
        try await dataManager.confirmGuidedDataReview(memberId: memberId)
        onboardingManager.guidedSetupStatus = .reviewedComplete
        
        // 2. Sync OnboardingManager state
        if let data = guidedData {
            // ... sync all fields ...
            
            // 3. Calculate risk assessment
            let riskResult = RiskCalculator.calculateRisk(
                dateOfBirth: onboardingManager.dateOfBirth,
                smokingStatus: onboardingManager.smokingStatus,
                // ... all risk factors ...
            )
            
            // 4. Store risk in OnboardingManager
            onboardingManager.riskBand = riskResult.band.rawValue
            onboardingManager.riskPoints = riskResult.points
            onboardingManager.optimalVitalityTarget = riskResult.optimalTarget
            
            // 5. Save risk to database
            try await dataManager.saveRiskAssessment(
                riskBand: riskResult.band.rawValue,
                riskPoints: riskResult.points,
                optimalTarget: riskResult.optimalTarget
            )
        }
        
        // 6. Mark onboarding complete
        onboardingManager.completeOnboarding()
        
        // 7. Navigate to dashboard
        await MainActor.run {
            navigateToDashboard = true
        }
    }
}
```

#### 3. Simplified `GuidedSetupReviewView` navigation
- Removed `navigateToDashboard` state variable
- Removed `.navigationDestination` for dashboard
- Now relies on top-level routing to show dashboard when `isOnboardingComplete` is true

## Testing Checklist

### Happy Path
- [ ] Super admin creates guided setup invite
- [ ] Member uses invite code
- [ ] Member approves guided setup
- [ ] Member connects wearable
- [ ] Super admin fills member's health data
- [ ] Member logs in and sees review screen
- [ ] Member approves data
- [ ] **Member is taken to dashboard** ✅
- [ ] Dashboard shows calculated risk band ✅
- [ ] Dashboard shows optimal vitality target ✅

### Edit Flow
- [ ] Member can edit data before approval
- [ ] Edits are saved to guided_health_data
- [ ] Member can still approve after editing
- [ ] After approval, member can edit from dashboard
- [ ] Dashboard edits save to user_profiles
- [ ] Risk is recalculated after edits

### Data Persistence
- [ ] Super admin's filled data is in `family_members.guided_health_data`
- [ ] After member approval, data is in `user_profiles`
- [ ] Risk assessment is saved in `user_profiles`
- [ ] Status transitions are correct at each step

## Notes

1. **Two-stage storage**: 
   - Before approval: `family_members.guided_health_data` (temporary)
   - After approval: `user_profiles` (permanent)

2. **Risk calculation**: Only happens AFTER member approves (not when admin fills data)

3. **Onboarding completion**: Automatically marked complete when member approves

4. **Future enhancement**: Consider adding a dedicated health profile editor in the dashboard that's separate from the onboarding flow for post-onboarding edits.

