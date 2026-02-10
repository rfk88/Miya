# Arlo Chat “Clever” Upgrade — Step-by-Step Execution Plan

This plan turns Arlo into a **facts-driven, pill-first** chat: the AI only explains what the backend has already computed. Pills are deterministic; the opener has a fixed structure; and “why” comes from pillar contributions, not from the model.

---

## Prerequisites (Current State)

- **Client:** `ArloChatView` gets `firstName` + `openingLine` (from `arloVitalityBand(for: familyVitalityScore).sentence`). No pills, no facts payload.
- **API:** `ArloChatAPI.send(messages, firstName, openingLine)` → Edge Function `arlo-chat`.
- **Edge Function:** Builds system prompt from `firstName` + `openingLine`; forbids “scores, trends, alerts”; sends conversation to OpenAI.
- **Data:** `get_family_vitality(family_id)` → score, members_with_data, members_total, last_updated_at, has_recent_data, family_progress_score. `get_family_vitality_scores(family_id, start_date, end_date)` → per-member, per-day total + pillar scores. No “delta vs prior period” or “contributions” yet.

---

## Phase 1 — Facts Payload (Server-Side)

**Goal:** One RPC returns everything Arlo is allowed to “know.” No new reasons, no new metrics—only this payload.

### Step 1.1 — New RPC: `get_arlo_facts(family_id)`

**Where:** New migration, e.g. `supabase/migrations/YYYYMMDD_add_get_arlo_facts.sql`.

**Returns (JSON-friendly table or single JSONB row):**

**Family-level**

| Field | Type | Source / Logic |
|-------|------|----------------|
| `family_vitality_current` | int | From `get_family_vitality` or same logic (avg of members with fresh data). |
| `family_vitality_delta` | int | This week’s avg vs last week’s avg using `get_family_vitality_scores` (or new helper). Null if insufficient history. |
| `time_window_label` | text | e.g. `"since last week"` or `"since last check-in"` — pick one and use consistently. |
| `confidence` | text | `"high"` \| `"medium"` \| `"low"` from data completeness (e.g. members_with_data/members_total, coverage days). |

**Pillar contributions (the WHY, still factual)**

| Field | Type | Logic |
|-------|------|--------|
| `movement_contribution` | int | +N / 0 / -N: change in family-avg movement pillar this week vs last week (or 0 if no prior week). |
| `sleep_contribution` | int | Same for sleep pillar. |
| `recovery_contribution` | int | Same for stress/recovery pillar. |

Compute these inside the RPC from `get_family_vitality_scores` for “this week” and “last week” (reuse the same week boundaries as Champions/badges: UTC week, last 7 days vs previous 7).

**Member highlights (for pills like “who slept best”)**

For each member with `data_completeness_pct >= threshold` (e.g. 70%):

| Field | Type |
|-------|------|
| `member_id` | uuid |
| `name` | text (from family_members / user_profiles or display name) |
| `vitality_delta` | int (this week vs last week for that member) |
| `top_pillar` | text: `"movement"` \| `"sleep"` \| `"recovery"` (whichever pillar is highest this week) |
| `sleep_avg_hours` | numeric, optional |
| `steps_avg` | numeric, optional |
| `recovery_signal` | text or numeric, optional (e.g. HRV avg / RHR avg if you have it) |
| `data_completeness_pct` | int (0–100) |

**Rankings (deterministic, from contribution logic — not AI)**

| Field | Type | Logic |
|-------|------|--------|
| `best_sleep_member_name` | text \| null | Member with best sleep metric in window; only set if their `data_completeness_pct >= 70`. |
| `sleep_metric_used` | text | e.g. `"hours"` \| `"consistency"` \| `"efficiency"` — whatever the RPC uses to decide “best.” |
| `most_improved_member_name` | text \| null | Largest positive vitality_delta among members with sufficient data. |
| `improvement_reason_key` | text | e.g. `"sleep_up"` \| `"movement_up"` — derived from which pillar improved most for that member. |
| `family_win_key` | text | e.g. `"sleep_consistency_up"` — from which family-level contribution is largest positive. |

**Data quality (for “Based on the data we have…”-style phrasing)**

| Field | Type |
|-------|------|
| `data_coverage_days` | int (e.g. 5 for “5/7 days”) |
| `missing_members_count` | int |
| `confidence_level` | text, same as `confidence` |

