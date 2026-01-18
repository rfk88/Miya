# Complete Flow: Rook Data → Vitality Scores → Dashboard

This document explains exactly how health data flows from Rook into Miya, how individual and family vitality scores are calculated, and how everything appears on the dashboard.

---

## 📊 Dashboard Overview

**File:** `Miya Health/DashboardView.swift`

The dashboard displays:
1. **Family Members Strip** - Avatar circles with vitality progress rings
2. **Family Vitality Card** - Overall family score (0-100) with pillar breakdown
3. **Personal Vitality Card** - Current user's individual score
4. **Family Notifications** - Insights about patterns and trends
5. **Champions Badges** - Daily and weekly winners

---

## 🔄 Complete Data Flow

### 1️⃣ **Data Ingestion from Rook**

#### When Rook Sends Data
Rook webhook triggers the Supabase Edge Function:
- **File:** `supabase/functions/rook/index.ts`
- **Endpoint:** `/rook` (webhook handler)
- **Trigger:** Rook sends health data after user syncs their wearable

#### What Rook Sends
Two main data types arrive:
- **Sleep Summary** (`sleep_health.sleep_summaries[]`)
  - Sleep duration, REM, deep sleep, efficiency
  - HRV (SDNN/RMSSD)
  - Resting heart rate
  - Breathing rate
  
- **Physical Summary** (`physical_health.physical_summaries[]`)
  - Steps, active calories
  - Heart rate data (backup)

---

### 2️⃣ **Data Transformation: ROOK → VitalityRawMetrics**

#### Step 2A: Daily Mapping (One Day)
**File:** `Miya Health/ROOKDayToMiyaAdapter.swift`

```swift
ROOKDayToMiyaAdapter.mapOneDay(
    age: userAge,
    sleepSummary: oneDayOfSleep,
    physicalSummary: oneDayOfPhysical
) → VitalityRawMetrics
```

**Transformations:**
- `sleep_duration_seconds_int / 3600` → `sleepDurationHours`
- `(rem + deep) / total * 100` → `restorativeSleepPercent`
- `sleep_efficiency_1_100_score_int` → `sleepEfficiencyPercent`
- `time_awake / time_in_bed * 100` → `awakePercent`
- Prefer `hrv_avg_sdnn_float`, fallback to `hrv_avg_rmssd_float` → `hrvMs`
- `hr_resting_bpm_int` → `restingHeartRate`
- `breaths_avg_per_min_int` → `breathingRate`
- `steps_int` → `steps`
- `calories_net_active_kcal_float` → `activeCalories`

#### Step 2B: Window Aggregation (7-30 Days)
**File:** `Miya Health/ROOKWindowAggregator.swift`

```swift
ROOKWindowAggregator.buildWindowRawMetrics(
    age: userAge,
    dataset: rookDataset,
    windowMaxDays: 30,
    windowMinDays: 7
) → VitalityRawMetrics (aggregated)
```

**Window Logic:**
- If ≥30 days available: use last 30 days
- If 7-29 days: use all available
- If <7 days: use what we have

**Aggregation:**
- Most metrics: **average** across the window
- Missing metrics: **backfill** from previous 7 days (last-known-value)
- HRV type rollup:
  - If ≥60% "rmssd" → "rmssd"
  - Else if ≥60% "sdnn" → "sdnn"
  - Else if both → "mixed"

---

### 3️⃣ **Individual Vitality Score Calculation**

#### Scoring Engine
**File:** `Miya Health/VitalityScoringEngine.swift`

```swift
VitalityScoringEngine().scoreIfPossible(
    raw: VitalityRawMetrics
) → (snapshot: VitalitySnapshot, breakdown: VitalityBreakdown)?
```

#### Scoring Formula

**Phase 1: Sub-Metric Scoring (0-100 each)**

Each raw metric is scored based on age-specific ranges:

**Three scoring directions:**

1. **Optimal Range** (e.g., sleep duration)
   - In optimal range (e.g., 7-9 hrs) → 80-100 points
   - In acceptable range → 50-80 points
   - In poor range → 0-50 points

