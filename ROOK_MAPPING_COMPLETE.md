# ✅ ROOK to Miya Mapping Complete

**Date:** December 14, 2025  
**Status:** 🔒 Locked for Implementation

---

## What Was Delivered

A complete, production-ready specification for integrating ROOK Health API with Miya's vitality scoring system. **No code was changed** (as requested), but all transformation rules, data structures, and implementation requirements are now documented and locked.

---

## 📚 Documentation Created

### 1. Core Specification (START HERE)

**[docs/ROOK_TO_MIYA_MAPPING.md](./docs/ROOK_TO_MIYA_MAPPING.md)** 🔒
- **Purpose:** Single source of truth for ROOK integration
- **Size:** Comprehensive (60+ sections)
- **Status:** Locked — do not deviate without team review

**Contents:**
- Complete field mapping table (10 metrics)
- Locked transformation rules (A-J)
- ROOK API structure reference
- Data quality notes by device (Whoop, Apple, Fitbit, Oura, Garmin)
- Coverage expectations for testing
- Minimum viable requirements (sleep, steps, HRV/RHR)

**Key Decisions Locked:**
- ✅ HRV: Store SDNN or RMSSD raw, track type, **no conversion**
- ✅ Active Calories: Only active, **never substitute total calories**
- ✅ Missing Data: Use nil, **never substitute zero**
- ✅ Fallbacks: HRV types, RHR sources, movement minutes
- ✅ Units: Sleep (hours), Steps (count), HRV (ms), RHR (bpm), etc.

---

### 2. Developer Quick Reference

**[docs/ROOK_QUICK_REFERENCE.md](./docs/ROOK_QUICK_REFERENCE.md)**
- **Purpose:** Cheat sheet for developers during implementation
- **Size:** 3-4 pages, highly scannable

**Contents:**
- Critical rules (what NOT to do)
- Field mapping cheat sheet (one table, color-coded by priority)
- Calculation formulas (copy-paste ready)
- Testing checklist (5 test cases)
- Common pitfalls (❌ wrong vs ✅ correct)
- Implementation template (Swift code skeleton)

**Use this while coding the adapter!**

---

### 3. Implementation Requirements

**[docs/ROOK_IMPLEMENTATION_REQUIREMENTS.md](./docs/ROOK_IMPLEMENTATION_REQUIREMENTS.md)**
- **Purpose:** Complete project plan and checklist
- **Size:** ~3,000 words, 16 sections

**Contents:**
- Required code changes (6 new files, 3 modified files)
- Struct definitions (ROOKSleepSummary, ROOKPhysicalSummary, etc.)
- Testing requirements (unit, integration, E2E)
- Migration strategy (3 phases: Side-by-side → ROOK Primary → ROOK Only)
- Rollout plan (5 weeks: Core → Sync → UI → Beta → Production)
- Success metrics (>95% sync rate, >80% data completeness)
- Risk mitigation (API downtime, device incompatibility, etc.)

**Use this for project planning and sprint breakdown!**

---

### 4. Data Flow Visualization

**[docs/ROOK_DATA_FLOW.md](./docs/ROOK_DATA_FLOW.md)**
- **Purpose:** Visual explanation of data journey
- **Size:** ASCII diagrams + detailed explanations

**Contents:**
- End-to-end flow diagram (wearable → ROOK → Miya → UI)
- Step-by-step breakdown (5 stages)
- Fallback logic flow charts (HRV, RHR, movement minutes)
- Error handling flows (network, missing data, invalid data)
- Performance optimization strategies (caching, batching, background sync)
- Testing integration points

**Use this to understand the big picture!**

---

### 5. Documentation Index

**[docs/README.md](./docs/README.md)**
- **Purpose:** Central hub for all Miya documentation
- **Contents:** Links to all docs with descriptions, organized by topic

---

## 🔒 Locked Transformation Rules

### A. HRV Standardization
```
Primary: SDNN (ms)
Secondary: RMSSD (ms) if SDNN missing
Do NOT convert RMSSD to SDNN
Store whichever value exists in hrvMs
Record type in hrvType field ("sdnn" or "rmssd")
```

### B. Sleep Duration
```
sleepDurationHours = sleep_duration_seconds_int / 3600.0
```

### C. Restorative Sleep %
```
restorativeSleepPercent = ((rem + deep) / total) * 100
```

### D. Sleep Efficiency %
```
IF sleep_efficiency_1_100_score_int exists:
    USE that value directly
ELSE:
    sleepEfficiencyPercent = (sleep_duration / time_in_bed) * 100
```

### E. Awake %
```
awakePercent = (time_awake / time_in_bed) * 100
Fallback denominator: sleep_duration if time_in_bed missing
```

