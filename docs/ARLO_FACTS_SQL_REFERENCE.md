# Arlo Facts — SQL & Schema Reference

Surgical reference for building `get_arlo_facts`: RPC definitions, Champions week logic, and tables/columns for vitality and membership.

---

## 1. `get_family_vitality_scores` (current RPC)

**Source:** `supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql`

**Signature:**
```sql
get_family_vitality_scores(
  family_id uuid,
  start_date text,   -- YYYY-MM-DD
  end_date text      -- YYYY-MM-DD
)
```

**Returns:** Table rows:
- `user_id uuid`
- `score_date text` (YYYY-MM-DD)
- `total_score int`
- `progress_score int` (from `vitality_progress_score()` when it exists, else null)
- `vitality_sleep_pillar_score int`
- `vitality_movement_pillar_score int`
- `vitality_stress_pillar_score int`

**Full SQL:**

```sql
create function public.get_family_vitality_scores(
  family_id uuid,
  start_date text,
  end_date text
)
returns table (
  user_id uuid,
  score_date text,
  total_score int,
  progress_score int,
  vitality_sleep_pillar_score int,
  vitality_movement_pillar_score int,
  vitality_stress_pillar_score int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_is_member boolean;
  has_progress_function boolean;
begin
  select exists (
    select 1
    from public.family_members fm
    where fm.family_id = get_family_vitality_scores.family_id
      and fm.user_id = auth.uid()
  )
  into caller_is_member;

  if not caller_is_member then
    raise exception 'Not authorized to access family vitality scores';
  end if;

  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'vitality_progress_score'
  )
  into has_progress_function;

  if has_progress_function then
    return query
    select
      vs.user_id,
      vs.score_date::text,
      vs.total_score,
      public.vitality_progress_score(vs.total_score, up.date_of_birth, up.risk_band) as progress_score,
      vs.vitality_sleep_pillar_score,
      vs.vitality_movement_pillar_score,
      vs.vitality_stress_pillar_score
    from public.vitality_scores vs
    left join public.user_profiles up
      on up.user_id = vs.user_id
    where vs.user_id in (
      select fm.user_id
      from public.family_members fm
      where fm.family_id = get_family_vitality_scores.family_id
        and fm.user_id is not null
    )
      and vs.score_date::text >= get_family_vitality_scores.start_date
      and vs.score_date::text <= get_family_vitality_scores.end_date
    order by vs.user_id, vs.score_date asc;
  else
    return query
    select
      vs.user_id,
      vs.score_date::text,
      vs.total_score,
      null::int as progress_score,
      vs.vitality_sleep_pillar_score,
      vs.vitality_movement_pillar_score,
      vs.vitality_stress_pillar_score
    from public.vitality_scores vs
    where vs.user_id in (
      select fm.user_id
      from public.family_members fm
      where fm.family_id = get_family_vitality_scores.family_id
        and fm.user_id is not null
    )
      and vs.score_date::text >= get_family_vitality_scores.start_date
      and vs.score_date::text <= get_family_vitality_scores.end_date
    order by vs.user_id, vs.score_date asc;
  end if;
end;
$$;
```

**Data source:** `vitality_scores` (filtered by `family_id` via `family_members.user_id`). Dates are UTC day keys `YYYY-MM-DD`; `score_date` in the table is `date`, cast to `text` for the API.

---

## 2. Champions week logic (reuse for “this week” vs “last week”)

**Where:** Swift in `Miya Health/Dashboard/DashboardView+DataLoading.swift`, inside `computeFamilyBadgesIfNeeded()`.

**No SQL function or view** — the app computes week windows in Swift and passes `start_date` / `end_date` into `get_family_vitality_scores`. For `get_arlo_facts` you can either:

- implement the same windows in SQL using `current_date` and intervals, or  
- keep the same definitions and call `get_family_vitality_scores` twice from SQL (this week, last week) using equivalent date logic.

**Swift logic (UTC day keys, `yyyy-MM-dd`):**

```swift
internal func utcDayKey(for date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: date)
}

internal func dateByAddingDays(_ days: Int, to date: Date) -> Date {
    Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date) ?? date
}

// In computeFamilyBadgesIfNeeded():
let today = Date()
let todayKey = utcDayKey(for: today)

// This week: last 7 days INCLUDING today
let weekEndDate = today
let weekStartDate = dateByAddingDays(-6, to: weekEndDate)
let weekEndKey = utcDayKey(for: weekEndDate)   // today
let weekStartKey = utcDayKey(for: weekStartDate)  // today - 6

// Previous week: 7 days before this week
let prevEndDate = dateByAddingDays(-1, to: weekStartDate)   // yesterday of week start
let prevStartDate = dateByAddingDays(-6, to: prevEndDate)
let prevEndKey = utcDayKey(for: prevEndDate)
let prevStartKey = utcDayKey(for: prevStartDate)

// Fetch uses: startDate = prevStartKey, endDate = todayKey
// So one call covers prev week + this week. For Arlo you need two ranges:
// - This week: start_date = weekStartKey, end_date = weekEndKey
// - Last week: start_date = prevStartKey, end_date = prevEndKey
```

