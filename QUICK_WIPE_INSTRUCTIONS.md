# Quick Database Wipe Instructions

## Step-by-Step

### 1. Open Supabase Dashboard
- Go to https://supabase.com/dashboard
- Select your Miya Health project

### 2. Open SQL Editor
- Click "SQL Editor" in the left sidebar
- Click "New query"

### 3. Copy & Paste This SQL

```sql
BEGIN;

-- Delete all app data
DELETE FROM vitality_scores;
DELETE FROM health_conditions;
DELETE FROM family_members;
DELETE FROM family_invites;
DELETE FROM families;
DELETE FROM user_profiles;
DELETE FROM alert_preferences;

COMMIT;

-- Verify deletion
SELECT 
    (SELECT COUNT(*) FROM vitality_scores) as vitality_scores_count,
    (SELECT COUNT(*) FROM health_conditions) as health_conditions_count,
    (SELECT COUNT(*) FROM family_members) as family_members_count,
    (SELECT COUNT(*) FROM family_invites) as family_invites_count,
    (SELECT COUNT(*) FROM families) as families_count,
    (SELECT COUNT(*) FROM user_profiles) as user_profiles_count,
    (SELECT COUNT(*) FROM alert_preferences) as alert_preferences_count;
```

### 4. Run the Query
- Click "Run" button (or press Cmd+Enter)
- Wait for completion

### 5. Verify Results
- You should see all counts = 0
- If any count > 0, there may be foreign key constraints preventing deletion

### 6. Done!
- Database is now wiped
- Auth users remain (you can still log in)
- Ready for fresh testing

---

## If You Get Foreign Key Errors

If you see errors about foreign keys, run this instead (more aggressive):

```sql
BEGIN;

-- Delete with CASCADE to handle foreign keys
DELETE FROM vitality_scores CASCADE;
DELETE FROM health_conditions CASCADE;
DELETE FROM family_members CASCADE;
DELETE FROM family_invites CASCADE;
DELETE FROM families CASCADE;
DELETE FROM user_profiles CASCADE;
DELETE FROM alert_preferences CASCADE;

COMMIT;
```

---

## After Wiping

1. **Launch the app**
2. **Create a new account** (sign up)
3. **Complete onboarding** (all steps fresh)
4. **Import test data** (use `vitality_sample.json`)
5. **Test new engine** (see side-by-side comparison)

Everything will work perfectly! 🎉

