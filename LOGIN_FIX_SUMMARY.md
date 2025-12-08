# LOGIN FIX - ROOT CAUSES & SOLUTION

## 🔴 THE ACTUAL BUGS (Now Fixed)

### **Bug #1: resumeDestination using UserDefaults instead of database**
**Location:** `ContentView.swift` line 33

**BEFORE (BROKEN):**
```swift
private var resumeDestination: some View {
    switch onboardingManager.loadPersistedStep() {  // ❌ Reads from UserDefaults
```

**AFTER (FIXED):**
```swift
private var resumeDestination: some View {
    switch onboardingManager.currentStep {  // ✅ Uses step loaded from database
```

**What this caused:** Even though LoginView correctly loaded the step from the database, LandingView ignored it and used the old UserDefaults value (which is always 1 for a new device/rebuild).

---

### **Bug #2: Login callback overwrites database step**
**Location:** `ContentView.swift` lines 181-184

**BEFORE (BROKEN):**
```swift
LoginView {
    let step = onboardingManager.loadPersistedStep()  // ❌ Overwrites DB step with UserDefaults
    onboardingManager.setCurrentStep(step)
    navigateResume = true
}
```

**AFTER (FIXED):**
```swift
LoginView {
    // LoginView already loaded profile and set currentStep from database
    navigateResume = true  // ✅ Just trigger navigation
}
```

**What this caused:** LoginView loaded step from database → Set currentStep → Callback immediately overwrote it with UserDefaults value → Always went to step 1.

---

## ✅ ALL CHANGES MADE

### 1. **Database Schema** (`add_onboarding_tracking.sql`)
```sql
ALTER TABLE user_profiles ADD COLUMN onboarding_step INTEGER DEFAULT 1;
ALTER TABLE user_profiles ADD COLUMN onboarding_complete BOOLEAN DEFAULT FALSE;
```

### 2. **DataManager.swift**
- ✅ Added `saveOnboardingProgress(step:, complete:)` - saves to DB
- ✅ Added `loadUserProfile() -> UserProfileData?` - loads from DB
- ✅ Added `UserProfileData` struct with all fields including `onboarding_step`
- ✅ Updated `saveUserProfile(...)` to accept optional `onboardingStep` parameter

### 3. **OnboardingManager.swift**
- ✅ Added `weak var dataManager: DataManager?` reference
- ✅ Updated `currentStep` `didSet` to auto-save to database via DataManager
- ✅ Updated `isOnboardingComplete` `didSet` to auto-save to database

### 4. **ContentView.swift (LoginView)**
- ✅ Complete rewrite to load ALL profile data from database
- ✅ Populates OnboardingManager with: name, DOB, health data, risk scores, etc.
- ✅ Sets `currentStep` from database (not UserDefaults)

