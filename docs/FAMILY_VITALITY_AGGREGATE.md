# Family Vitality Aggregate (Real-Time)

## How the family aggregate works

The **family aggregate score** (the single number such as "Family vitality: 72") is **not** stored in its own table. It is **computed on demand** by the Supabase RPC `get_family_vitality`, which:

- Reads `user_profiles.vitality_score_current` (and 7-day recency) for all active family members
- Returns the average as `family_vitality_score`, plus member counts and `last_updated_at`

So the aggregate is only as fresh as (a) the data in `user_profiles`, and (b) when the client calls the RPC.

## When member data is updated

- **Real time (webhook):** When a member syncs their wearable, the ROOK webhook (`rook/index.ts`) updates **that member's** `user_profiles` row in the same request (vitality_score_current, vitality_score_updated_at, pillar scores). So the DB is already up to date for the syncing user.
- **Batch (cron):** `rook_daily_recompute` runs on a schedule and can update other members' `user_profiles` from recent `vitality_scores`.

## Keeping the displayed aggregate fresh

To show a real-time family number, the iOS app:

1. **On dashboard appear:** Calls `refresh_family_vitality_snapshots` (copies latest `vitality_scores` into `user_profiles` for all family members), then `get_family_vitality`. This keeps the aggregate fresh when the user opens or returns to the dashboard tab.
2. **On app foreground:** When the app returns from background, the dashboard again calls `refresh_family_vitality_snapshots` then `loadFamilyVitality()`, so the family score updates without requiring manual pull-to-refresh.
3. **Pull-to-refresh:** The same refresh-then-load sequence runs when the user pulls to refresh.

So the family aggregate stays fresh by refetch on appear and on foreground, using the existing RPCs.

The dashboard shows a "last synced" caption per member on each member card using `user_profiles.vitality_score_updated_at`, consistent with missing-wearable notifications.