2. **Higher is Better** (e.g., steps, HRV)
   - Above optimal upper bound → 100 points
   - In optimal range → 80-100 points
   - In acceptable range → 60-80 points
   - Below acceptable → 0-60 points

3. **Lower is Better** (e.g., resting HR, awake %)
   - Below optimal lower bound → 100 points
   - In optimal range → 80-100 points
   - In acceptable range → 60-80 points
   - Above acceptable → 0-60 points

**Phase 2: Pillar Aggregation**

Three pillars aggregate sub-metrics:

```
Pillar Score = Weighted Average of Sub-Metric Scores
```

**Sleep Pillar (40% weight in total)**
- Sleep Duration (40% within pillar)
- Restorative Sleep % (30%)
- Sleep Efficiency (20%)
- Awake % (10%)

**Movement Pillar (30% weight in total)**
- Steps (40% within pillar)
- Movement Minutes (30%)
- Active Calories (30%)

**Stress Pillar (30% weight in total)**
- HRV (40% within pillar)
- Resting Heart Rate (30%)
- Breathing Rate (30%)

**Important:** Missing sub-metrics don't penalize the score - weights are normalized across available metrics only.

**Phase 3: Total Vitality Score**

```
Total Vitality = Weighted Average of Pillar Scores
```

Where pillars with no available data are excluded from the calculation.

**Example:**
```
Sleep: 72 (40% weight, available)
Movement: 86 (30% weight, available)
Stress: nil (no data, excluded)

Total = (72 × 0.4 + 86 × 0.3) / (0.4 + 0.3)
      = (28.8 + 25.8) / 0.7
      = 54.6 / 0.7
      = 78
```

#### Minimum Data Requirement

Score is only computed if **at least 2 pillars** have at least 1 available sub-metric each.

---

### 4️⃣ **Score Persistence**

#### Server-Side (Webhook)
**File:** `supabase/functions/rook/index.ts`

When Rook webhook fires:
1. Transform data using TypeScript equivalent of adapters
2. Call `recomputeRolling7dScoresForUser()` (in `scoring/recompute.ts`)
3. Compute scores for each day in the window
4. Upsert to `vitality_scores` table (daily history)
5. Update `user_profiles` with latest snapshot:
   ```sql
   vitality_score_current = totalScore
   vitality_sleep_pillar_score = sleepScore
   vitality_movement_pillar_score = movementScore
   vitality_stress_pillar_score = stressScore
   vitality_score_updated_at = NOW()
   vitality_score_source = 'wearable'
   ```

#### Client-Side (Manual Upload)
**File:** `Miya Health/RiskResultsView.swift` (ROOK Export handler)

When user manually uploads ROOK JSON:
1. Parse JSON → ROOKDataset
2. `ROOKWindowAggregator.buildWindowRawMetrics()` → aggregated metrics
3. `ROOKWindowAggregator.buildDailyRawMetricsByUTCKey()` → daily metrics
4. Score window with `VitalityScoringEngine()`
5. Save daily scores to `vitality_scores`
6. Save current snapshot to `user_profiles` via `DataManager.saveVitalitySnapshot()`

---

### 5️⃣ **Family Vitality Score Calculation**

#### Database RPC
**File:** `supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql`

**Function:** `get_family_vitality(family_id)`

**Logic:**
```sql
1. Find all active family members
2. Get their vitality_score_current from user_profiles
3. Filter to members with:
   - vitality_score_current IS NOT NULL
   - vitality_score_updated_at >= NOW() - INTERVAL '3 days'
   
4. Compute family averages:
   family_vitality_score = ROUND(AVG(vitality_score_current))
   family_progress_score = ROUND(AVG(vitality_progress_score_current))
   
5. Return:
   - family_vitality_score (0-100)
   - family_progress_score (0-100, capped)
   - members_with_data (count of members with fresh scores)
   - members_total (all active members)
   - has_recent_data (boolean)
```

**Fresh Data Window:** 3 days
- Scores older than 3 days are excluded from family calculations
- This prevents stale data from skewing the family score

