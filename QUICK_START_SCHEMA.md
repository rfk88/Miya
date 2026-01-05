# Quick Start: Vitality Scoring Schema

## ✅ What's Done

The vitality scoring schema is **fully integrated** and **validated**. You now have a single source of truth for how Miya Health scores vitality.

---

## 🚀 See It In Action (2 minutes)

### Step 1: Run the App
```
1. Open Miya Health.xcodeproj in Xcode
2. Press Cmd+R to run in simulator
3. Check the Xcode console
```

**You should see:**
```
🔍 Validating vitality scoring schema...
  ✅ Pillar weights sum to 1.0
  ✅ Sleep: 4 sub-metrics, weights sum to 1.0
  ✅ Movement: 3 sub-metrics, weights sum to 1.0
  ✅ Stress: 3 sub-metrics, weights sum to 1.0
✅ Vitality scoring schema validated successfully
   Total pillars: 3
   Total sub-metrics: 10
```

✅ **If you see this, the schema is working!**

---

### Step 2: See Detailed Examples (Optional)

1. Open `Miya Health/Miya_HealthApp.swift`
2. Find this line (around line 25):
   ```swift
   // ScoringSchemaExamples.runAllExamples()
   ```
3. Uncomment it:
   ```swift
   ScoringSchemaExamples.runAllExamples()
   ```
4. Run app again (Cmd+R)
5. Check console for detailed schema breakdown

**You'll see:**
- All sub-metrics with their weights
- Benchmark values for each metric
- How weights contribute to total vitality
- Sample scoring scenarios

---

## 📋 What You Have Now

### Files Created
1. **`ScoringSchema.swift`** - The complete schema (430 lines)
   - 3 pillars: Sleep, Movement, Stress
   - 10 sub-metrics with weights and benchmarks
   - Type-safe access via enums and extensions
   - Automatic validation

2. **`ScoringSchemaExamples.swift`** - Usage examples (270 lines)
   - Shows how to access schema data
   - Demonstrates weight calculations
   - Sample scoring scenarios

3. **Documentation**
   - `VITALITY_SCORING_SCHEMA.md` - Full technical docs
   - `SCHEMA_INTEGRATION_SUMMARY.md` - Implementation details
   - `QUICK_START_SCHEMA.md` - This file

### Files Modified
- **`Miya_HealthApp.swift`** - Added validation on app launch

---

## 🎯 Quick Reference: The Schema

```
VITALITY (0-100)
├── SLEEP (33%)
│   ├── Duration (40%)      → 13.2% of vitality
│   ├── Restorative % (30%) → 9.9% of vitality
│   ├── Efficiency (20%)    → 6.6% of vitality
│   └── Awake % (10%)       → 3.3% of vitality
│
├── MOVEMENT (33%)
│   ├── Minutes (40%)       → 13.2% of vitality
│   ├── Steps (30%)         → 9.9% of vitality
│   └── Calories (30%)      → 9.9% of vitality
│
└── STRESS (34%)
    ├── HRV (40%)           → 13.6% of vitality
    ├── Resting HR (40%)    → 13.6% of vitality
    └── Breathing (20%)     → 6.8% of vitality
```

---

## 💡 Common Tasks

### Task: Get benchmark for a metric
```swift
if let def = VitalitySubMetric.sleepDuration.definition {
    print("Excellent: \(def.benchmarks.excellent ?? 0) hours")
    print("Good: \(def.benchmarks.good ?? 0) hours")
}
```

### Task: List all sub-metrics in a pillar
```swift
let sleepMetrics = VitalityPillar.sleep.subMetrics
for metric in sleepMetrics {
    print("\(metric.id.displayName): \(metric.weightWithinPillar * 100)%")
}
```

### Task: Calculate metric's contribution to vitality
```swift
if let def = VitalitySubMetric.steps.definition,
   let pillar = def.parentPillar.definition {
    let contribution = pillar.weightInVitality * def.weightWithinPillar * 100
    print("Steps contribute \(contribution)% to total vitality")
}
```

### Task: Print complete schema
```swift
#if DEBUG
VitalitySchemaInfo.printSchema()
#endif
```

---

## 🔄 What Hasn't Changed

**Your app still works exactly as before!** The schema is a parallel system:

- ✅ `VitalityCalculator.swift` still works (old threshold-based scoring)
- ✅ Dashboard still shows scores (using old calculator)
- ✅ No breaking changes to existing functionality

The schema is **ready** but **not yet active** in scoring calculations.

---

## 📈 What's Next

### Phase 2: Build the Scoring Engine
**Goal**: Transform raw values → 0-100 scores using the schema

**What it will do**:
- Take raw values (e.g., 7.5 hours sleep)
- Use schema benchmarks (8h excellent, 7h good)
- Compute continuous score (7.5h → 94/100)
- Apply to all 10 sub-metrics

**When to start**: When you're ready to replace the old scoring system

### To begin Phase 2, say:
> "Implement Phase 2: Create the scoring engine"

---

## ❓ Troubleshooting

### Problem: Don't see validation message
**Solution**: 
- Make sure you're running in Debug mode (not Release)
- Check Xcode console (Cmd+Shift+Y to show)
- Validation only runs on first app launch per session

### Problem: Want to see more details
**Solution**: Uncomment `ScoringSchemaExamples.runAllExamples()` in `Miya_HealthApp.swift`

### Problem: Want to change a weight
**Solution**: 
1. Open `ScoringSchema.swift`
2. Find `vitalityScoringSchema` constant
3. Edit the weight values
4. Run app - validation will catch errors if weights don't sum to 1.0

---

## 📚 Resources

- **Full Documentation**: See `VITALITY_SCORING_SCHEMA.md`
- **Implementation Details**: See `SCHEMA_INTEGRATION_SUMMARY.md`
- **Code Examples**: See `ScoringSchemaExamples.swift`
- **Schema Code**: See `ScoringSchema.swift`

---

## ✅ Success!

Your vitality scoring schema is:
- ✅ Fully defined
- ✅ Validated automatically
- ✅ Documented thoroughly
- ✅ Ready to use

**You're now ready for Phase 2!** 🚀

---

## Need Help?

Add this to any view to inspect the schema:
```swift
.onAppear {
    #if DEBUG
    // Print everything
    VitalitySchemaInfo.printSchema()
    
    // Or specific examples
    ScoringSchemaExamples.demonstrateSubMetricAccess()
    ScoringSchemaExamples.demonstrateWeightCalculation()
    #endif
}
```

Or just ask me: "Show me how to [do X] with the schema"