**Equivalent in PostgreSQL (UTC, `YYYY-MM-DD`):**

```sql
-- Today (UTC date)
today_utc := (current_timestamp at time zone 'UTC')::date;

-- This week: 7 days including today
this_week_start := today_utc - interval '6 days';  -- date
this_week_end   := today_utc;

-- Last week: the 7 days before this week
last_week_end   := this_week_start - interval '1 day';
last_week_start := last_week_end - interval '6 days';

-- As text for get_family_vitality_scores
this_week_start_t := to_char(this_week_start::date, 'YYYY-MM-DD');
this_week_end_t   := to_char(this_week_end::date, 'YYYY-MM-DD');
last_week_start_t := to_char(last_week_start::date, 'YYYY-MM-DD');
last_week_end_t   := to_char(last_week_end::date, 'YYYY-MM-DD');
```

**Calls to reuse:**

- This week: `get_family_vitality_scores(family_id, this_week_start_t, this_week_end_t)`
- Last week: `get_family_vitality_scores(family_id, last_week_start_t, last_week_end_t)`

---

## 3. Tables and columns (vitality + membership)

### 3.1 Families

**Table:** `public.families`  
**Source:** `supabase/migrations/20251203202306_create_miya_tables.sql`

| Column           | Type      | Notes                        |
|------------------|-----------|------------------------------|
| `id`             | uuid      | PK, default `gen_random_uuid()` |
| `name`           | text      | NOT NULL                     |
| `size_category`  | text      | NOT NULL, e.g. `'twoToFour'` |
| `created_by`     | uuid      | FK → `auth.users(id)`        |
| `created_at`     | timestamptz | default now()              |

**Family → members:** via `family_members.family_id` → `families.id`.

---

### 3.2 Family members (family → user_id map)

**Table:** `public.family_members`  
**Source:** `supabase/migrations/20251203202306_create_miya_tables.sql`

| Column           | Type      | Notes                        |
|------------------|-----------|------------------------------|
| `id`             | uuid      | PK                           |
| `user_id`        | uuid      | FK → `auth.users(id)`; NULL if invite not accepted |
| `family_id`      | uuid      | FK → `families(id)` NOT NULL  |
| `role`           | text      | 'superadmin','admin','member' |
| `relationship`   | text      | e.g. 'Partner','Parent'      |
| `first_name`     | text      | NOT NULL                     |
| `invite_code`    | text      | unique                       |
| `invite_status`  | text      | 'pending','accepted'         |
| `onboarding_type` | text    | e.g. 'Guided Setup'          |
| `joined_at`      | timestamptz | default now()             |
| `is_active`      | boolean   | optional; if present, RPCs use `is_active is true` |

**Mapping family → member user_ids:**

```sql
select fm.user_id
from public.family_members fm
where fm.family_id = :family_id
  and fm.user_id is not null
  -- and (fm.is_active is true)   -- if column exists
```

Member display name: `family_members.first_name` (or from `user_profiles` if you join).

---

### 3.3 Where “family vitality score” lives

The **family** vitality score is **not** stored in a column. It is **computed** by the RPC `get_family_vitality(family_id)`.

**RPC:** `get_family_vitality(family_id uuid)`  
**Source:** `supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql`

**Returns (single row):**

| Column                   | Type    | Meaning |
|--------------------------|---------|---------|
| `family_vitality_score`  | int     | ROUND(AVG(member `vitality_score_current`)) over members with fresh data |
| `members_with_data`     | int     | Count of members with non-null score and `vitality_score_updated_at >= now() - 7 days` |
| `members_total`         | int     | Count of active family members |
| `last_updated_at`       | timestamptz | Max `vitality_score_updated_at` among those members |
| `has_recent_data`       | boolean | True if `members_with_data > 0` |
| `family_progress_score` | int     | Avg of `vitality_progress_score_current` (when column exists) |

**Source of per-member scores for that RPC:** `user_profiles.vitality_score_current` and `user_profiles.vitality_score_updated_at` (and optionally `vitality_progress_score_current`). “Fresh” is **7 days** in the current `get_family_vitality` definition.

So:

- **Table:** `user_profiles`
- **Columns:** `vitality_score_current`, `vitality_score_updated_at`, and optionally `vitality_progress_score_current`
- **Aggregation:** done inside `get_family_vitality`; no separate “family vitality” table.

