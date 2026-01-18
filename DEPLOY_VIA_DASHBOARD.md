# Deploy Notification System via Supabase Dashboard
## No Terminal or CLI Required! 🎉

Everything can be done through the web interface. Follow these steps exactly.

---

## Step 1: Deploy Edge Functions (5 minutes)

### A. Go to Edge Functions
1. Open https://supabase.com/dashboard
2. Click on your **Miya Health** project
3. Click **Edge Functions** in the left sidebar

### B. Deploy process_notifications
1. Click **"Deploy new function"** or **"New Function"**
2. You'll see options. Choose **"Import from local"** or **"Deploy from CLI"**
   
   **Wait - there's an easier way!** Let's use the Dashboard's editor:

3. Click **"Create a new function"**
4. Name it: `process_notifications`
5. Copy the ENTIRE contents of this file on your computer:
   ```
   /Users/ramikaawach/Desktop/Miya/supabase/functions/process_notifications/index.ts
   ```
6. Paste it into the editor
7. Click **"Deploy"**

**If you don't see "Create a new function" option:**

Alternative method:
1. Click on the **Settings** or **Configuration** tab
2. Look for **"Deploy Function"** or **"Upload"** button
3. If you see a **"Deploy via GitHub"** option, you can connect your GitHub repo
4. Otherwise, follow the manual SQL method below in "Alternative: Manual Deployment"

### C. Repeat for other functions

Repeat the same process for:
- Function name: `rook` (file: `supabase/functions/rook/index.ts`)
- Function name: `rook_daily_recompute` (file: `supabase/functions/rook_daily_recompute/index.ts`)

**Note:** If these functions are already deployed, skip them!

---

## Step 2: Apply Database Migrations (10 minutes)

### A. Go to SQL Editor
1. In your Supabase dashboard
2. Click **"SQL Editor"** in the left sidebar
3. Click **"New query"**

### B. Run Migration 1: Pattern Alerts

1. Open this file on your computer:
   ```
   /Users/ramikaawach/Desktop/Miya/supabase/migrations/20260109120000_add_pattern_alerts.sql
   ```
2. Copy ALL the contents (Cmd+A, Cmd+C)
3. Paste into the SQL Editor
4. Click **"Run"** (bottom right)
5. Wait for "Success" message

### C. Run Migration 2: Quiet Hours & Snooze

1. Click **"New query"** again
2. Open this file:
   ```
   /Users/ramikaawach/Desktop/Miya/supabase/migrations/20260125120000_add_quiet_hours_and_snooze.sql
   ```
3. Copy ALL the contents
4. Paste into the SQL Editor
5. Click **"Run"**
6. Wait for "Success"

### D. Run Migration 3: Get Family Pattern Alerts

1. Click **"New query"** again
2. Open this file:
   ```
   /Users/ramikaawach/Desktop/Miya/supabase/migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql
   ```
3. Copy ALL the contents
4. Paste into the SQL Editor
5. Click **"Run"**
6. Wait for "Success"

### E. Verify Tables Were Created

1. Click **"Table Editor"** in the left sidebar
2. You should now see these new tables:
   - ✅ `pattern_alert_state`
   - ✅ `notification_queue`
   - ✅ `device_tokens`

If you see them, migrations worked! 🎉

---

## Step 3: Set Environment Variables (3 minutes)

### A. Generate Admin Secret First

Open this website: https://passwordsgenerator.net/
- Set length: 32 characters
- Check: Uppercase, Lowercase, Numbers, Symbols
- Click **Generate**
- Copy the password (this is your `MIYA_ADMIN_SECRET`)
- **SAVE IT SOMEWHERE** - you'll need it twice!

Example: `Xy9kL2mN4pQ6rS8tU0vW2xY4zA6bC8dE`

### B. Add Environment Variables

1. In Supabase Dashboard, click **"Edge Functions"**
2. Click **"Settings"** or **"Configuration"** tab
3. Look for **"Environment Variables"** or **"Secrets"** section
4. Click **"Add variable"** or **"New secret"**

Add these two variables:

**Variable 1:**
- Name: `MIYA_PATTERN_SHADOW_MODE`
- Value: `false`
- Click **Save**

**Variable 2:**
- Name: `MIYA_ADMIN_SECRET`
- Value: (paste the secret you generated above)
- Click **Save**

### C. Redeploy Functions (Important!)

After adding environment variables, you need to redeploy functions so they pick up the new values.

**If you deployed via Dashboard editor:**
- Go back to each function and click **"Redeploy"** or **"Deploy"** again

**If functions already existed:**
- They'll automatically use the new environment variables

---

## Step 4: Set Up Cron Job (5 minutes)

### A. Get Your Project URL

Look at your browser's address bar. It should look like:
```
https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/...
```

Copy the part that looks like: `xmfgdeyrpzpqptckmcbr`
This is your **Project Reference ID**

### B. Create the Cron Job

