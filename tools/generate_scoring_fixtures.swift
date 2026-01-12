import Foundation

// This tool generates TS parity fixtures for server-side scoring.
// It compiles the Swift scoring engine sources directly and writes a JSON file
// into `supabase/functions/rook/scoring/fixtures.v1.json`.
//
// Run:
//   swiftc -O -o /tmp/gen \
//     "tools/generate_scoring_fixtures.swift" \
//     "Miya Health/ScoringSchema.swift" \
//     "Miya Health/VitalityBreakdown.swift" \
//     "Miya Health/VitalityExplanation.swift" \
//     "Miya Health/VitalityScoringEngine.swift"
//   /tmp/gen

struct FixtureInput: Codable {
    let age: Int
    let sleepDurationHours: Double?
    let restorativeSleepPercent: Double?
    let sleepEfficiencyPercent: Double?
    let awakePercent: Double?
    let movementMinutes: Double?
    let steps: Int?
    let activeCalories: Double?
    let hrvMs: Double?
    let hrvType: String?
    let restingHeartRate: Double?
    let breathingRate: Double?
}

struct FixtureExpected: Codable {
    let totalScore: Int
    let sleep: Int
    let movement: Int
    let stress: Int
}

struct Fixture: Codable {
    let id: String
    let input: FixtureInput
    let expected: FixtureExpected?
}

struct FixtureFile: Codable {
    let schemaVersion: String
    let generatedAt: String
    let fixtures: [Fixture]
}

func pillarScore(_ snapshot: VitalitySnapshot, _ pillar: VitalityPillar) -> Int {
    snapshot.pillarScores.first(where: { $0.pillar == pillar })?.score ?? 0
}

func makeRaw(_ i: FixtureInput) -> VitalityRawMetrics {
    VitalityRawMetrics(
        age: i.age,
        sleepDurationHours: i.sleepDurationHours,
        restorativeSleepPercent: i.restorativeSleepPercent,
        sleepEfficiencyPercent: i.sleepEfficiencyPercent,
        awakePercent: i.awakePercent,
        movementMinutes: i.movementMinutes,
        steps: i.steps,
        activeCalories: i.activeCalories,
        hrvMs: i.hrvMs,
        hrvType: i.hrvType,
        restingHeartRate: i.restingHeartRate,
        breathingRate: i.breathingRate
    )
}

func nowISO() -> String {
    ISO8601DateFormatter().string(from: Date())
}

let engine = VitalityScoringEngine()

