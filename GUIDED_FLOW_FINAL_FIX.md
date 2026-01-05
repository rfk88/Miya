# Guided Onboarding Flow - Final Fix

## Issues Addressed

### ✅ Issue 1: Where is data stored before member accepts?

**Answer**: The data IS being saved immediately when the super admin fills it out.

**Storage Location**:
- **Table**: `family_members`
- **Column**: `guided_health_data` (JSONB)

**When it's written**: As soon as the super admin clicks "Save" in the guided data entry form.

**What happens on member approval**: 
1. Data is copied from `family_members.guided_health_data` → `user_profiles` table
2. Risk assessment is calculated and saved
3. Status transitions to `reviewed_complete`

**For live users**: ✅ Data is safe and persisted in the database before the member ever logs in.

---

### ✅ Issue 2: Member seeing "Build your health team" after approval

**Problem**: After approving guided data, members were stuck in the onboarding flow and seeing admin-only screens.

**Root Cause**: The app's top-level routing (`LandingView`) didn't check if onboarding was complete. Even after marking `isOnboardingComplete = true`, the app stayed in the onboarding navigation flow.

**Fix Applied**:
1. Updated `LandingView.body` to check `isOnboardingComplete` and show dashboard
2. Simplified `GuidedSetupReviewView` to rely on top-level routing

---

## How It Works Now

### Complete Flow:

1. **Super admin invites member with guided setup** ✅
   - Status: `pending_acceptance`

2. **Member accepts invite and connects wearable** ✅
   - Status → `accepted_awaiting_data`

3. **Super admin fills member's health data** ✅
   - Data saved to `family_members.guided_health_data` (JSONB column)
   - Status → `data_complete_pending_review`
   - **Data is persisted immediately - safe for live users**

4. **Member logs in and sees review screen** ✅
   - Shows all pre-filled data
   - Member can edit if needed

5. **Member clicks "Confirm & Continue"** ✅
   - Writes data to `user_profiles` table
   - Calculates risk assessment
   - Saves risk to database
   - Marks `isOnboardingComplete = true`
   - **App automatically shows dashboard** (no more onboarding screens)

---

## Code Changes

### File: `ContentView.swift`

#### Change 1: Top-level routing in `LandingView` (line 81)

**Before**:
```swift
var body: some View {
    NavigationStack {
        // ... onboarding flow ...
    }
}
```

**After**:
```swift
var body: some View {
    // If authenticated and onboarding is complete, show dashboard
    if authManager.isAuthenticated && onboardingManager.isOnboardingComplete {
        DashboardView(familyName: onboardingManager.familyName.isEmpty ? "Miya" : onboardingManager.familyName)
    } else {
        NavigationStack {
            // ... onboarding flow ...
        }
    }
}
```

**Why this fixes it**: Once `isOnboardingComplete` is true, the entire view hierarchy switches from onboarding to dashboard. No more getting stuck in onboarding navigation.

#### Change 2: `GuidedSetupReviewView.confirmData()` (lines 4843-4905)

**Key additions**:
```swift
// Calculate risk assessment
let riskResult = RiskCalculator.calculateRisk(
    dateOfBirth: onboardingManager.dateOfBirth,
    smokingStatus: onboardingManager.smokingStatus,
    // ... all risk factors ...
)

// Store risk in OnboardingManager
onboardingManager.riskBand = riskResult.band.rawValue
onboardingManager.riskPoints = riskResult.points
onboardingManager.optimalVitalityTarget = riskResult.optimalTarget

// Save risk to database
try await dataManager.saveRiskAssessment(
    riskBand: riskResult.band.rawValue,
    riskPoints: riskResult.points,
    optimalTarget: riskResult.optimalTarget
)

// Mark onboarding as complete (triggers dashboard display)
await MainActor.run {
    onboardingManager.completeOnboarding()
}
```

#### Change 3: Simplified navigation
- Removed `navigateToDashboard` state variable
- Removed `.navigationDestination` for dashboard
- Now relies on top-level routing (Change 1)

---

## Database Tables

### `family_members` table
**Columns used**:
- `guided_health_data` (JSONB) - Stores admin-filled data before member approval
- `guided_setup_status` - Tracks workflow state
- `guided_data_filled_at` - Timestamp when admin completed data
- `guided_data_reviewed_at` - Timestamp when member approved

**Example data in `guided_health_data`**:
```json
{
  "about_you": {
    "gender": "Male",
    "date_of_birth": "1990-01-15",
    "height_cm": 175,
    "weight_kg": 75,
    "ethnicity": "White",
    "smoking_status": "Never"
  },
  "heart_health": {
    "blood_pressure_status": "normal",
    "diabetes_status": "none",
    "has_prior_heart_attack": false,
    "has_prior_stroke": false,
    "has_chronic_kidney_disease": false,
    "has_atrial_fibrillation": false,
    "has_high_cholesterol": false
  },
  "medical_history": {
    "family_heart_disease_early": false,
    "family_stroke_early": false,
    "family_type2_diabetes": false
  }
}
```

### `user_profiles` table
**Columns written on member approval**:
- All profile fields (gender, date_of_birth, height_cm, weight_kg, etc.)
- WHO risk fields (blood_pressure_status, diabetes_status, etc.)
- Risk assessment (risk_band, risk_points, optimal_vitality_target)
- `onboarding_complete` = true

---

## Testing Checklist

### Happy Path
- [x] Super admin creates guided setup invite
- [x] Member uses invite code
- [x] Member approves guided setup
- [x] Member connects wearable
- [x] Super admin fills member's health data
- [x] **Verify data is in `family_members.guided_health_data`** ✅
- [x] Member logs in and sees review screen
- [x] Member approves data
- [x] **Member sees dashboard (not "Build your health team")** ✅
- [x] Dashboard shows calculated risk band ✅
- [x] Dashboard shows optimal vitality target ✅

### Edge Cases
- [ ] Member edits data before approval
- [ ] Member logs out and back in during flow
- [ ] Super admin edits data multiple times
- [ ] Member switches from guided to self setup

---

## Key Takeaways

1. **Data is safe**: Admin-filled data is stored in `family_members.guided_health_data` immediately. It's not lost if the member doesn't log in right away.

2. **Two-stage storage**:
   - Before approval: `family_members.guided_health_data` (temporary)
   - After approval: `user_profiles` (permanent)

3. **Top-level routing is critical**: The fix required changing how the app decides what to show at the root level, not just adding navigation links.

4. **Onboarding completion triggers dashboard**: Setting `isOnboardingComplete = true` now actually works because `LandingView` checks it.

5. **No more admin-only screens for members**: Members will never see "Build your health team" or other superadmin screens after completing their guided setup.






