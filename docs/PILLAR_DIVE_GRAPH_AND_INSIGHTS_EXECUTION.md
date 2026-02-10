# Pillar Dive Sheet: Graph (30/60/90 days) + Insights — Full Execution Guide

Replace the current “7 / 14 / 30 day boxes” and “What’s changing / Breakdown / What this means” with a **time-series graph** (30 / 60 / 90 day selector) and a single **“Insights”** block of trend-based copy. Same treatment for **Movement**, **Sleep**, and **Recovery**.

---

## 1. Current State (What We’re Changing)

| Where | What exists today |
|-------|-------------------|
| **FamilyMemberProfileView** | Three pillar rows (Movement, Sleep, Recovery). Tapping a row sets `selectedPillarForDive` and presents `PillarDiveDeeperSheet`. |
| **PillarDiveDeeperSheet** | Receives: `memberName`, `pillar` (PillarType), `movement` / `sleep` / `recovery` (ProfilePillarData?). Shows: header “Last 7–30 days”, **snapshotRow** (three boxes: “7‑day avg”, “14‑day avg”, “30‑day avg” — all showing same `primaryValue`), **summaryCard** (“What’s changing”), **breakdownSection** (“Breakdown” + “Current status”), **insightCard** (“What this means”). All copy is hardcoded per pillar. |
| **Data** | Profile loads pillar summary from `wearable_daily_metrics` (last 21 days) via `fetchDailyMetrics()` and builds `ProfilePillarData` (value, status, changeText, context). No use of `vitality_scores` in the profile today. |
| **DataManager** | Already has `fetchUserPillarHistory(userId: String, pillar: VitalityPillar, days: Int = 21)` → `[(date: String, value: Int?)]` from table `vitality_scores` (pillar scores 0–100 per day). |

**Goal:** One dive sheet per pillar that shows a **graph** of daily pillar score over 30 / 60 / 90 days and one **Insights** section with **rule-based** trend text (good / bad / what to improve). Remove the three boxes and the “What’s changing / Breakdown / What this means” blocks.

---

## 2. Data Layer

### 2.1 Source of truth for the graph

- **Table:** `vitality_scores`
- **Columns:** `user_id`, `score_date` (date, stored as YYYY-MM-DD), `vitality_sleep_pillar_score`, `vitality_movement_pillar_score`, `vitality_stress_pillar_score` (0–100).
- **Existing API:** `DataManager.fetchUserPillarHistory(userId: String, pillar: VitalityPillar, days: Int)` returns `[(date: String, value: Int?)]` for that user and pillar.

**Change:** Use **90 days** when loading for the dive sheet so we can slice to 30 / 60 / 90 in the UI. Either:

- **Option A:** Call `fetchUserPillarHistory(userId: memberUserId, pillar: vitalityPillar, days: 90)` from the sheet (recommended).
- **Option B:** Add a dedicated method, e.g. `fetchMemberPillarHistoryForDive(userId: String, pillar: VitalityPillar)` that returns 90 days; internally still uses the same Supabase query with `days: 90`.

**Pillar mapping (PillarType → VitalityPillar):**

- `PillarType.movement` → `VitalityPillar.movement`
- `PillarType.sleep` → `VitalityPillar.sleep`
- `PillarType.recovery` → `VitalityPillar.stress`

### 2.2 Data flow into the sheet

- **New inputs for PillarDiveDeeperSheet:**  
  - `memberUserId: String` (required for fetching history).  
  - `dataManager: DataManager` (or use `@EnvironmentObject var dataManager: DataManager` in the sheet so it can call `fetchUserPillarHistory`).
- **On appear (or when pillar/memberUserId changes):**  
  - Call `dataManager.fetchUserPillarHistory(userId: memberUserId, pillar: vitalityPillar(for: pillar), days: 90)`.  
  - Store result in `@State private var history: [(date: String, value: Int?)] = []` and a loading/error state.