**Deliverable:** Migration that creates `get_arlo_facts(p_family_id uuid)` returning one row (e.g. `jsonb` or a composite type). Auth: same as `get_family_vitality` (caller must be family member).

---

### Step 1.2 — Implement delta + contributions + rankings in SQL

**Dependencies:** Existing `get_family_vitality_scores`, plus a defined “this week” / “last week” (e.g. UTC 7-day windows).

- Reuse week math from Champions (e.g. `DashboardView+DataLoading`: `weekStartKey` / `weekEndKey` and previous week). In SQL, use `date_trunc('week', ...)` or fixed “today − 6..today” and “today − 13..today − 7” so it’s deterministic.
- In `get_arlo_facts`:
  - Call shared logic or inline queries to get family-level and per-member scores for “this week” and “last week.”
  - `family_vitality_delta` = this_week_avg − last_week_avg.
  - Pillar contributions = same for family-level sleep/movement/stress averages.
  - Member highlights: join to `family_members` / names, compute `vitality_delta`, `top_pillar`, optional `sleep_avg_hours` / `steps_avg` from `vitality_scores` or existing aggregates.
  - Rankings: from member highlights and contribution keys; set to null when `data_completeness_pct < 70` for that member.

**Deliverable:** RPC that returns the full facts structure; can be one JSON object per family for easier Edge Function consumption.

---

## Phase 2 — Deterministic Pills + Opener

**Goal:** Pills and the first message are fully driven by facts. No AI freedom for “what to show” or “what happened.”

### Step 2.1 — Pill selection rules (backend or client)

**Where:** Either inside `get_arlo_facts` (e.g. return `suggested_pill_labels string[]`) or in the client from the facts object. Recommended: **compute in RPC** so rules live in one place and the client just renders.

**Rules (exactly as you specified):**

- **If `family_vitality_delta > 0`:**
  - “What are we doing well?”
  - “Who improved most?”
  - If `sleep_contribution` is top: “Who had the best sleep?”
  - If `movement_contribution` is top: “Who moved most consistently?”
- **If `family_vitality_delta == 0`:**
  - “What’s holding us back?”
  - “Quick win for this week”
  - “Who needs a nudge?”
- **If `family_vitality_delta < 0`:**
  - “What changed?”
  - “Who’s under pressure?”
  - “Small reset plan”

**Guard:** Include a ranking pill (“Who had the best sleep?”, “Who improved most?”, etc.) only if the member used for that rank has `data_completeness_pct >= 70` (or family-level equivalent you define). Otherwise omit that pill.

**Deliverable:** Either (a) `get_arlo_facts` returns `suggested_pill_labels text[]`, or (b) a small shared spec (e.g. in this doc or a tiny TS/Swift helper) that both RPC and client can implement so pill sets are identical.

---

### Step 2.2 — Fixed opener template (Headline → Why → Hook → Pills)

**Rule:** Arlo’s first message is not freeform. It follows:

1. **Headline** — What happened (e.g. “Your family vitality is up this week.”).
2. **Why** — Which pillars drove it, from contribution fields only (e.g. “Biggest lift came from sleep consistency, with movement holding steady.”).
3. **Family hook** — One short human line (e.g. “Nice work — small habits compound.”).
4. **Pills** — “What do you want to look at?” + render the chosen pills as tappable chips.

**Where to build it:** Two options.

- **Option A (recommended):** Build the opener **in the backend** inside `get_arlo_facts` or a tiny companion (e.g. `get_arlo_opener(facts)`). Return `opener_headline`, `opener_why`, `opener_hook`, and `suggested_pill_labels`. Client concatenates and shows; first “message” is never sent to the AI.
- **Option B:** Client builds the same four parts from the facts JSON and displays them. No AI involved for the opener.

**Deliverable:** A single, documented template and the code (SQL or TypeScript/Swift) that fills it from the facts payload. Arlo’s first UI message is always this structured block, not a model reply.

---

## Phase 3 — Client: Facts, Pills, and Opener

**Goal:** Arlo chat starts from facts, shows deterministic pills, and uses the fixed opener.

### Step 3.1 — Fetch facts when opening Arlo

