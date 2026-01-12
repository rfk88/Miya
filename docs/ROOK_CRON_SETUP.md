## ROOK Daily Recompute Cron

This project includes a server-side Edge Function that recomputes vitality scores
for users with recent ROOK webhook data without inserting duplicate metrics.

### Function
- Endpoint: `<SUPABASE_URL>/functions/v1/rook_daily_recompute`
- Method: `POST`
- Auth header: `x-miya-admin-secret: <MIYA_ADMIN_SECRET>`

### Recommended Schedule
- Daily (ex: `0 6 * * *` in UTC or your preferred time zone)

### Example Payload
```json
{
  "daysBack": 2,
  "maxUsers": 500
}
```

### Notes
- The function reads from `wearable_daily_metrics` and recomputes scores.
- It **does not** insert new wearable metrics, so it won’t duplicate ROOK data.
- It upserts into `vitality_scores` and updates `user_profiles` snapshots.