- **Range selector:**  
  - `@State private var selectedRange: PillarRange = .days30` with enum `PillarRange: Int, CaseIterable { case days30 = 30; case days60 = 60; case days90 = 90 }`.  
  - Slice `history` to the last `selectedRange.rawValue` days for the chart and for insight computation.

### 2.3 No backend/RPC changes

- All data comes from existing `vitality_scores` and existing `DataManager.fetchUserPillarHistory`.  
- If `fetchUserPillarHistory` currently caps at 21 days, extend the `days` parameter to support **90** (call site passes 90; no schema change).

---

## 3. Models and Types

### 3.1 Chart data (in-memory)

Use the existing `(date: String, value: Int?)` from `fetchUserPillarHistory`. For the chart, you can map to a simple struct if helpful:

```swift
struct PillarChartPoint: Identifiable {
    let id: String  // date
    let date: String
    let value: Int?  // 0–100, nil if missing
}
```

Slicing for the selected range:

- Take the last `selectedRange.rawValue` entries from `history` (already sorted ascending by date).
- Map to `[PillarChartPoint]` for the chart.

### 3.2 Insight result (trend + copy)

Compute **client-side** from the sliced series:

```swift
struct PillarInsight {
    let trend: PillarTrend       // .improving / .stable / .declining
    let summary: String          // 2–4 sentences: what’s good, what’s off, what to do
    let dataQuality: DataQuality  // .high / .medium / .low (e.g. by % of days with value)
}

enum PillarTrend {
    case improving
    case stable
    case declining
}

enum DataQuality {
    case high   // e.g. ≥80% of days have a value
    case medium // e.g. 50–79%
    case low    // e.g. <50% or very few points
}
```

**Trend logic (example):**

- Compare “recent half” vs “prior half” of the selected window (e.g. last 15 vs previous 15 for 30 days).
- If recent average > prior by a threshold (e.g. 3+ points) → `improving`.
- If recent average < prior by threshold → `declining`.
- Else → `stable`.
- If there are fewer than ~5 valid points in the window, treat as `stable` and set summary to “Not enough data yet.”

**Summary text:** Rule-based templates per pillar and trend (see Section 5). No AI; no new backend.

---

## 4. UI Changes

### 4.1 PillarDiveDeeperSheet: new layout

**Remove:**

- `snapshotRow` (three boxes: 7 / 14 / 30 day avg).
- `summaryCard` (“What’s changing”).
- `breakdownSection` (“Breakdown” + “Current status”).
- `insightCard` (“What this means”).

**Keep:**

- Same sheet presentation (`.sheet(isPresented: $showPillarDiveSheet)`).
- Same header concept; update subtitle to reflect range, e.g. “Last 30 days” / “Last 60 days” / “Last 90 days”.
- Background and detents.

**Add:**

1. **Range selector**  
   Segmented control or pill buttons: **30 days** | **60 days** | **90 days**. Binding: `$selectedRange`. When changed, re-slice `history` and recompute insight (no new network call).

2. **Chart**  
   - X-axis: dates (e.g. last N days, can show a subset of labels to avoid clutter).  
   - Y-axis: pillar score 0–100.  
   - Plot: line or smoothed line; optional fill. Points can be `(date, value)`; skip or show gap for nil.  
   - Use a simple SwiftUI chart (e.g. `Charts` from iOS 16+) or a small custom path. Same component for all three pillars; pass in `[PillarChartPoint]`, accent color, and pillar label.

3. **Insights section**  
   - Title: **“Insights”** (under the chart).  
   - Body: `PillarInsight.summary` (2–4 lines).  
   - Optional: if `dataQuality == .low`, prefix with a short line like “Based on limited data so far.”

### 4.2 FamilyMemberProfileView: pass what the sheet needs

