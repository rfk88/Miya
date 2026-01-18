# Miya Notification System - Deployment Guide

This guide walks you through deploying the notification system step-by-step.

## Prerequisites

Before starting, make sure you have:
- [ ] Supabase project created (you already have this)
- [ ] Supabase CLI installed
- [ ] Terminal/Command Prompt access
- [ ] Project files downloaded locally

---

## Step 1: Install Supabase CLI (if not already installed)

### macOS (using Homebrew)
```bash
brew install supabase/tap/supabase
```

### macOS/Linux (using npm)
```bash
npm install -g supabase
```

### Windows (using npm)
```bash
npm install -g supabase
```

### Verify installation
```bash
supabase --version
# Should show: supabase 1.x.x
```

---

## Step 2: Login to Supabase

```bash
supabase login
```

This will:
1. Open your browser
2. Ask you to authorize the CLI
3. Return a success message

If you see "Logged in", you're ready to proceed!

---

## Step 3: Link Your Project

First, get your project reference ID:
1. Go to https://supabase.com/dashboard
2. Click on your "Miya Health" project
3. Go to Settings → General
4. Copy the "Reference ID" (looks like: `xmfgdeyrpzpqptckmcbr`)

Now link your local project:

```bash
cd /Users/ramikaawach/Desktop/Miya

supabase link --project-ref xmfgdeyrpzpqptckmcbr
```

**Replace `xmfgdeyrpzpqptckmcbr` with your actual project reference ID!**

You'll be prompted for your database password. Enter it and press Enter.

---

## Step 4: Apply Database Migrations

Run these commands in order:

```bash
# Navigate to your project directory (if not already there)
cd /Users/ramikaawach/Desktop/Miya

# Apply migration 1: Pattern alerts schema
supabase db push --include supabase/migrations/20260109120000_add_pattern_alerts.sql

# Apply migration 2: Quiet hours & snooze
supabase db push --include supabase/migrations/20260125120000_add_quiet_hours_and_snooze.sql

# Apply migration 3: Get family pattern alerts RPC
supabase db push --include supabase/migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql
```

