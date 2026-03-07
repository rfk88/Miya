# Check Wearable Staleness Cron

The `check_wearable_staleness` Edge Function detects family members whose wearable data is stale (3+ or 7+ days) and enqueues notifications for caregivers (superadmin/admin). Run it on a schedule so caregivers receive push (and other channels) via `process_notifications`.

## Function

- **Endpoint:** `<SUPABASE_URL>/functions/v1/check_wearable_staleness`
- **Method:** `POST`
- **Auth header:** `x-miya-admin-secret: <MIYA_ADMIN_SECRET>`

## Recommended schedule

- **Daily** at a fixed time, e.g. **06:00 UTC** (`0 6 * * *` in cron syntax).

This keeps notifications aligned with "last sync" without running too frequently (dedupe windows are 24h for 3-day and 7 days for 7-day).

## Example payload

The function accepts an optional JSON body; no parameters are required for normal runs.

```json
{}
```

## Setting up the cron job

1. **Deploy the function** (if not already deployed):

   ```bash
   supabase functions deploy check_wearable_staleness --no-verify-jwt
   ```

2. **Enable pg_cron** (Database → Extensions in Supabase Dashboard) if needed.

3. **Create the cron job** in the SQL Editor (replace project ref and admin secret):

   ```sql
   SELECT cron.schedule(
     'check-wearable-staleness',
     '0 6 * * *',
     $$
     SELECT net.http_post(
       url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/check_wearable_staleness',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'x-miya-admin-secret', 'YOUR_MIYA_ADMIN_SECRET'
       ),
       body := '{}'::jsonb
     );
     $$
   );
   ```

4. **Verify:**

   ```sql
   SELECT * FROM cron.job WHERE jobname = 'check-wearable-staleness';
   ```

## Manual test

```bash
curl -X POST "https://YOUR_PROJECT_REF.supabase.co/functions/v1/check_wearable_staleness" \
  -H "Content-Type: application/json" \
  -H "x-miya-admin-secret: YOUR_MIYA_ADMIN_SECRET" \
  -d '{}'
```

Expected response when successful: `{ "ok": true, "stats": { "staleMembers": ..., "rowsInserted": ..., ... } }`.

## Notes

- The function computes last sync from `wearable_daily_metrics` (max `metric_date` per user) with fallback to `user_profiles.vitality_score_updated_at`.
- Only caregivers (family members with `role` in `superadmin`/`admin`, `invite_status = accepted`) receive notifications; the stale member is not notified.
- Duplicate notifications for the same (member, threshold) are suppressed: 3-day within 24h, 7-day within 7 days.
- Enqueued rows are processed by the existing `process_notifications` worker (same cron or separate 5-minute job).