// Representative fixtures:
// - Covers all 4 age groups
// - Covers missing-pillars behavior (eligibility requires >=2 pillars)
// - Covers each scoring direction bucket behavior around thresholds
let inputs: [(String, FixtureInput)] = [
    ("young_all_optimal", FixtureInput(
        age: 30,
        sleepDurationHours: 8.0,
        restorativeSleepPercent: 40.0,
        sleepEfficiencyPercent: 95.0,
        awakePercent: 3.0,
        movementMinutes: 40.0,
        steps: 9500,
        activeCalories: 500.0,
        hrvMs: 85.0,
        hrvType: "sdnn",
        restingHeartRate: 58.0,
        breathingRate: 14.0
    )),
    ("young_sleep_low_movement_ok_stress_ok", FixtureInput(
        age: 30,
        sleepDurationHours: 6.0,
        restorativeSleepPercent: 28.0,
        sleepEfficiencyPercent: 84.0,
        awakePercent: 12.0,
        movementMinutes: 25.0,
        steps: 7000,
        activeCalories: 250.0,
        hrvMs: 55.0,
        hrvType: "sdnn",
        restingHeartRate: 72.0,
        breathingRate: 18.5
    )),
    ("middle_missing_sleep_but_movement_and_stress_present", FixtureInput(
        age: 50,
        sleepDurationHours: nil,
        restorativeSleepPercent: nil,
        sleepEfficiencyPercent: nil,
        awakePercent: nil,
        movementMinutes: 35.0,
        steps: 9000,
        activeCalories: 450.0,
        hrvMs: 70.0,
        hrvType: "sdnn",
        restingHeartRate: 60.0,
        breathingRate: 15.0
    )),
    ("middle_only_one_pillar_movement_should_be_ineligible", FixtureInput(
        age: 50,
        sleepDurationHours: nil,
        restorativeSleepPercent: nil,
        sleepEfficiencyPercent: nil,
        awakePercent: nil,
        movementMinutes: 35.0,
        steps: 9000,
        activeCalories: 450.0,
        hrvMs: nil,
        hrvType: nil,
        restingHeartRate: nil,
        breathingRate: nil
    )),
    ("senior_stress_low_rhr_high", FixtureInput(
        age: 65,
        sleepDurationHours: 7.5,
        restorativeSleepPercent: 28.0,
        sleepEfficiencyPercent: 86.0,
        awakePercent: 11.0,
        movementMinutes: 18.0,
        steps: 4500,
        activeCalories: 180.0,
        hrvMs: 35.0,
        hrvType: "sdnn",
        restingHeartRate: 88.0,
        breathingRate: 19.5
    )),
    ("elderly_steps_optimal_range", FixtureInput(
        age: 80,
        sleepDurationHours: 7.2,
        restorativeSleepPercent: 24.0,
        sleepEfficiencyPercent: 84.0,
        awakePercent: 13.0,
        movementMinutes: 22.0,
        steps: 6500,
        activeCalories: 320.0,
        hrvMs: 45.0,
        hrvType: "sdnn",
        restingHeartRate: 68.0,
        breathingRate: 16.0
    )),
    // Boundary-ish values around schema cutoffs
    ("young_sleep_duration_at_optimal_min", FixtureInput(
        age: 25,
        sleepDurationHours: 7.0,
        restorativeSleepPercent: 35.0,
        sleepEfficiencyPercent: 90.0,
        awakePercent: 5.0,
        movementMinutes: 30.0,
        steps: 8000,
        activeCalories: 300.0,
        hrvMs: 70.0,
        hrvType: "sdnn",
        restingHeartRate: 65.0,
        breathingRate: 12.0
    )),
    ("young_sleep_duration_at_optimal_max", FixtureInput(
        age: 25,
        sleepDurationHours: 9.0,
        restorativeSleepPercent: 45.0,
        sleepEfficiencyPercent: 100.0,
        awakePercent: 5.0,
        movementMinutes: 45.0,
        steps: 10000,
        activeCalories: 600.0,
        hrvMs: 100.0,
        hrvType: "sdnn",
        restingHeartRate: 50.0,
        breathingRate: 18.0
    )),
    ("young_sleep_duration_just_below_poor_low", FixtureInput(
        age: 25,
        sleepDurationHours: 6.4,
        restorativeSleepPercent: 29.0,
        sleepEfficiencyPercent: 84.9,
        awakePercent: 10.1,
        movementMinutes: 19.9,
        steps: 5999,
        activeCalories: 199.0,
        hrvMs: 49.0,
        hrvType: "sdnn",
        restingHeartRate: 90.0,
        breathingRate: 20.1
    ))
]

@main
struct GenerateScoringFixtures {
    static func main() throws {
        var fixtures: [Fixture] = []
        for (id, input) in inputs {
            let raw = makeRaw(input)
            let maybe = engine.scoreIfPossible(raw: raw)
            let expected: FixtureExpected?
            if let snap = maybe?.snapshot {
                expected = FixtureExpected(
                    totalScore: snap.totalScore,
                    sleep: pillarScore(snap, .sleep),
                    movement: pillarScore(snap, .movement),
                    stress: pillarScore(snap, .stress)
                )
            } else {
                expected = nil
            }
            fixtures.append(Fixture(id: id, input: input, expected: expected))
        }
        
        let out = FixtureFile(
            schemaVersion: "v1_2026_01_07",
            generatedAt: nowISO(),
            fixtures: fixtures
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(out)
        
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let outPath = "\(cwd)/supabase/functions/rook/scoring/fixtures.v1.json"
        try data.write(to: URL(fileURLWithPath: outPath), options: [.atomic])
        print("✅ Wrote fixtures to \(outPath) (\(fixtures.count) cases)")
    }
}