**Alternative method (if above doesn't work):**

You can apply migrations directly via the Supabase Dashboard:

1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to "SQL Editor"
4. Click "New query"
5. Copy the contents of each migration file and paste into the editor
6. Click "Run" for each one

Files to run in order:
- `supabase/migrations/20260109120000_add_pattern_alerts.sql`
- `supabase/migrations/20260125120000_add_quiet_hours_and_snooze.sql`
- `supabase/migrations/20260110153000_add_get_family_pattern_alerts_rpc.sql`

**Verify migrations worked:**
```bash
# Check if tables were created
supabase db list
```

Or in the Supabase Dashboard:
1. Go to Table Editor
2. You should see: `pattern_alert_state`, `notification_queue`, `device_tokens`

---

## Step 5: Deploy Edge Functions

### A. Deploy the notification worker

```bash
cd /Users/ramikaawach/Desktop/Miya

supabase functions deploy process_notifications
```

Expected output:
```
Deploying function process_notifications...
Function process_notifications deployed successfully
```

### B. Deploy or verify existing functions

If these aren't already deployed, deploy them now:

```bash
# Deploy Rook webhook handler
supabase functions deploy rook

# Deploy daily recompute function
supabase functions deploy rook_daily_recompute

# Deploy AI insight chat (if you have it)
supabase functions deploy miya_insight_chat
```

**Verify functions are deployed:**

1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to "Edge Functions"
4. You should see:
   - ✅ `process_notifications`
   - ✅ `rook`
   - ✅ `rook_daily_recompute`
   - ✅ `miya_insight_chat`

---

## Step 6: Configure Environment Variables

### A. Set variables for all functions

1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to "Edge Functions" → "Settings" (or "Configuration")
4. Add these environment variables:

#### Required Variables:

**MIYA_PATTERN_SHADOW_MODE**
- Value: `false`
- Description: Enable pattern alerts in production (set to `true` for testing)

**MIYA_ADMIN_SECRET**
- Value: `<generate a secure random string>`
- Description: Secret key for authenticating cron jobs
- **To generate a secure secret:**
  ```bash
  # macOS/Linux
  openssl rand -base64 32
  
  # Or use this website: https://passwordsgenerator.net/
  # Settings: 32 characters, include uppercase, lowercase, numbers, symbols
  ```

**Example:**
- `MIYA_ADMIN_SECRET` = `Xy9kL2mN4pQ6rS8tU0vW2xY4zA6bC8dE`

#### These should already exist (auto-populated by Supabase):

- `SUPABASE_URL` - Your project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (keep secret!)
- `SUPABASE_ANON_KEY` - Anonymous public key

### B. How to add environment variables:

In the Supabase Dashboard:
1. Edge Functions → Settings/Configuration
2. Click "Add variable" or "New secret"
3. Enter name: `MIYA_PATTERN_SHADOW_MODE`
4. Enter value: `false`
5. Click "Save"
6. Repeat for `MIYA_ADMIN_SECRET`

**Important:** After adding environment variables, you may need to redeploy functions:
```bash
supabase functions deploy process_notifications
supabase functions deploy rook
```

---

## Step 7: Set Up Cron Job

We'll use Supabase's pg_cron extension to automatically run the notification worker every 5 minutes.

### A. Enable pg_cron extension (if not enabled)

1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to "Database" → "Extensions"
4. Search for "pg_cron"
5. Click "Enable" (if not already enabled)

### B. Create the cron job

Go to "SQL Editor" and run this query:

```sql
-- Create cron job to process notifications every 5 minutes
SELECT cron.schedule(
  'process-notifications',           -- Job name
  '*/5 * * * *',                      -- Every 5 minutes
  $$
  SELECT net.http_post(
    url := 'https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/process_notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-miya-admin-secret', 'YOUR_ADMIN_SECRET_HERE'
    ),
    body := jsonb_build_object(
      'batchSize', 50,
      'maxAge', 24
    )
  );
  $$
);
```

**IMPORTANT:** Replace these values:
1. `xmfgdeyrpzpqptckmcbr` → Your project reference ID
2. `YOUR_ADMIN_SECRET_HERE` → The `MIYA_ADMIN_SECRET` you set in Step 6

### C. Verify cron job was created

```sql
-- List all cron jobs
SELECT * FROM cron.job;
```

You should see:
- jobname: `process-notifications`
- schedule: `*/5 * * * *`
- active: `true`

### D. Test the cron job manually

```sql
-- Run the job immediately (without waiting 5 minutes)
SELECT cron.run_job('process-notifications');
```

Check the logs:
```sql
-- View recent job runs
SELECT * FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'process-notifications')
ORDER BY start_time DESC 
LIMIT 10;
```

**Alternative: Manual testing via curl**

If you want to test the worker manually:

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-miya-admin-secret: YOUR_ADMIN_SECRET_HERE" \
  -d '{"batchSize": 50, "maxAge": 24}' \
  https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/process_notifications
```

Expected response:
```json
{
  "ok": true,
  "processed": 0,
  "sent": 0,
  "skipped": 0,
  "failed": 0,
  "message": "No pending notifications"
}
```

---

## Step 8: Verify Everything Works

### A. Check database tables exist

In SQL Editor, run:
```sql
-- Check pattern_alert_state table
SELECT * FROM pattern_alert_state LIMIT 1;

-- Check notification_queue table
SELECT * FROM notification_queue LIMIT 1;

-- Check user_profiles has new columns
SELECT 
  quiet_hours_notification_level, 
  timezone 
FROM user_profiles 
LIMIT 1;
```

### B. Check RPCs work

```sql
-- Test get_family_pattern_alerts (replace with your family_id)
SELECT * FROM get_family_pattern_alerts('your-family-id-here');

-- Test snooze_pattern_alert (replace with a real alert_id)
SELECT snooze_pattern_alert('alert-id-here', 3);
```

### C. Check edge functions are live

Visit these URLs in your browser (replace with your project ref):

```
https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/process_notifications
```

You should get:
```json
{"ok": true, "message": "process_notifications worker alive"}
```

```
https://xmfgdeyrpzpqptckmcbr.supabase.co/functions/v1/rook
```

You should get:
```json
{"ok": true, "message": "rook webhook alive"}
```

### D. Test in the iOS app

1. Rebuild the Miya Health app in Xcode (Cmd+B)
2. Run on simulator or device
3. Go to Settings → Edit Profile → Notifications
4. You should see:
   - Timezone dropdown (NEW!)
   - Quiet hours time pickers
   - "During quiet hours, send:" segmented control (NEW!)
5. Test changing timezone and quiet hours level
6. Tap "Save"

---

## Troubleshooting

### "supabase: command not found"
- Solution: Install Supabase CLI (see Step 1)

### "Project not linked"
- Solution: Run `supabase link --project-ref YOUR_PROJECT_REF` (see Step 3)

### "Permission denied" when applying migrations
- Solution: Make sure you entered the correct database password when linking

### Functions deploy but show errors
- Solution: Check environment variables are set correctly (Step 6)

### Cron job doesn't run
- Solution: 
  1. Check pg_cron extension is enabled
  2. Verify the URL in the cron job is correct (your project ref)
  3. Verify `MIYA_ADMIN_SECRET` matches in both cron job and environment variables

### "Invalid admin secret" error
- Solution: Make sure `MIYA_ADMIN_SECRET` environment variable matches the secret in your cron job

### Functions work but notifications don't send
- Solution: This is expected! Push notification integration (APNs/FCM) is not implemented yet. The system is working - it's just logging to console instead of sending actual push notifications.

---

## What Happens After Setup

Once everything is deployed:

1. **Wearable data flows in** → Rook webhook receives it
2. **Pattern evaluation runs** → Creates alerts in `pattern_alert_state`
3. **Notifications are queued** → Inserted into `notification_queue`
4. **Cron job runs every 5 minutes** → Processes pending notifications
5. **Worker checks preferences** → Respects quiet hours, snooze, dismiss
6. **Notifications are "sent"** → Currently logs to console (APNs integration TODO)
7. **Dashboard shows alerts** → Users see notifications in-app

---

## Quick Command Reference

```bash
# Link project
supabase link --project-ref YOUR_PROJECT_REF

# Apply all migrations (run from project root)
supabase db push

# Deploy functions
supabase functions deploy process_notifications
supabase functions deploy rook
supabase functions deploy rook_daily_recompute

# View function logs
supabase functions logs process_notifications
supabase functions logs rook

# Test worker manually
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-miya-admin-secret: YOUR_SECRET" \
  https://YOUR_PROJECT_REF.supabase.co/functions/v1/process_notifications
```

---

## Need Help?

If you run into issues:

1. **Check function logs:**
   ```bash
   supabase functions logs process_notifications --tail
   ```

2. **Check database for errors:**
   ```sql
   -- View notification queue status
   SELECT status, count(*) 
   FROM notification_queue 
   GROUP BY status;
   
   -- View recent alerts
   SELECT * FROM pattern_alert_state 
   ORDER BY created_at DESC 
   LIMIT 10;
   ```

3. **Verify cron job is running:**
   ```sql
   SELECT * FROM cron.job_run_details 
   ORDER BY start_time DESC 
   LIMIT 10;
   ```

---

**You're all set!** 🚀

The notification system is now deployed and will automatically process alerts every 5 minutes.
