# ROOK Implementation Requirements

**Version:** 1.0  
**Date:** December 14, 2025  
**Status:** 📋 Ready for Implementation

---

## Overview

This document lists all code changes required to implement the ROOK integration based on the locked mapping specification in [ROOK_TO_MIYA_MAPPING.md](./ROOK_TO_MIYA_MAPPING.md).

**DO NOT make these changes yet.** This is a checklist for the next phase.

---

## 1. Update VitalityRawMetrics Struct

**File:** `Miya Health/VitalityScoringEngine.swift`

**Current Definition:**
```swift
struct VitalityRawMetrics {
    let age: Int
    // Sleep
    let sleepDurationHours: Double?
    let restorativeSleepPercent: Double?
    let sleepEfficiencyPercent: Double?
    let awakePercent: Double?
    // Movement
    let movementMinutes: Double?
    let steps: Int?
    let activeCalories: Double?
    // Stress
    let hrvMs: Double?
    let restingHeartRate: Double?
    let breathingRate: Double?
}
```

**Required Change:**
```swift
struct VitalityRawMetrics {
    let age: Int
    // Sleep
    let sleepDurationHours: Double?
    let restorativeSleepPercent: Double?
    let sleepEfficiencyPercent: Double?
    let awakePercent: Double?
    // Movement
    let movementMinutes: Double?
    let steps: Int?
    let activeCalories: Double?
    // Stress
    let hrvMs: Double?
    let hrvType: String?  // ← NEW: "sdnn" or "rmssd"
    let restingHeartRate: Double?
    let breathingRate: Double?
}
```

**Rationale:**
- ROOK sources provide either SDNN or RMSSD, not both
- We don't convert between them (introduces error)
- Tracking the type allows future refinement of scoring ranges
- Scoring engine treats both as generic "HRV" for now

**Migration Impact:**
- Existing test data and CSV/JSON parsers set `hrvType = nil`
- ROOK adapter will populate `hrvType = "sdnn"` or `"rmssd"`
- No breaking changes (optional field)

---

## 2. Create ROOK API Client

**New File:** `Miya Health/ROOKAPIClient.swift`

**Responsibilities:**
- Authenticate with ROOK API (user provisioning)
- Fetch sleep summaries for date range
- Fetch physical summaries for date range
- Fetch activity events (for movement minutes fallback)
- Handle rate limiting and retries
- Cache responses locally (reduce API calls)

**Key Methods:**
```swift
class ROOKAPIClient {
    func authenticate(userId: String) async throws -> ROOKAuthToken
    
    func fetchSleepSummary(
        userId: String, 
        date: Date
    ) async throws -> ROOKSleepSummary
    
    func fetchPhysicalSummary(
        userId: String,
        date: Date
    ) async throws -> ROOKPhysicalSummary
    
    func fetchActivityEvents(
        userId: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [ROOKActivityEvent]
}
```

**Dependencies:**
- Add ROOK SDK via Swift Package Manager
- Store ROOK API keys in `SupabaseConfig` or similar
- Handle token refresh and expiration

---

## 3. Create ROOK Data Models

**New File:** `Miya Health/ROOKModels.swift`

**Required Structs:**
```swift
struct ROOKSleepSummary: Codable {
    let sleep_duration_seconds_int: Int?
    let time_in_bed_seconds_int: Int?
    let time_awake_during_sleep_seconds_int: Int?
    let rem_sleep_duration_seconds_int: Int?
    let deep_sleep_duration_seconds_int: Int?
    let light_sleep_duration_seconds_int: Int?
    let sleep_efficiency_1_100_score_int: Int?
    let hrv_sdnn_ms_double: Double?
    let hrv_rmssd_ms_double: Double?
    let hr_resting_bpm_int: Int?
    let breaths_avg_per_min_int: Int?
}

struct ROOKPhysicalSummary: Codable {
    let steps_int: Int?
    let active_minutes_total_int: Int?
    let active_calories_kcal_double: Double?
    let total_calories_kcal_double: Double?
    let hr_resting_bpm_int: Int?
    let hrv_sdnn_avg_ms: Double?
    let hrv_rmssd_avg_ms: Double?
}

struct ROOKActivityEvent: Codable {
    let type: String  // "moderate", "vigorous", etc.
    let duration_seconds_int: Int?
    let calories_burned_kcal: Double?
}
```