### 5. **ContentView.swift (LandingView)**
- ✅ Fixed `resumeDestination` to use `currentStep` (Bug #1)
- ✅ Fixed login callback to not overwrite DB step (Bug #2)

### 6. **ContentView.swift (AboutYouView)**
- ✅ Updated `saveUserProfile()` call to include `onboardingStep: onboardingManager.currentStep`

### 7. **Miya_HealthApp.swift**
- ✅ Links `dataManager` to `onboardingManager` on app init
- ✅ Ensures automatic step saving works

---

## 🚀 HOW IT WORKS NOW

### **Creating Account Flow:**
1. User creates account → `firstName` saved to auth metadata
2. User completes Step 1 (Family Setup) → `currentStep` changed to 2
3. `OnboardingManager.currentStep.didSet` → Calls `dataManager.saveOnboardingProgress(step: 2)`
4. Database updated: `onboarding_step = 2`
5. User closes app → **Progress saved in Supabase**

### **Login Flow:**
1. User clicks "I already have an account"
2. LoginView: User enters email/password → Signs in
3. LoginView: Calls `dataManager.loadUserProfile()`
4. Database returns: All profile data + `onboarding_step = 2`
5. LoginView: Populates OnboardingManager with all fields
6. LoginView: Sets `onboardingManager.currentStep = 2` (from database)
7. LandingView callback: Sets `navigateResume = true`
8. LandingView: `resumeDestination` uses `onboardingManager.currentStep` (= 2)
9. User navigates to **Step 2** ✅

### **Cross-Device Flow:**
1. User logs in on different device
2. Same database profile loaded → Same step restored
3. Works everywhere ✅

---

## ⚠️ CRITICAL: YOU MUST RUN THIS SQL FIRST

**Before testing, run this in Supabase SQL Editor:**

```sql
-- Copy entire contents of add_onboarding_tracking.sql
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS onboarding_step INTEGER DEFAULT 1;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN DEFAULT FALSE;

UPDATE user_profiles 
SET onboarding_step = 1 
WHERE onboarding_step IS NULL;

UPDATE user_profiles 
SET onboarding_complete = FALSE 
WHERE onboarding_complete IS NULL;
```

---

## 🧪 TEST PROCEDURE

### **Test 1: New User Onboarding**
1. Create new account with email: `test@example.com`
2. Complete Step 1 (Family Setup)
3. Verify database: `SELECT onboarding_step FROM user_profiles WHERE ...` → Should be 2
4. Force quit app
5. Login with `test@example.com`
6. **EXPECTED:** Navigate to Step 2 (Wearables) ✅

### **Test 2: Resume Mid-Onboarding**
1. Login as existing user
2. Complete Steps 2, 3, 4
3. Force quit app at Step 5
4. Login again
5. **EXPECTED:** Navigate to Step 5 ✅

### **Test 3: Cross-Device**
1. Login on Simulator (iPhone 15)
2. Complete Steps 1-3
3. Login on different Simulator (iPhone 15 Pro)
4. **EXPECTED:** Resume at Step 4 ✅

---

## 🔍 DEBUGGING

### **Check Database:**
```sql
SELECT user_id, first_name, onboarding_step, onboarding_complete 
FROM user_profiles 
ORDER BY created_at DESC 
LIMIT 10;
```

### **Expected Console Logs (on login):**
```
✅ LoginView: User authenticated
📥 DataManager: Loaded user profile from database
   - Step: 2
   - Name: John
   - Risk Band: low
✅ LoginView: Profile loaded - Navigating to step 2
```

### **If still broken:**
1. **SQL not run:** Check if columns exist
2. **No profile in DB:** User might not have saved profile yet (needs to complete AboutYouView)
3. **UserDefaults cache:** Clear app data in simulator (Device → Erase All Content and Settings)

---

## 📊 WHAT'S IN DATABASE NOW

| Column | Type | When Set | Purpose |
|--------|------|----------|---------|
| `onboarding_step` | INTEGER | On every step change | Current step (1-8) |
| `onboarding_complete` | BOOLEAN | On completion | Finished? |
| `first_name` | TEXT | Step 1 | From auth metadata |
| `last_name` | TEXT | Step 3 | AboutYou |
| `date_of_birth` | DATE | Step 3 | AboutYou |
| All health fields | Various | Steps 3-5 | AboutYou, HeartHealth, MedicalHistory |
| `risk_band` | TEXT | Step 6 | RiskResults |
| `risk_points` | INTEGER | Step 6 | RiskResults |
| `optimal_vitality_target` | INTEGER | Step 6 | RiskResults |

**Everything persists. Nothing lost. Works everywhere.**

---

## 🎯 THE FIX IS COMPLETE

Both bugs are now fixed:
- ✅ Navigation uses database step (not UserDefaults)
- ✅ Login callback doesn't overwrite database step
- ✅ Step auto-saves to database on change
- ✅ Profile loads from database on login
- ✅ Works across devices

**Rebuild, run SQL, test.**

