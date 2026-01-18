# Architecture Flow Diagram

## 📊 Complete Data Flow: Wearable → Dashboard

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER'S WEARABLE DEVICE                       │
│                    (Apple Watch, Whoop, Oura, etc.)                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            ROOK PLATFORM                             │
│  • Collects health data from wearables via SDK/OAuth               │
│  • Normalizes data into unified format                              │
│  • Sends webhook to Miya when new data arrives                     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼ (webhook POST)
┌─────────────────────────────────────────────────────────────────────┐
│                    SUPABASE EDGE FUNCTION                            │
│                 supabase/functions/rook/index.ts                     │
│                                                                      │
│  1. Receive webhook (sleep_health + physical_health)                │
│  2. Extract user_id from webhook                                    │
│  3. Fetch user age from user_profiles                              │
│  4. Transform ROOK JSON → VitalityRawMetrics (per day)            │
│  5. Call recomputeRolling7dScoresForUser()                         │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   SCORING ENGINE (TypeScript)                        │
│            supabase/functions/rook/scoring/recompute.ts              │
│                                                                      │
│  For each day in 7-day rolling window:                             │
│    1. Aggregate raw metrics from activity_events                    │
│    2. Build VitalityRawMetrics for that day                        │
│    3. Call scoreIfPossible(raw)                                    │
│    4. Get VitalitySnapshot (total + pillar scores)                 │
│    5. Upsert to vitality_scores table                              │
│                                                                      │
│  Latest score also updates user_profiles:                           │
│    • vitality_score_current                                         │
│    • vitality_sleep_pillar_score                                    │
│    • vitality_movement_pillar_score                                 │
│    • vitality_stress_pillar_score                                   │
│    • vitality_score_updated_at                                      │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        POSTGRES DATABASE                             │
│                                                                      │
│  Tables:                                                            │
│  • vitality_scores (daily history, per user)                       │
│    - user_id, score_date, total_score, pillar scores              │
│                                                                      │
│  • user_profiles (current snapshot, per user)                      │
│    - user_id, vitality_score_current, pillar scores               │
│    - vitality_score_updated_at                                     │
│                                                                      │
│  • family_members (links users to families)                        │
│    - family_id, user_id, role, is_active                          │
│                                                                      │
│  RPC Functions:                                                     │
│  • get_family_vitality(family_id)                                  │
│    → Computes family average from member scores (fresh only)       │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       MIYA iOS APP                                   │
│                     DashboardView.swift                              │
│                                                                      │
│  On Load / Pull-to-Refresh:                                         │
│  1. loadFamilyMembers()                                            │
│     → Fetch all family member scores                               │
│                                                                      │
│  2. loadFamilyVitality()                                           │
│     → Call get_family_vitality RPC                                 │
│     → Store familyVitalityScore                                     │
│                                                                      │
│  3. computeAndStoreFamilySnapshot()                                │
│     → FamilyVitalitySnapshotEngine.compute()                       │
│     → Generate insights (support/celebrate members)                │
│                                                                      │
│  4. Display on Dashboard:                                           │
│     • Family Vitality Card (semicircle gauge)                      │
│     • Family Members Strip (avatars with rings)                    │
│     • Personal Vitality Card (current user)                        │
│     • Notifications (insights & trends)                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Scoring Flow (Detailed)