#### Family Vitality Formula

```
Family Score = Average of all fresh individual scores

Example:
Dad: 78 (fresh)
Mom: 82 (fresh)
Kid: 65 (fresh)
Grandma: 71 (stale, 5 days old - EXCLUDED)

Family Score = (78 + 82 + 65) / 3 = 75
```

#### Progress Score
Each user has a `progress_score` (0-100) that represents progress toward their **personal optimal target** based on:
- Age
- Risk band (from QRISK3 or WHO CVD risk)
- Current score vs optimal target matrix

Family progress score = average of individual progress scores (same 3-day freshness rule).

---

### 6️⃣ **Dashboard Data Loading**

#### On Dashboard Load
**File:** `Miya Health/DashboardView.swift`

**Sequence:**
```swift
1. loadFamilyMembers()
   → Fetch all family members with their current scores
   → Build FamilyMemberScore array
   
2. loadFamilyVitality()
   → Call get_family_vitality RPC
   → Store familyVitalityScore, familyVitalityProgressScore
   
3. computeAndStoreFamilySnapshot()
   → FamilyVitalitySnapshotEngine.compute(...)
   → Generate insights: support members, celebrate members
   → Identify focus pillar (lowest) and strength pillar (highest)
   
4. computeTrendInsights()
   → Analyze historical pillar scores
   → Detect improving/declining trends
   
5. computeFamilyBadgesIfNeeded()
   → Award daily/weekly champions
```

#### Family Members Strip

**Display:**
- Circular avatars with initials
- Progress ring around avatar: `progressScore / 100` or `currentScore / optimalScore`
- Ring color:
  - Green: score ≥70
  - Yellow: 50-69
  - Red: <50

**Source:** `FamilyMemberScore` array from `DataManager.fetchFamilyMembers()`

#### Family Vitality Card

**File:** `Miya Health/Dashboard/DashboardVitalityCards.swift`

**Displays:**
- Large semicircle gauge showing `familyVitalityScore`
- Label: "Rebuilding" (<50), "Steady" (50-70), "Strong" (>70)
- Pillar breakdown: Sleep, Movement, Stress scores
- "Included members: X/Y" text
- Progress score (if available)

**Data Source:** State variables populated by `loadFamilyVitality()`

#### Personal Vitality Card

**Displays:**
- Current user's individual score
- Current score vs optimal target
- Sub-metrics breakdown (if available)

**Data Source:** `familyMembers.first(where: { $0.isMe })`

---

## 🔍 Key Data Structures

### VitalityRawMetrics
```swift
struct VitalityRawMetrics {
    let age: Int
    let sleepDurationHours: Double?
    let restorativeSleepPercent: Double?
    let sleepEfficiencyPercent: Double?
    let awakePercent: Double?
    let movementMinutes: Double?
    let steps: Int?
    let activeCalories: Double?
    let hrvMs: Double?
    let hrvType: String?  // "sdnn", "rmssd", or "mixed"
    let restingHeartRate: Double?
    let breathingRate: Double?
}
```

### VitalitySnapshot
```swift
struct VitalitySnapshot {
    let age: Int
    let ageGroup: AgeGroup
    let totalScore: Int  // 0-100
    let pillarScores: [PillarScore]  // Sleep, Movement, Stress
}
```

### FamilyMemberScore
```swift
struct FamilyMemberScore {
    let name: String
    let userId: String?
    let hasScore: Bool
    let isScoreFresh: Bool  // Updated within 3 days
    let currentScore: Int   // 0-100
    let optimalScore: Int   // Target based on age/risk
    let progressScore: Int? // 0-100 (capped progress to optimal)
    let isMe: Bool
}
```

### FamilyVitalitySnapshot
```swift
struct FamilyVitalitySnapshot {
    let familyStateLabel: FamilyState  // rebuilding, steady, strong
    let alignmentLevel: AlignmentLevel  // tight, mixed, wide
    let focusPillar: VitalityPillar?    // Lowest pillar
    let strengthPillar: VitalityPillar? // Highest pillar
    let supportMembers: [MemberInsight] // Members <75% of target
    let celebrateMembers: [MemberInsight] // Members ≥90% of target
    let familyAverageScore: Int?
    let membersIncluded: Int
    let membersTotal: Int
}
```