1. Click **"SQL Editor"** in the left sidebar
2. Click **"New query"**
3. Copy this SQL (but don't run yet!):

```sql
-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove existing job if it exists
SELECT cron.unschedule('process-notifications');

-- Create cron job to process notifications every 5 minutes
SELECT cron.schedule(
  'process-notifications',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-miya-admin-secret', 'YOUR_ADMIN_SECRET'
    ),
    body := jsonb_build_object(
      'batchSize', 50,
      'maxAge', 24
    )
  );
  $$
);

-- Verify it worked
SELECT * FROM cron.job WHERE jobname = 'process-notifications';
```

4. **BEFORE running, replace these two things:**
   - Replace `YOUR_PROJECT_REF` with your project reference ID (e.g., `xmfgdeyrpzpqptckmcbr`)
   - Replace `YOUR_ADMIN_SECRET` with the admin secret from Step 3

5. Now click **"Run"**

6. You should see a result showing your cron job with:
   - jobname: `process-notifications`
   - schedule: `*/5 * * * *`
   - active: `true`

If you see that, the cron job is set up! ✅

---

## Step 5: Test Everything (5 minutes)

### A. Test Edge Functions

Open these URLs in your browser (replace `xmfgdeyrpzpqptckmcbr` with YOUR project ref):

**Test 1:**
```
https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/process_notifications
```
Should show: `{"ok":true,"message":"process_notifications worker alive"}`

**Test 2:**
```
https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/rook
```
Should show: `{"ok":true,"message":"rook webhook alive"}`

If you see those messages, functions are working! ✅

### B. Test Cron Job

Go back to SQL Editor and run:
```sql
-- Check cron job status
SELECT * FROM cron.job WHERE jobname = 'process-notifications';

-- Check if it's run yet
SELECT * FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'process-notifications')
ORDER BY start_time DESC 
LIMIT 5;
```

If you see records, the cron job is running! ✅

### C. Check Database Tables

Go to **Table Editor** and check these tables:

**pattern_alert_state:**
- Click on the table
- You might see 0 rows (that's okay - alerts will appear when wearable data arrives)

**notification_queue:**
- Click on the table
- You might see 0 rows (that's okay - notifications will be queued when alerts are created)

**user_profiles:**
- Click on the table
- Click on any row
- Scroll to the right
- You should see these NEW columns:
  - `quiet_hours_notification_level`
  - `timezone`

If you see those columns, everything worked! ✅

---

## Step 6: Test in iOS App (5 minutes)

### A. Rebuild the App

1. Open Xcode
2. Open your project: `/Users/ramikaawach/Desktop/Miya/Miya Health.xcodeproj`
3. Press **Cmd+B** to build
4. Press **Cmd+R** to run

### B. Test New Features

1. **Test Timezone Picker:**
   - Open app
   - Go to Settings → Edit Profile
   - Scroll to "Notifications" section
   - You should see a **Timezone** dropdown (NEW!)
   - Tap it and select a different timezone
   - Tap "Save" at the top

2. **Test Quiet Hours Settings:**
   - In the same Notifications section
   - You should see **"During quiet hours, send:"** segmented control (NEW!)
   - Try selecting "No notifications" / "Critical alerts only" / "All notifications"
   - Tap "Save"

3. **Test Snooze Button:**
   - Go to Dashboard
   - If you have any notifications, tap one
   - In the detail view, look at the top-left corner
   - You should see a **bell with a slash icon** (NEW!)
   - Tap it to see snooze options

If you see all these features, deployment is complete! 🎉

---

## Troubleshooting

### "I can't find Edge Functions in the dashboard"

It might be under:
- **Functions** (older UI)
- **Edge Functions** (newer UI)
- **Database** → **Functions** (some versions)

If you still can't find it, use the alternative method below.

### "Edge Function deployment isn't working"

**Alternative: Skip this step for now**

The notification system will still work! The edge functions might already be deployed, or you can deploy them later via GitHub integration.

### "SQL migrations are failing"

Check which line is causing the error. Common issues:

1. **"relation already exists"** - This means the table/function already exists. That's fine! Skip to the next migration.

2. **"permission denied"** - Make sure you're logged in as the project owner.

3. **"syntax error"** - Make sure you copied the ENTIRE file contents, not just part of it.

### "Cron job isn't working"

Try this simpler version:

```sql
-- Just create the cron job without the unschedule command
SELECT cron.schedule(
  'process-notifications',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-miya-admin-secret', 'YOUR_ADMIN_SECRET'
    ),
    body := jsonb_build_object('batchSize', 50)
  );
  $$
);
```

### "I don't see the new features in the iOS app"

Make sure you:
1. Actually rebuilt the app (Cmd+B)
2. Closed and reopened the app
3. Are looking in Settings → Edit Profile → Notifications section (scroll down)

---

## Summary Checklist

- [ ] Migrations run successfully (3 SQL files)
- [ ] Tables exist: `pattern_alert_state`, `notification_queue`, `device_tokens`
- [ ] Environment variables set: `MIYA_PATTERN_SHADOW_MODE`, `MIYA_ADMIN_SECRET`
- [ ] Cron job created and active
- [ ] Edge functions respond with "alive" messages
- [ ] iOS app shows timezone picker
- [ ] iOS app shows quiet hours segmented control
- [ ] iOS app shows snooze button on notifications

If all checkboxes are ✅, you're done! 🎊

---

## What Happens Now?

The system is live and will:
1. **Every 5 minutes:** Check for pending notifications and send them (respecting quiet hours)
2. **When wearable data arrives:** Evaluate patterns and create alerts
3. **When user opens dashboard:** Show active alerts (excluding snoozed/dismissed ones)
4. **When user snoozes:** Hide alert for specified days
5. **When user sets quiet hours:** Respect their timezone and preferences

You don't need to do anything else - it runs automatically! 🚀