**Note:** Field names match ROOK's snake_case JSON exactly (no camelCase conversion).

---

## 4. Create ROOK Data Adapter

**New File:** `Miya Health/ROOKDataAdapter.swift`

**Responsibility:**
- Map ROOK data models → `VitalityRawMetrics`
- Implement all transformation rules from mapping spec
- Handle fallbacks (HRV types, RHR sources, movement minutes)
- Log data quality issues

**Key Method:**
```swift
struct ROOKDataAdapter {
    static func mapToVitalityRawMetrics(
        age: Int,
        sleepSummary: ROOKSleepSummary?,
        physicalSummary: ROOKPhysicalSummary?,
        activityEvents: [ROOKActivityEvent]?
    ) -> VitalityRawMetrics {
        // See ROOK_QUICK_REFERENCE.md for implementation template
    }
}
```

**Implementation Notes:**
- Follow transformation rules exactly as specified in [ROOK_TO_MIYA_MAPPING.md](./ROOK_TO_MIYA_MAPPING.md)
- Use guard statements to safely unwrap optionals
- Log which fields are missing (for debugging)
- Return partial data (scoring engine handles nils)

---

## 5. Create ROOK Sync Manager

**New File:** `Miya Health/ROOKSyncManager.swift`

**Responsibilities:**
- Orchestrate multi-day data fetching
- Build VitalityRawMetrics for date ranges (7-30 days)
- Reuse `VitalityMetricsBuilder.fromWindow()` for averaging
- Cache results locally (avoid re-fetching)
- Schedule background sync (daily at 6 AM)
- Handle sync errors gracefully

**Key Methods:**
```swift
class ROOKSyncManager: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var isSyncing: Bool = false
    @Published var syncError: String?
    
    func syncLastNDays(
        userId: String,
        age: Int,
        days: Int
    ) async throws -> VitalityRawMetrics
    
    func scheduleDailySync()
    
    func manualRefresh() async
}
```

**Flow:**
1. Fetch sleep summaries for last N days
2. Fetch physical summaries for last N days
3. Map each day to partial `VitalityData`
4. Use `VitalityMetricsBuilder.fromWindow()` to aggregate
5. Return single `VitalityRawMetrics` for scoring

---

## 6. Update RiskResultsView for ROOK

**File:** `Miya Health/RiskResultsView.swift`

**Changes:**
- Add "Connect Wearable" button (alternative to file import)
- Trigger ROOK sync flow when button tapped
- Display ROOK sync status and last sync date
- Keep existing file import for testing/migration

**UI Addition:**
```swift
Section(header: Text("Automatic Data Sync")) {
    if rookSyncManager.lastSyncDate != nil {
        HStack {
            Text("Last synced:")
            Spacer()
            Text(rookSyncManager.lastSyncDate!, style: .date)
                .foregroundColor(.secondary)
        }
        Button("Refresh Now") {
            Task { await rookSyncManager.manualRefresh() }
        }
    } else {
        Button("Connect Wearable") {
            showingROOKSetup = true
        }
    }
}
```

---

## 7. Create ROOK Onboarding Flow

**New File:** `Miya Health/ROOKSetupView.swift`

**Responsibilities:**
- Explain ROOK integration (what wearables supported)
- User grants permission (ROOK SDK auth)
- User selects primary wearable (Apple Health, Whoop, Fitbit, etc.)
- Trigger initial sync (last 30 days)
- Show progress and completion