### F. Breathing Rate
```
breathingRate = breaths_avg_per_min_int (direct, already correct unit)
```

### G. Resting Heart Rate
```
restingHeartRate = hr_resting_bpm_int (direct, already in bpm)
Prefer sleep_summary, fallback to physical_summary
```

### H. Steps
```
steps = physical_summary.steps_int (direct)
```

### I. Movement Minutes
```
Primary: active_minutes_total_int
Fallback: Aggregate from activity_sessions (moderate + vigorous)
If missing: nil
```

### J. Active Calories
```
activeCalories = active_calories_kcal_double
If missing: nil
Do NOT use total_calories as substitute
```

---

## ✅ Coverage Requirements

### Must Have (Required for Scoring)
- ✅ Sleep Duration
- ✅ Steps
- ✅ At least one of: HRV **OR** Resting Heart Rate

**Without these → skip day from scoring**

### Nice to Have (Improves Accuracy)
- 🟢 Restorative Sleep %
- 🟢 Sleep Efficiency %
- 🟢 Awake %
- 🟢 Breathing Rate

**Without these → scoring still works, uses available sub-metrics**

### Can Be Nil Initially
- 🔵 Movement Minutes
- 🔵 Active Calories

**Without these → Movement pillar uses steps only**

---

## 🎯 Next Steps for Implementation

### Phase 1: Core Adapter (Week 1)
1. Add ROOK SDK to project via Swift Package Manager
2. Create `ROOKModels.swift` (data structures)
3. Create `ROOKDataAdapter.swift` (transformation logic)
4. Add `hrvType: String?` to `VitalityRawMetrics`
5. Write unit tests for all 10 transformation rules
6. Test with static sample JSON (create `rook_sample_whoop_full.json`)

### Phase 2: API Client (Week 2)
1. Create `ROOKAPIClient.swift` (network layer)
2. Implement authentication flow
3. Implement sleep summary endpoint
4. Implement physical summary endpoint
5. Add caching layer (SQLite or UserDefaults)
6. Test with ROOK sandbox environment

### Phase 3: Sync Manager (Week 3)
1. Create `ROOKSyncManager.swift` (orchestration)
2. Implement multi-day fetch (7-30 days)
3. Integrate with `VitalityMetricsBuilder.fromWindow()`
4. Add background sync scheduling
5. Handle errors gracefully (network, missing data)
6. Test with real ROOK data from team's wearables

### Phase 4: UI Integration (Week 4)
1. Create `ROOKSetupView.swift` (onboarding flow)
2. Update `RiskResultsView` (add "Connect Wearable" button)
3. Display sync status and last sync timestamp
4. Add manual refresh button
5. Keep CSV/JSON import for comparison
6. Internal testing with team

### Phase 5: Beta & Production (Week 5)
1. Invite 10-20 beta users
2. Monitor sync logs and data quality
3. Compare ROOK scores vs CSV scores (should be within 5 points)
4. Fix device-specific edge cases
5. Release to all users
6. Monitor error rates and iterate

---

## 📊 Data Quality by Device

### Excellent (All Metrics)
- **Whoop:** HRV (SDNN), sleep stages, breathing rate, RHR
- **Oura:** HRV (RMSSD), sleep stages, breathing rate, RHR

### Good (Most Metrics)
- **Garmin:** Steps, movement minutes, HRV (SDNN), activity sessions
- **Apple Watch:** Steps, sleep duration, RHR (HRV less reliable)
- **Fitbit:** Steps, sleep stages, HRV (RMSSD only)

### Limited (Basic Metrics)
- **Basic trackers:** Steps, sleep duration only

**Quality hierarchy:**
- Sleep: Whoop ≈ Oura > Garmin > Fitbit > Apple Watch
- Movement: Garmin > Fitbit > Apple Health > Whoop
- HRV: Whoop ≈ Oura > Garmin > Polar > Apple Watch > Fitbit

---

## 🚨 Critical Rules (Don't Break These!)

### 1. Never Convert HRV Types
```swift
// ❌ WRONG
let hrvMs = rmssd * 1.3  // Conversion introduces error

// ✅ CORRECT
if let sdnn = sdnn {
    raw.hrvMs = sdnn
    raw.hrvType = "sdnn"
} else if let rmssd = rmssd {
    raw.hrvMs = rmssd
    raw.hrvType = "rmssd"
}
```

### 2. Never Substitute Total Calories
```swift
// ❌ WRONG
raw.activeCalories = total_calories ?? 0

// ✅ CORRECT
raw.activeCalories = active_calories_kcal_double
```

### 3. Never Substitute Zeros for Nil
```swift
// ❌ WRONG
raw.steps = rook.steps ?? 0

// ✅ CORRECT
raw.steps = rook.steps  // Preserve nil
```