---

## 📝 Complete File Reference

### Core Scoring Files
1. **VitalityScoringEngine.swift** - Individual scoring logic
2. **ROOKDayToMiyaAdapter.swift** - One-day ROOK → Miya mapping
3. **ROOKWindowAggregator.swift** - Multi-day aggregation + backfill
4. **ScoringSchema.swift** - Age-specific benchmarks and weights

### Dashboard Files
1. **DashboardView.swift** - Main dashboard layout and data orchestration
2. **Dashboard/DashboardVitalityCards.swift** - Family and personal vitality cards
3. **Dashboard/DashboardModels.swift** - FamilyMemberScore model
4. **FamilyVitalitySnapshot.swift** - Family insights computation

### Data Layer Files
1. **DataManager.swift** - All database queries and mutations
2. **RookAPIService.swift** - Rook REST API integration

### Database Files
1. **supabase/migrations/20251227121000_update_family_vitality_rpcs_add_progress_score.sql**
   - `get_family_vitality(family_id)` RPC
   - `get_family_vitality_scores(family_id, start_date, end_date)` RPC

### Server-Side Functions
1. **supabase/functions/rook/index.ts** - Webhook handler
2. **supabase/functions/rook/scoring/score.ts** - TypeScript scoring engine
3. **supabase/functions/rook/scoring/recompute.ts** - Rolling 7-day recomputation

---

## 🔄 Refresh Logic

### Pull-to-Refresh on Dashboard
1. `refreshFamilyVitalitySnapshotsIfPossible()` - Calls RPC to recompute all family scores
2. `loadFamilyMembers()` - Refreshes member list
3. `loadServerPatternAlerts()` - Fetches server-generated insights
4. `loadFamilyVitality()` - Fetches latest family score
5. `computeAndStoreFamilySnapshot()` - Client-side insight generation
6. `computeTrendInsights()` - Historical trend analysis
7. `computeFamilyBadgesIfNeeded()` - Champion awards

### Weekly Refresh (Sundays Only)
**File:** `Miya Health/Services/WeeklyVitalityScheduler.swift`

- Checks if last refresh was >7 days ago OR if it's Sunday
- If true: triggers server recomputation for all family members
- Marks refresh timestamp in UserDefaults

---

## 🎯 Summary

**Individual Score:**
1. Rook sends data → Edge function receives webhook
2. Rook data → VitalityRawMetrics (10 metrics)
3. VitalityRawMetrics → VitalitySnapshot (weighted scoring)
4. VitalitySnapshot → user_profiles (current score + pillars)

**Family Score:**
1. Database RPC averages all family members' current scores
2. Only includes scores updated within last 3 days
3. Returns family average (0-100) + member counts

**Dashboard Display:**
1. Loads family vitality via RPC
2. Loads individual member scores
3. Computes insights (support/celebrate members, focus pillar)
4. Renders cards with gauges, rings, and recommendations

**Key Formula:**
```
Individual Score = Weighted avg of pillar scores
                 = (Sleep × 40% + Movement × 30% + Stress × 30%)
                   / (sum of available pillar weights)

Family Score = Simple average of fresh individual scores
             = (member1 + member2 + ... + memberN) / N
               (where each member was updated ≤3 days ago)
```

---

## 🔧 Testing the Flow

### Manual Testing
1. Upload ROOK JSON via Debug view
2. Check `vitality_scores` table for daily history
3. Check `user_profiles.vitality_score_current` for snapshot
4. Pull to refresh dashboard
5. Verify family card shows updated score

### Server Testing (when webhook is live)
1. User syncs wearable via ROOK SDK
2. ROOK sends webhook to `/rook` function
3. Function computes scores and updates DB
4. User pulls to refresh dashboard
5. New scores appear immediately

---

**Last Updated:** Jan 24, 2026
