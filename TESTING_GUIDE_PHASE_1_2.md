# Testing Guide: Phase 1 & 2

## ✅ What's Been Implemented

### **Phase 1: Critical Profile Creation Fix (7 tasks completed)**
- ✅ Added `createInitialProfile()` function to DataManager
- ✅ Updated `saveUserProfile()` to always UPDATE instead of INSERT
- ✅ SuperadminOnboardingView creates profile immediately after signup
- ✅ EnterCodeView creates profile for invited users
- ✅ Added `isInvitedUser` flag to OnboardingManager

### **Phase 2: Backend Functions (5 tasks completed)**
- ✅ Created database migration for guided setup columns
- ✅ Added `loadGuidedHealthData()` function
- ✅ Added `saveGuidedHealthData()` function
- ✅ Updated `lookupInviteCode()` to check `guided_data_complete`
- ✅ Added `GuidedHealthData` struct for typed health data

---

## 🗄️ STEP 1: Run Database Migration

**IMPORTANT:** Before testing, run the SQL migration in Supabase.

1. Open Supabase Dashboard
2. Navigate to: **SQL Editor**
3. Copy the contents of `guided_setup_migration.sql`
4. Paste into SQL Editor
5. Click **"Run"**
6. Verify success message

**Expected Output:**
```
Success. No rows returned
```

**What this adds:**
- `guided_data_complete` BOOLEAN column to `family_members`
- `guided_health_data` JSONB column to `family_members`

---

## 🧪 STEP 2: Test Phase 1 - Profile Creation Fix

### **Test 1A: Abandon at Step 1 (Account Creation)**

**Goal:** Verify that user_profile is created immediately after signup, so login works even if user quits before completing onboarding.

1. **Create new account:**
   - Email: `test1@test.com`
   - Password: `Test1234!`
   - First Name: `TestUser1`
   - Last Name: `One`

2. **DO NOT complete Step 1** (do not click Continue after account creation)

3. **Force quit the app** (swipe up or Cmd+Q)

4. **Check Supabase `user_profiles` table:**
   ```sql
   SELECT user_id, first_name, onboarding_step, onboarding_complete 
   FROM user_profiles 
   WHERE first_name = 'TestUser1';
   ```
   
   **Expected Result:**
   ```
   user_id: <uuid>
   first_name: TestUser1
   onboarding_step: 1
   onboarding_complete: false
   ```
   ✅ **PASS if row exists with step = 1**

5. **Relaunch app and login:**
   - Click "I already have an account"
   - Email: `test1@test.com`
   - Password: `Test1234!`

6. **Expected Behavior:**
   - ✅ Login succeeds
   - ✅ User is taken to **Step 1** (Family Setup)
   - ✅ No errors about missing profile

---

### **Test 1B: Abandon at Step 2 (After Family Setup)**

1. **Create new account:**
   - Email: `test2@test.com`
   - Password: `Test1234!`
   - First Name: `TestUser2`

2. **Complete Step 1** (create family)

3. **DO NOT complete Step 2** (quit at Wearables screen)

4. **Force quit app**

5. **Check database:**
   ```sql
   SELECT onboarding_step FROM user_profiles WHERE first_name = 'TestUser2';
   ```
   
   **Expected:** `onboarding_step = 2`

6. **Login again:**
   - ✅ Should resume at **Step 2** (Wearables)

---

### **Test 1C: Abandon at Step 5 (After Medical History)**

1. **Create new account:** `test3@test.com`

2. **Complete steps 1-4:**
   - Family Setup
   - Wearables
   - About You
   - Heart Health
   - Medical History

3. **Quit at Risk Results screen** (Step 5)

4. **Check database:**
   ```sql
   SELECT onboarding_step FROM user_profiles WHERE email = 'test3@test.com';
   ```
   
   **Expected:** `onboarding_step = 5`

5. **Login again:**
   - ✅ Should resume at **Step 5** (Risk Results)

---

## 🧪 STEP 3: Test Phase 2 - Guided Setup Backend

### **Test 2A: Invite Code Validation (Guided Setup - Incomplete)**

**Goal:** Verify that guided setup invites cannot be used until superadmin completes health data entry.

1. **Create a new family** as a superadmin (use `test-superadmin@test.com`)

2. **Generate a guided setup invite:**
   - Go to Family Members Invite screen
   - Add member: Name = "GuidedUser1", Relationship = "Parent"
   - Select **"Guided Setup"**
   - Note the invite code (e.g., `ABC123`)