---

### 3.4 User profiles (vitality snapshot + pillars)

**Table:** `public.user_profiles`  
**Relevant parts from:** `20251203202306_create_miya_tables.sql`, `20251217183000_add_user_profiles_onboarding_and_who_fields.sql`, `20251221220000_add_user_profiles_vitality_pillar_scores.sql`, `20251227120000_add_vitality_optimal_targets_and_progress_score.sql`

**Vitality-related columns:**

| Column                           | Type        | Notes |
|----------------------------------|-------------|--------|
| `user_id`                        | uuid        | FK → `auth.users(id)` UNIQUE NOT NULL |
| `vitality_score_current`         | int         | 0–100, current snapshot |
| `vitality_score_updated_at`      | timestamptz | When snapshot was updated |
| `vitality_score_source`          | text        | e.g. 'wearable','csv','manual' |
| `vitality_sleep_pillar_score`    | int         | 0–100 |
| `vitality_movement_pillar_score` | int         | 0–100 |
| `vitality_stress_pillar_score`   | int         | 0–100 |
| `vitality_progress_score_current`| int         | 0–100, progress to optimal (when present) |
| `date_of_birth`                  | date        | For progress/risk |
| `risk_band`                      | text        | For progress/risk |

Family score is derived from these **snapshot** fields via `get_family_vitality`. Daily history (for deltas, pillars, “this week vs last week”) comes from `vitality_scores`.

---

### 3.5 Vitality scores (daily history)

**Table:** `public.vitality_scores`  
**Source:** `vitality_scores_table.sql` (project root) + `20251221230000_add_vitality_scores_pillar_scores.sql`

| Column                         | Type    | Notes |
|--------------------------------|---------|--------|
| `id`                           | uuid    | PK |
| `user_id`                      | uuid    | FK → `auth.users(id)` NOT NULL |
| `score_date`                   | date    | NOT NULL, UTC day; unique with `user_id` |
| `total_score`                  | int     | 0–100 |
| `vitality_sleep_pillar_score`  | int     | 0–100 (added by migration) |
| `vitality_movement_pillar_score`| int     | 0–100 (added by migration) |
| `vitality_stress_pillar_score` | int     | 0–100 (added by migration) |
| `progress_score`               | —       | Not a column; computed in `get_family_vitality_scores` via `vitality_progress_score()` |
| `source`                       | text    | 'csv','wearable','manual' |
| `created_at`                   | timestamptz | default now() |

**Unique:** `(user_id, score_date)`.

**Mapping to family:** `vitality_scores.user_id` is in the set of `family_members.user_id` for the given `family_id`. `get_family_vitality_scores` does that filter via the subquery on `family_members`.

---

### 3.6 Quick reference: family → vitality

| What you need           | Where it lives / how to get it |
|-------------------------|----------------------------------|
| Family id               | `families.id`                    |
| Member user_ids         | `family_members.user_id` where `family_id = :id` and `user_id is not null` |
| Member first name       | `family_members.first_name`     |
| “Family vitality score” | **Computed:** `get_family_vitality(family_id)` → `family_vitality_score` (from `user_profiles.vitality_score_current` / `vitality_score_updated_at`) |
| Per-member current score | `user_profiles.vitality_score_current`, `vitality_score_updated_at` |
| Per-member, per-day scores + pillars | `vitality_scores` via `get_family_vitality_scores(family_id, start_date, end_date)` |

---

## Summary

1. **`get_family_vitality_scores(family_id, start_date, end_date)**  
   - Returns daily rows from `vitality_scores` for that family’s members and date range.  
   - Use **Champions-style windows** (this week = last 7 days including today, last week = previous 7 days) so “this week” vs “last week” match the app.

2. **Champions week logic**  
   - Implemented in Swift in `DashboardView+DataLoading.swift`; no SQL view.  
   - Use the PostgreSQL equivalent above (or two calls to `get_family_vitality_scores` with `this_week_start/end` and `last_week_start/end`) inside `get_arlo_facts`.

3. **Tables**  
   - **families** – `id`, `name`, …  
   - **family_members** – `family_id`, `user_id`, `first_name`, optional `is_active`  
   - **user_profiles** – `user_id`, `vitality_score_current`, `vitality_score_updated_at`, pillar columns, progress  
   - **vitality_scores** – `user_id`, `score_date`, `total_score`, pillar columns (daily history)

4. **Where family vitality score lives**  
   - Only inside **`get_family_vitality(family_id)`**, computed from **`user_profiles.vitality_score_current`** and **`vitality_score_updated_at`** for members of that family.

5. **Family → member user_ids**  
   - `select user_id from family_members where family_id = :id and user_id is not null` (and `is_active is true` if that column exists).
