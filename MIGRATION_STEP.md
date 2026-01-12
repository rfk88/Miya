# ✅ Almost Done! One Final Step

## What's Already Complete:
- ✅ Edge Function secret `MIYA_ADMIN_SECRET` is set
- ✅ Edge Functions `rook` and `recompute_vitality_scores` are deployed

## One Thing Left: Run the Migration SQL

You need to add 3 new columns to your database. Here's how:

### Step 1: Open Supabase SQL Editor
Go to: **https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/sql/new**

### Step 2: Copy and Paste This SQL

```sql
ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS schema_version text;

ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS computed_at timestamptz;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS vitality_schema_version text;
```

### Step 3: Click "Run" (or press Cmd+Enter)

You should see: **"Success. No rows returned"**

---

## That's It! 🎉

After running the SQL, your server-side scoring is fully set up:
- ROOK webhooks will automatically compute vitality scores
- Scores update in real-time as data arrives
- No need to visit specific screens in the app

---

## Your Secret (save this somewhere safe):
```
MIYA_ADMIN_SECRET=060d3ade1d2a53e987e7c63409e330a6ed88eb4dd6114308be1ac27dde807d97
```

You'll need this if you want to call the backfill function manually.