### 4. Always Check Denominators Before Division
```swift
// ❌ WRONG
let efficiency = duration / timeInBed  // Crash if timeInBed = 0

// ✅ CORRECT
guard timeInBed > 0 else { efficiency = nil; return }
let efficiency = (duration / timeInBed) * 100
```

---

## 📝 Files to Create

### New Swift Files (6 files)
1. `ROOKAPIClient.swift` — Network layer
2. `ROOKModels.swift` — Data structures
3. `ROOKDataAdapter.swift` — Transformation logic (MOST IMPORTANT)
4. `ROOKSyncManager.swift` — Orchestration
5. `ROOKSetupView.swift` — Onboarding UI
6. `ROOKDataAdapterTests.swift` — Unit tests

### Files to Modify (3 files)
1. `VitalityScoringEngine.swift` — Add `hrvType: String?` to `VitalityRawMetrics`
2. `RiskResultsView.swift` — Add "Connect Wearable" button, sync status
3. `DataManager.swift` — Save ROOK sync metadata (optional)

### Test Data Files (3 files)
1. `rook_sample_whoop_full.json` — All 10 metrics
2. `rook_sample_apple_minimal.json` — Sleep, steps, RHR only
3. `rook_sample_fitbit_rmssd.json` — RMSSD instead of SDNN

**Total estimated LOC:** ~1,500 lines (including tests)

---

## ✅ Success Criteria

### Technical
- [ ] Sync success rate >95%
- [ ] Data completeness >80% (all required fields)
- [ ] API latency <2 seconds (30-day fetch)
- [ ] Cache hit rate >50%
- [ ] Unit test coverage >90% for adapter

### Product
- [ ] Adoption rate >60% (new users connect wearable)
- [ ] Retention: ROOK users have >2x engagement vs CSV
- [ ] Accuracy: ROOK scores within 5 points of manual CSV scores
- [ ] User satisfaction: >4.5 stars for wearable sync feature

---

## 🎉 What's Ready

✅ **Complete specification** for ROOK integration  
✅ **Locked transformation rules** (no ambiguity)  
✅ **Data quality notes** by device (Whoop, Apple, Fitbit, etc.)  
✅ **Testing requirements** (unit, integration, E2E)  
✅ **Rollout plan** (5 weeks, 5 phases)  
✅ **Risk mitigation** (API downtime, device issues, etc.)  
✅ **Implementation checklist** (what to build, in what order)  

🚀 **Ready to implement when team approves!**

---

## 📂 Documentation Structure

```
docs/
├── README.md                              ← Documentation index
├── ROOK_TO_MIYA_MAPPING.md               ← 🔒 LOCKED SPEC (read first)
├── ROOK_QUICK_REFERENCE.md               ← Developer cheat sheet
├── ROOK_IMPLEMENTATION_REQUIREMENTS.md   ← Project plan & checklist
└── ROOK_DATA_FLOW.md                     ← Visual data flow

Root (existing docs):
├── OPTIMAL_TARGET_REFACTOR.md            ← Age-fair goal system (today)
├── TARGET_COMPARISON_TABLE.md            ← Old vs new targets
├── VITALITY_SCORING_SCHEMA.md            ← Schema design
├── AGE_SPECIFIC_SCHEMA.md                ← Age ranges
├── SCORING_ENGINE_COMPLETE.md            ← Engine implementation
└── (other existing docs)
```

---

## 🔗 Quick Links

- **Read First:** [docs/ROOK_TO_MIYA_MAPPING.md](./docs/ROOK_TO_MIYA_MAPPING.md)
- **While Coding:** [docs/ROOK_QUICK_REFERENCE.md](./docs/ROOK_QUICK_REFERENCE.md)
- **Project Plan:** [docs/ROOK_IMPLEMENTATION_REQUIREMENTS.md](./docs/ROOK_IMPLEMENTATION_REQUIREMENTS.md)
- **Big Picture:** [docs/ROOK_DATA_FLOW.md](./docs/ROOK_DATA_FLOW.md)

---

## Summary

**Task:** Create ROOK to Miya mapping (documentation only, no code changes)

**Delivered:**
- 4 comprehensive documentation files (~10,000 words total)
- Locked transformation rules for all 10 vitality metrics
- Complete implementation checklist (6 new files, 3 modifications)
- 5-week rollout plan with success metrics
- Data quality notes for 6 major wearable brands
- Testing requirements and sample data specs

**Status:** 🔒 Specification locked and ready for implementation

**No production code was changed** (as requested). All changes are documentation-only.

**Next action:** Review docs with team → approve → begin Phase 1 implementation

**The mapping is unambiguous, testable, and production-ready! 🎯**