```
┌─────────────────────────────────────────────────────────────────────┐
│                       RAW HEALTH METRICS                             │
│  from ROOK: sleep_health + physical_health summaries                │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ROOKDayToMiyaAdapter                              │
│  One day of ROOK data → VitalityRawMetrics                          │
│                                                                      │
│  Mappings:                                                          │
│  • sleep_duration_seconds_int / 3600 → sleepDurationHours          │
│  • (rem + deep) / total × 100 → restorativeSleepPercent            │
│  • sleep_efficiency_1_100_score_int → sleepEfficiencyPercent       │
│  • time_awake / time_in_bed × 100 → awakePercent                   │
│  • hrv_avg_sdnn_float (prefer) or hrv_avg_rmssd_float → hrvMs     │
│  • hr_resting_bpm_int → restingHeartRate                           │
│  • breaths_avg_per_min_int → breathingRate                         │
│  • steps_int → steps                                               │
│  • calories_net_active_kcal_float → activeCalories                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   ROOKWindowAggregator                               │
│  Multiple days → Aggregated VitalityRawMetrics                      │
│                                                                      │
│  Logic:                                                             │
│  • Use last 7-30 days (prefer 30 if available)                     │
│  • Average each metric across the window                           │
│  • Backfill missing metrics from previous 7 days                   │
│  • HRV type rollup: if ≥60% same type, use that; else "mixed"     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  VitalityScoringEngine                               │
│  VitalityRawMetrics → VitalitySnapshot                              │
│                                                                      │
│  Step 1: Score each sub-metric (0-100)                             │
│    • Compare raw value to age-specific ranges                      │
│    • Optimal range → 80-100 points                                 │
│    • Acceptable range → 50-80 points                               │
│    • Poor range → 0-50 points                                      │
│    • Missing data → 0 points (excluded from weights)               │
│                                                                      │
│  Step 2: Aggregate to pillar scores (weighted average)             │
│    Sleep = weighted avg of 4 sub-metrics                           │
│    Movement = weighted avg of 3 sub-metrics                        │
│    Stress = weighted avg of 3 sub-metrics                          │
│                                                                      │
│  Step 3: Compute total score (weighted average)                    │
│    Total = (Sleep×40% + Movement×30% + Stress×30%)                 │
│            / (sum of available pillar weights)                      │
│                                                                      │
│  Minimum requirement: ≥2 pillars with data                          │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     VitalitySnapshot                                 │
│  • totalScore: 0-100                                                │
│  • pillarScores: [sleep, movement, stress]                         │
│  • age, ageGroup                                                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 👨‍👩‍👧‍👦 Family Score Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│              INDIVIDUAL USER SCORES (in user_profiles)               │
│                                                                      │
│  Dad:    vitality_score_current = 78, updated 2 days ago           │
│  Mom:    vitality_score_current = 82, updated 1 day ago            │
│  Kid:    vitality_score_current = 65, updated today                │
│  Grandma: vitality_score_current = 71, updated 5 days ago          │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              DATABASE RPC: get_family_vitality(family_id)           │
│                                                                      │
│  1. Find all active family members                                 │
│  2. Filter to members with:                                         │
│     • vitality_score_current IS NOT NULL                           │
│     • vitality_score_updated_at >= NOW() - INTERVAL '3 days'      │
│                                                                      │
│  3. Compute averages:                                              │
│     family_vitality_score = ROUND(AVG(vitality_score_current))    │
│     family_progress_score = ROUND(AVG(vitality_progress_score_current)) │
│                                                                      │
│  4. Count members:                                                  │
│     members_with_data = count of fresh scores                      │
│     members_total = count of all active members                    │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      FAMILY SCORE RESULT                             │
│                                                                      │
│  family_vitality_score: 75  (Dad + Mom + Kid) / 3                  │
│  family_progress_score: 82                                          │
│  members_with_data: 3       (Grandma excluded - stale)             │
│  members_total: 4                                                   │
│  has_recent_data: true                                              │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│               FamilyVitalitySnapshotEngine.compute()                 │
│  Generates insights from family + member data:                      │
│                                                                      │
│  • Family state: "Steady" (score 50-70)                            │
│  • Alignment: "Tight" (similar scores)                             │
│  • Focus pillar: "Sleep" (lowest avg)                              │
│  • Strength pillar: "Movement" (highest avg)                       │
│  • Support members: [Kid] (<75% of target)                         │
│  • Celebrate members: [Mom] (≥90% of target)                       │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    DASHBOARD DISPLAY                                 │
│                                                                      │
│  ┌─────────────────────────────────────────┐                       │
│  │       FAMILY VITALITY CARD              │                       │
│  │                                         │                       │
│  │     ╭─────────╮                         │                       │
│  │    ╱           ╲   Family Vitality      │                       │
│  │   │     75      │   Steady              │                       │
│  │    ╲           ╱                        │                       │
│  │     ╰─────────╯                         │                       │
│  │                                         │                       │
│  │  Sleep: 72   Movement: 86   Stress: 64 │                       │
│  │  Included members: 3/4                  │                       │
│  └─────────────────────────────────────────┘                       │
│                                                                      │
│  ┌─────────────────────────────────────────┐                       │
│  │     FAMILY MEMBERS STRIP                │                       │
│  │                                         │                       │
│  │  👤 Dad    👤 Mom    👤 Kid   👤 Grandma│                       │
│  │  (78)     (82)     (65)       (71)      │                       │
│  │   🟢       🟢       🟡         ⚪       │                       │
│  └─────────────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Webhook vs Manual Upload

### Option 1: Webhook (Production)
```
Wearable → ROOK → Webhook → Edge Function → DB → Dashboard
         (auto)  (POST)    (compute)      (save) (display)
```

**Trigger:** Automatic when user syncs wearable  
**Latency:** ~1-5 minutes after sync  
**Files:** `supabase/functions/rook/index.ts`

### Option 2: Manual Upload (Testing)
```
User → Upload JSON → RiskResultsView → Adapters → Engine → DB → Dashboard
       (file)        (parse)           (map)      (score) (save) (display)
```

**Trigger:** User manually uploads ROOK JSON export  
**Latency:** Immediate after upload  
**Files:** `RiskResultsView.swift` + adapters

---

## 📊 Key Weights & Thresholds

### Pillar Weights (Total Score)
```
Sleep:    40%
Movement: 30%
Stress:   30%
```

### Sub-Metric Weights (Within Each Pillar)

**Sleep Pillar:**
```
Duration:       40%
Restorative:    30%
Efficiency:     20%
Awake:          10%
```

**Movement Pillar:**
```
Steps:          40%
Minutes:        30%
Calories:       30%
```

**Stress Pillar:**
```
HRV:            40%
Resting HR:     30%
Breathing:      30%
```

### Freshness Thresholds
```
Individual score: No age limit (uses rolling window)
Family inclusion: 3 days max age
Backfill lookback: 7 days max
```

### Data Minimums
```
Individual score: ≥2 pillars with ≥1 sub-metric each
Family score:     ≥1 member with fresh score
```

---

## 🎯 Decision Points

### When is a score computed?
- **YES:** If ≥2 pillars have data
- **NO:** If <2 pillars have data
- **NULL sub-metrics** are excluded from weights (no penalty)

### When is a member included in family score?
- **YES:** vitality_score_current IS NOT NULL AND updated ≤3 days ago
- **NO:** NULL score OR updated >3 days ago OR is_active = false

### When does backfill happen?
- **During window aggregation:** If metric is NULL across current window
- **Lookback period:** Previous 7 days only
- **Method:** Last-known-value (most recent non-NULL)
- **Never:** Invent values or average across weeks

---

**Last Updated:** Jan 24, 2026
