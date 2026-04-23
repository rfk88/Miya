# WHOOP via ROOK — operator setup (Miya)

This document implements the **dashboard + OAuth + webhook + E2E** checklist from the WHOOP/ROOK integration plan. The iOS app already calls ROOK’s authorizer for `Whoop` and stores `whoop` in `connected_wearables`; most remaining work is **outside the repo**.

## 1) Enable WHOOP in ROOK (todo: rook-dashboard)

1. Sign in to the [ROOK client portal](https://www.tryrook.io/) (or the environment your team uses).
2. Open your Miya project that matches the **same** `client_uuid` / secret as in local [`Miya Health/Secrets.xcconfig`](../Miya%20Health/Secrets.xcconfig) (never commit secrets).
3. Enable the **Whoop** data source for that project so authorizer requests succeed for `data_source/Whoop`.

If the authorizer returns 404 or refuses the data source, WHOOP is not enabled for that ROOK client.

## 2) WHOOP developer app + credentials in ROOK (todo: whoop-oauth)

ROOK’s **bring-your-own-credentials** flow is documented here:

- [How can I integrate Whoop with ROOK using my own credentials?](https://support.tryrook.io/en/articles/8839664-how-can-i-integrate-whoop-with-rook-using-my-own-credentials)

Summary for operators:

1. **WHOOP Developer Portal:** [developer.whoop.com](https://developer.whoop.com/) — create apps (ROOK’s KB recommends **separate sandbox and production** apps).
2. **Redirect URIs** in the WHOOP app settings (from ROOK’s KB):
   - **Sandbox:** `https://api.whoop.rook-connect.review/callback-whoop`
   - **Production:** `https://api.whoop.rook-connect.com/callback-whoop`
3. **Share Client ID + Client Secret** with ROOK securely (one-time secret / CSE / portal chat), per their KB — ROOK wires them to your client.
4. **Production:** In the WHOOP portal, use **Request Upgrade** (or equivalent) when you are ready for production traffic.

Technical references:

- [WHOOP | ROOK data sources](https://docs.tryrook.io/data-sources/whoop/)
- [WHOOP OAuth 2.0](https://developer.whoop.com/docs/developing/oauth/)

## 3) Webhook target for Miya (todo: rook-dashboard)

ROOK should deliver webhooks to your **Supabase Edge Function** `rook`.

**URL pattern**

```text
https://<PROJECT_REF>.supabase.co/functions/v1/rook
```

Replace `<PROJECT_REF>` with your Supabase project reference (same host as `SUPABASE_URL` in Supabase Settings → API).

**In-repo verification**

- JWT is disabled for this function so ROOK can POST without a Supabase JWT: [`supabase/functions/rook/config.toml`](../supabase/functions/rook/config.toml) (`verify_jwt = false`).
- **Smoke test (no secrets):** from a machine allowed to reach the internet:

  ```bash
  SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co" ./tools/verify_miya_rook_webhook.sh
  ```

  Expect HTTP `200` and JSON containing `rook webhook alive` (the function’s `GET` handler in [`supabase/functions/rook/index.ts`](../supabase/functions/rook/index.ts)).

Configure the **same** URL in the ROOK dashboard (or as ROOK instructs if they issue a project-specific inbound URL). The Edge Function runtime must have `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` set (see Supabase → Edge Functions → `rook` → Secrets).

## 4) End-to-end after a real WHOOP link (todo: e2e-verify)

### In the app

1. Sign in as a test user whose `auth.users.id` you know (Miya passes this UUID to ROOK as `user_id` in authorizer calls).
2. On **Link your health tech**, choose **WHOOP**, complete OAuth in the system browser / sheet.
3. Confirm the app marks WHOOP connected (it polls ROOK’s authorizer until `authorized` is true).

### In Supabase SQL

Run [`supabase/diagnostics/whoop_rook_post_link_checks.sql`](../supabase/diagnostics/whoop_rook_post_link_checks.sql) in the SQL editor, replacing `:user_id` with the test user’s UUID.

You should see:

- A row in `connected_wearables` with `wearable_type = 'whoop'`.
- Recent `rook_webhook_events` rows (payloads vary by event type).
- For parsed summaries, `wearable_daily_metrics` rows with `source = 'whoop'` when the webhook pipeline has enough fields to upsert.

### Automated tests (sample WHOOP JSON)

If your Xcode scheme includes test targets, run WHOOP-focused adapter tests, for example:

```bash
xcodebuild test \
  -project "Miya Health.xcodeproj" \
  -scheme "Miya Health" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"Miya HealthTests/ROOKDayToMiyaAdapterTests/testWhoopDayMapping"
```

(Adjust `-destination` / test bundle name to match your project.)

## 5) Branding (optional)

If you use WHOOP marks in marketing, follow [WHOOP’s brand guide](https://developer.whoop.com/docs/developing-your-app/branding). In-app logos live under `Miya Health/Assets.xcassets` (`WearableLogoWhoop`, etc.).
