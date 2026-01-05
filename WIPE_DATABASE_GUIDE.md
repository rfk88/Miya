# 🗑️ Database Wipe Guide

## ⚠️ What This Does

**Deletes ALL app data:**
- ✅ All vitality scores
- ✅ All health conditions
- ✅ All family memberships
- ✅ All family invites
- ✅ All families
- ✅ All user profiles (onboarding data, risk assessments, etc.)
- ✅ All alert preferences

**Preserves:**
- ✅ Auth users (you can still log in with existing accounts)
- ✅ Database schema (tables, columns, constraints remain intact)

---

## ✅ Will This Cause Errors?

**No, the app handles empty database gracefully:**

### 1. **Missing User Profile**
- `loadUserProfile()` returns `nil` if no profile found
- App treats this as "new user" → starts onboarding
- ✅ **No crash**

### 2. **Missing Family Data**
- `fetchFamilyData()` handles empty results with `if let` checks
- `currentFamilyId` will be `nil`
- Dashboard will show empty state
- ✅ **No crash**

### 3. **Missing Vitality Scores**
- `importedVitalityScore` will be `nil` initially
- UI shows "Import Health Data" button
- ✅ **No crash**

### 4. **Error Handling**
- All database calls wrapped in `try/catch`
- Errors logged to console, not shown to user
- ✅ **No crash**

---

## 📋 How to Wipe Database

### Option 1: SQL Script (Recommended)

1. Open Supabase Dashboard
2. Go to SQL Editor
3. Copy contents of `wipe_database.sql`
4. Paste and run
5. Verify all counts are 0

### Option 2: Manual Deletion

In Supabase SQL Editor, run:

```sql
BEGIN;

DELETE FROM vitality_scores;
DELETE FROM health_conditions;
DELETE FROM family_members;
DELETE FROM family_invites;
DELETE FROM families;
DELETE FROM user_profiles;
DELETE FROM alert_preferences;

COMMIT;
```

### Option 3: Delete Auth Users Too (Complete Reset)

If you want to delete auth users as well:

```sql
-- ⚠️ This deletes EVERYTHING including auth accounts
DELETE FROM auth.users CASCADE;
```

**Note:** After this, you'll need to create new accounts.

---

## 🔄 What Happens After Wipe

### On Next App Launch:

1. **If logged in:**
   - App tries to fetch user profile → finds nothing
   - App tries to fetch family data → finds nothing
   - User sees onboarding screen (or dashboard with empty state)
   - ✅ **No errors, graceful handling**

2. **If not logged in:**
   - User sees login/signup screen
   - Can create new account
   - Starts fresh onboarding

3. **Onboarding Flow:**
   - All steps start fresh
   - No existing data to restore
   - User completes onboarding normally

4. **Dashboard:**
   - Shows empty state (no family members)
   - Shows mock vitality data (hardcoded 78/100)
   - Can import new vitality data

---

## 🧪 Testing After Wipe

### Test Scenarios:

1. **New User Signup**
   - ✅ Should work normally
   - ✅ Creates new user profile
   - ✅ Starts onboarding at step 1

2. **Existing User Login**
   - ✅ Should work (auth account still exists)
   - ✅ No profile found → starts onboarding
   - ✅ Can complete onboarding fresh

3. **Vitality Import**
   - ✅ Should work normally
   - ✅ Saves to empty database
   - ✅ Shows scores in UI

4. **Family Creation**
   - ✅ Should work normally
   - ✅ Creates new family
   - ✅ Can invite members

---

## ⚠️ Important Notes

### Before Wiping:

1. **Backup if needed:**
   ```sql
   -- Export data before wiping (optional)
   SELECT * FROM user_profiles;
   SELECT * FROM vitality_scores;
   SELECT * FROM families;
   ```

2. **Check current data:**
   ```sql
   SELECT COUNT(*) FROM user_profiles;
   SELECT COUNT(*) FROM vitality_scores;
   ```

### After Wiping:

1. **Verify deletion:**
   ```sql
   SELECT COUNT(*) FROM user_profiles;  -- Should be 0
   SELECT COUNT(*) FROM vitality_scores; -- Should be 0
   ```

2. **Test app:**
   - Launch app
   - Sign in (or create account)
   - Complete onboarding
   - Import vitality data
   - Verify everything works

---

## 🐛 Potential Issues (Rare)

### Issue 1: Cached Auth Session
**Symptom:** App thinks user is logged in but database has no profile

**Solution:**
- Log out and log back in
- Or delete app and reinstall
- Or clear UserDefaults (in code)

### Issue 2: Foreign Key Constraints
**Symptom:** SQL error about foreign keys

**Solution:**
- Delete in correct order (as shown in script)
- Or use `CASCADE` delete:
  ```sql
  DELETE FROM user_profiles CASCADE;
  ```

### Issue 3: Dashboard Shows Old Data
**Symptom:** Dashboard still shows mock data

**Solution:**
- This is expected (mock data is hardcoded)
- Import real data to see actual scores

---

## ✅ Summary

**Safe to wipe?** ✅ **YES**

**Will cause errors?** ✅ **NO** - App handles empty database gracefully

**What to do:**
1. Run `wipe_database.sql` in Supabase SQL Editor
2. Verify all counts are 0
3. Launch app and test
4. Complete onboarding fresh
5. Import test vitality data

**Expected behavior:**
- App launches normally
- No crashes or errors
- Onboarding starts fresh
- All features work normally

---

## 🚀 Quick Start After Wipe

1. **Sign up/Login** → Create account or use existing auth
2. **Complete onboarding** → Go through all steps
3. **Import vitality data** → Use `vitality_sample.json` or CSV
4. **Test new engine** → See side-by-side comparison in RiskResultsView
5. **Create family** → Test family features

**Everything should work perfectly! 🎉**