- When the user taps “Chat with Arlo,” **before** presenting the sheet (or on sheet appear), call a new client method that invokes `get_arlo_facts(family_id)`.
- **New in DataManager (or Arlo-specific layer):** e.g. `fetchArloFacts() async throws -> ArloFacts` that maps the RPC response to a Swift struct `ArloFacts` mirroring the payload (family_vitality_current, family_vitality_delta, contributions, member_highlights, rankings, data_coverage_days, missing_members_count, confidence_level, suggested_pill_labels, opener_headline, opener_why, opener_hook if you use Option A).
- **DashboardView / presenter:** Ensure `presentArloChat()` (or the path that opens the sheet) triggers this fetch and passes the result into `ArloChatView`.

**Deliverable:** `ArloFacts` model, `fetchArloFacts()`, and wiring so the sheet receives a non-optional `ArloFacts?` (or a clear “loading / error” state).

---

### Step 3.2 — ArloChatView accepts facts and shows pills + opener

- **New inputs:** e.g. `facts: ArloFacts?`, `firstName: String`. Drop `openingLine` as a freeform string; opener comes from facts (or keep it only as fallback when facts are nil).
- **First message:**  
  - If `facts != nil`: first “message” = headline + why + hook + “What do you want to look at?” and show `facts.suggested_pill_labels` as tappable pills.  
  - If `facts == nil`: keep current behavior (e.g. “Hey {name} — things look generally on track… What would you like help with today?”) and no pills.
- **Pill tap:** When the user taps a pill, send that as the **first user message** with an explicit **intent** (see Phase 4). For example, send “What are we doing well?” as the visible message and attach `selected_intent: "doing_well"` in the API payload.

**Deliverable:** Arlo first screen shows the structured opener and deterministic pills; pill tap sends a user message plus intent.

---

## Phase 4 — Edge Function: Facts + Intent + Narrative-Only AI

**Goal:** The AI receives only facts and intent; it is forbidden to invent new reasons or metrics.

### Step 4.1 — Extend `arlo-chat` request body

**New/updated fields:**

- `facts` — The full facts payload (or a reference the Edge Function can re-fetch). Prefer **client sends facts** in the first request so the Edge Function stays stateless and you don’t need to call Supabase from the function. If payload size is a concern, you can later add “fetch facts by family_id” inside the function using the auth token.
- `firstName` — Keep.
- `openingLine` — Remove or repurpose: e.g. only used when facts are missing (fallback).
- For **every** request (including when user taps a pill or sends a message):
  - `selected_intent` — e.g. `"doing_well"` \| `"best_sleep"` \| `"who_improved"` \| `"what_changed"` \| `"who_needs_nudge"` \| `null` when it’s free text.
  - `supporting_facts` — Optional small blob: the 3–5 numbers or keys needed for that intent (e.g. for `best_sleep`: `best_sleep_member_name`, `sleep_metric_used`). Client or backend can trim the full facts to this.

**Deliverable:** Documented request schema: `messages`, `firstName`, `facts`, `selected_intent`, `supporting_facts` (and deprecate or limit `openingLine` to fallback).

---

### Step 4.2 — System prompt: facts + narrative-only rule

- **System prompt:**  
  “You are Arlo, a family health coach. You explain only the facts you are given. Do not add new reasons, new metrics, or medical claims. Use only: family vitality change, pillar contributions, member highlights, and rankings provided in the facts. Be warm, concise, and family-first. Prefer one short clarifying question when needed.”
- **Inject facts:** Append a single “Facts for this conversation” block (e.g. a sanitized, stringified subset of `facts`) to the system prompt or as a dedicated system message, so every reply is conditioned on that.
- **Intent:** If `selected_intent` is present, add one line: “The user is asking about: {selected_intent}. Use the supporting_facts to shape your reply.”
- **Optional:** `allowed_output_format` — e.g. “3 bullets + 1 suggestion + 1 question” — to keep answers structured. Can be derived from intent (e.g. “doing_well” → that format).

**Deliverable:** Updated `arlo-chat` that (a) reads `facts` / `selected_intent` / `supporting_facts`, (b) builds the narrative-only system prompt, and (c) never lets the model “guess” why the score changed.

---

### Step 4.3 — Mode: score-forward language

- Decide once: **Score-forward** (“vitality up/down,” “family score,” “pillars”).  
- In the same system prompt, add: “Use score-forward language: vitality, family score, sleep/movement/recovery contributions. Do not mix with other modes.”
- Remove or soften the old “Never mention scores, trends, alerts” to “Do not invent scores or trends; only refer to the vitality and facts you are given.”

**Deliverable:** Final Arlo system prompt text that is consistently score-forward and narrative-only.

