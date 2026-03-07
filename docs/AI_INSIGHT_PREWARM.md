# AI insight pre-cache when alert fires

When a pattern alert fires (e.g. sleep below baseline for 7 days), the AI insight (headline, interpretation, action steps, message suggestions) is **pre-generated and cached** so the first caregiver who opens the alert sees it immediately instead of waiting for generation.

## How it works

1. **Alert fires:** The Rook pattern engine (`supabase/functions/rook/patterns/engine.ts`) runs as part of the Rook webhook. When it enqueues a notification (e.g. level escalation), it calls `prewarmInsightCache(supabase, alertStateId)` (fire-and-forget).

2. **Server prewarm:** `prewarmInsightCache` sends a POST to the `miya_insight` Edge Function with:
   - `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`
   - `x-miya-internal: prewarm`
   - Body: `{ "alert_state_id": "<uuid>" }`

3. **miya_insight auth:** The `miya_insight` function accepts two call patterns:
   - **Client (app):** Bearer token is a **user JWT**. The function validates the user and that they share a family with the alert’s member, then generates or returns cached insight.
   - **Server prewarm:** Bearer token is the **service role key** and the request includes `x-miya-internal: prewarm`. The function skips user/family auth, loads the alert by `alert_state_id`, and runs the same generate-and-cache logic. Only this path is used for prewarming; the header ensures only our server can use the service-role path.

4. **Cache:** The result is stored in `pattern_alert_ai_insights` (same cache key as client requests: `alert_state_id`, `evaluated_end_date`, `prompt_version`). When the caregiver opens the alert, the app calls `miya_insight` with their user JWT and receives the cached insight.

## Verification

- **Logs (engine):** When an alert fires you should see:
  - `MIYA_PREWARM: Starting insight generation for alert <id>`
  - `MIYA_PREWARM: Insight cached successfully for alert <id>` (or `MIYA_PREWARM: Failed` with status/body if something went wrong).

- **Logs (miya_insight):** For a server prewarm you should see:
  - `MIYA_INSIGHT: Server prewarm path` then cache insert and success.
  - For a client request: `MIYA_INSIGHT: Client request` then either cache hit or generate.

- **In the app:** Trigger a pattern escalation (or use a test that enqueues a notification), then open the alert as a caregiver. The insight should appear quickly (cached) without a multi-second wait.

## Security

- The service role key is only in server env (Rook/engine); the app never has it.
- The server prewarm path also requires `x-miya-internal: prewarm`, which only the Rook engine sends when calling `miya_insight` for prewarming.

## Related code

- **Engine prewarm:** `supabase/functions/rook/patterns/engine.ts` — `prewarmInsightCache()`, called after inserting into `notification_queue` and updating `pattern_alert_state`.
- **Insight function:** `supabase/functions/miya_insight/index.ts` — server prewarm path when `token === serviceKey` and `x-miya-internal === "prewarm"`; client path uses user JWT and family auth.