- Add **memberUserId** and **DataManager** to the sheet call.  
  - If the app uses `@EnvironmentObject var dataManager: DataManager` in the dashboard, add it to `FamilyMemberProfileView` and pass `dataManager` into `PillarDiveDeeperSheet`.  
  - Or pass `memberUserId` and have the sheet use `@EnvironmentObject var dataManager: DataManager` to call `fetchUserPillarHistory(memberUserId, ...)`.
- Signature change, e.g.:

```swift
PillarDiveDeeperSheet(
    memberUserId: memberUserId,
    memberName: memberName,
    pillar: pillar,
    dataManager: dataManager,  // or read from environment in sheet
    movement: movementData,
    sleep: sleepData,
    recovery: stressData
)
```

You can keep `movement` / `sleep` / `recovery` for any remaining summary line in the header or for fallback when history is empty; the main content is chart + insights from `history`.

---

## 5. Insight Text: Rule-Based Templates

Use **only** the sliced series and the computed `PillarTrend` + `DataQuality`. No freeform AI.

**Suggested template matrix (pillar × trend):**

**Movement**

- **Improving:** “Movement is trending up over this period — a sign that consistency is paying off. Keeping a mix of steps and structured activity will help maintain this.”
- **Stable:** “Movement has been fairly consistent. If you’re looking for a next step, try adding one or two short walks on lighter days.”
- **Declining:** “Movement has dipped compared to the start of this period. A small, realistic goal — e.g. one extra walk or a few more minutes of activity — can help turn it around.”

**Sleep**

- **Improving:** “Sleep is improving over this window — duration or consistency is moving in the right direction. Keeping a steady wind-down time will help lock this in.”
- **Stable:** “Sleep has been relatively stable. If you want to optimise further, focus on a consistent bedtime and limiting late screens.”
- **Declining:** “Sleep has slipped compared to earlier in the period. Even small steps — a bit earlier to bed or a calmer wind-down — can help over time.”

**Recovery**

- **Improving:** “Recovery is trending up — your body is handling stress and rest better. Keeping sleep and movement steady will support this.”
- **Stable:** “Recovery has been holding steady. Good sleep and manageable activity are the main levers if you want to nudge it up.”
- **Declining:** “Recovery has come down over this period, which often goes with more strain or less rest. Prioritising sleep and not overdoing activity can help.”

**When `DataQuality` is low:** Prepend one line, e.g. “Based on limited data so far. Keep wearing your device to see clearer trends.”

You can store these as static strings in a small helper (e.g. `PillarInsightText.template(pillar: PillarType, trend: PillarTrend, dataQuality: DataQuality)`) and keep the rest of the logic in the sheet or a dedicated “insight generator” type.

---

## 6. Implementation Order