---

## Phase 5 — Family Dynamics (Optional but High Impact)

**Goal:** Arlo can sound like it “knows” the family (goal, routine, tone).

### Step 5.1 — Where to store

- **Option A:** New table or columns, e.g. `family_settings` or `families.arlo_preferences` (jsonb): `family_goal_focus`, `household_routine_context`, `preferred_tone`, `nudge_style`.
- **Option B:** Client sends these when opening chat or in the first request (e.g. from onboarding or a simple “How should Arlo sound?” screen). Stored in app prefs or a small API later.

**Suggested first step:** Client sends **optional** `family_dynamics` in the first `arlo-chat` request (or in a “prepare Arlo” call):  
`{ family_goal_focus, household_routine_context, preferred_tone, nudge_style }`.  
Edge Function appends to the system prompt: “Family context: goal={…}, routine={…}, tone={…}, nudge_style={…}. Adapt your replies accordingly.”  
No DB change required for v1.

**Deliverable:** Optional `family_dynamics` object in the API and 1–2 sentences in the system prompt. Later, move to DB + UI for editing.

---

## Phase 6 — Insight Classifier (Optional “Clever” Layer)

**Goal:** Backend decides “what kind of week it was”; Arlo’s job is “explain this insight.”

### Step 6.1 — Add to `get_arlo_facts` (or a small follow-up RPC)

- `insight_type`: `"sleep_debt"` \| `"movement_drop"` \| `"recovery_strain"` \| `"balanced_week"` \| `"missing_data"`.
- `insight_evidence`: minimal structured object (e.g. which metric changed, by how much, for whom).

**Logic:** Simple rules, e.g.  
- If family sleep contribution is most negative → `"sleep_debt"`.  
- If movement contribution is most negative → `"movement_drop"`.  
- If recovery is most negative → `"recovery_strain"`.  
- If all contributions ≥ 0 and delta ≥ 0 → `"balanced_week"`.  
- If confidence low or missing_members_count > 0 → `"missing_data"`.

**Deliverable:** `insight_type` + `insight_evidence` in the facts payload. In the system prompt: “This week’s insight type is {insight_type}. Evidence: {insight_evidence}. Explain this in a short, friendly way when relevant.”

---

## Phase 7 — End-to-End Flow Checklist

Use this to verify you didn’t skip anything:

1. **Open Arlo**
   - Dashboard triggers `fetchArloFacts()` (or equivalent).
   - Client gets facts (or loading/error).

2. **First screen**
   - If facts exist: show Headline + Why + Hook + “What do you want to look at?” and the deterministic pills from `suggested_pill_labels`.
   - If no facts: show fallback opener, no pills.

3. **Pill tap**
   - Append user message with the pill label.
   - Call Edge Function with `messages`, `facts`, `selected_intent` = mapping of pill → intent, `supporting_facts` = relevant slice.

4. **AI reply**
   - Model sees only facts + intent + supporting_facts; system prompt forbids new reasons/metrics and uses score-forward language.

5. **Subsequent turns**
   - Same: client sends `messages`, `facts` (or latest), `selected_intent` (if inferrable from last message), `supporting_facts`.

6. **Family dynamics**
   - If you added optional `family_dynamics`, it’s included in the first request and reflected in the system prompt.

7. **Insight**
   - If you added `insight_type` / `insight_evidence`, the opener or first reply can explicitly “explain this insight” using only that evidence.

---

## Suggested Order of Work

| Order | Phase / Step | Deliverable |
|-------|-----------------------------|-------------|
| 1 | 1.1–1.2 | RPC `get_arlo_facts` returning full facts (with stub or simple contribution logic if needed to ship) |
| 2 | 2.1–2.2 | Pill rules + opener template in backend (or spec + client impl) |
| 3 | 3.1–3.2 | Client: fetch facts, pass to Arlo; Arlo shows opener + pills and sends intent on pill tap |
| 4 | 4.1–4.3 | Edge Function: new body (facts, intent, supporting_facts), narrative-only + score-forward prompt |
| 5 | 5.1 | Optional family_dynamics in request + prompt (client or DB later) |
| 6 | 6.1 | Optional insight_type + insight_evidence in facts and prompt |

Doing 1 → 2 → 3 → 4 gives you the “clever but no hallucinations” experience; 5 and 6 add personality and the “explain this insight” polish.