**Flow:**
1. **Intro screen:** "Connect your wearable for automatic vitality tracking"
2. **Device selection:** List of supported devices with logos
3. **ROOK authentication:** SDK handles device-specific OAuth
4. **Initial sync:** Fetch last 30 days, show progress
5. **Completion:** "Data synced! Your vitality score is ready."

---

## 8. Update DataManager for ROOK

**File:** `Miya Health/DataManager.swift`

**Changes:**
- Add `saveROOKSyncMetadata(userId:lastSyncDate:source:)`
- Store which wearable is connected
- Store last successful sync timestamp
- Optional: Store raw ROOK data for debugging

**New Supabase Table (Optional):**
```sql
CREATE TABLE rook_sync_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES user_profiles(id),
    sync_date TIMESTAMP DEFAULT NOW(),
    data_source TEXT,  -- "whoop", "apple_health", etc.
    days_fetched INT,
    metrics_available JSONB,  -- Which fields were present
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## 9. Testing Requirements

### 9.1 Unit Tests

**New File:** `Miya HealthTests/ROOKDataAdapterTests.swift`

**Test Cases:**
- ✅ Full coverage (all fields present) → all metrics mapped
- ✅ Minimal coverage (sleep, steps, RHR only) → partial metrics
- ✅ HRV fallback (SDNN missing, RMSSD present) → RMSSD used, type tracked
- ✅ RHR fallback (sleep RHR missing, physical RHR present) → physical used
- ✅ Movement minutes fallback (summary missing, sessions present) → aggregated
- ✅ Missing denominators (time_in_bed = 0) → efficiency = nil
- ✅ Active calories missing, total present → activeCalories = nil (not substituted)

### 9.2 Integration Tests

**Test Scenarios:**
1. **Whoop Full Sync:** All 10 metrics, SDNN, breathing rate
2. **Apple Health Partial Sync:** Sleep, steps, RHR only
3. **Fitbit RMSSD Sync:** RMSSD instead of SDNN
4. **Multi-Day Sync:** 30 days, some days missing
5. **Background Sync:** Automatic daily refresh

### 9.3 Sample Data

**Create Test Files:**
- `rook_sample_whoop_full.json` (all fields)
- `rook_sample_apple_minimal.json` (sleep, steps, RHR)
- `rook_sample_fitbit_rmssd.json` (RMSSD only)
- `rook_sample_multi_day_30.json` (30 days, gaps)

---

## 10. Migration Strategy

### Phase 1: Side-by-Side (Testing)
- Keep CSV/JSON import working
- Add ROOK as alternative data source
- Display both in UI (compare results)
- Beta test with real users

### Phase 2: ROOK Primary (Transition)
- Encourage new users to connect wearables
- Existing users: offer one-time CSV import, then switch to ROOK
- Keep CSV import as fallback

### Phase 3: ROOK Only (Production)
- Remove CSV/JSON import from UI
- Keep parsing code for data migration scripts
- All new vitality data comes from ROOK

---

## 11. Dependencies

### Swift Package Manager

Add to `Miya Health.xcodeproj`:
```swift
dependencies: [
    .package(url: "https://github.com/RookeriesDevelopment/rook-ios-sdk.git", from: "1.0.0")
]
```

### API Keys

Add to `SupabaseConfig.swift` or environment variables:
```swift
struct ROOKConfig {
    static let apiKey = "YOUR_ROOK_API_KEY"
    static let secretKey = "YOUR_ROOK_SECRET_KEY"
    static let environment = "production"  // or "sandbox"
}
```

---

## 12. Documentation Updates

### User-Facing
- [ ] Help article: "Connecting Your Wearable"
- [ ] FAQ: "Which wearables are supported?"
- [ ] FAQ: "Why is my data not syncing?"
- [ ] Privacy policy: Add ROOK data handling

### Developer-Facing
- [ ] API integration guide (this doc)
- [ ] Testing guide with sample data
- [ ] Troubleshooting common ROOK issues
- [ ] Data quality notes by device

---

## 13. Quality Assurance Checklist

### Correctness
- [ ] All 10 metrics map correctly (unit tests pass)
- [ ] HRV type tracking works (SDNN vs RMSSD)
- [ ] Fallbacks work (HRV types, RHR sources, movement minutes)
- [ ] No zero substitution (nil preserved)
- [ ] No RMSSD→SDNN conversion

### Completeness
- [ ] Minimum coverage enforced (sleep, steps, HRV/RHR)
- [ ] Partial data handled gracefully
- [ ] Missing data logged for debugging
- [ ] Multi-day sync works (7-30 days)

### Performance
- [ ] API calls batched (not per-field)
- [ ] Results cached locally
- [ ] Background sync doesn't drain battery
- [ ] Sync errors don't crash app

### UX
- [ ] Sync status visible to user
- [ ] Manual refresh button works
- [ ] Error messages are clear
- [ ] Setup flow is simple (3-5 steps max)

---

## 14. Rollout Plan

### Week 1: Core Integration
- [ ] Add ROOK SDK dependency
- [ ] Create API client, models, adapter
- [ ] Unit tests for adapter (all transformation rules)
- [ ] Test with static sample JSON

### Week 2: Sync Manager
- [ ] Implement multi-day fetch
- [ ] Integrate with `VitalityMetricsBuilder`
- [ ] Add caching layer
- [ ] Test with real ROOK sandbox data

### Week 3: UI Integration
- [ ] Add "Connect Wearable" flow
- [ ] Display sync status in RiskResultsView
- [ ] Keep file import for comparison
- [ ] Internal testing with team wearables

### Week 4: Beta Testing
- [ ] Invite 10-20 beta users
- [ ] Monitor sync logs and data quality
- [ ] Compare ROOK scores vs CSV scores
- [ ] Fix edge cases

### Week 5: Production
- [ ] Release to all users
- [ ] Monitor error rates
- [ ] Iterate on device-specific issues
- [ ] Plan removal of CSV import

---

## 15. Success Metrics

### Technical
- **Sync success rate:** >95% of attempts succeed
- **Data completeness:** >80% of syncs have all required fields
- **API latency:** <2 seconds for 30-day fetch
- **Cache hit rate:** >50% (reduce redundant API calls)

### Product
- **Adoption rate:** >60% of new users connect wearable
- **Retention:** Users with ROOK sync have >2x engagement
- **Accuracy:** ROOK-based scores match manual CSV scores within 5 points

---

## 16. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ROOK API downtime | High (no data sync) | Cache last 30 days locally; graceful degradation |
| Device incompatibility | Medium (some users can't sync) | Keep CSV import as fallback |
| Data quality varies by device | Medium (scoring inaccurate) | Log quality metrics; adjust ranges per device in future |
| Sync delays (24h lag) | Low (not real-time) | Set user expectations; show last sync timestamp |
| API rate limits | Low (throttling) | Batch requests; cache aggressively |

---

## Summary

**This is a documentation task only. No code changes have been made.**

**Next Steps:**
1. Review and approve this implementation plan
2. Estimate effort (likely 3-4 weeks for full integration)
3. Prioritize: Core adapter first, then sync manager, then UI
4. Begin Phase 1 (Core Integration) when ready

**Key Files to Create:**
- `ROOKAPIClient.swift`
- `ROOKModels.swift`
- `ROOKDataAdapter.swift`
- `ROOKSyncManager.swift`
- `ROOKSetupView.swift`

**Key Files to Modify:**
- `VitalityScoringEngine.swift` (add `hrvType` field)
- `RiskResultsView.swift` (add ROOK sync UI)
- `DataManager.swift` (save sync metadata)

**Total LOC Estimate:** ~1,500 lines (including tests)

**Dependencies:** ROOK iOS SDK (~external dependency)

**Ready to implement when approved! 🚀**

