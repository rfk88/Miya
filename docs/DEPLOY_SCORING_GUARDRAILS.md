# Deploy Scoring Guardrails (Sleep + Active Calories)

After updating sleep guardrails in `recompute.ts` and active-calorie keys/logging in the Rook webhook, deploy the affected Edge Functions so production uses the new logic.

---

## Prerequisites

- **Supabase CLI** installed and logged in: `supabase login`
- **Linked project**: from the repo root, run `supabase link` (or ensure you’re already linked to the correct project)

---

## 1. Deploy the Rook webhook (required)

The Rook webhook both **ingests** data (new active-calorie keys + `MIYA_ACTIVE_CALORIES_MISSING` log) and **calls** `recomputeRolling7dScoresForUser`, which uses the new **sleep guardrails** in `recompute.ts`. Deploying `rook` deploys that whole bundle.

From the **project root** (where `supabase/` lives):

```bash
supabase functions deploy rook --no-verify-jwt
```

- `--no-verify-jwt` matches the Rook webhook config (Rook sends webhooks without a user JWT).

---

## 2. Deploy other functions that use recompute (optional)

If you use these, deploy them so they also use the updated `recompute.ts`:

**Scheduled daily recompute (e.g. cron):**

```bash
supabase functions deploy rook_daily_recompute --no-verify-jwt
```

**Manual / admin recompute:**

```bash
supabase functions deploy recompute_vitality_scores --no-verify-jwt
```

(Use the same flags you normally use for these functions if different.)

---

## 3. Check logs after deploy

**Stream Rook webhook logs (invocations + your new log):**

```bash
supabase functions logs rook --follow
```

When a payload has steps or movement but **no** active calories, you’ll see:

- `🟡 MIYA_ACTIVE_CALORIES_MISSING` with `metric_date`, `rook_user_id`, and the hint.

**One-off log view (no follow):**

```bash
supabase functions logs rook
```

**In the Supabase Dashboard:**

1. Open your project → **Edge Functions**.
2. Click **rook** → **Logs**.
3. Filter or search for `MIYA_ACTIVE_CALORIES_MISSING` to see when active calories were missing for a given payload.

---

## 4. Quick checklist

| Step | Command / action |
|------|-------------------|
| 1. Deploy Rook (required) | `supabase functions deploy rook --no-verify-jwt` |
| 2. Deploy daily recompute (if used) | `supabase functions deploy rook_daily_recompute --no-verify-jwt` |
| 3. Deploy recompute_vitality_scores (if used) | `supabase functions deploy recompute_vitality_scores --no-verify-jwt` |
| 4. Watch logs | `supabase functions logs rook --follow` |
| 5. Trigger a sync | Send data from Rook (or run your normal sync); check logs for `MIYA_ACTIVE_CALORIES_MISSING` if active calories still don’t show |

---

## Troubleshooting

- **“Project not linked”**  
  Run `supabase link` and choose your project.

- **“Permission denied” / 401**  
  Run `supabase login` and ensure your account has access to the project.

- **Logs empty or old**  
  Invoke the Rook webhook (e.g. sync from app or Rook dashboard) and check again; logs are per-invocation.

- **Active calories still missing**  
  Look for `MIYA_ACTIVE_CALORIES_MISSING` in Rook logs; the payload may use a key we don’t yet support. Add that key to the extraction in `supabase/functions/rook/index.ts` (calorie metrics section) and redeploy `rook`.
