import XCTest
@testable import Miya_Health

/// Parity guard: ensures the committed TS fixtures match the current Swift scoring engine outputs.
/// If this test fails after intended scoring/schema changes, regenerate fixtures by running:
///   swiftc -O -o /tmp/gen_scoring_fixtures \
///     "tools/VitalityDataStub.swift" \
///     "tools/generate_scoring_fixtures.swift" \
///     "Miya Health/ScoringSchema.swift" \
///     "Miya Health/VitalityBreakdown.swift" \
///     "Miya Health/VitalityExplanation.swift" \
///     "Miya Health/VitalityScoringEngine.swift"
///   /tmp/gen_scoring_fixtures
///
/// Or set environment variable `MIYA_UPDATE_SCORING_FIXTURES=1` to update the committed file during the test run.
final class ScoringParityFixtureTests: XCTestCase {
    
    private struct FixtureInput: Codable {
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
    
    private struct FixtureExpected: Codable, Equatable {
        let totalScore: Int
        let sleep: Int
        let movement: Int
        let stress: Int
    }
    
    private struct Fixture: Codable {
        let id: String
        let input: FixtureInput
        let expected: FixtureExpected?
    }
    
    private struct FixtureFile: Codable {
        let schemaVersion: String
        let generatedAt: String
        let fixtures: [Fixture]
    }
    
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Miya HealthTests
            .deletingLastPathComponent() // project root
    }
    
    private func fixturesURL() -> URL {
        projectRootURL().appendingPathComponent("supabase/functions/rook/scoring/fixtures.v1.json")
    }
    
    private func nowISO() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
    
    private func toRaw(_ i: FixtureInput) -> VitalityRawMetrics {
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
    
    private func pillarScore(_ snapshot: VitalitySnapshot, _ pillar: VitalityPillar) -> Int {
        snapshot.pillarScores.first(where: { $0.pillar == pillar })?.score ?? 0
    }
    
    func testCommittedFixturesMatchSwiftEngine() throws {
        let url = fixturesURL()
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(FixtureFile.self, from: data)
        
        let engine = VitalityScoringEngine()
        
        var updatedFixtures: [Fixture] = []
        var mismatches: [String] = []
        
        for fx in file.fixtures {
            let raw = toRaw(fx.input)
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
            
            if expected != fx.expected {
                mismatches.append("\(fx.id): expected=\(String(describing: fx.expected)) got=\(String(describing: expected))")
            }
            
            updatedFixtures.append(Fixture(id: fx.id, input: fx.input, expected: expected))
        }
        
        if !mismatches.isEmpty {
            let shouldUpdate = (ProcessInfo.processInfo.environment["MIYA_UPDATE_SCORING_FIXTURES"] == "1")
            if shouldUpdate {
                let updatedFile = FixtureFile(
                    schemaVersion: file.schemaVersion,
                    generatedAt: nowISO(),
                    fixtures: updatedFixtures
                )
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let outData = try enc.encode(updatedFile)
                try outData.write(to: url, options: [.atomic])
            } else {
                XCTFail(
                    """
                    Scoring parity fixtures mismatch (\(mismatches.count) cases).
                    First mismatch: \(mismatches.first ?? "n/a")
                    
                    To regenerate fixtures, run tools/generate_scoring_fixtures.swift or set MIYA_UPDATE_SCORING_FIXTURES=1.
                    """
                )
            }
        }
    }
}