3. **Check database:**
   ```sql
   SELECT invite_code, onboarding_type, guided_data_complete 
   FROM family_members 
   WHERE first_name = 'GuidedUser1';
   ```
   
   **Expected:**
   ```
   invite_code: ABC123
   onboarding_type: Guided Setup
   guided_data_complete: false  ← Should be FALSE
   ```

4. **Try to use the invite code:**
   - On landing page, click "I have an invite code"
   - Enter the code: `ABC123`
   - Click "Look Up Code"

5. **Expected Error:**
   ```
   "This invite is not ready yet. Your family member needs to complete 
   your health information first. Please contact them."
   ```
   
   ✅ **PASS if error message appears**

---

### **Test 2B: Self Setup Invite (Should Work Immediately)**

1. **Generate a self-setup invite:**
   - Add member: Name = "SelfUser1", Relationship = "Spouse"
   - Select **"Self Setup"**
   - Note invite code (e.g., `XYZ789`)

2. **Check database:**
   ```sql
   SELECT invite_code, onboarding_type, guided_data_complete 
   FROM family_members 
   WHERE first_name = 'SelfUser1';
   ```
   
   **Expected:**
   ```
   guided_data_complete: true  ← Should be TRUE for Self Setup
   ```

3. **Use the invite code:**
   - Enter code: `XYZ789`
   - Click "Look Up Code"

4. **Expected Result:**
   - ✅ Invite code accepted
   - ✅ Shows family info and onboarding type
   - ✅ No error about incomplete data

---

### **Test 2C: Guided Setup Data Entry (Manual)**

**Note:** The UI for guided data entry doesn't exist yet (that's Phase 3). This test verifies the backend functions work.

1. **Manually insert guided health data into database:**
   
   ```sql
   UPDATE family_members
   SET 
     guided_health_data = '{
       "about_you": {
         "gender": "Male",
         "date_of_birth": "1980-05-15",
         "height_cm": 180,
         "weight_kg": 80,
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
         "family_type2_diabetes": true
       }
     }'::jsonb,
     guided_data_complete = true
   WHERE first_name = 'GuidedUser1';
   ```

2. **Verify update:**
   ```sql
   SELECT guided_data_complete FROM family_members WHERE first_name = 'GuidedUser1';
   ```
   
   **Expected:** `true`

3. **Try to use invite code again:**
   - Enter code for GuidedUser1
   - ✅ Should now work (no error)

---

## 📊 Success Criteria

### **Phase 1 Tests**
- ✅ All 3 abandon tests (1A, 1B, 1C) should pass
- ✅ `user_profiles` table should have a row for every authenticated user
- ✅ `onboarding_step` should persist correctly across app restarts
- ✅ Login always resumes at correct step

### **Phase 2 Tests**
- ✅ Guided setup invites are blocked when `guided_data_complete = false`
- ✅ Self-setup invites work immediately
- ✅ Guided setup invites work after data is completed
- ✅ No database errors or crashes

---

## 🐛 Common Issues & Fixes

### **Issue: "Column guided_data_complete does not exist"**
**Fix:** Run `guided_setup_migration.sql` in Supabase SQL Editor

### **Issue: Login always goes to step 1**
**Fix:** Check that `add_onboarding_tracking.sql` was run (adds `onboarding_step` column)

### **Issue: "This information already exists" error**
**Fix:** This should be fixed now (saveUserProfile always UPDATEs). If still happening, check console logs for details.

### **Issue: User profile not created**
**Fix:** Check console logs for errors in `createInitialProfile()`. Verify user is authenticated before calling.

---

## 📝 What to Report Back

After testing, please report:

1. **Which tests passed?** (1A, 1B, 1C, 2A, 2B, 2C)
2. **Which tests failed?** (with error messages/screenshots)
3. **Any database errors?** (check Supabase logs)
4. **Any console errors?** (check Xcode console)

Once Phase 1 & 2 tests pass, we'll move to Phase 3 (Guided Setup UI) and Phase 4 (Self-Setup Invited Users).

---

## 🎯 Files to Review

If you want to verify the code changes:

- **DataManager.swift:** Lines 106-145 (createInitialProfile), Lines 424-436 (saveUserProfile UPDATE logic), Lines 545-600 (guided setup functions)
- **ContentView.swift:** Lines 959-962 (SuperadminOnboardingView), Lines 489-496 (EnterCodeView)
- **OnboardingManager.swift:** Line 21 (isInvitedUser flag)
- **guided_setup_migration.sql:** Database migration

---

**Ready to test!** Let me know the results and we'll proceed to Phase 3 when you're ready.

