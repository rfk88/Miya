# Miya Health Documentation

**Last Updated:** December 14, 2025

---

## 📂 Document Index

### ROOK Integration (New)

1. **[ROOK_TO_MIYA_MAPPING.md](./ROOK_TO_MIYA_MAPPING.md)** 🔒
   - **Status:** Locked for implementation
   - **Purpose:** Single source of truth for ROOK API → Miya vitality mapping
   - **Contents:**
     - Complete field mapping table (10 metrics)
     - Locked transformation rules (HRV, sleep, movement, calories)
     - ROOK API structure reference
     - Data quality notes by device
     - Coverage expectations for testing
   - **Read this first** before implementing ROOK integration

2. **[ROOK_QUICK_REFERENCE.md](./ROOK_QUICK_REFERENCE.md)**
   - **Purpose:** Developer cheat sheet for ROOK integration
   - **Contents:**
     - Critical rules (HRV, calories, nil handling)
     - Field mapping cheat sheet
     - Calculation formulas
     - Testing checklist
     - Common pitfalls
     - Implementation template
   - **Use this** while coding the adapter

3. **[ROOK_IMPLEMENTATION_REQUIREMENTS.md](./ROOK_IMPLEMENTATION_REQUIREMENTS.md)**
   - **Purpose:** Complete checklist for ROOK integration
   - **Contents:**
     - Required code changes (`VitalityRawMetrics`, API client, adapter)
     - New files to create (6 files)
     - Testing requirements
     - Migration strategy (3 phases)
     - Rollout plan (5 weeks)
     - Success metrics and risks
   - **Use this** for project planning and implementation tracking

---

## 🎯 Vitality Scoring System

### Core Schema
- **[../VITALITY_SCORING_SCHEMA.md](../VITALITY_SCORING_SCHEMA.md)** — Original schema design
- **[../AGE_SPECIFIC_SCHEMA.md](../AGE_SPECIFIC_SCHEMA.md)** — Age-specific benchmarks
- **[../SCORING_ENGINE_COMPLETE.md](../SCORING_ENGINE_COMPLETE.md)** — Production engine

### Quick Starts
- **[../QUICK_START_AGE_SCHEMA.md](../QUICK_START_AGE_SCHEMA.md)** — Using age-specific ranges
- **[../QUICK_START_SCHEMA.md](../QUICK_START_SCHEMA.md)** — Basic schema usage

### Integration Guides
- **[../INTEGRATION_COMPLETE.md](../INTEGRATION_COMPLETE.md)** — CSV/JSON import integration
- **[../UI_COMPARISON_COMPLETE.md](../UI_COMPARISON_COMPLETE.md)** — Displaying new engine in UI
- **[../ENGINE_COMPARISON_GUIDE.md](../ENGINE_COMPARISON_GUIDE.md)** — Old vs new engine

### Testing
- **[../SMOKE_TEST_EXAMPLE.md](../SMOKE_TEST_EXAMPLE.md)** — Manual testing examples
- **[../VITALITY_TESTING_README.md](../VITALITY_TESTING_README.md)** — Testing guide

---

## 🎲 Risk Assessment

- **[../WHO_IMPLEMENTATION_STATUS.md](../WHO_IMPLEMENTATION_STATUS.md)** — WHO risk calculation
- **[../OPTIMAL_TARGET_REFACTOR.md](../OPTIMAL_TARGET_REFACTOR.md)** — Age-fair goal system (NEW)
- **[../TARGET_COMPARISON_TABLE.md](../TARGET_COMPARISON_TABLE.md)** — Old vs new targets

---

## 🗄️ Database

- **[../WIPE_DATABASE_GUIDE.md](../WIPE_DATABASE_GUIDE.md)** — Safe database wipe
- **[../QUICK_WIPE_INSTRUCTIONS.md](../QUICK_WIPE_INSTRUCTIONS.md)** — Quick wipe for testing

---

## 🔄 Current State (December 2025)

### ✅ Completed
- [x] Vitality scoring schema (10 metrics, 3 pillars, age-specific ranges)
- [x] Production scoring engine (`VitalityScoringEngine`)
- [x] CSV/JSON import integration
- [x] New engine UI comparison in `RiskResultsView`
- [x] Age-fair optimal target (risk-only, no age penalty)
- [x] ROOK integration mapping (documentation)

### 🚧 In Progress
- [ ] ROOK API integration (planned, not implemented)
- [ ] Dashboard vitality display (mock data only)
- [ ] Baseline tracking and trends

### 📋 Planned
- [ ] Multi-device sync via ROOK
- [ ] Real-time vitality updates
- [ ] Personalized recommendations based on scores
- [ ] Family vitality comparison

---

## 🚀 Next Steps

### For ROOK Integration
1. **Read:** [ROOK_TO_MIYA_MAPPING.md](./ROOK_TO_MIYA_MAPPING.md) (locked spec)
2. **Review:** [ROOK_IMPLEMENTATION_REQUIREMENTS.md](./ROOK_IMPLEMENTATION_REQUIREMENTS.md) (checklist)
3. **Implement:** Start with `ROOKDataAdapter` (core transformation logic)
4. **Test:** Use sample data from multiple devices (Whoop, Apple, Fitbit)
5. **Integrate:** Add ROOK sync to `RiskResultsView`

### For Vitality Display
1. **Wire Dashboard:** Connect `VitalityScoringEngine` to `DashboardView`
2. **Replace Mock Data:** Use real scored data instead of placeholders
3. **Add Trends:** Show 7-day, 30-day trends
4. **Add Recommendations:** Suggest actions based on low pillar scores

---

## 📝 Document Conventions

### Status Tags
- 🔒 **Locked:** Spec is finalized, do not change without team review
- ✅ **Complete:** Implementation finished and tested
- 🚧 **In Progress:** Actively being worked on
- 📋 **Planned:** Documented but not started

### File Types
- **`*_MAPPING.md`** — Data transformation specs (external → internal)
- **`*_SCHEMA.md`** — Data structure definitions
- **`*_COMPLETE.md`** — Implementation summaries (what was done)
- **`QUICK_START_*.md`** — Short getting-started guides
- **`*_GUIDE.md`** — Step-by-step instructions
- **`*_REQUIREMENTS.md`** — Implementation checklists

---

## 🤝 Contributing

### Before Making Code Changes
1. Check if a locked spec exists (🔒)
2. Read the relevant `*_COMPLETE.md` for context
3. Update documentation if you change core logic
4. Run tests and update test data if needed

### When Adding New Features
1. Create a design doc (like `ROOK_TO_MIYA_MAPPING.md`)
2. Get team review and lock the spec
3. Create an implementation checklist (like `ROOK_IMPLEMENTATION_REQUIREMENTS.md`)
4. Implement, test, and document completion

---

## 📞 Questions?

- **ROOK Integration:** See [ROOK_QUICK_REFERENCE.md](./ROOK_QUICK_REFERENCE.md) for FAQs
- **Vitality Scoring:** See [../QUICK_START_AGE_SCHEMA.md](../QUICK_START_AGE_SCHEMA.md)
- **Database Issues:** See [../WIPE_DATABASE_GUIDE.md](../WIPE_DATABASE_GUIDE.md)

**For unlisted questions, check the relevant `*_COMPLETE.md` file first, then ask the team.**

---

**This documentation is living and evolving. Keep it updated as the product grows! 📚**