| Step | Task | Notes |
|------|------|------|
| 1 | **Extend fetchUserPillarHistory usage to 90 days** | Call `fetchUserPillarHistory(..., days: 90)` from the dive sheet. Confirm the method supports `days: 90` (it already takes `days`; just pass 90). |
| 2 | **Add PillarRange and chart/insight types** | Add `PillarRange` (30/60/90), `PillarChartPoint`, `PillarInsight`, `PillarTrend`, `DataQuality` in `FamilyMemberProfileView.swift` or a small shared file. |
| 3 | **PillarDiveDeeperSheet: new inputs and state** | Add `memberUserId: String` and `dataManager: DataManager` (or `@EnvironmentObject`). Add `@State history`, `@State selectedRange`, `@State insight: PillarInsight?`, loading/error state. |
| 4 | **PillarDiveDeeperSheet: load history on appear** | In `.task` or `.onAppear`, map `pillar` → `VitalityPillar`, call `dataManager.fetchUserPillarHistory(userId: memberUserId, pillar: vp, days: 90)`, assign `history`. On failure, set error state (and optionally keep existing summary/placeholder). |
| 5 | **PillarDiveDeeperSheet: range selector + slice** | Add a segmented control for 30/60/90. From `history`, take the last `selectedRange.rawValue` entries; use that for chart and insight. |
| 6 | **PillarDiveDeeperSheet: insight generator** | Implement a function `computeInsight(pillar: PillarType, slicedHistory: [(date: String, value: Int?)]) -> PillarInsight`: compute trend (recent vs prior half), data quality, and pick template from Section 5. Call when history or range changes. |
| 7 | **PillarDiveDeeperSheet: chart view** | Add a chart (SwiftUI `Charts` or custom) that takes `[PillarChartPoint]`, Y-axis 0–100, X-axis dates. Use existing pillar accent colors. |
| 8 | **PillarDiveDeeperSheet: replace old blocks with chart + Insights** | Remove snapshot row, summary card, breakdown, and old insight card. Add range selector, chart, then “Insights” title + `PillarInsight.summary`. Handle empty/loading/error (e.g. “No data for this period” or retry). |
| 9 | **FamilyMemberProfileView: pass memberUserId and DataManager** | Add `@EnvironmentObject var dataManager: DataManager` to `FamilyMemberProfileView` (if not already present) and pass `memberUserId` and `dataManager` into `PillarDiveDeeperSheet`. Ensure the dashboard (or parent) provides `dataManager` in the environment when navigating to the profile. |
| 10 | **Smoke test** | Open a family member profile, tap Movement, Sleep, and Recovery. For each, confirm 30/60/90 switch updates the graph and insight text; confirm copy matches trend and pillar. |

---

## 7. File Checklist

| File | Changes |
|------|--------|
| **FamilyMemberProfileView.swift** | (1) Add `@EnvironmentObject var dataManager: DataManager` if needed. (2) Pass `memberUserId` and `dataManager` into `PillarDiveDeeperSheet`. (3) Add types: `PillarRange`, `PillarChartPoint`, `PillarInsight`, `PillarTrend`, `DataQuality`. (4) In `PillarDiveDeeperSheet`: new init params, state, load 90-day history, range selector, chart, insight generator, replace old UI with chart + Insights. |
| **DataManager.swift** | No signature change. Ensure `fetchUserPillarHistory(userId:pillar:days:)` is callable with `days: 90` (it is). |
| **DashboardMemberViews.swift** (or wherever profile is presented) | Ensure `FamilyMemberProfileView` is inside a view hierarchy that has `.environmentObject(dataManager)` so the profile and sheet can access it. |

---

## 8. Edge Cases

- **No history / empty array:** Show a message like “No pillar data for this period” and hide or disable the chart; show a generic insight line if you want (e.g. “Keep syncing your device to see trends here”).  
- **All nil values in slice:** Treat as low data quality; show “Based on limited data so far” and a neutral line.  
- **Overview pillar:** If the sheet is ever shown for `pillar == .overview`, keep existing overview UI (overview summary card + optional chat); do not show the graph/insights for overview, or hide the range selector.  
- **Member has no user_id (pending):** The profile is already not shown for such members in the normal flow; if somehow the sheet opens without a valid `memberUserId`, guard the fetch and show “Unable to load data.”

---

## 9. Summary

- **Data:** Use existing `vitality_scores` via `DataManager.fetchUserPillarHistory(userId, pillar, days: 90)`. Map `PillarType` → `VitalityPillar`.  
- **UI:** One graph (30/60/90) + one “Insights” block per pillar; remove 7/14/30 boxes and “What’s changing / Breakdown / What this means.”  
- **Insights:** Deterministic, rule-based text from trend (improving/stable/declining) and data quality, using the template matrix in Section 5.  
- **Same flow for all three pillars:** Same component, parameterised by pillar type and accent color.  
- **No new backend or RPCs.**  
- **Wiring:** Pass `memberUserId` and `DataManager` into the sheet and load history when the sheet appears.

This gives you everything needed to implement the pillar dive graph and insights end-to-end in the family member profile.
